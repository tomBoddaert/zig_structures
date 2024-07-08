const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A circular doubly linked list.
pub fn CircularList(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate nodes.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The node currently being pointed to.
        node: ?*Node = null,

        const Self = @This();
        const Node = struct {
            previous: *Node,
            next: *Node,
            data: T,
        };
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new circular doubly linked list.
        pub fn init(allocator: Allocator) Self {
            return Self{ .allocator = allocator };
        }

        /// Deallocate the list and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            var node_ptr = self.node orelse return;

            while (true) {
                const next_ptr = node_ptr.next;

                deinit_t(&node_ptr.data);
                self.allocator.destroy(node_ptr);

                node_ptr = next_ptr;

                if (node_ptr == self.node) {
                    break;
                }
            }

            self.node = null;
        }

        /// Returns `true` if the list is empty.
        pub fn is_empty(self: *const Self) bool {
            return self.node == null;
        }

        /// Get a pointer to the data at the cursor.
        ///
        /// Returns `null` if the list is empty.
        pub fn get(self: *Self) ?*T {
            return &(self.node orelse return null).data;
        }

        /// Insert a new node before the current one. If the list is empty,
        /// this adds the node and makes it the cursor.
        pub fn insert_before(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);

            if (self.node) |cursor| {
                node.* = Node{
                    .previous = cursor.previous,
                    .next = cursor,
                    .data = data,
                };

                cursor.previous.next = node;
                cursor.previous = node;
            } else {
                node.* = Node{
                    .previous = node,
                    .next = node,
                    .data = data,
                };

                self.node = node;
            }
        }

        /// Insert a new node after the current one. If the list is empty,
        /// this adds the node and makes it the cursor.
        pub fn insert_after(self: *Self, data: T) Allocator.Error!void {
            const node = try self.allocator.create(Node);

            if (self.node) |cursor| {
                node.* = Node{
                    .previous = cursor,
                    .next = cursor.next,
                    .data = data,
                };

                cursor.next.previous = node;
                cursor.next = node;
            } else {
                node.* = Node{
                    .previous = node,
                    .next = node,
                    .data = data,
                };

                self.node = node;
            }
        }

        fn remove_patch(self: *Self, node: *Node) bool {
            if (node.previous == node) {
                self.node = null;

                return false;
            } else {
                node.previous.next = node.next;
                node.next.previous = node.previous;

                return true;
            }
        }

        /// Removes the current node, returns its data, and moves to the previous one.
        ///
        /// Returns `null` if the list is empty.
        pub fn remove_to_previous(self: *Self) ?T {
            const node = self.node orelse return null;
            const data = node.data;

            if (self.remove_patch(node)) {
                self.node = node.previous;
            }

            self.allocator.destroy(node);

            return data;
        }

        /// Removes the current node, returns its data, and moves to the next one.
        ///
        /// Returns `null` if the list is empty.
        pub fn remove_to_next(self: *Self) ?T {
            const node = self.node orelse return null;
            const data = node.data;

            if (self.remove_patch(node)) {
                self.node = node.next;
            }

            self.allocator.destroy(node);

            return data;
        }

        /// Deletes the current node, deinitialising its data if a deinit function is set,
        /// and moves to the previous one.
        ///
        /// If the list is empty, this does nothing.
        pub fn delete_to_previous(self: *Self) void {
            const node = self.node orelse return;

            if (self.remove_patch(node)) {
                self.node = node.previous;
            }

            deinit_t(&node.data);
            self.list.allocator.destroy(node);
        }

        /// Deletes the current node, deinitialising its data if a deinit function is set,
        /// and moves to the next one.
        ///
        /// If the list is empty, this does nothing.
        pub fn delete_to_next(self: *Self) void {
            const node = self.node orelse return;

            if (self.remove_patch(node)) {
                self.node = node.next;
            }

            deinit_t(&node.data);
            self.allocator.destroy(node);
        }

        /// Moves to the previous node in the list.
        ///
        /// If the list is empty, this does nothing.
        pub fn previous(self: *Self) void {
            self.node = (self.node orelse return).previous;
        }

        /// Moves to the next node in the list.
        ///
        /// If the list is empty, this does nothing.
        pub fn next(self: *Self) void {
            self.node = (self.node orelse return).next;
        }

        /// Moves `n` nodes backwards in the list.
        ///
        /// If the list is empty, this does nothing.
        pub inline fn move_backward(self: *Self, n: usize) void {
            for (0..n) |_| {
                self.previous();
            }
        }

        /// Moves `n` nodes forwards in the list.
        ///
        /// If the list is empty, this does nothing.
        pub inline fn move_forward(self: *Self, n: usize) void {
            for (0..n) |_| {
                self.next();
            }
        }

        /// Apply a function to all elements of the circular list.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn apply(self: *Self, f: *const fn (T) T) void {
            var node = self.node orelse return;

            while (true) {
                node.data = f(node.data);
                node = node.next;

                if (node == self.node) {
                    break;
                }
            }
        }

        /// Remove elements that do not match a predicate.
        ///
        /// If the current node is removed, the next node that has not been removed is selected.
        pub fn filter(self: *Self, f: *const fn (*const T) bool) void {
            const node = self.node orelse return;
            var current = node.next;

            while (current != node) {
                if (f(&current.data)) {
                    current = current.next;
                    continue;
                }

                current.next.previous = current.previous;
                current.previous.next = current.next;

                const next_ = current.next;

                Self.deinit_t(&current.data);
                self.allocator.destroy(current);

                current = next_;
            }

            if (f(&node.data)) return;

            if (self.remove_patch(node)) {
                self.node = node.next;
            }

            Self.deinit_t(&node.data);
            self.allocator.destroy(node);
        }

        /// Apply a function to all elements. If the function returns
        /// `null`, the element is removed.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn filter_apply(self: *Self, f: *const fn (T) ?T) void {
            const node = self.node orelse return;
            var current = node.next;

            while (current != node) {
                if (f(current.data)) |data| {
                    current.data = data;
                    current = current.next;
                    continue;
                }

                current.next.previous = current.previous;
                current.previous.next = current.next;

                const next_ = current.next;

                self.allocator.destroy(current);

                current = next_;
            }

            if (f(current.data)) |data| {
                current.data = data;
                return;
            }

            if (self.remove_patch(current)) {
                self.node = current.next;
            }

            self.allocator.destroy(current);
        }

        /// Reduce the list to a single value in the forwards direction.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn fold(self: *Self, comptime R: type, initial: R, f: *const fn (R, T) R) R {
            var result = initial;
            while (self.remove_to_next()) |element| {
                result = f(result, element);
            }

            return result;
        }

        /// Reduce the list to a single value in the backwards direction.
        ///
        /// If `f` discards an instance of `T`, it must properly deinit it.
        pub fn foldr(self: *Self, comptime R: type, initial: R, f: *const fn (R, T) R) R {
            var result = initial;
            while (self.remove_to_previous()) |element| {
                result = f(result, element);
            }

            return result;
        }
    };
}

const TestType = interfaces.DeinitTest(u16);

test "zig_structures.linked.circular_list" {
    const testing = std.testing;
    testing.refAllDecls(@This());

    interfaces.assert_deinit(CircularList(u8));
}

test "zig_structures.linked.circular_list.CircularList(_).{insert_after,is_empty,deinit}" {
    const testing = std.testing;
    const allocator = testing.allocator;

    TestType.reset();

    var list = CircularList(TestType).init(allocator);
    errdefer list.deinit();
    try testing.expect(list.is_empty());

    const Node = CircularList(TestType).Node;

    var node1: *Node = undefined;
    {
        try list.insert_after(.{ .value = 1 });

        try testing.expect(!list.is_empty());

        node1 = list.node.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(node1, node1.previous);
        try testing.expectEqual(node1, node1.next);
    }

    var node2: *Node = undefined;
    {
        try list.insert_after(.{ .value = 2 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(node1, list.node);

        node2 = node1.next;
        try testing.expect(node1 != node2);
        try testing.expectEqual(2, node2.data.value);
        try testing.expectEqual(node1, node2.previous);
        try testing.expectEqual(node1, node2.next);

        try testing.expectEqual(node2, node1.previous);
        try testing.expectEqual(node2, node1.next);
    }

    var node3: *Node = undefined;
    {
        try list.insert_after(.{ .value = 3 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(node1, list.node);

        node3 = node1.next;
        try testing.expectEqual(3, node3.data.value);
        try testing.expectEqual(node1, node3.previous);
        try testing.expectEqual(node2, node3.next);

        try testing.expectEqual(node3, node2.previous);
        try testing.expectEqual(node3, node1.next);
    }

    try testing.expect(!TestType.deinit_called);

    list.deinit();
    try testing.expect(TestType.deinit_called);
    try testing.expect(list.is_empty());
    try testing.expectEqual(null, list.node);
}

test "zig_structures.linked.circular_list.CircularList(_).insert_before" {
    const testing = std.testing;
    const allocator = testing.allocator;

    TestType.reset();

    var list = CircularList(TestType).init(allocator);
    defer list.deinit();

    const Node = CircularList(TestType).Node;

    var node1: *Node = undefined;
    {
        try list.insert_before(.{ .value = 1 });

        try testing.expect(!list.is_empty());

        node1 = list.node.?;
        try testing.expectEqual(1, node1.data.value);
        try testing.expectEqual(node1, node1.previous);
        try testing.expectEqual(node1, node1.next);
    }

    var node2: *Node = undefined;
    {
        try list.insert_before(.{ .value = 2 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(node1, list.node);

        node2 = node1.previous;
        try testing.expect(node1 != node2);
        try testing.expectEqual(2, node2.data.value);
        try testing.expectEqual(node1, node2.previous);
        try testing.expectEqual(node1, node2.next);

        try testing.expectEqual(node2, node1.previous);
        try testing.expectEqual(node2, node1.next);
    }

    var node3: *Node = undefined;
    {
        try list.insert_before(.{ .value = 3 });

        try testing.expect(!list.is_empty());
        try testing.expectEqual(node1, list.node);

        node3 = node1.previous;
        try testing.expectEqual(3, node3.data.value);
        try testing.expectEqual(node2, node3.previous);
        try testing.expectEqual(node1, node3.next);

        try testing.expectEqual(node3, node1.previous);
        try testing.expectEqual(node3, node2.next);
    }

    try testing.expect(!TestType.deinit_called);
}

fn test_create(allocator: Allocator) Allocator.Error!CircularList(TestType) {
    TestType.reset();

    var list = CircularList(TestType).init(allocator);
    errdefer list.deinit();

    try list.insert_after(.{ .value = 1 });
    try list.insert_after(.{ .value = 2 });
    try list.insert_before(.{ .value = 3 });

    return list;
}

test "zig_structures.linked.circular_list.CircularList(_).get" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    const data = list.get().?;
    try testing.expectEqual(&list.node.?.data, data);
    try testing.expectEqual(1, data.value);

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.circular_list.CircularList(_).next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    const node1 = list.node.?;

    list.next();
    try testing.expectEqual(node1.next, list.node);
    var data = list.get().?;
    try testing.expectEqual(2, data.value);

    list.next();
    try testing.expectEqual(node1.previous, list.node);
    data = list.get().?;
    try testing.expectEqual(3, data.value);

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.circular_list.CircularList(_).previous" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    const node1 = list.node.?;

    list.previous();
    try testing.expectEqual(node1.previous, list.node);
    var data = list.get().?;
    try testing.expectEqual(3, data.value);

    list.previous();
    try testing.expectEqual(node1.next, list.node);
    data = list.get().?;
    try testing.expectEqual(2, data.value);

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.circular_list.CircularList(_).remove_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    var data = list.remove_to_next().?;
    try testing.expectEqual(1, data.value);

    const data_current = list.get().?;
    try testing.expectEqual(2, data_current.value);

    data = list.remove_to_next().?;
    try testing.expectEqual(2, data.value);

    data = list.remove_to_next().?;
    try testing.expectEqual(3, data.value);

    try testing.expect(list.is_empty());

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.circular_list.CircularList(_).remove_to_previous" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    var data = list.remove_to_previous().?;
    try testing.expectEqual(1, data.value);

    const data_current = list.get().?;
    try testing.expectEqual(3, data_current.value);

    data = list.remove_to_previous().?;
    try testing.expectEqual(3, data.value);

    data = list.remove_to_previous().?;
    try testing.expectEqual(2, data.value);

    try testing.expect(list.is_empty());

    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.circular_list.CircularList(_).delete_to_next" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);
    TestType.reset();

    var data_current = list.get().?;
    try testing.expectEqual(2, data_current.value);

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);
    TestType.reset();

    data_current = list.get().?;
    try testing.expectEqual(3, data_current.value);

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);

    try testing.expect(list.is_empty());
}

test "zig_structures.linked.circular_list.CircularList(_).delete_to_previous" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = try test_create(allocator);
    defer list.deinit();

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);
    TestType.reset();

    var data_current = list.get().?;
    try testing.expectEqual(2, data_current.value);

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);
    TestType.reset();

    data_current = list.get().?;
    try testing.expectEqual(3, data_current.value);

    list.delete_to_next();
    try testing.expect(TestType.deinit_called);

    try testing.expect(list.is_empty());
}

test "zig_structures.linked.circular_list.CircularList(_).apply" {
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

    const node = list.node;
    var data = list.get().?;
    try testing.expectEqual(11, data.value);

    list.next();
    data = list.get().?;
    try testing.expectEqual(22, data.value);

    list.next();
    data = list.get().?;
    try testing.expectEqual(33, data.value);

    list.next();
    try testing.expectEqual(node, list.node);
}

test "zig_structures.linked.circular_list.CircularList(_).filter" {
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

    const node = list.node;
    var data = list.get().?;
    try testing.expectEqual(1, data.value);

    list.next();
    data = list.get().?;
    try testing.expectEqual(3, data.value);

    list.next();
    try testing.expectEqual(node, list.node);
}

test "zig_structures.linked.circular_list.CircularList(_).filter_apply" {
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

    const node = list.node;
    var data = list.get().?;
    try testing.expectEqual(11, data.value);

    list.next();
    data = list.get().?;
    try testing.expectEqual(33, data.value);

    list.next();
    try testing.expectEqual(node, list.node);
}

test "zig_structures.linked.circular_list.CircularList(_).fold" {
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

test "zig_structures.linked.circular_list.CircularList(_).foldr" {
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
    try testing.expectEqual(132, result);

    // Deinit should be handled by `f`
    try testing.expect(!TestType.deinit_called);
}
