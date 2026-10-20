const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zz0_client", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const interop = b.addExecutable(.{
        .name = "zz0_interop_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("interop/client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zz0_client", .module = mod }},
        }),
    });
    const install_interop = b.addInstallArtifact(interop, .{});
    b.step("interop-client", "Build the independent-agent test client").dependOn(&install_interop.step);

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run zz0_client tests");
    test_step.dependOn(&run_tests.step);
}
