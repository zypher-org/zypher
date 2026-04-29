const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl },
    });
    const optimize = b.standardOptimizeOption(.{});

    // ── Vendored SQLite3 ─────────────────────────────────────────────
    const sqlite3_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    sqlite3_mod.addCSourceFiles(.{
        .root = b.path("vendor/sqlite-amalgamation-3530000"),
        .files = &.{"sqlite3.c"},
        .flags = &.{ "-std=c11", "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" },
    });
    sqlite3_mod.addIncludePath(b.path("vendor/sqlite-amalgamation-3530000"));
    sqlite3_mod.link_libc = true;

    const sqlite3_lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = sqlite3_mod,
    });

    // ── Library module ──────────────────────────────────────────────
    const lib_mod = b.addModule("zypher", .{
        .root_source_file = b.path("src/zypher.zig"),
        .target = target,
    });
    lib_mod.linkLibrary(sqlite3_lib);
    lib_mod.addIncludePath(b.path("vendor/sqlite-amalgamation-3530000"));
    lib_mod.link_libc = true;

    // ── CLI executable ──────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "zypher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
            },
        }),
    });
    b.installArtifact(exe);

    // ── Run the CLI ─────────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the zypher CLI");
    run_step.dependOn(&run_cmd.step);

    // ── Demo app ────────────────────────────────────────────────────
    const demo_exe = b.addExecutable(.{
        .name = "zypher-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
            },
        }),
    });

    const run_demo_cmd = b.addRunArtifact(demo_exe);
    if (b.args) |args| run_demo_cmd.addArgs(args);

    const run_demo_step = b.step("run-demo", "Run the demo app");
    run_demo_step.dependOn(&run_demo_cmd.step);

    // ── Test infrastructure ─────────────────────────────────────────
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    // sqlite3 linking inherited from lib_mod

    const exe_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/test_runner.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
    });
    // sqlite3 linking inherited from lib_mod

    const integration_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/test_runner.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const integration_tests = b.addTest(.{
        .root_module = integration_test_mod,
    });
    // sqlite3 linking inherited from lib_mod

    const e2e_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e/test_runner.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const e2e_tests = b.addTest(.{
        .root_module = e2e_test_mod,
    });
    // sqlite3 linking inherited from lib_mod

    const regression_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/regression/test_runner.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const regression_tests = b.addTest(.{
        .root_module = regression_test_mod,
    });
    // sqlite3 linking inherited from lib_mod

    // ── Test step targets ───────────────────────────────────────────
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(lib_unit_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_unit_tests).step);
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    test_step.dependOn(&b.addRunArtifact(integration_tests).step);
    test_step.dependOn(&b.addRunArtifact(e2e_tests).step);
    test_step.dependOn(&b.addRunArtifact(regression_tests).step);

    const test_unit_step = b.step("test-unit", "Run unit tests only");
    test_unit_step.dependOn(&b.addRunArtifact(lib_unit_tests).step);
    test_unit_step.dependOn(&b.addRunArtifact(exe_unit_tests).step);
    test_unit_step.dependOn(&b.addRunArtifact(unit_tests).step);

    const test_integration_step = b.step("test-integration", "Run integration tests only");
    test_integration_step.dependOn(&b.addRunArtifact(integration_tests).step);

    const test_e2e_step = b.step("test-e2e", "Run end-to-end tests only");
    test_e2e_step.dependOn(&b.addRunArtifact(e2e_tests).step);

    // ── Docs ────────────────────────────────────────────────────────
    const docs_step = b.step("docs", "Generate documentation");
    const lib_test_for_docs = b.addTest(.{
        .root_module = lib_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib_test_for_docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // ── Bench ───────────────────────────────────────────────────────
    _ = b.step("bench", "Run benchmarks (not yet implemented)");
}
