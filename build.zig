const std = @import("std");
const build_sdl3 = @import("build_sdl3.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var lib_sdl3 = LibSdl3.init(b, target, optimize);
    try lib_sdl3.build();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sdl", lib_sdl3.sdl_c.?.createModule());

    const exe = b.addExecutable(.{
        .name = "learn-zig-sdl3",
        .root_module = exe_mod,
    });
    exe.subsystem = .Console;

    lib_sdl3.link(exe);

    lib_sdl3.install();
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(blk: {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.addPassthruArgs();
        break :blk &run_cmd.step;
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_module = exe_mod,
    })).step);
}

const LibSdl3 = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.OptimizeMode,

    build_dir: []const u8,

    cmake_build: ?*std.Build.Step.Run = null,
    sdl_c: ?*std.Build.Step.TranslateC = null,

    pub fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.OptimizeMode) @This() {
        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .build_dir = build_sdl3.getBuildDir(optimize),
        };
    }

    pub fn build(this: *@This()) !void {
        const b = this.b;

        var build_sdl3_argv: std.ArrayList([]const u8) = .empty;
        try build_sdl3_argv.appendSlice(b.allocator, &.{ "zig", "run", "build_sdl3.zig", "--" });
        try build_sdl3_argv.append(b.allocator, switch (this.optimize) {
            .Debug => "-Doptimize=Debug",
            .ReleaseSafe => "-Doptimize=ReleaseSafe",
            .ReleaseFast => "-Doptimize=ReleaseFast",
            .ReleaseSmall => "-Doptimize=ReleaseSmall",
        });
        const build_sdl3_cmd = b.addSystemCommand(build_sdl3_argv.items);

        // translate c
        this.sdl_c = b.addTranslateC(.{
            .root_source_file = b.path("src/sdl.h"),
            .target = this.target,
            .optimize = .Debug,
        });
        this.sdl_c.?.addIncludePath(b.path("vendor/SDL/include"));
        this.sdl_c.?.step.dependOn(&build_sdl3_cmd.step);
    }

    pub fn link(this: *@This(), exe: *std.Build.Step.Compile) void {
        std.debug.assert(this.sdl_c != null);

        const b = this.b;

        exe.step.dependOn(&this.sdl_c.?.step);
        exe.root_module.addLibraryPath(b.path(this.build_dir));
        exe.root_module.linkSystemLibrary("SDL3", .{});
    }

    pub fn install(this: *@This()) void {
        std.debug.assert(this.sdl_c != null);

        const b = this.b;

        switch (this.target.result.os.tag) {
            .windows => {
                const dll_install = b.addInstallBinFile(b.path(build_sdl3.getLibPath(this.optimize)), "SDL3.dll");
                dll_install.step.dependOn(&this.sdl_c.?.step);
                b.getInstallStep().dependOn(&dll_install.step);
            },
            else => @panic("TODO"),
        }
    }
};
