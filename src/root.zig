pub const interfaces = @import("interfaces.zig");

pub const linked = @import("linked/root.zig");
pub const array = @import("array/root.zig");

test "test the modules" {
    const testing = @import("std").testing;
    testing.refAllDecls(@This());
}
