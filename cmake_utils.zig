const std = @import("std");

pub fn osTagToCmake(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .freestanding => "Generic",
        .linux => "Linux",
        .macos => "Darwin",
        .windows => "Windows",
        .emscripten => "Emscripten",
        else => @panic("Unknown OS"),
    };
}

pub fn cpuArchToCmake(os_tag: std.Target.Os.Tag, cpu_arch: std.Target.Cpu.Arch) []const u8 {
    return switch (os_tag) {
        // https://github.com/search?q=repo%3Atorvalds%2Flinux+UTS_MACHINE&type=code
        // https://stackoverflow.com/questions/45125516/possible-values-for-uname-m/45125525#45125525
        .linux => switch (cpu_arch) {
            .x86 => "i386",
            .powerpc => "ppc",
            .powerpc64 => "ppc64",
            .powerpcle => "ppcle",
            .powerpc64le => "ppc64le",
            else => @tagName(cpu_arch),
        },
        // https://ohanaware.com/blog/2020/08/macOS-CPU-Architecture.html
        .macos => switch (cpu_arch) {
            .x86 => "i386",
            .x86_64 => "x86_64",
            .aarch64 => "arm64",
            else => @panic("Unknown CPU arch for macOS"),
        },
        // https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details#environment-variables
        .windows => switch (cpu_arch) {
            .x86 => "x86",
            .x86_64 => "AMD64",
            .aarch64 => "ARM64",
            else => @panic("Unknown CPU arch for Windows"),
        },
        else => @panic("Unsupported OS tag for CMake mapping"),
    };
}
