const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "aether",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // QuickJS include & library paths
    lib.addIncludePath(.{ .path = "libs/quickjs" });
    lib.addLibraryPath(.{ .path = "libs/quickjs" });
    lib.linkSystemLibrary("quickjs");

    // Export JNI symbols
    lib.defineCMacro("_GNU_SOURCE", null);

    b.installArtifact(lib);
}
