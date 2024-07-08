//! Data structures made up of linked nodes that hold data.

pub const List = @import("list.zig").List;
pub const Stack = @import("stack.zig").Stack;
pub const Queue = @import("queue.zig").Queue;
pub const CircularList = @import("circular_list.zig").CircularList;

pub const AvlTree = @import("avl_tree.zig").AvlTree;

test "zig_structures.linked" {
    const testing = @import("std").testing;
    testing.refAllDecls(@This());
}
