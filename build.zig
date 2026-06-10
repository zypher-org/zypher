const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl },
    });
    const optimize = b.standardOptimizeOption(.{});

    // ── Vendored SQLite3 ─────────────────────────────────────────────
    const sqlite3_lib = createSqlite3Library(b, target, optimize);

    // ── Library module ──────────────────────────────────────────────
    const lib_mod = b.addModule("zypher", .{
        .root_source_file = b.path("src/zypher.zig"),
        .target = target,
        .optimize = optimize,
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

    // ── Cross-target CLI binaries ──────────────────────────────────
    const all_targets_step = b.step("all-targets", "Build zypher CLI binaries for all supported targets");
    for (release_targets) |release_target| {
        const release_resolved_target = b.resolveTargetQuery(release_target.query);
        const release_sqlite3_lib = createSqlite3Library(b, release_resolved_target, optimize);
        const release_lib_mod = createZypherModule(b, release_resolved_target, optimize, release_sqlite3_lib);
        const release_exe = createCliExecutable(b, release_resolved_target, optimize, release_lib_mod);
        const install_release_exe = b.addInstallArtifact(release_exe, .{
            .dest_sub_path = b.fmt("{s}/zypher{s}", .{ release_target.name, release_target.exe_suffix }),
        });

        all_targets_step.dependOn(&install_release_exe.step);
        b.getInstallStep().dependOn(&install_release_exe.step);
    }

    // ── Run the CLI ─────────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the zypher CLI");
    run_step.dependOn(&run_cmd.step);

    // ── Demo app ────────────────────────────────────────────────────
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/demo/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const demo_exe = b.addExecutable(.{
        .name = "zypher-demo",
        .root_module = demo_mod,
    });

    const run_demo_cmd = b.addRunArtifact(demo_exe);
    run_demo_cmd.addPassthruArgs();

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
            .{ .name = "demo", .module = demo_mod },
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
    const doc_mod = b.createModule(.{
        .root_source_file = b.path("src/docs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const project_docs = b.addTest(.{
        .root_module = doc_mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = project_docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const doc_step = b.step("doc", "Generate documentation for the whole project");
    doc_step.dependOn(&install_docs.step);

    const docs_step = b.step("docs", "Alias for doc");
    docs_step.dependOn(doc_step);

    // ── Bench ───────────────────────────────────────────────────────
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tests/bench/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
        },
    });

    const bench_exe = b.addExecutable(.{
        .name = "zypher-bench",
        .root_module = bench_mod,
    });

    const run_bench_cmd = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench_cmd.step);
}

const ReleaseTarget = struct {
    name: []const u8,
    query: std.Target.Query,
    exe_suffix: []const u8 = "",
};

const release_targets = [_]ReleaseTarget{
    .{ .name = "x86_64-linux-musl", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "aarch64-linux-musl", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "x86_64-macos", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
    .{ .name = "aarch64-macos", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
    .{ .name = "x86_64-windows-gnu", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }, .exe_suffix = ".exe" },
    .{ .name = "aarch64-windows-gnu", .query = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu }, .exe_suffix = ".exe" },
};

fn createSqlite3Library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
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

    return b.addLibrary(.{
        .name = "sqlite3",
        .root_module = sqlite3_mod,
    });
}

fn createZypherModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sqlite3_lib: *std.Build.Step.Compile,
) *std.Build.Module {
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/zypher.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.linkLibrary(sqlite3_lib);
    lib_mod.addIncludePath(b.path("vendor/sqlite-amalgamation-3530000"));
    lib_mod.link_libc = true;
    return lib_mod;
}

fn createCliExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
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
}
