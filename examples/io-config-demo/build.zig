const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .musl } });
    const optimize = b.standardOptimizeOption(.{});

    const sqlite3_mod = b.createModule(.{ .target = target, .optimize = optimize });
    sqlite3_mod.addCSourceFiles(.{
        .root = b.path("../../vendor/sqlite-amalgamation-3530000"),
        .files = &.{"sqlite3.c"},
        .flags = &.{ "-std=c11", "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" },
    });
    sqlite3_mod.addIncludePath(b.path("../../vendor/sqlite-amalgamation-3530000"));
    sqlite3_mod.link_libc = true;
    const sqlite3_lib = b.addLibrary(.{ .name = "sqlite3", .root_module = sqlite3_mod });

    const opts = b.addOptions();
    opts.addOption([]const u8, "version", "0.1.0-beta");
    const build_config_mod = opts.createModule();

    const zypher_mod = b.createModule(.{
        .root_source_file = b.path("../../src/zypher.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_config", .module = build_config_mod },
        },
    });
    zypher_mod.linkLibrary(sqlite3_lib);
    zypher_mod.addIncludePath(b.path("../../vendor/sqlite-amalgamation-3530000"));
    zypher_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "io-config-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zypher", .module = zypher_mod }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run the IO config demo").dependOn(&run_cmd.step);

    const test_exe = b.addTest(.{ .root_module = zypher_mod });
    const test_run = b.addRunArtifact(test_exe);
    b.step("test", "Run zypher tests").dependOn(&test_run.step);
}
