const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A doubly linked list.
pub fn List(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate nodes.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The head of the list.
        head: ?*Node = null,
        /// Private: this is not part of the public API.
        ///
        /// The tail of the list.
        tail: ?*Node = null,

        const Self = @This();
        const Node = struct {
            previous: ?*Node = null,
            next: ?*Node = null,
            data: T,
        };
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new doubly linked list.
        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        /// Deallocate the list and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            var node_ptr = self.head;

            self.head = null;
            self.tail = null;

            while (node_ptr) |node| {
                const next_ptr = node.next;

                deinit_t(&node.data);
                self.allocator.destroy(node);

                node_ptr = next_ptr;
            }
        }

        /// Returns `true` if the list is empty.
        pub fn is_empty(self: *const Self) bool {
            return self.head == null;
        }

        /// Get a pointer to the data at the head of the list.
        ///
        /// Returns `null` if the list is empty.
        pub fn get_head(self: *Self) ?*T {
            return &(self.head orelse return null).data;
        }

        /// Get a pointer to the data at the tail of the list.
        ///
        /// Returns `null` if the list is empty.
        pub fn get_tail(self: *Self) ?*T {
            return &(self.tail orelse return null).data;
        }

        /// Prepend the list with a new node.
        pub fn prepend(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = Node{
                .next = self.head,
                .data = data,
            };

            if (self.head) |head| {
                head.previous = node;
            } else {
                self.tail = node;
            }

            self.head = node;
        }

        /// Append a new node to the end of the list.
        pub fn append(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);
            node.* = Node{
                .previous = self.tail,
                .data = data,
            };

            if (self.tail) |tail| {
                tail.next = node;
            } else {
                self.head = node;
            }

            self.tail = node;
        }

        /// Removes the node at the head of the list and returns its data.
        ///
        /// Returns `null` if the list is empty.
        pub fn remove_head(self: *Self) ?T {
            const head = self.head orelse return null;

            const data = head.data;

            if (head.next) |next| {
                next.previous = null;
            } else {
                self.tail = null;
            }

            self.head = head.next;

            self.allocator.destroy(head);

            return data;
        }

        /// Removes the node at the tail of the list and returns its data.
        ///
        /// Returns `null` if the list is empty.
        pub fn remove_tail(self: *Self) ?T {
            const tail = self.tail orelse return null;

            const data = tail.data;

            if (tail.previous) |previous| {
                previous.next = null;
            } else {
                self.head = null;
            }

            self.tail = tail.previous;

            self.allocator.destroy(tail);

            return data;
        }

        /// Deletes the node at the head of the list and deinits the data
        /// if a deinit function is set.
        ///
        /// If the list is empty, this does nothing.
        pub fn delete_head(self: *Self) void {
            const head = self.head orelse return;

            if (head.next) |next| {
                next.previous = null;
            } else {
                self.tail = null;
            }

            self.head = head.next;

            deinit_t(&head.data);
            self.allocator.destroy(head);
        }

        /// Deletes the node at the tail of the list and deinits the data
        /// if a deinit function is set.
        ///
        /// If the list is empty, this does nothing.
        pub fn delete_tail(self: *Self) void {
            const tail = self.tail orelse return;

            if (tail.previous) |previous| {
                previous.next = null;
            } else {
                self.head = null;
            }

            self.tail = tail.previous;

            deinit_t(&tail.data);
            self.allocator.destroy(tail);
        }

        /// Gets a cursor to the node at the head of the list.
        ///
        /// If the list is empty, this returns a null cursor.
        pub fn cursor_head(self: *Self) Cursor {
            return Cursor{
                .list = self,
                .node = self.head,
            };
        }

        /// Gets a cursor to the node at the tail of the list.
        ///
        /// If the list is empty, this returns a null cursor.
        pub fn cursor_tail(self: *Self) Cursor {
            return Cursor{
                .list = self,
                .node = self.tail,
            };
        }

        /// A cursor to a node in a doubly linked list.
        pub const Cursor = struct {
            /// Private: this is not part of the public API.
            ///
            /// The list that this cursor is in.
            list: *Self,
            /// Private: this is not part of the public API.
            ///
            /// The node that this cursor is currently pointing to.
            /// This may be `null`, in which case, the cursor is a 'null cursor'.
            node: ?*Node,

            /// The error returned by cursor operations.
            pub const Error = error{
                OperationOnNullCursor,
            };
            /// The error returned by cursor insert operations.
            pub const InsertError = error{
                OperationOnNullCursor,
                OutOfMemory,
            };

            /// Returns `true` if this cursor is null (is not pointing to a node).
            pub fn is_null(self: *const Cursor) bool {
                return self.node == null;
            }

            /// Get a pointer to the data in the current node.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn get(self: *Cursor) Error!*T {
                return &(self.node orelse
                    return Error.OperationOnNullCursor).data;
            }

            /// Moves to the previous node in the list.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn previous(self: *Cursor) Error!void {
                self.node = (self.node orelse
                    return Error.OperationOnNullCursor)
                    .previous;
            }

            /// Moves to the next node in the list.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn next(self: *Cursor) Error!void {
                self.node = (self.node orelse
                    return Error.OperationOnNullCursor)
                    .next;
            }

            /// Moves `n` nodes backwards in the list.
            ///
            /// Returns `Error.OperationOnNullCursor` if moving past the end.
            pub inline fn move_backward(self: *Cursor, n: usize) Error!void {
                for (0..n) |_| {
                    try self.previous();
                }
            }

            /// Moves `n` nodes forwards in the list.
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

                const new_node = try self.list.allocator.create(Node);
                new_node.* = Node{ .previous = node.previous, .next = node, .data = data };

                if (node.previous) |previous_node| {
                    previous_node.next = new_node;
                } else {
                    self.list.head = new_node;
                }

                node.previous = new_node;
            }

            /// Inserts a new node after the current node.
            ///
            /// Returns `InsertError.OperationOnNullCursor` if this is a null cursor.
            /// Returns `InsertError.OutOfMemory` if the allocation fails.
            pub fn insert_after(self: *Cursor, data: T) InsertError!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                const new_node = try self.list.allocator.create(Node);
                new_node.* = Node{ .previous = node, .next = node.next, .data = data };

                if (node.next) |next_node| {
                    next_node.previous = new_node;
                } else {
                    self.list.tail = new_node;
                }

                node.next = new_node;
            }

            inline fn remove_patch(list: *Self, node: *Node) void {
                if (node.previous) |previous_node| {
                    previous_node.next = node.next;
                } else {
                    list.head = node.next;
                }

                if (node.next) |next_node| {
                    next_node.previous = node.previous;
                } else {
                    list.tail = node.previous;
                }
            }

            /// Removes the current node, returns its data, and moves to the previous one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn remove_to_previous(self: *Cursor) Error!T {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;
                const data = node.data;

                remove_patch(self.list, node);
                self.node = node.previous;

                self.list.allocator.destroy(node);

                return data;
            }

            /// Removes the current node, returns its data, and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn remove_to_next(self: *Cursor) Error!T {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;
                const data = node.data;

                remove_patch(self.list, node);
                self.node = node.next;

                self.list.allocator.destroy(node);

                return data;
            }

            /// Deletes the current node, deinitialising its data if a deinit function is set,
            /// and moves to the previous one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn delete_to_previous(self: *Cursor) Error!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                remove_patch(self.list, node);
                self.node = node.previous;

                deinit_t(&node.data);
                self.list.allocator.destroy(node);
            }

            /// Deletes the current node, deinitialising its data if a deinit function is set,
            /// and moves to the next one.
            ///
            /// Returns `Error.OperationOnNullCursor` if this is a null cursor.
            pub fn delete_to_next(self: *Cursor) Error!void {
                const node = self.node orelse
                    return Error.OperationOnNullCursor;

                remove_patch(self.list, node);
                self.node = node.next;

                deinit_t(&node.data);
                self.list.allocator.destroy(node);
            }

            /// Moves the cursor to the head of the list.
            pub fn move_to_head(self: *Cursor) void {
                self.node = self.list.head;
            }

            /// Moves the cursor to the head of the list.
            pub fn move_to_tail(self: *Cursor) void {
                self.node = self.list.tail;
            }
        };

        /// Apply a function to all elements of the list.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn apply(self: *Self, f: *const fn (T) T) void {
            var node = self.head;

            while (node) |current| {
                current.data = f(current.data);
                node = current.next;
            }
        }

        /// Remove elements that do not match a predicate.
        pub fn filter(self: *Self, f: *const fn (*const T) bool) void {
            var cursor = self.cursor_head();

            while (cursor.get() catch null) |element| {
                if (f(element)) {
                    cursor.next() catch {};
                } else {
                    cursor.delete_to_next() catch {};
                }
            }
        }

        /// Apply a function to all elements. If the function returns
        /// `null`, the element is removed.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn filter_apply(self: *Self, f: *const fn (T) ?T) void {
            var cursor = self.cursor_head();

            while (cursor.node) |node| {
                if (f(node.data)) |data| {
                    node.data = data;
                    cursor.node = node.next;
                } else {
                    // Delete without deiniting, as this should be handled by `f`
                    Cursor.remove_patch(self, node);
                    cursor.node = node.next;

                    self.allocator.destroy(node);
                }
            }
        }

        /// Reduce the list to a single value from left to right.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn fold(self: *Self, comptime R: type, initial: R, f: *const fn (R, T) R) R {
            var cursor = self.cursor_head();

            var result = initial;
            while (cursor.remove_to_next() catch null) |element| {
                result = f(result, element);
            }

            return result;
        }

        /// Reduce the list to a single value from right to left.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn foldr(self: *Self, comptime R: type, initial: R, f: *const fn (R, T) R) R {
            var cursor = self.cursor_tail();

            var result = initial;
            while (cursor.remove_to_previous() catch null) |element| {
                result = f(result, element);
            }

            return result;
        }
    };
}

const TestType = interfaces.DeinitTest(u16);

test "zig_structures.linked.list" {
    const testing = std.testing;
    testing.refAllDecls(@This());

    interfaces.assert_deinit(List(u8));
}

test "zig_structures.linked.list.List(_).{append,is_empty,deinit}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    TestType.reset();

    var list = List(TestType).init(allocator);
    errdefer list.deinit();
    try testing.expect(list.is_empty());

    const Node = List(TestType).Node;

    var node1: *Node = undefined;
    {
        try list.append(.{ .value = 1 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(list.tail, list.head);

        node1 = list.head.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(null, node1.previous);
        try testing.expectEqual(null, node1.next);
    }

    var node2: *Node = undefined;
    {
        try list.append(.{ .value = 2 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(node1, list.head);
        try testing.expect(node1 != list.tail);

        try testing.expectEqual(null, node1.previous);

        node2 = list.tail.?;
        try testing.expectEqual(2, node2.data.value);
        try testing.expectEqual(null, node2.next);
        try testing.expectEqual(node1, node2.previous);

        try testing.expectEqual(node2, node1.next);
    }

    try testing.expect(!TestType.deinit_called);

    list.deinit();
    try testing.expect(TestType.deinit_called);
    try testing.expect(list.is_empty());
    try testing.expectEqual(null, list.head);
    try testing.expectEqual(null, list.tail);
}

test "zig_structures.linked.list.List(_).prepend" {
    const testing = std.testing;
    const allocator = testing.allocator;

    TestType.reset();

    var list = List(TestType).init(allocator);
    defer list.deinit();

    const Node = List(TestType).Node;

    var node1: *Node = undefined;
    {
        try list.prepend(.{ .value = 1 });

        try testing.expectEqual(list.tail, list.head);

        node1 = list.tail.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(null, node1.previous);
        try testing.expectEqual(null, node1.next);
    }

    var node2: *Node = undefined;
    {
        try list.prepend(.{ .value = 2 });

        try testing.expectEqual(node1, list.tail);
        try testing.expect(node1 != list.head);

        try testing.expectEqual(null, node1.next);

        node2 = list.head.?;
        try testing.expectEqual(2, node2.data.value);
        try testing.expectEqual(null, node2.previous);
        try testing.expectEqual(node1, node2.next);

        try testing.expectEqual(node2, node1.previous);
    }

    try testing.expect(!TestType.deinit_called);
}

fn test_create(allocator: Allocator) Allocator.Error!List(TestType) {
    TestType.reset();

    var list = List(TestType).init(allocator);
    errdefer list.deinit();

    try list.append(.{ .value = 1 });
    try list.append(.{ .value = 2 });
    try list.append(.{ .value = 3 });

    return list;
}

test "zig_structures.linked.list.List(_).{get_head,get_tail}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        const head = list.get_head().?;
        try testing.expectEqual(&list.head.?.data, head);
        try testing.expectEqual(1, head.value);
    }

    {
        const tail = list.get_tail().?;
        try testing.expectEqual(&list.tail.?.data, tail);
        try testing.expectEqual(3, tail.value);
    }

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.list.List(_).{remove_head,remove_tail}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    const node2 = list.head.?.next.?;
    try testing.expectEqual(list.tail.?.previous, node2);

    {
        const head = list.remove_head().?;
        try testing.expectEqual(1, head.value);

        try testing.expectEqual(list.head, node2);

        try testing.expectEqual(null, node2.previous);
    }

    {
        const tail = list.remove_tail().?;
        try testing.expectEqual(3, tail.value);

        try testing.expectEqual(list.tail, node2);

        try testing.expectEqual(null, node2.next);
    }

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.list.List(_).{delete_head,delete_tail}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    const node2 = list.head.?.next.?;
    try testing.expectEqual(list.tail.?.previous, node2);

    {
        list.delete_head();

        try testing.expectEqual(list.head, node2);

        try testing.expectEqual(null, node2.previous);
    }
    try testing.expect(TestType.deinit_called);
    TestType.reset();

    {
        list.delete_tail();

        try testing.expectEqual(list.tail, node2);

        try testing.expectEqual(null, node2.next);
    }
    try testing.expect(TestType.deinit_called);
}

test "zig_structures.linked.list.List(_).{cursor_head,cursor_tail,Cursor.get}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        var cursor = list.cursor_head();
        try testing.expectEqual(&list, cursor.list);
        try testing.expectEqual(list.head, cursor.node);

        const data = try cursor.get();
        try testing.expectEqual(&list.head.?.data, data);
    }

    {
        var cursor = list.cursor_tail();
        try testing.expectEqual(&list, cursor.list);
        try testing.expectEqual(list.tail, cursor.node);

        const data = try cursor.get();
        try testing.expectEqual(&list.tail.?.data, data);
    }
}

test "zig_structures.linked.list.List(_).Cursor.{previous,next,is_null}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        var cursor = list.cursor_head();
        try testing.expect(!cursor.is_null());

        try cursor.next();
        try testing.expect(!cursor.is_null());
        try testing.expectEqual(list.head.?.next, cursor.node);

        cursor = list.cursor_tail();

        try cursor.next();
        try testing.expectEqual(null, cursor.node);
        try testing.expect(cursor.is_null());

        try testing.expectError(
            List(TestType).Cursor.Error.OperationOnNullCursor,
            cursor.next(),
        );
    }

    {
        var cursor = list.cursor_tail();
        try testing.expect(!cursor.is_null());

        try cursor.previous();
        try testing.expect(!cursor.is_null());
        try testing.expectEqual(list.tail.?.previous, cursor.node);

        cursor = list.cursor_head();

        try cursor.previous();
        try testing.expectEqual(null, cursor.node);
        try testing.expect(cursor.is_null());

        try testing.expectError(
            List(TestType).Cursor.Error.OperationOnNullCursor,
            cursor.previous(),
        );
    }
}

test "zig_structures.linked.list.List(_).Cursor.{move_forwards,move_backwards}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        var cursor = list.cursor_head();
        try cursor.move_forward(0);
        try testing.expectEqual(list.head, cursor.node);

        cursor = list.cursor_head();
        try cursor.move_forward(1);
        try testing.expectEqual(list.head.?.next, cursor.node);

        cursor = list.cursor_head();
        try cursor.move_forward(2);
        try testing.expectEqual(list.tail, cursor.node);

        cursor = list.cursor_head();
        try cursor.move_forward(3);
        try testing.expectEqual(null, cursor.node);

        cursor = list.cursor_head();
        try testing.expectError(
            List(TestType).Cursor.Error.OperationOnNullCursor,
            cursor.move_forward(4),
        );
    }

    {
        var cursor = list.cursor_tail();
        try cursor.move_backward(0);
        try testing.expectEqual(list.tail, cursor.node);

        cursor = list.cursor_tail();
        try cursor.move_backward(1);
        try testing.expectEqual(list.tail.?.previous, cursor.node);

        cursor = list.cursor_tail();
        try cursor.move_backward(2);
        try testing.expectEqual(list.head, cursor.node);

        cursor = list.cursor_tail();
        try cursor.move_backward(3);
        try testing.expectEqual(null, cursor.node);

        cursor = list.cursor_tail();
        try testing.expectError(
            List(TestType).Cursor.Error.OperationOnNullCursor,
            cursor.move_backward(4),
        );
    }
}

test "zig_structures.linked.list.List(_).Cursor.insert_before" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        var cursor = list.cursor_head();
        const node = cursor.node.?;
        try testing.expectEqual(list.head, node);

        try cursor.insert_before(.{ .value = 0 });
        try testing.expectEqual(node, cursor.node);

        const new = list.head.?;
        try testing.expect(node != new);
        try testing.expectEqual(0, new.data.value);

        try testing.expectEqual(null, new.previous);
        try testing.expectEqual(node, new.next);

        try testing.expectEqual(new, node.previous);
    }

    {
        var cursor = list.cursor_head();
        try cursor.next();
        const node = cursor.node.?;

        try cursor.insert_before(.{ .value = 11 });
        try testing.expectEqual(node, cursor.node);

        const new = list.head.?.next.?;
        try testing.expectEqual(11, new.data.value);

        try testing.expectEqual(list.head, new.previous);
        try testing.expectEqual(node, new.next);

        try testing.expectEqual(new, node.previous);
    }
}

test "zig_structures.linked.list.List(_).Cursor.insert_after" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    {
        var cursor = list.cursor_tail();
        const node = cursor.node.?;
        try testing.expectEqual(list.tail, node);

        try cursor.insert_after(.{ .value = 33 });
        try testing.expectEqual(node, cursor.node);

        const new = list.tail.?;
        try testing.expect(node != new);
        try testing.expectEqual(33, new.data.value);

        try testing.expectEqual(node, new.previous);
        try testing.expectEqual(null, new.next);

        try testing.expectEqual(new, node.next);
    }

    {
        var cursor = list.cursor_tail();
        try cursor.previous();
        const node = cursor.node.?;

        try cursor.insert_after(.{ .value = 22 });
        try testing.expectEqual(node, cursor.node);

        const new = list.tail.?.previous.?;
        try testing.expectEqual(22, new.data.value);

        try testing.expectEqual(node, new.previous);
        try testing.expectEqual(list.tail, new.next);

        try testing.expectEqual(new, node.next);
    }
}

test "zig_structures.linked.list.List(_).Cursor.remove_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(list.head, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(2, head.data.value);
        try testing.expectEqual(null, head.previous);
    }

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();
        try cursor.next();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(list.tail, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(1, head.data.value);
        try testing.expectEqual(list.tail, head.next);

        const tail = list.tail.?;
        try testing.expectEqual(3, tail.data.value);
        try testing.expectEqual(list.head, tail.previous);
    }

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_tail();

        const data = try cursor.remove_to_next();
        try testing.expectEqual(3, data.value);

        try testing.expectEqual(null, cursor.node);

        const tail = list.tail.?;
        try testing.expectEqual(2, tail.data.value);
        try testing.expectEqual(null, tail.next);
    }
}

test "zig_structures.linked.list.List(_).Cursor.remove_to_previous" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();

        const data = try cursor.remove_to_previous();
        try testing.expectEqual(1, data.value);

        try testing.expectEqual(null, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(2, head.data.value);
        try testing.expectEqual(null, head.previous);
    }

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();
        try cursor.next();

        const data = try cursor.remove_to_previous();
        try testing.expectEqual(2, data.value);

        try testing.expectEqual(list.head, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(1, head.data.value);
        try testing.expectEqual(list.tail, head.next);

        const tail = list.tail.?;
        try testing.expectEqual(3, tail.data.value);
        try testing.expectEqual(list.head, tail.previous);
    }

    {
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_tail();

        const data = try cursor.remove_to_previous();
        try testing.expectEqual(3, data.value);

        try testing.expectEqual(list.tail, cursor.node);

        const tail = list.tail.?;
        try testing.expectEqual(2, tail.data.value);
        try testing.expectEqual(null, tail.next);
    }
}

test "zig_structures.linked.list.List(_).Cursor.delete_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(list.head, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(2, head.data.value);
        try testing.expectEqual(null, head.previous);
    }

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();
        try cursor.next();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(list.tail, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(1, head.data.value);
        try testing.expectEqual(list.tail, head.next);

        const tail = list.tail.?;
        try testing.expectEqual(3, tail.data.value);
        try testing.expectEqual(list.head, tail.previous);
    }

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_tail();

        try cursor.delete_to_next();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(null, cursor.node);

        const tail = list.tail.?;
        try testing.expectEqual(2, tail.data.value);
        try testing.expectEqual(null, tail.next);
    }
}

test "zig_structures.linked.list.List(_).Cursor.delete_to_previous" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();

        try cursor.delete_to_previous();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(null, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(2, head.data.value);
        try testing.expectEqual(null, head.previous);
    }

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_head();
        try cursor.next();

        try cursor.delete_to_previous();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(list.head, cursor.node);

        const head = list.head.?;
        try testing.expectEqual(1, head.data.value);
        try testing.expectEqual(list.tail, head.next);

        const tail = list.tail.?;
        try testing.expectEqual(3, tail.data.value);
        try testing.expectEqual(list.head, tail.previous);
    }

    {
        // Resets 'TestType.deinit_called'
        var list = try test_create(allocator);
        defer list.deinit();

        var cursor = list.cursor_tail();

        try cursor.delete_to_previous();
        try testing.expect(TestType.deinit_called);

        try testing.expectEqual(list.tail, cursor.node);

        const tail = list.tail.?;
        try testing.expectEqual(2, tail.data.value);
        try testing.expectEqual(null, tail.next);
    }
}

test "zig_structures.linked.list.List(_).apply" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: TestType) TestType {
            return .{ .value = data.value * 11 };
        }
    };

    var list = try test_create(allocator);
    defer list.deinit();
    list.apply(__.f);

    var cursor = list.cursor_head();

    var data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(22, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(33, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.list.List(_).filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(data: *const TestType) bool {
            return data.value != 2;
        }
    };

    var list = try test_create(allocator);
    defer list.deinit();
    list.filter(__.f);

    try testing.expect(TestType.deinit_called);

    var cursor = list.cursor_head();

    var data = try cursor.get();
    try testing.expectEqual(1, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(3, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.list.List(_).filter_apply" {
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

    var list = try test_create(allocator);
    defer list.deinit();
    list.filter_apply(__.f);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);

    var cursor = list.cursor_head();

    var data = try cursor.get();
    try testing.expectEqual(11, data.value);

    try cursor.next();
    data = try cursor.get();
    try testing.expectEqual(33, data.value);

    try cursor.next();
    try testing.expect(cursor.is_null());
}

test "zig_structures.linked.list.List(_).fold" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(acc: u16, x: TestType) u16 {
            return acc * 10 + x.value;
        }
    };

    var list = try test_create(allocator);
    defer list.deinit();

    const result = list.fold(u16, 0, __.f);
    try testing.expectEqual(123, result);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.list.List(_).foldr" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const __ = struct {
        fn f(acc: u16, x: TestType) u16 {
            return acc * 10 + x.value;
        }
    };

    var list = try test_create(allocator);
    defer list.deinit();

    const result = list.foldr(u16, 0, __.f);
    try testing.expectEqual(321, result);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);
}
