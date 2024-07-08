const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A queue backed by a singly linked list.
pub fn Queue(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate nodes.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The front of the queue.
        front: ?*Node = null,
        /// Private: this is not part of the public API.
        ///
        /// The back of the queue.
        back: ?*Node = null,

        const Self = @This();
        const Node = struct {
            next: ?*Node = null,
            data: T,
        };
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new queue.
        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        /// Deallocate the queue and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            var node_ptr = self.front;

            self.front = null;
            self.back = null;

            while (node_ptr) |node| {
                const next_ptr = node.next;

                deinit_t(&node.data);
                self.allocator.destroy(node);

                node_ptr = next_ptr;
            }
        }

        /// Returns `true` if the queue is empty.
        pub fn is_empty(self: *Self) bool {
            return self.front == null;
        }

        /// Get a pointer to the data at the front of the queue.
        ///
        /// Returns `null` if the queue is empty.
        pub fn get_front(self: *Self) ?*T {
            return &(self.front orelse return null).data;
        }

        /// Push a new node to the back of the queue.
        pub fn push(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = Node{
                .data = data,
            };

            if (self.back) |back| {
                back.next = node;
            } else {
                self.front = node;
            }

            self.back = node;
        }

        /// Removes the node at the front of the queue and returns its data.
        ///
        /// Returns `null` if the queue is empty.
        pub fn pop(self: *Self) ?T {
            const front = self.front orelse return null;

            const data = front.data;

            if (front.next == null) {
                self.back = null;
            }

            self.front = front.next;

            self.allocator.destroy(front);

            return data;
        }

        /// Deletes the node at the front of the queue and deinits the data
        /// if a deinit function is set.
        ///
        /// If the queue is empty, this does nothing.
        pub fn delete_front(self: *Self) void {
            const front = self.front orelse return;

            if (front.next == null) {
                self.back = null;
            }

            self.front = front.next;

            deinit_t(&front.data);
            self.allocator.destroy(front);
        }

        /// Gets a cursor to the node at the front of the queue.
        ///
        /// If the queue is empty, this returns a null cursor.
        pub fn cursor(self: *Self) Cursor {
            return Cursor{
                .queue = self,
                .node = self.front,
            };
        }

        /// A cursor to a node in a queue backed by a singly linked list.
        pub const Cursor = struct {
            /// Private: this is not part of the public API.
            ///
            /// The queue that this cursor is in.
            queue: *Self,
            /// Private: this is not part of the public API.
            ///
            /// The node that this cursor is currently pointing to.
            /// This may be `null`, in which case, the cursor is a 'null cursor'.
            node: ?*Node,
            /// Private: this is not part of the public API.
            ///
            /// The node before the node that this cursor is currently pointing to.
            /// This may be `null`.
            previous: ?*Node = null,

            /// The error returned by cursor operations.
            pub const Error = error{OperationOnNullCursor};
            /// The error returned by cursor insert operations.
            pub const InsertError = error{
                OperationOnNullCursor,
                OutOfMemory,
            };

            /// Returns `true` if this cursor is null (is not pointing to a node).
            pub fn is_null(self: *Cursor) bool {
                return self.node == null;
            }

            /// Get a pointer to the data in the current node.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn get(self: *Cursor) Error!*T {
                return &(self.node orelse
                    return Error.OperationOnNullCursor).data;
            }

            /// Moves to the next node in the queue. This moves towards the back.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn next(self: *Cursor) Error!void {
                const node = (self.node orelse
                    return Error.OperationOnNullCursor);

                self.previous = node;
                self.node = node.next;
            }

            /// Moves `n` nodes backwards in the queue.
            ///
            /// Returns `Error.OperationOnNullCursor` if moving past the end.
            pub inline fn move_backward(self: *Cursor, n: usize) Error!void {
                for (0..n) |_| {
                    try self.next();
                }
            }

            /// Inserts a new node before the current node.
            ///
            /// Returns `InsertError.OperationOnNullCursor` if this is a null cursor.
            /// Returns `InsertError.OutOfMemory` if the allocation fails.
            pub fn insert_before(self: *Cursor, data: T) InsertError!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                const new_node = try self.queue.allocator.create(Node);
                new_node.* = Node{ .next = node, .data = data };

                if (self.previous) |previous_node| {
                    previous_node.next = new_node;
                } else {
                    self.queue.front = new_node;
                }

                self.previous = new_node;
            }

            /// Inserts a new node after the current node.
            ///
            /// Returns `InsertError.OperationOnNullCursor` if this is a null cursor.
            /// Returns `InsertError.OutOfMemory` if the allocation fails.
            pub fn insert_after(self: *Cursor, data: T) InsertError!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                const new_node = try self.queue.allocator.create(Node);
                new_node.* = Node{ .next = node.next, .data = data };

                if (node.next == null) {
                    self.queue.back = new_node;
                }

                node.next = new_node;
            }

            /// Inserts a new node before the current node and move to it.
            ///
            /// Returns `InsertError.OperationOnNullCursor` if this is a null cursor.
            /// Returns `InsertError.OutOfMemory` if the allocation fails.
            pub fn insert_before_to(self: *Cursor, data: T) InsertError!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                const new_node = try self.queue.allocator.create(Node);
                new_node.* = Node{ .next = node, .data = data };

                if (self.previous) |previous_node| {
                    previous_node.next = new_node;
                } else {
                    self.queue.front = new_node;
                }

                self.node = new_node;
            }

            inline fn remove_patch(queue: *Self, node: *Node, previous: ?*Node) void {
                if (previous) |previous_node| {
                    previous_node.next = node.next;
                } else {
                    queue.front = node.next;
                }

                if (node.next == null) {
                    queue.back = previous;
                }
            }

            /// Removes the current node, returns its data, and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn remove_to_next(self: *Cursor) Error!T {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;
                const data = node.data;

                remove_patch(self.queue, node, self.previous);
                self.node = node.next;

                self.queue.allocator.destroy(node);

                return data;
            }

            /// Deletes the current node, deinitalising its data if a deinit function is set,
            /// and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn delete_to_next(self: *Cursor) Error!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                remove_patch(self.queue, node, self.previous);
                self.node = node.next;

                deinit_t(&node.data);
                self.queue.allocator.destroy(node);
            }

            /// Moves the cursor to the front of the queue.
            pub fn move_to_front(self: *Cursor) void {
                self.node = self.queue.front;
                self.previous = null;
            }
        };

        /// Apply a function to all elements of the queue.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn apply(self: *Self, f: *const fn (T) T) void {
            var node = self.front;

            while (node) |current| {
                current.data = f(current.data);
                node = current.next;
            }
        }

        /// Remove elements that do not match a predicate.
        pub fn filter(self: *Self, f: *const fn (*const T) bool) void {
            var cursor_ = self.cursor();

            while (cursor_.get() catch null) |element| {
                if (f(element)) {
                    cursor_.next() catch {};
                } else {
                    cursor_.delete_to_next() catch {};
                }
            }
        }

        /// Apply a function to all elements. If the function returns
        /// `null`, the element is removed.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn filter_apply(self: *Self, f: *const fn (T) ?T) void {
            var cursor_ = self.cursor();

            while (cursor_.node) |node| {
                if (f(node.data)) |data| {
                    node.data = data;
                    cursor_.node = node.next;
                    cursor_.previous = node;
                } else {
                    // Delete without deiniting, as this should be handled by `f`
                    Cursor.remove_patch(self, node, cursor_.previous);
                    cursor_.node = node.next;

                    self.allocator.destroy(node);
                }
            }
        }

        /// Reduce the queue to a single value from front to back.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn fold(self: *Self, comptime R: type, initial: R, f: *const fn (R, T) R) R {
            var cursor_ = self.cursor();

            var result = initial;
            while (cursor_.remove_to_next() catch null) |element| {
                result = f(result, element);
            }

            return result;
        }
    };
}

const TestType = interfaces.DeinitTest(u8);

test "zig_structures.linked.queue" {
    const testing = @import("std").testing;
    testing.refAllDecls(@This());

    interfaces.assert_deinit(Queue(u8));
}

test "zig_structures.linked.queue.Queue(_).{push,is_empty,deinit}" {
    const testing = @import("std").testing;
    const allocator = testing.allocator;

    TestType.deinit_called = false;

    var queue = Queue(TestType).init(allocator);
    errdefer queue.deinit();
    try testing.expect(queue.is_empty());

    const Node = Queue(TestType).Node;

    var node1: *Node = undefined;
    {
        try queue.push(.{ .value = 1 });

        try testing.expect(!queue.is_empty());

        node1 = queue.front.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(null, node1.next);
    }

    var node2: *Node = undefined;
    {
        try queue.push(.{ .value = 2 });

        try testing.expect(!queue.is_empty());

        node2 = queue.back.?;
        try testing.expectEqual(2, node2.data.value);
    }

    try testing.expectEqual(node2, node1.next);

    try testing.expect(!TestType.deinit_called);

    queue.deinit();
    try testing.expect(TestType.deinit_called);
    try testing.expect(queue.is_empty());
    try testing.expectEqual(null, queue.front);
    try testing.expectEqual(null, queue.back);
}

fn test_create(allocator: Allocator) Allocator.Error!Queue(TestType) {
    TestType.reset();

    var queue = Queue(TestType).init(allocator);
    errdefer queue.deinit();

    try queue.push(.{ .value = 1 });
    try queue.push(.{ .value = 2 });

    return queue;
}

test "zig_structures.linked.queue.Queue(_).{get_front,pop}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = try test_create(allocator);
    defer queue.deinit();

    {
        const front = queue.get_front().?;
        try testing.expectEqual(&queue.front.?.data, front);
        try testing.expectEqual(1, front.value);
    }

    {
        const data = queue.pop().?;
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(null, queue.front.?.next);
    }

    {
        const front = queue.get_front().?;
        try testing.expectEqual(&queue.front.?.data, front);
        try testing.expectEqual(2, front.value);
    }

    {
        const data = queue.pop().?;
        try testing.expectEqual(2, data.value);
    }

    try testing.expectEqual(null, queue.front);

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.queue.Queue(_).delete_front" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = try test_create(allocator);
    defer queue.deinit();

    queue.delete_front();
    try testing.expectEqual(null, queue.front.?.next);

    try testing.expect(TestType.deinit_called);
    TestType.reset();

    queue.delete_front();

    try testing.expect(TestType.deinit_called);

    try testing.expectEqual(null, queue.front);
}

test "zig_structures.linked.queue.Queue(_).{cursor,Cursor.get}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = try test_create(allocator);
    defer queue.deinit();

    var cursor = queue.cursor();
    try testing.expectEqual(queue.front, cursor.node);
    try testing.expectEqual(null, cursor.previous);

    const data = try cursor.get();
    try testing.expectEqual(&queue.front.?.data, data);
    try testing.expectEqual(1, data.value);
}

test "zig_structures.linked.queue.Queue(_).Cursor.{next,is_null}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = try test_create(allocator);
    defer queue.deinit();

    var cursor = queue.cursor();
    try testing.expect(!cursor.is_null());

    try cursor.next();
    try testing.expect(!cursor.is_null());
    try testing.expectEqual(queue.front.?.next, cursor.node);
    try testing.expectEqual(queue.front, cursor.previous);

    const data = try cursor.get();
    try testing.expectEqual(2, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
    try testing.expectEqual(null, cursor.node);

    try testing.expectError(
        Queue(TestType).Cursor.Error.OperationOnNullCursor,
        cursor.get(),
    );
    try testing.expectError(
        Queue(TestType).Cursor.Error.OperationOnNullCursor,
        cursor.next(),
    );
}

test "zig_structures.linked.queue.Queue(_).Cursor.insert_before" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();

        try cursor.insert_before(.{ .value = 11 });

        try testing.expectEqual(11, queue.front.?.data.value);
        try testing.expectEqual(queue.front, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();

        try cursor.insert_before(.{ .value = 22 });

        try testing.expectEqual(22, queue.front.?.next.?.data.value);
        try testing.expectEqual(queue.front.?.next, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Queue(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_before(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.queue.Queue(_).Cursor.insert_after" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();

        try cursor.insert_after(.{ .value = 11 });

        try testing.expectEqual(11, queue.front.?.next.?.data.value);
        try testing.expectEqual(queue.front, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(1, data.value);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();

        try cursor.insert_after(.{ .value = 22 });

        try testing.expectEqual(22, cursor.node.?.next.?.data.value);
        try testing.expectEqual(queue.front, cursor.previous);
        try testing.expectEqual(queue.front.?.next, cursor.node);

        const data = try cursor.get();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Queue(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_after(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.queue.Queue(_).Cursor.insert_before_to" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();

        try cursor.insert_before_to(.{ .value = 11 });

        try testing.expectEqual(11, queue.front.?.data.value);
        try testing.expectEqual(null, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(11, data.value);

        try testing.expectEqual(1, cursor.node.?.next.?.data.value);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();

        try cursor.insert_before_to(.{ .value = 22 });

        try testing.expectEqual(22, queue.front.?.next.?.data.value);
        try testing.expectEqual(queue.front, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(22, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Queue(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_before_to(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.queue.Queue(_).Cursor.remove_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(1, data.value);

        try testing.expect(!cursor.is_null());
        try testing.expectEqual(queue.front, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const front = queue.front.?;
        try testing.expectEqual(2, front.data.value);

        try testing.expect(!TestType.deinit_called);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(null, cursor.node);
        try testing.expectEqual(queue.front, cursor.previous);

        try testing.expect(!TestType.deinit_called);
    }
}

test "zig_structures.linked.queue.Queue(_).Cursor.delete_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expect(!cursor.is_null());
        try testing.expectEqual(queue.front, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const front = queue.front.?;
        try testing.expectEqual(2, front.data.value);
    }

    {
        var queue = try test_create(allocator);
        defer queue.deinit();

        var cursor = queue.cursor();
        try cursor.next();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(null, cursor.node);
        try testing.expectEqual(queue.front, cursor.previous);
    }
}

test "zig_structures.linked.queue.Queue(_).apply" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: TestType) TestType {
            return .{ .value = data.value * 11 };
        }
    };

    var queue = try test_create(allocator);
    defer queue.deinit();
    queue.apply(__.f);

    var cursor = queue.cursor();

    var data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(22, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.queue.Queue(_).filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: *const TestType) bool {
            return data.value != 2;
        }
    };

    var queue = try test_create(allocator);
    defer queue.deinit();
    queue.filter(__.f);

    try testing.expect(TestType.deinit_called);

    var cursor = queue.cursor();

    const data = try cursor.get();
    try testing.expectEqual(1, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.queue.Queue(_).filter_apply" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: TestType) ?TestType {
            return if (data.value != 2)
                .{ .value = data.value * 11 }
            else
                null;
        }
    };

    var queue = try test_create(allocator);
    defer queue.deinit();
    queue.filter_apply(__.f);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);

    var cursor = queue.cursor();

    const data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.queue.Queue(_).fold" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(acc: u8, x: TestType) u8 {
            return acc * 10 + x.value;
        }
    };

    var queue = try test_create(allocator);
    defer queue.deinit();

    const result = queue.fold(u8, 0, __.f);
    try testing.expectEqual(12, result);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);
}
