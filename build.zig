const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const exe = b.addExecutable(.{
        .name = "learn-zig-sdl3",
        .root_module = exe_mod,
    });
    exe.subsystem = .Console;
    b.installArtifact(exe);

    // Create vendor dir
    std.fs.cwd().makeDir("vendor") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // SDL3
    var lib_sdl3 = LibSdl3.init(b, target, optimize);
    try lib_sdl3.build("release-3.2.18");
    lib_sdl3.link(exe);
    lib_sdl3.install();

    // Run exe
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&(blk: {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addArgs(b.args orelse &.{});
        break :blk run_cmd;
    }).step);

    // Tests
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

const LibSdl3 = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    source_dir: []const u8,
    include_dir: []const u8,
    build_dir: []const u8,

    cmake_build: ?*std.Build.Step.Run = null,

    pub fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) @This() {
        const source_dir = "vendor/SDL/";
        const include_dir = source_dir ++ "include/";
        const build_dir = switch (optimize) {
            .Debug => source_dir ++ "build/clang_debug/",
            else => source_dir ++ "build/clang_release/",
        };

        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .source_dir = source_dir,
            .include_dir = include_dir,
            .build_dir = build_dir,
        };
    }

    pub fn build(this: *@This(), git_tag: []const u8) !void {
        const b = this.b;

        // git clone
        const git_url = "https://github.com/libsdl-org/SDL.git";
        const git_clone = b.addSystemCommand(&.{ "git", "clone", "--depth=1", "-b", git_tag, git_url });
        git_clone.cwd = b.path("vendor/");

        // cmake configure
        const cmake_conf = b.addSystemCommand(&.{ "cmake", "-S", this.source_dir, "-B", this.build_dir, "-G", "Ninja" });
        cmake_conf.setEnvironmentVariable("CC", "clang");
        cmake_conf.setEnvironmentVariable("CXX", "clang++");
        switch (this.optimize) {
            .Debug => cmake_conf.addArg("-DCMAKE_BUILD_TYPE=Debug"),
            else => cmake_conf.addArg("-DCMAKE_BUILD_TYPE=Release"),
        }
        _ = std.fs.cwd().access(this.source_dir, .{}) catch |err| switch (err) {
            error.FileNotFound => cmake_conf.step.dependOn(&git_clone.step),
            else => return err,
        };

        // cmake build
        this.cmake_build = b.addSystemCommand(&.{ "cmake", "--build", this.build_dir });
        _ = std.fs.cwd().access(this.build_dir, .{}) catch |err| switch (err) {
            error.FileNotFound => this.cmake_build.?.step.dependOn(&cmake_conf.step),
            else => return err,
        };
    }

    pub fn link(this: *@This(), exe: *std.Build.Step.Compile) void {
        std.debug.assert(this.cmake_build != null);

        const b = this.b;

        exe.step.dependOn(&this.cmake_build.?.step);
        exe.addIncludePath(b.path(this.include_dir));
        exe.addLibraryPath(b.path(this.build_dir));
        exe.linkSystemLibrary("SDL3");
    }

    pub fn install(this: *@This()) void {
        std.debug.assert(this.cmake_build != null);

        const b = this.b;

        switch (this.target.result.os.tag) {
            .windows => {
                const dll_path = b.pathJoin(&.{ this.build_dir, "SDL3.dll" });
                const dll_install = b.addInstallBinFile(b.path(dll_path), "SDL3.dll");
                dll_install.step.dependOn(&this.cmake_build.?.step);
                b.getInstallStep().dependOn(&dll_install.step);
            },
            else => {
                @panic("TODO");
            },
        }
    }
};
