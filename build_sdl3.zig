const builtin = @import("builtin");
const std = @import("std");

pub const root_dir = "vendor/SDL/";
pub const git_url = "https://github.com/libsdl-org/SDL.git";
pub const git_tag = "release-3.4.8";

pub fn getBuildDir(optimize: std.lang.OptimizeMode) [:0]const u8 {
    return switch (optimize) {
        .Debug => root_dir ++ "build/debug/",
        .ReleaseSafe => root_dir ++ "build/release_safe/",
        .ReleaseFast => root_dir ++ "build/release_fast/",
        .ReleaseSmall => root_dir ++ "build/elease_small/",
    };
}

pub fn getLibPath(os_tag: std.Target.Os.Tag, optimize: std.lang.OptimizeMode) [:0]const u8 {
    return switch (os_tag) {
        .windows => switch (optimize) {
            .Debug => root_dir ++ "build/debug/SDL3.dll",
            .ReleaseSafe => root_dir ++ "build/release_safe/SDL3.dll",
            .ReleaseFast => root_dir ++ "build/release_fast/SDL3.dll",
            .ReleaseSmall => root_dir ++ "build/release_small/SDL3.dll",
        },
        else => @panic("TODO"),
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    var target_triple = try builtin.target.zigTriple(alloc);
    var optimize: std.lang.OptimizeMode = .Debug;

    var args = try init.minimal.args.iterateAllocator(alloc);
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-Dtarget=")) {
            target_triple = try alloc.dupe(u8, arg["-Dtarget=".len..]);
        }
        if (std.mem.startsWith(u8, arg, "-Doptimize=")) {
            if (std.mem.eql(u8, arg, "-Doptimize=ReleaseSafe"))
                optimize = .ReleaseSafe;
            if (std.mem.eql(u8, arg, "-Doptimize=ReleaseFast"))
                optimize = .ReleaseFast;
            if (std.mem.eql(u8, arg, "-Doptimize=ReleaseSmall"))
                optimize = .ReleaseSmall;
        }
    }

    const target = try std.Target.Query.parse(.{ .arch_os_abi = target_triple });
    const os_tag = target.os_tag orelse builtin.os.tag;
    const cpu_arch = target.cpu_arch orelse builtin.cpu.arch;

    const build_dir = getBuildDir(optimize);
    const lib_path = getLibPath(os_tag, optimize);

    // Create vendor dir
    std.Io.Dir.cwd().createDirPath(io, "vendor") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // SDL git clone.
    std.Io.Dir.cwd().access(io, root_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            var git_clone = try std.process.spawn(io, .{
                .argv = &.{ "git", "clone", "--depth=1", "-b", git_tag, git_url, root_dir },
            });
            const git_clone_res = try git_clone.wait(io);
            if (!git_clone_res.success()) {
                return error.GitCloneFailed;
            }
        },
        else => return err,
    };

    // Run cmake.
    std.Io.Dir.cwd().access(io, lib_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const cwd = try std.process.currentPathAlloc(io, alloc);

            // cmake configure
            var cmake_conf_argv: std.ArrayList([]const u8) = .empty;
            try cmake_conf_argv.appendSlice(alloc, &.{ "cmake", "-S", root_dir, "-B", build_dir, "-G", "Ninja" });
            try cmake_conf_argv.appendSlice(alloc, &.{
                try std.mem.concat(alloc, u8, &.{ "-DCMAKE_TOOLCHAIN_FILE=", cwd, "/build_sdl3_toolchain.cmake" }),
                try std.mem.concat(alloc, u8, &.{ "-DTARGET=", target_triple }),
                try std.mem.concat(alloc, u8, &.{ "-DCMAKE_SYSTEM_PROCESSOR=", @tagName(cpu_arch) }),
                try std.mem.concat(alloc, u8, &.{ "-DCMAKE_SYSTEM_NAME=", switch (os_tag) {
                    .linux => "Linux",
                    .windows => "Windows",
                    .macos => "Darwin",
                    .freestanding => "Generic",
                    .emscripten => "Emscripten",
                    else => @panic("Unknown OS"),
                } }),
            });
            try cmake_conf_argv.append(alloc, switch (optimize) {
                .Debug => "-DCMAKE_BUILD_TYPE=Debug",
                .ReleaseSafe => "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
                .ReleaseFast => "-DCMAKE_BUILD_TYPE=Release",
                .ReleaseSmall => "-DCMAKE_BUILD_TYPE=MinSizeRel",
            });
            try cmake_conf_argv.appendSlice(alloc, &.{
                "-DSDL_TESTS=OFF",
                "-DSDL_TEST_LIBRARY=OFF",
            });
            var cmake_conf = try std.process.spawn(io, .{
                .argv = cmake_conf_argv.items,
            });
            const cmake_conf_res = try cmake_conf.wait(io);
            if (!cmake_conf_res.success()) return error.CmakeConfFailed;

            // cmake build
            var cmake_build = try std.process.spawn(io, .{
                .argv = &.{ "cmake", "--build", build_dir },
            });
            const cmake_build_res = try cmake_build.wait(io);
            if (!cmake_build_res.success()) return error.CmakeBuildFailed;
        },
        else => return err,
    };
}

pub const LibSdl3 = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.OptimizeMode,
    c: *std.Build.Step.TranslateC,

    pub fn init(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.OptimizeMode) !@This() {
        var build_sdl3_argv: std.ArrayList([]const u8) = .empty;
        try build_sdl3_argv.appendSlice(b.allocator, &.{ "zig", "run", "build_sdl3.zig", "--" });
        try build_sdl3_argv.append(b.allocator, switch (optimize) {
            .Debug => "-Doptimize=Debug",
            .ReleaseSafe => "-Doptimize=ReleaseSafe",
            .ReleaseFast => "-Doptimize=ReleaseFast",
            .ReleaseSmall => "-Doptimize=ReleaseSmall",
        });
        try build_sdl3_argv.append(
            b.allocator,
            try std.mem.concat(b.allocator, u8, &.{ "-Dtarget=", try target.result.zigTriple(b.allocator) }),
        );
        const build_sdl3_cmd = b.addSystemCommand(build_sdl3_argv.items);

        // translate c
        const c = b.addTranslateC(.{
            .root_source_file = b.path("src/sdl.h"),
            .target = target,
            .optimize = .Debug,
        });
        c.addIncludePath(b.path("vendor/SDL/include"));
        c.step.dependOn(&build_sdl3_cmd.step);

        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .c = c,
        };
    }

    pub fn link(this: *const @This(), exe: *std.Build.Step.Compile) void {
        const b = this.b;

        exe.step.dependOn(&this.c.step);
        exe.root_module.addLibraryPath(b.path(getBuildDir(this.optimize)));
        exe.root_module.linkSystemLibrary("SDL3", .{});
    }

    pub fn install(this: *const @This()) void {
        const b = this.b;

        const os_tag = this.target.result.os.tag;
        const lib_path = getLibPath(os_tag, this.optimize);
        switch (os_tag) {
            .windows => {
                const lib_install = b.addInstallBinFile(b.path(lib_path), "SDL3.dll");
                lib_install.step.dependOn(&this.c.step);
                b.getInstallStep().dependOn(&lib_install.step);
            },
            else => @panic("TODO"),
        }
    }
};
