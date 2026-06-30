const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl },
    });
    const optimize = b.standardOptimizeOption(.{});

    // ── Extract version from build.zig.zon (overridable via -Dversion) ─
    const version_option = b.option([]const u8, "version", "Override the version string (e.g. 0.2.0)");
    const version_string = if (version_option) |v| v else blk: {
        const zon = @embedFile("build.zig.zon");
        const marker = ".version = \"";
        const start = std.mem.indexOf(u8, zon, marker) orelse break :blk "0.0.0";
        const value_start = start + marker.len;
        const end = std.mem.indexOfScalar(u8, zon[value_start..], '"') orelse break :blk "0.0.0";
        break :blk zon[value_start..][0..end];
    };
    // ── Optional backend flags ───────────────────────────────────────
    const db_postgres = b.option(bool, "db_postgres", "Enable PostgreSQL driver support (vendored libpq)") orelse false;
    const db_mysql = b.option(bool, "db_mysql", "Enable MySQL/MariaDB driver support (vendored libmariadb)") orelse false;
    const db_mongodb = b.option(bool, "db_mongodb", "Enable MongoDB document store (vendored libmongoc)") orelse false;
    const db_redis = b.option(bool, "db_redis", "Enable Redis KV store (vendored hiredis)") orelse false;
    const io_evented = b.option(bool, "io_evented", "Enable experimental std.Io.Evented backend (io_uring on Linux, GCD on macOS). " ++
        "Networking support is incomplete on some platforms. Not a release blocker.") orelse false;

    const opts = b.addOptions();
    opts.addOption([]const u8, "version", version_string);
    opts.addOption(bool, "has_postgres", db_postgres);
    opts.addOption(bool, "has_mysql", db_mysql);
    opts.addOption(bool, "has_mongodb", db_mongodb);
    opts.addOption(bool, "has_redis", db_redis);
    const build_config_mod = opts.createModule();

    const io_opts = b.addOptions();
    io_opts.addOption(bool, "io_evented", io_evented);
    const io_options_mod = io_opts.createModule();

    // ── Vendored SQLite3 ─────────────────────────────────────────────
    const sqlite3_lib = createSqlite3Library(b, target, optimize);

    // ── Library module ──────────────────────────────────────────────
    const lib_mod = b.addModule("zypher", .{
        .root_source_file = b.path("src/zypher.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_config", .module = build_config_mod },
            .{ .name = "options", .module = io_options_mod },
        },
    });
    lib_mod.linkLibrary(sqlite3_lib);
    lib_mod.addIncludePath(b.path("vendor/sqlite-amalgamation-3530000"));
    lib_mod.link_libc = true;
    if (db_postgres) {
        addLibpqSources(lib_mod, b);
        lib_mod.linkSystemLibrary("pthread", .{});
    }
    if (db_mysql) {
        const mysql_lib = createMysqlClientLibrary(b, target, optimize);
        lib_mod.linkLibrary(mysql_lib);
        lib_mod.addIncludePath(b.path("vendor/mariadb-connector-c-3.4.2/include"));
        if (!db_postgres) {
            lib_mod.linkSystemLibrary("pthread", .{});
        }
    }
    if (db_mongodb) {
        addMongocSources(lib_mod, b);
    }
    if (db_redis) {
        const hiredis_lib = createHiredisLibrary(b, target, optimize);
        lib_mod.linkLibrary(hiredis_lib);
        lib_mod.addIncludePath(b.path("vendor/hiredis-1.0.2"));
    }

    // ── Generate embedded templates ────────────────────────────────
    const gen_templates_mod = b.createModule(.{
        .root_source_file = b.path("tools/generate_templates.zig"),
        .target = b.resolveTargetQuery(.{}),
    });
    const gen_templates = b.addExecutable(.{
        .name = "gen-embedded-templates",
        .root_module = gen_templates_mod,
    });
    const run_gen_templates = b.addRunArtifact(gen_templates);
    const gen_templates_step = b.step("gen-templates", "Regenerate embedded_templates.zig from templates/");
    gen_templates_step.dependOn(&run_gen_templates.step);

    // ── CLI executable ──────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "zypher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
                .{ .name = "build_config", .module = build_config_mod },
            },
        }),
    });
    b.installArtifact(exe);
    exe.step.dependOn(&run_gen_templates.step);

    // ── Cross-target CLI binaries ──────────────────────────────────
    const all_targets_step = b.step("all-targets", "Build zypher CLI binaries for all supported targets");
    const release_opts = b.addOptions();
    release_opts.addOption([]const u8, "version", version_string);
    release_opts.addOption(bool, "has_postgres", false);
    release_opts.addOption(bool, "has_mysql", false);
    release_opts.addOption(bool, "has_mongodb", false);
    release_opts.addOption(bool, "has_redis", false);
    const release_build_config_mod = release_opts.createModule();

    for (release_targets) |release_target| {
        const release_resolved_target = b.resolveTargetQuery(release_target.query);
        const release_sqlite3_lib = createSqlite3Library(b, release_resolved_target, optimize);
        const release_lib_mod = createZypherModule(b, release_resolved_target, optimize, release_sqlite3_lib, release_build_config_mod);
        const release_exe = createCliExecutable(b, release_resolved_target, optimize, release_lib_mod, release_build_config_mod);
        const install_release_exe = b.addInstallArtifact(release_exe, .{
            .dest_sub_path = b.fmt("{s}/zypher{s}", .{ release_target.name, release_target.exe_suffix }),
        });
        release_exe.step.dependOn(&run_gen_templates.step);

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

    // ── Examples compilation checks ────────────────────────────────
    const check_examples_step = b.step("check-examples", "Build all example apps");

    inline for (comptime [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "notes-app", .path = "examples/notes-app/src/main.zig" },
        .{ .name = "books-api", .path = "examples/books-api/src/main.zig" },
        .{ .name = "online-storage", .path = "examples/online-storage/src/main.zig" },
    }) |example| {
        const example_exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zypher", .module = lib_mod },
                },
            }),
        });
        check_examples_step.dependOn(&example_exe.step);
    }

    // ── Test infrastructure ─────────────────────────────────────────
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    // sqlite3 linking inherited from lib_mod

    const exe_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const test_helpers_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/io.zig"),
        .target = target,
    });

    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/test_runner.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zypher", .module = lib_mod },
            .{ .name = "test_io", .module = test_helpers_mod },
            .{ .name = "build_config", .module = build_config_mod },
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
            .{ .name = "test_io", .module = test_helpers_mod },
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
            .{ .name = "test_io", .module = test_helpers_mod },
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
            .{ .name = "test_io", .module = test_helpers_mod },
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

    // ── Phase 14 — IO backend test targets ─────────────────────────
    {
        const concurrent_fallback_test_mod = b.createModule(.{
            .root_source_file = b.path("tests/unit/core/concurrent_fallback_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
                .{ .name = "options", .module = io_options_mod },
            },
        });
        concurrent_fallback_test_mod.single_threaded = true;

        const io_single_test = b.addTest(.{
            .root_module = concurrent_fallback_test_mod,
        });

        const test_io_single_step = b.step("test-io-single", "Run IO tests with -fsingle-threaded");
        test_io_single_step.dependOn(&b.addRunArtifact(io_single_test).step);
    }

    {
        const cancel_audit_test_mod = b.createModule(.{
            .root_source_file = b.path("tests/unit/io/cancel_audit_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
                .{ .name = "options", .module = io_options_mod },
            },
        });

        const cancel_audit_test = b.addTest(.{
            .root_module = cancel_audit_test_mod,
        });

        const test_cancel_audit_step = b.step("test-cancel-audit", "Run cancellation contract audit tests");
        test_cancel_audit_step.dependOn(&b.addRunArtifact(cancel_audit_test).step);
    }

    // ── I/O Cleanliness Guard ──────────────────────────────────────
    // Asserts that src/ (the library core) contains no direct POSIX syscalls,
    // no std.Thread usage, and no synchronous I/O primitives.
    // All I/O must flow through the injected std.Io vtable.
    const io_clean_step = b.step("test-io-clean", "Assert no forbidden OS primitives in src/");
    const io_clean_check = b.addSystemCommand(&.{
        "sh", "-c",
        \\grep -rn 'std\.posix\|std\.net\.\|std\.os\.linux\|std\.time\.Instant\|std\.io\.GenericReader\|AnyReader\|FixedBufferStream\|std\.Thread\|std\.io\.getStd' src/ \
        \\  --include='*.zig' \
        \\  --exclude-dir='orm/driver/' \
        \\  --exclude-dir='orm/document/' \
        \\  --exclude-dir='orm/kv/' \
        \\  --exclude='embedded_templates.zig' \
        \\  --exclude='main.zig' \
        \\  --exclude='runner.zig' \
        \\  --exclude='io_backend.zig' \
        \\  | grep -v '^\s*//' > /tmp/zypher_io_clean.txt; \
        \\if [ -s /tmp/zypher_io_clean.txt ]; then \
        \\  echo 'ERROR: Forbidden OS primitives found in src/'; \
        \\  cat /tmp/zypher_io_clean.txt; \
        \\  exit 1; \
        \\else \
        \\  echo 'OK: No forbidden OS primitives in src/'; \
        \\fi
    });
    io_clean_step.dependOn(&io_clean_check.step);

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

fn createHiredisLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const hiredis_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    hiredis_mod.addCSourceFiles(.{
        .root = b.path("vendor/hiredis-1.0.2"),
        .files = &.{ "hiredis.c", "net.c", "sds.c", "read.c", "alloc.c", "dict.c", "async.c" },
        .flags = &.{"-std=c99"},
    });
    hiredis_mod.addIncludePath(b.path("vendor/hiredis-1.0.2"));
    hiredis_mod.link_libc = true;

    return b.addLibrary(.{
        .name = "hiredis",
        .root_module = hiredis_mod,
    });
}

fn addLibpqSources(lib_mod: *std.Build.Module, b: *std.Build) void {
    const root = "vendor/postgresql-17.4";
    // libpq core (14 files, excludes GSSAPI/OpenSSL/Windows variants)
    lib_mod.addCSourceFiles(.{
        .root = b.path(root),
        .files = &.{
            "src/interfaces/libpq/fe-auth.c",
            "src/interfaces/libpq/fe-auth-scram.c",
            "src/interfaces/libpq/fe-cancel.c",
            "src/interfaces/libpq/fe-connect.c",
            "src/interfaces/libpq/fe-exec.c",
            "src/interfaces/libpq/fe-lobj.c",
            "src/interfaces/libpq/fe-misc.c",
            "src/interfaces/libpq/fe-print.c",
            "src/interfaces/libpq/fe-protocol3.c",
            "src/interfaces/libpq/fe-secure.c",
            "src/interfaces/libpq/fe-trace.c",
            "src/interfaces/libpq/libpq-events.c",
            "src/interfaces/libpq/pqexpbuffer.c",
        },
        .flags = &.{ "-std=c11", "-D_GNU_SOURCE" },
    });
    // common support (needed by libpq)
    // Compile with -DFRONTEND so these files use the frontend (libpq) include
    // path instead of the backend (postgres.h) include path, avoiding
    // references to backend-only symbols (errstart, palloc, etc.).
    lib_mod.addCSourceFiles(.{
        .root = b.path(root),
        .files = &.{
            "src/common/base64.c",
            "src/common/cryptohash.c",
            "src/common/encnames.c",
            "src/common/fe_memutils.c",
            "src/common/fe_stubs.c",
            "src/common/hmac.c",
            "src/common/ip.c",
            "src/common/link-canary.c",
            "src/common/md5.c",
            "src/common/md5_common.c",
            "src/common/pg_prng.c",
            "src/common/saslprep.c",
            "src/common/scram-common.c",
            "src/common/sha1.c",
            "src/common/sha2.c",
            "src/common/string.c",
            "src/common/username.c",
            "src/common/wchar.c",
        },
        .flags = &.{ "-std=c11", "-D_GNU_SOURCE", "-DFRONTEND" },
    });
    // portability layer (needed by libpq)
    // musl's strerror_r uses POSIX (returns int), not GNU (returns char*)
    const port_cflags = &.{ "-std=c11", "-D_GNU_SOURCE", "-DSTRERROR_R_INT", "-DFRONTEND" };
    lib_mod.addCSourceFiles(.{
        .root = b.path(root),
        .files = &.{
            "src/port/bsearch_arg.c",
            "src/port/chklocale.c",
            "src/port/getpeereid.c",
            "src/port/inet_net_ntop.c",
            "src/port/noblock.c",
            "src/port/path.c",
            "src/port/pg_bitutils.c",
            "src/port/pgcheckdir.c",
            "src/port/pgmkdirp.c",
            "src/port/pgsleep.c",
            "src/port/pgstrcasecmp.c",
            "src/port/pg_strong_random.c",
            "src/port/pgstrsignal.c",
            "src/port/pqsignal.c",
            "src/port/qsort.c",
            "src/port/qsort_arg.c",
            "src/port/quotes.c",
            "src/port/snprintf.c",
            "src/port/strerror.c",
            "src/port/tar.c",
            "src/port/user.c",
        },
        .flags = port_cflags,
    });
    lib_mod.addIncludePath(b.path(root ++ "/src/include"));
    lib_mod.addIncludePath(b.path(root ++ "/src/port"));
    lib_mod.addIncludePath(b.path(root ++ "/src/common"));
    lib_mod.addIncludePath(b.path(root ++ "/src/interfaces/libpq"));
}

fn createZypherModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sqlite3_lib: *std.Build.Step.Compile,
    build_config_mod: *std.Build.Module,
) *std.Build.Module {
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/zypher.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_config", .module = build_config_mod },
        },
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
    build_config_mod: *std.Build.Module,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zypher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zypher", .module = lib_mod },
                .{ .name = "build_config", .module = build_config_mod },
            },
        }),
    });
}

fn createMysqlClientLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const root = "vendor/mariadb-connector-c-3.4.2";
    const cflags = &.{ "-std=c11", "-D_GNU_SOURCE" };
    const mysql_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    mysql_mod.addCSourceFiles(.{
        .root = b.path(root),
        .files = &.{
            "libmariadb/bmove_upp.c",
            "libmariadb/get_password.c",
            "libmariadb/ma_alloc.c",
            "libmariadb/ma_array.c",
            "libmariadb/ma_charset.c",
            "libmariadb/ma_client_plugin.c",
            "libmariadb/ma_compress.c",
            "libmariadb/ma_context.c",
            "libmariadb/ma_decimal.c",
            "libmariadb/ma_default.c",
            "libmariadb/ma_dtoa.c",
            "libmariadb/ma_errmsg.c",
            "libmariadb/ma_hashtbl.c",
            "libmariadb/ma_init.c",
            "libmariadb/ma_io.c",
            "libmariadb/ma_list.c",
            "libmariadb/ma_ll2str.c",
            "libmariadb/ma_loaddata.c",
            "libmariadb/ma_net.c",
            "libmariadb/ma_password.c",
            "libmariadb/ma_pvio.c",
            "libmariadb/ma_string.c",
            "libmariadb/ma_time.c",
            "libmariadb/ma_tls.c",
            "libmariadb/mariadb_async.c",
            "libmariadb/mariadb_charset.c",
            "libmariadb/mariadb_lib.c",
            "libmariadb/mariadb_stmt.c",
            "libmariadb/ma_stmt_codec.c",
            "libmariadb/secure/fallback.c",
        },
        .flags = cflags,
    });

    mysql_mod.addCSourceFiles(.{
        .root = b.path(root),
        .files = &.{
            "plugins/auth/dialog.c",
            "plugins/auth/mariadb_cleartext.c",
            "plugins/auth/my_auth.c",
            "plugins/pvio/pvio_socket.c",
        },
        .flags = cflags,
    });

    mysql_mod.addIncludePath(b.path(root ++ "/include"));
    mysql_mod.link_libc = true;
    mysql_mod.linkSystemLibrary("pthread", .{});

    return b.addLibrary(.{
        .name = "mysqlclient",
        .root_module = mysql_mod,
    });
}

fn addMongocSources(lib_mod: *std.Build.Module, b: *std.Build) void {
    const root = "vendor/mongo-c-driver-1.28.1";
    const mongoc_cflags = &.{ "-std=c11", "-D_GNU_SOURCE", "-DBSON_COMPILATION", "-DMONGOC_COMPILATION" };

    lib_mod.addIncludePath(b.path(root ++ "/src/libbson/src"));
    lib_mod.addIncludePath(b.path(root ++ "/src/libbson/src/bson"));
    lib_mod.addIncludePath(b.path(root ++ "/src/libmongoc/src"));
    lib_mod.addIncludePath(b.path(root ++ "/src/libmongoc/src/mongoc"));
    lib_mod.addIncludePath(b.path(root ++ "/src/common"));
    lib_mod.addIncludePath(b.path(root ++ "/src/libbson/src/jsonsl"));
    lib_mod.addIncludePath(b.path(root ++ "/src/uthash"));

    lib_mod.addCSourceFiles(.{
        .root = b.path(root ++ "/src/libbson/src/bson"),
        .files = &.{
            "bcon.c",
            "bson-atomic.c",
            "bson.c",
            "bson-clock.c",
            "bson-context.c",
            "bson-decimal128.c",
            "bson-error.c",
            "bson-iso8601.c",
            "bson-iter.c",
            "bson-json.c",
            "bson-keys.c",
            "bson-md5.c",
            "bson-memory.c",
            "bson-oid.c",
            "bson-reader.c",
            "bson-string.c",
            "bson-timegm.c",
            "bson-utf8.c",
            "bson-value.c",
            "bson-version-functions.c",
            "bson-writer.c",
        },
        .flags = mongoc_cflags,
    });

    lib_mod.addCSourceFiles(.{
        .root = b.path(root ++ "/src/libbson/src/jsonsl"),
        .files = &.{"jsonsl.c"},
        .flags = mongoc_cflags,
    });

    lib_mod.addCSourceFiles(.{
        .root = b.path(root ++ "/src/common"),
        .files = &.{
            "common-b64.c",
            "common-md5.c",
            "common-thread.c",
        },
        .flags = mongoc_cflags,
    });

    lib_mod.addCSourceFiles(.{
        .root = b.path(root ++ "/src/libmongoc/src/mongoc"),
        .files = &.{
            "mcd-nsinfo.c",
            "mcd-rpc.c",
            "mongoc-aggregate.c",
            "mongoc-apm.c",
            "mongoc-array.c",
            "mongoc-async.c",
            "mongoc-async-cmd.c",
            "mongoc-buffer.c",
            "mongoc-bulk-operation.c",
            "mongoc-bulkwrite.c",
            "mongoc-change-stream.c",
            "mongoc-client.c",
            "mongoc-client-side-encryption.c",
            "mongoc-compression.c",
            "mongoc-client-pool.c",
            "mongoc-client-session.c",
            "mongoc-cluster.c",
            "mongoc-cluster-aws.c",
            "mongoc-cluster-sasl.c",
            "mongoc-cmd.c",
            "mongoc-collection.c",
            "mongoc-counters.c",
            "mongoc-cursor-array.c",
            "mongoc-cursor.c",
            "mongoc-cursor-change-stream.c",
            "mongoc-cursor-cmd.c",
            "mongoc-cursor-cmd-deprecated.c",
            "mongoc-cursor-find.c",
            "mongoc-cursor-find-cmd.c",
            "mongoc-cursor-find-opquery.c",
            "mongoc-cursor-legacy.c",
            "mongoc-database.c",
            "mongoc-deprioritized-servers.c",
            "mongoc-error.c",
            "mongoc-find-and-modify.c",
            "mongoc-flags.c",
            "mongoc-generation-map.c",
            "mongoc-gridfs-bucket.c",
            "mongoc-gridfs-bucket-file.c",
            "mongoc-gridfs.c",
            "mongoc-gridfs-file.c",
            "mongoc-gridfs-file-list.c",
            "mongoc-gridfs-file-page.c",
            "mongoc-handshake.c",
            "mongoc-host-list.c",
            "mongoc-http.c",
            "mongoc-index.c",
            "mongoc-init.c",
            "mongoc-interrupt.c",
            "mongoc-linux-distro-scanner.c",
            "mongoc-list.c",
            "mongoc-log.c",
            "mongoc-matcher.c",
            "mongoc-matcher-op.c",
            "mongoc-memcmp.c",
            "mongoc-opcode.c",
            "mongoc-optional.c",
            "mongoc-opts.c",
            "mongoc-opts-helpers.c",
            "mongoc-queue.c",
            "mongoc-read-concern.c",
            "mongoc-read-prefs.c",
            "mongoc-rpc.c",
            "mongoc-server-api.c",
            "mongoc-server-description.c",
            "mongoc-server-monitor.c",
            "mongoc-server-stream.c",
            "mongoc-set.c",
            "mongoc-shared.c",
            "mongoc-socket.c",
            "mongoc-stream-buffered.c",
            "mongoc-stream.c",
            "mongoc-stream-file.c",
            "mongoc-stream-gridfs.c",
            "mongoc-stream-gridfs-download.c",
            "mongoc-stream-gridfs-upload.c",
            "mongoc-stream-socket.c",
            "mongoc-timeout.c",
            "mongoc-topology-background-monitoring.c",
            "mongoc-topology.c",
            "mongoc-topology-description-apm.c",
            "mongoc-topology-description.c",
            "mongoc-topology-scanner.c",
            "mongoc-ts-pool.c",
            "mongoc-uri.c",
            "mongoc-util.c",
            "mongoc-version-functions.c",
            "mongoc-write-command.c",
            "mongoc-write-concern.c",
        },
        .flags = mongoc_cflags,
    });
}
