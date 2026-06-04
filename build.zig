const std = @import("std");

const build_sdl3 = @import("build_sdl3.zig");
const LibSdl3 = build_sdl3.LibSdl3;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var lib_sdl3 = try LibSdl3.init(b, target, optimize);
    const lib_sdl3_c = lib_sdl3.c.createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("sdl", lib_sdl3_c);

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
