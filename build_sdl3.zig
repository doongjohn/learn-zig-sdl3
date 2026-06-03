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

pub fn getLibPath(optimize: std.lang.OptimizeMode) [:0]const u8 {
    return switch (builtin.os.tag) {
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

    const optimize: std.lang.OptimizeMode = blk: {
        var args = try init.minimal.args.iterateAllocator(alloc);
        while (args.next()) |arg| {
            if (std.mem.startsWith(u8, arg, "-Doptimize=")) {
                if (std.mem.eql(u8, arg, "-Doptimize=ReleaseSafe"))
                    break :blk .ReleaseSafe;
                if (std.mem.eql(u8, arg, "-Doptimize=ReleaseFast"))
                    break :blk .ReleaseFast;
                if (std.mem.eql(u8, arg, "-Doptimize=ReleaseSmall"))
                    break :blk .ReleaseSmall;
            }
        }
        break :blk .Debug;
    };

    // Create vendor dir
    std.Io.Dir.cwd().createDirPath(io, "vendor") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // SDL git clone.
    std.Io.Dir.cwd().access(io, root_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            var git_clone = try std.process.spawn(io, .{ .argv = &.{ "git", "clone", "--depth=1", "-b", git_tag, git_url, root_dir } });
            const git_clone_res = try git_clone.wait(io);
            if (!git_clone_res.success()) {
                return error.GitCloneFailed;
            }
        },
        else => return err,
    };

    // Run cmake.
    std.Io.Dir.cwd().access(io, getLibPath(optimize), .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // cmake configure
            var cmake_conf_args: std.ArrayList([]const u8) = .empty;
            try cmake_conf_args.appendSlice(alloc, &.{ "cmake", "-S", root_dir, "-B", getBuildDir(optimize), "-G", "Ninja" });
            try cmake_conf_args.append(alloc, switch (optimize) {
                .Debug => "-DCMAKE_BUILD_TYPE=Debug",
                .ReleaseSafe => "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
                .ReleaseFast => "-DCMAKE_BUILD_TYPE=Release",
                .ReleaseSmall => "-DCMAKE_BUILD_TYPE=MinSizeRel",
            });

            var cmake_conf_env = try std.process.Environ.createMap(init.minimal.environ, alloc);
            if (cmake_conf_env.get("CC") == null) try cmake_conf_env.put("CC", "clang");
            if (cmake_conf_env.get("CXX") == null) try cmake_conf_env.put("CXX", "clang++");

            var cmake_conf = try std.process.spawn(io, .{
                .argv = cmake_conf_args.items,
                .environ_map = &cmake_conf_env,
            });
            const cmake_conf_res = try cmake_conf.wait(io);
            if (!cmake_conf_res.success()) return error.CmakeConfFailed;

            // cmake build
            var cmake_build = try std.process.spawn(io, .{
                .argv = &.{ "cmake", "--build", getBuildDir(optimize) },
                .environ_map = &cmake_conf_env,
            });
            const cmake_build_res = try cmake_build.wait(io);
            if (!cmake_build_res.success()) return error.CmakeBuildFailed;
        },
        else => return err,
    };
}
