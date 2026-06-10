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

    const zypher_mod = b.createModule(.{
        .root_source_file = b.path("../../src/zypher.zig"),
        .target = target,
        .optimize = optimize,
    });
    zypher_mod.linkLibrary(sqlite3_lib);
    zypher_mod.addIncludePath(b.path("../../vendor/sqlite-amalgamation-3530000"));
    zypher_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "books-api",
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
    b.step("run", "Run the books API").dependOn(&run_cmd.step);
    const app_docs = b.addTest(.{ .root_module = exe.root_module });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = app_docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("doc", "Generate app documentation").dependOn(&install_docs.step);

    b.step("test", "Run books API tests").dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
}
