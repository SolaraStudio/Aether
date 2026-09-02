const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addExecutable(.{
        .name = "aether",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .linkage = .shared,
    });

    lib.addIncludePath(.{ .path = "libs/quickjs" });
    lib.addLibraryPath(.{ .path = "libs/quickjs" });
    lib.linkSystemLibrary("quickjs");

    b.installArtifact(lib);
}
