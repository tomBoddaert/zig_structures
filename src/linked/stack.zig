const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A stack backed by a singly linked list.
pub fn Stack(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate nodes.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The top of the stack.
        top: ?*Node = null,

        const Self = @This();
        const Node = struct {
            next: ?*Node = null,
            data: T,
        };
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new stack.
        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        /// Deallocate the stack and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            var node_ptr = self.top;

            self.top = null;

            while (node_ptr) |node| {
                const next_ptr = node.next;

                deinit_t(&node.data);
                self.allocator.destroy(node);

                node_ptr = next_ptr;
            }
        }

        /// Returns `true` if the stack is empty.
        pub fn is_empty(self: *Self) bool {
            return self.top == null;
        }

        /// Get a pointer to the data at the top of the stack.
        ///
        /// Returns `null` if the stack is empty.
        pub fn get_top(self: *Self) ?*T {
            return &(self.top orelse return null).data;
        }

        /// Push a new node to the stack.
        pub fn push(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = Node{
                .next = self.top,
                .data = data,
            };

            self.top = node;
        }

        /// Removes the node at the top of the stack and returns its data.
        ///
        /// Returns `null` if the stack is empty.
        pub fn pop(self: *Self) ?T {
            const top = self.top orelse return null;
            self.top = top.next;

            const data = top.data;

            self.allocator.destroy(top);
            return data;
        }

        /// Deletes the node at the top of the stack and deinits the data
        /// if a deinit function is set.
        ///
        /// If the stack is empty, this does nothing.
        pub fn delete_top(self: *Self) void {
            const top = self.top orelse return;
            self.top = top.next;

            deinit_t(&top.data);
            self.allocator.destroy(top);
        }

        /// Gets a cursor to the node at the top of the stack.
        ///
        /// If the stack is empty, this returns a null cursor.
        pub fn cursor(self: *Self) Cursor {
            return Cursor{
                .stack = self,
                .node = self.top,
            };
        }

        /// A cursor to a node in a stack backed by a singly linked list.
        pub const Cursor = struct {
            /// Private: this is not part of the public API.
            ///
            /// The stack that this cursor is in.
            stack: *Self,
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

            /// Returns true if this cursor is null (is not pointing to a node).
            pub inline fn is_null(self: *Cursor) bool {
                return self.node == null;
            }

            /// Get a pointer to the data in the current node.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn get(self: *Cursor) Error!*T {
                return &(self.node orelse
                    return Error.OperationOnNullCursor).data;
            }

            /// Moves to the next node in the stack.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn next(self: *Cursor) Error!void {
                const node = (self.node orelse
                    return Error.OperationOnNullCursor);

                self.previous = node;
                self.node = node.next;
            }

            /// Moves `n` nodes forwards in the stack.
            ///
            /// Returns `Error.OperationOnNullCursor` if moving past the end.
            pub inline fn move_forward(self: *Cursor, n: usize) Error!void {
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

                const new_node = try self.stack.allocator.create(Node);
                new_node.* = Node{ .next = node, .data = data };

                if (self.previous) |previous_node| {
                    previous_node.next = new_node;
                } else {
                    self.stack.top = new_node;
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

                const new_node = try self.stack.allocator.create(Node);
                new_node.* = Node{ .next = node.next, .data = data };

                node.next = new_node;
            }

            /// Inserts a new node before the current node and move to it.
            ///
            /// Returns `InsertError.OperationOnNullCursor` if this is a null cursor.
            /// Returns `InsertError.OutOfMemory` if the allocation fails.
            pub fn insert_before_to(self: *Cursor, data: T) InsertError!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                const new_node = try self.stack.allocator.create(Node);
                new_node.* = Node{ .next = node, .data = data };

                if (self.previous) |previous_node| {
                    previous_node.next = new_node;
                } else {
                    self.stack.top = new_node;
                }

                self.node = new_node;
            }

            inline fn remove_patch(stack: *Self, node: *Node, previous: ?*Node) void {
                if (previous) |previous_node| {
                    previous_node.next = node.next;
                } else {
                    stack.top = node.next;
                }
            }

            /// Removes the current node, returns its data, and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn remove_to_next(self: *Cursor) Error!T {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;
                const data = node.data;

                remove_patch(self.stack, node, self.previous);
                self.node = node.next;

                self.stack.allocator.destroy(node);

                return data;
            }

            /// Deletes the current node, deinitialising its data if a deinit function is set,
            /// and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn delete_to_next(self: *Cursor) Error!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                remove_patch(self.stack, node, self.previous);
                self.node = node.next;

                deinit_t(&node.data);
                self.stack.allocator.destroy(node);
            }

            /// Moves the cursor to the top of the stack.
            pub fn move_to_top(self: *Cursor) void {
                self.node = self.stack.top;
                self.previous = null;
            }
        };

        /// Apply a function to all elements of the stack.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn apply(self: *Self, f: *const fn (T) T) void {
            var node = self.top;

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

        /// Reduce the stack to a single value from the top down.
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

test "zig_structures.linked.stack" {
    const testing = @import("std").testing;
    testing.refAllDecls(@This());

    interfaces.assert_deinit(Stack(u8));
}

test "zig_structures.linked.stack.Stack(_).{push,is_empty,deinit}" {
    const testing = @import("std").testing;
    const allocator = testing.allocator;

    TestType.deinit_called = false;

    var stack = Stack(TestType).init(allocator);
    errdefer stack.deinit();
    try testing.expect(stack.is_empty());

    const Node = Stack(TestType).Node;

    var node1: *Node = undefined;
    {
        try stack.push(.{ .value = 1 });

        try testing.expect(!stack.is_empty());

        node1 = stack.top.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(null, node1.next);
    }

    var node2: *Node = undefined;
    {
        try stack.push(.{ .value = 2 });

        try testing.expect(!stack.is_empty());

        node2 = stack.top.?;
        try testing.expectEqual(2, node2.data.value);
        try testing.expectEqual(node1, node2.next);
    }

    try testing.expect(!TestType.deinit_called);

    stack.deinit();
    try testing.expect(TestType.deinit_called);
    try testing.expect(stack.is_empty());
    try testing.expectEqual(null, stack.top);
}

fn test_create(allocator: Allocator) Allocator.Error!Stack(TestType) {
    TestType.reset();

    var stack = Stack(TestType).init(allocator);
    errdefer stack.deinit();

    try stack.push(.{ .value = 2 });
    try stack.push(.{ .value = 1 });

    return stack;
}

test "zig_structures.linked.stack.Stack(_).{get_top,pop}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = try test_create(allocator);
    defer stack.deinit();

    {
        const top = stack.get_top().?;
        try testing.expectEqual(&stack.top.?.data, top);
        try testing.expectEqual(1, top.value);
    }

    {
        const data = stack.pop().?;
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(null, stack.top.?.next);
    }

    {
        const top = stack.get_top().?;
        try testing.expectEqual(&stack.top.?.data, top);
        try testing.expectEqual(2, top.value);
    }

    {
        const data = stack.pop().?;
        try testing.expectEqual(2, data.value);
    }

    try testing.expectEqual(null, stack.top);

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.stack.Stack(_).delete_top" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = try test_create(allocator);
    defer stack.deinit();

    stack.delete_top();
    try testing.expectEqual(null, stack.top.?.next);

    try testing.expect(TestType.deinit_called);
    TestType.reset();

    stack.delete_top();

    try testing.expect(TestType.deinit_called);

    try testing.expectEqual(null, stack.top);
}

test "zig_structures.linked.stack.Stack(_).{cursor,Cursor.get}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = try test_create(allocator);
    defer stack.deinit();

    var cursor = stack.cursor();
    try testing.expectEqual(stack.top, cursor.node);
    try testing.expectEqual(null, cursor.previous);

    const data = try cursor.get();
    try testing.expectEqual(&stack.top.?.data, data);
    try testing.expectEqual(1, data.value);
}

test "zig_structures.linked.stack.Stack(_).Cursor.{next,is_null}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = try test_create(allocator);
    defer stack.deinit();

    var cursor = stack.cursor();
    try testing.expect(!cursor.is_null());

    try cursor.next();
    try testing.expect(!cursor.is_null());
    try testing.expectEqual(stack.top.?.next, cursor.node);
    try testing.expectEqual(stack.top, cursor.previous);

    const data = try cursor.get();
    try testing.expectEqual(2, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
    try testing.expectEqual(null, cursor.node);

    try testing.expectError(
        Stack(TestType).Cursor.Error.OperationOnNullCursor,
        cursor.get(),
    );
    try testing.expectError(
        Stack(TestType).Cursor.Error.OperationOnNullCursor,
        cursor.next(),
    );
}

test "zig_structures.linked.stack.Stack(_).Cursor.insert_before" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();

        try cursor.insert_before(.{ .value = 11 });

        try testing.expectEqual(11, stack.top.?.data.value);
        try testing.expectEqual(stack.top, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();

        try cursor.insert_before(.{ .value = 22 });

        try testing.expectEqual(22, stack.top.?.next.?.data.value);
        try testing.expectEqual(stack.top.?.next, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Stack(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_before(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.stack.Stack(_).Cursor.insert_after" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();

        try cursor.insert_after(.{ .value = 11 });

        try testing.expectEqual(11, stack.top.?.next.?.data.value);
        try testing.expectEqual(stack.top, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(1, data.value);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();

        try cursor.insert_after(.{ .value = 22 });

        try testing.expectEqual(22, cursor.node.?.next.?.data.value);
        try testing.expectEqual(stack.top, cursor.previous);
        try testing.expectEqual(stack.top.?.next, cursor.node);

        const data = try cursor.get();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Stack(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_after(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.stack.Stack(_).Cursor.insert_before_to" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();

        try cursor.insert_before_to(.{ .value = 11 });

        try testing.expectEqual(11, stack.top.?.data.value);
        try testing.expectEqual(null, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(11, data.value);

        try testing.expectEqual(1, cursor.node.?.next.?.data.value);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();

        try cursor.insert_before_to(.{ .value = 22 });

        try testing.expectEqual(22, stack.top.?.next.?.data.value);
        try testing.expectEqual(stack.top, cursor.previous);

        const data = try cursor.get();
        try testing.expectEqual(22, data.value);

        try testing.expectEqual(cursor.node, cursor.previous.?.next);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();
        try cursor.next();
        try testing.expect(cursor.is_null());

        try testing.expectError(
            Stack(TestType).Cursor.InsertError.OperationOnNullCursor,
            cursor.insert_before_to(.{ .value = 33 }),
        );
    }
}

test "zig_structures.linked.stack.Stack(_).Cursor.remove_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(1, data.value);

        try testing.expect(!cursor.is_null());
        try testing.expectEqual(stack.top, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const top = stack.top.?;
        try testing.expectEqual(2, top.data.value);

        try testing.expect(!TestType.deinit_called);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(null, cursor.node);
        try testing.expectEqual(stack.top, cursor.previous);

        try testing.expect(!TestType.deinit_called);
    }
}

test "zig_structures.linked.stack.Stack(_).Cursor.delete_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expect(!cursor.is_null());
        try testing.expectEqual(stack.top, cursor.node);
        try testing.expectEqual(null, cursor.previous);

        const top = stack.top.?;
        try testing.expectEqual(2, top.data.value);
    }

    {
        var stack = try test_create(allocator);
        defer stack.deinit();

        var cursor = stack.cursor();
        try cursor.next();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(null, cursor.node);
        try testing.expectEqual(stack.top, cursor.previous);
    }
}

test "zig_structures.linked.stack.Stack(_).apply" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: TestType) TestType {
            return .{ .value = data.value * 11 };
        }
    };

    var stack = try test_create(allocator);
    defer stack.deinit();
    stack.apply(__.f);

    var cursor = stack.cursor();

    var data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(22, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.stack.Stack(_).filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: *const TestType) bool {
            return data.value != 2;
        }
    };

    var stack = try test_create(allocator);
    defer stack.deinit();
    stack.filter(__.f);

    try testing.expect(TestType.deinit_called);

    var cursor = stack.cursor();

    const data = try cursor.get();
    try testing.expectEqual(1, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.stack.Stack(_).filter_apply" {
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

    var stack = try test_create(allocator);
    defer stack.deinit();
    stack.filter_apply(__.f);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);

    var cursor = stack.cursor();

    const data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.stack.Stack(_).fold" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(acc: u8, x: TestType) u8 {
            return acc * 10 + x.value;
        }
    };

    var stack = try test_create(allocator);
    defer stack.deinit();

    const result = stack.fold(u8, 0, __.f);
    try testing.expectEqual(12, result);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);
}
