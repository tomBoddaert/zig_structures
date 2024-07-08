//! Data structures backed by a contiguous slice of memory.

pub const List = @import("list.zig").List;
pub const Stack = @import("stack.zig").Stack;
pub const Queue = @import("queue.zig").Queue;
const heap = @import("heap.zig");
pub const Heap = heap.Heap;
pub const HeapType = heap.HeapType;
pub const heapsort = heap.heapsort;

test "zig_structures.array" {
    const testing = @import("std").testing;
    testing.refAllDecls(@This());
}
