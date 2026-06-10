const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .musl } });
    const optimize = b.standardOptimizeOption(.{});
    const zypher_root = b.option([]const u8, "zypher-root", "Path to the Zypher source tree") orelse "../..";
    const sqlite_root = b.pathJoin(&.{ zypher_root, "vendor/sqlite-amalgamation-3530000" });

    const sqlite3_mod = b.createModule(.{ .target = target, .optimize = optimize });
    sqlite3_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = sqlite_root },
        .files = &.{"sqlite3.c"},
        .flags = &.{ "-std=c11", "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" },
    });
    sqlite3_mod.addIncludePath(.{ .cwd_relative = sqlite_root });
    sqlite3_mod.link_libc = true;
    const sqlite3_lib = b.addLibrary(.{ .name = "sqlite3", .root_module = sqlite3_mod });

    const zypher_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zypher_root, "src/zypher.zig" }) },
        .target = target,
        .optimize = optimize,
    });
    zypher_mod.linkLibrary(sqlite3_lib);
    zypher_mod.addIncludePath(.{ .cwd_relative = sqlite_root });
    zypher_mod.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "{{project_name}}",
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
    b.step("run", "Run the app").dependOn(&run_cmd.step);
    b.step("test", "Run app tests").dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
}
