/// IO Configuration — provides a unified API for choosing IO backends.
/// This module allows library users to easily select their preferred IO model
/// while maintaining the invariant that std.Io is always caller-supplied.
const std = @import("std");

/// Available IO model types.
pub const IoModel = enum {
    /// Default IO backend provided by std.process.Init
    default,
    /// Custom user-provided IO instance
    custom,
};

/// Configuration for IO model selection.
pub const IoConfig = struct {
    /// The IO model to use
    model: IoModel = .default,
    /// Custom IO instance (required when model is .custom)
    custom_io: ?std.Io = null,

    /// Create an IoConfig with default settings.
    pub fn init() IoConfig {
        return .{};
    }

    /// Create an IoConfig for the default IO model.
    pub fn default() IoConfig {
        return .{ .model = .default };
    }

    /// Create an IoConfig with a custom IO instance.
    pub fn custom(io: std.Io) IoConfig {
        return .{ .model = .custom, .custom_io = io };
    }

    /// Create or retrieve the std.Io instance based on configuration.
    /// For .default model, returns the io from std.process.Init.
    /// For .custom model, returns the provided custom_io.
    pub fn createIo(self: IoConfig, process_init: std.process.Init) !std.Io {
        return switch (self.model) {
            .default => process_init.io,
            .custom => self.custom_io orelse error.MissingCustomIo,
        };
    }
};
