const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const meta_match_dep = b.dependency("meta_match", .{
        .target = target,
        .optimize = optimize,
    });
    const meta_match_mod = meta_match_dep.module("meta_match");

    const root = b.path("src/root.zig");
    const mod = b.addModule("zig_structures", .{
        .root_source_file = root,
        .imports = &.{.{
            .name = "meta_match",
            .module = meta_match_mod,
        }},
    });
    _ = mod;

    const unit_tests = b.addTest(.{
        .name = "zig_structures",

        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("meta_match", meta_match_mod);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const fmt = b.addFmt(.{
        .paths = &.{"src/"},
    });

    const fmt_step = b.step("fmt", "Format source code");
    fmt_step.dependOn(&fmt.step);

    const docs = b.addInstallDirectory(.{
        .source_dir = unit_tests.getEmittedDocs(),
        .install_dir = .{ .prefix = {} },
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}
