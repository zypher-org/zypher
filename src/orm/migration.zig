const std = @import("std");
const iface = @import("driver/interface.zig");

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

pub const Migration = struct {
    id: i64,
    name: [:0]const u8,
    up_sql: [:0]const u8,
    down_sql: [:0]const u8,
};

pub const MigrationStatus = struct {
    id: i64,
    name: [:0]const u8,
    applied: bool,
};

const RelationalDb = iface.RelationalDb;

pub const MigrationRunner = struct {
    db: RelationalDb,

    pub fn init(db: RelationalDb) MigrationRunner {
        return .{ .db = db };
    }

    pub fn ensureHistoryTable(self: *MigrationRunner) MigrationError!void {
        const d = self.db.dialect();
        const int_type: []const u8 = if (std.mem.indexOf(u8, d.pk_type, "INTEGER") != null) "INTEGER" else "BIGINT";
        var buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(buf[0..], "CREATE TABLE IF NOT EXISTS zypher_migrations (id {s} PRIMARY KEY, name TEXT NOT NULL, applied_at {s} NOT NULL DEFAULT ({s}))", .{ int_type, int_type, d.timestamp_now }) catch return error.ExecFailed;
        buf[result.len] = 0;
        const sql: [:0]const u8 = buf[0..result.len :0];
        self.db.exec(sql) catch return error.ExecFailed;
    }

    fn isApplied(self: *MigrationRunner, id: i64) MigrationError!bool {
        var stmt = self.db.prepare("SELECT id FROM zypher_migrations WHERE id = ?") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
        const has_row = stmt.step() catch return error.StepFailed;
        return has_row;
    }

    fn recordApplied(self: *MigrationRunner, m: Migration) MigrationError!void {
        var stmt = self.db.prepare("INSERT INTO zypher_migrations (id, name) VALUES (?, ?)") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = m.id }, 1) catch return error.BindFailed;
        stmt.bind(.{ .text = m.name }, 2) catch return error.BindFailed;
        _ = stmt.step() catch return error.StepFailed;
    }

    fn removeRecord(self: *MigrationRunner, id: i64) MigrationError!void {
        var stmt = self.db.prepare("DELETE FROM zypher_migrations WHERE id = ?") catch return error.PrepareFailed;
        defer stmt.finalize();
        stmt.bind(.{ .int = id }, 1) catch return error.BindFailed;
        _ = stmt.step() catch return error.StepFailed;
    }

    pub fn countApplied(self: *MigrationRunner) MigrationError!u64 {
        var stmt = self.db.prepare("SELECT COUNT(*) FROM zypher_migrations") catch return error.PrepareFailed;
        defer stmt.finalize();
        const has_row = stmt.step() catch return error.StepFailed;
        if (!has_row) return 0;
        const val = stmt.column(.integer, 0) catch return error.ColumnFailed;
        return @intCast(val.int);
    }

    pub fn migrate(self: *MigrationRunner, migrations: []const Migration, io: std.Io) MigrationError!void {
        _ = io;
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

    pub fn rollback(self: *MigrationRunner, migrations: []const Migration, n: usize) MigrationError!void {
        try self.ensureHistoryTable();

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
