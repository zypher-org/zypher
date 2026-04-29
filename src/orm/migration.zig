/// zypher ORM — database migration runner.
const std = @import("std");
const sqlite = @import("sqlite.zig");

const log = std.log.scoped(.migration);

pub const MigrationError = error{
    PrepareFailed,
    StepFailed,
    ExecFailed,
    BindFailed,
    ColumnFailed,
    AllocatorFailed,
    NoMigrationsToRollback,
};

/// A single migration with up/down SQL.
pub const Migration = struct {
    id: i64,
    name: [:0]const u8,
    up_sql: [:0]const u8,
    down_sql: [:0]const u8,
};

/// Status of a single migration.
pub const MigrationStatus = struct {
    id: i64,
    name: [:0]const u8,
    applied: bool,
};

/// Migration runner — manages the zypher_migrations history table.
pub const MigrationRunner = struct {
    db: *sqlite.Db,

    /// Initialize the runner. Call migrate() to apply migrations.
    pub fn init(db: *sqlite.Db) MigrationRunner {
        return .{ .db = db };
    }

    /// Ensure the migration history table exists.
    fn ensureHistoryTable(self: *MigrationRunner) MigrationError!void {
        self.db.exec(
            \\CREATE TABLE IF NOT EXISTS zypher_migrations (
            \\  id INTEGER PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  applied_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
            \\)
        ) catch return error.ExecFailed;
    }

    /// Check if a migration has been applied.
    fn isApplied(self: *MigrationRunner, id: i64) MigrationError!bool {
        var stmt = self.db.prepare("SELECT id FROM zypher_migrations WHERE id = ?") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
        const has_row = stmt.step() catch return error.StepFailed;
        return has_row;
    }

    /// Record a migration as applied.
    fn recordApplied(self: *MigrationRunner, m: Migration) MigrationError!void {
        var stmt = self.db.prepare("INSERT INTO zypher_migrations (id, name) VALUES (?, ?)") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = m.id }, 1) catch return error.BindFailed;
        stmt.bind(.{ .text = m.name }, 2) catch return error.BindFailed;
        _ = stmt.step() catch return error.StepFailed;
    }

    /// Remove a migration record (for rollback).
    fn removeRecord(self: *MigrationRunner, id: i64) MigrationError!void {
        var stmt = self.db.prepare("DELETE FROM zypher_migrations WHERE id = ?") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
        _ = stmt.step() catch return error.StepFailed;
    }

    /// Count the number of applied migrations.
    pub fn countApplied(self: *MigrationRunner) MigrationError!u64 {
        var stmt = self.db.prepare("SELECT COUNT(*) FROM zypher_migrations") catch return error.PrepareFailed;
        defer stmt.finalize();
        const has_row = stmt.step() catch return error.StepFailed;
        if (!has_row) return 0;
        const val = stmt.column(.integer, 0) catch return error.ColumnFailed;
        return @intCast(val.int);
    }

    /// Apply all pending migrations in order.
    pub fn migrate(self: *MigrationRunner, migrations: []const Migration) MigrationError!void {
        try self.ensureHistoryTable();
        for (migrations) |m| {
            if (try self.isApplied(m.id)) {
                log.info("skipping already-applied migration {d}: {s}", .{ m.id, m.name });
                continue;
            }
            self.db.exec(m.up_sql) catch {
                log.err("migration {d} ({s}) UP failed", .{ m.id, m.name });
                return error.ExecFailed;
            };
            try self.recordApplied(m);
            log.info("applied migration {d}: {s}", .{ m.id, m.name });
        }
    }

    /// Get the status of all migrations.
    pub fn status(self: *MigrationRunner, gpa: std.mem.Allocator, migrations: []const Migration) MigrationError![]MigrationStatus {
        try self.ensureHistoryTable();
        var list = std.ArrayList(MigrationStatus).empty;
        for (migrations) |m| {
            const applied = try self.isApplied(m.id);
            list.append(gpa, .{
                .id = m.id,
                .name = m.name,
                .applied = applied,
            }) catch return error.AllocatorFailed;
        }
        return list.toOwnedSlice(gpa) catch return error.AllocatorFailed;
    }

    /// Rollback the last N applied migrations (in reverse order).
    pub fn rollback(self: *MigrationRunner, migrations: []const Migration, n: usize) MigrationError!void {
        try self.ensureHistoryTable();

        // Find applied migrations in reverse order
        var rolled_back: usize = 0;
        var i: usize = migrations.len;
        while (i > 0 and rolled_back < n) {
            i -= 1;
            const m = migrations[i];
            if (!try self.isApplied(m.id)) continue;

            self.db.exec(m.down_sql) catch {
                log.err("migration {d} ({s}) DOWN failed", .{ m.id, m.name });
                return error.ExecFailed;
            };
            try self.removeRecord(m.id);
            log.info("rolled back migration {d}: {s}", .{ m.id, m.name });
            rolled_back += 1;
        }

        if (rolled_back == 0) {
            log.warn("no migrations to rollback", .{});
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
