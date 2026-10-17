const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("realtime_queue", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(b.addTest(.{
        .root_module = mod,
    }));

    const test_step = b.step("test", "run tests");
    test_step.dependOn(&run_tests.step);
}
