/// Documentation root for the zypher project.
///
/// This module points the documentation generator at the public framework API.
/// `zypher.zig` re-exports the framework namespaces and CLI runner surface.
pub const zypher = @import("zypher");

test {
    @import("std").testing.refAllDecls(@This());
}
