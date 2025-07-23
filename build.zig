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

    // create vendor dir
    std.fs.cwd().makeDir("vendor") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // SDL3 paths
    const sdl3_src_dir = "vendor/SDL/";
    const sdl3_include_dir = sdl3_src_dir ++ "include";
    const sdl3_build_dir = switch (optimize) {
        .Debug => sdl3_src_dir ++ "build/clang_debug/",
        else => sdl3_src_dir ++ "build/clang_release/",
    };

    // SDL3 git clone
    const sdl3_git_clone = b.addSystemCommand(&.{ "git", "clone", "https://github.com/libsdl-org/SDL.git" });
    sdl3_git_clone.cwd = b.path("vendor/");

    // SDL3 cmake configure
    const sdl3_cmake_conf = b.addSystemCommand(&.{ "cmake", "-S", sdl3_src_dir, "-B", sdl3_build_dir, "-G", "Ninja" });
    sdl3_cmake_conf.setEnvironmentVariable("CC", "clang");
    sdl3_cmake_conf.setEnvironmentVariable("CXX", "clang++");
    switch (optimize) {
        .Debug => sdl3_cmake_conf.addArg("-DCMAKE_BUILD_TYPE=Debug"),
        else => sdl3_cmake_conf.addArg("-DCMAKE_BUILD_TYPE=Release"),
    }
    _ = std.fs.cwd().access(sdl3_src_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => sdl3_cmake_conf.step.dependOn(&sdl3_git_clone.step),
        else => return err,
    };

    // SDL3 cmake build
    const sdl3_cmake_build = b.addSystemCommand(&.{ "cmake", "--build", sdl3_build_dir });
    _ = std.fs.cwd().access(sdl3_build_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => sdl3_cmake_build.step.dependOn(&sdl3_cmake_conf.step),
        else => return err,
    };

    // SDL3 install dll
    switch (target.result.os.tag) {
        .windows => {
            const sdl3_dll_path = b.pathJoin(&.{ sdl3_build_dir, "SDL3.dll" });
            const sdl3_install_dll = b.addInstallBinFile(b.path(sdl3_dll_path), "SDL3.dll");
            sdl3_install_dll.step.dependOn(&sdl3_cmake_build.step);
            b.getInstallStep().dependOn(&sdl3_install_dll.step);
        },
        else => {
            @panic("TODO");
        },
    }

    // SDL3 link
    {
        exe.step.dependOn(&sdl3_cmake_build.step);
        exe.addIncludePath(b.path(sdl3_include_dir));
        exe.addLibraryPath(.{ .cwd_relative = b.exe_dir });
        exe.linkSystemLibrary("SDL3");
    }

    b.installArtifact(exe);

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
