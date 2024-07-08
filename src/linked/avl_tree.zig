const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const interfaces = @import("../interfaces.zig");

/// An AVL tree.
pub fn AvlTree(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate nodes.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// A sentinel edge into the tree.
        sentinel: ?*Node = null,

        const Self = @This();
        const order_t = interfaces.Order(T).order;
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new AVL tree.
        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Deallocate the tree and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            const root = self.sentinel orelse return;
            root.deinit_recursive(self.allocator);
            self.sentinel = null;
        }

        /// Returns `true` if the tree is empty.
        pub inline fn is_empty(self: *const Self) bool {
            return self.sentinel == null;
        }

        /// Get the height of the tree.
        pub fn height(self: *const Self) usize {
            return (self.sentinel orelse return 0).height;
        }

        /// Insert a node with the data.
        ///
        /// If there was a node with equal data, the data is swapped and
        /// the old data is returned.
        pub fn insert(self: *Self, data: T) Allocator.Error!?T {
            defer Node.update_child_height(&self.sentinel);
            return try Node.insert(&self.sentinel, self.allocator, data);
        }

        /// Get a pointer to data that matches `key`.
        ///
        /// If there is no maching data, this returns `null`.
        pub fn get(self: *Self, key: *const T) ?*T {
            return (self.sentinel orelse return null).get(key);
        }

        /// Remove and return data that matches `key`.
        ///
        /// If there is no matching data, this returns `null`.
        pub fn remove(self: *Self, key: *const T) ?T {
            defer Node.update_child_height(&self.sentinel);
            return Node.remove(&self.sentinel, self.allocator, key);
        }

        /// Delete data that matches `key` after deinitialising it if a
        /// deinit function is set.
        ///
        /// If there is no matching data, does nothing.
        pub fn delete(self: *Self, key: *const T) void {
            defer Node.update_child_height(&self.sentinel);
            Node.delete(&self.sentinel, self.allocator, key);
        }

        const Node = struct {
            left: ?*Node = null,
            right: ?*Node = null,
            height: usize,
            data: T,

            fn deinit_recursive(self: *Node, allocator: Allocator) void {
                if (self.left) |left| {
                    left.deinit_recursive(allocator);
                }
                if (self.right) |right| {
                    right.deinit_recursive(allocator);
                }

                Self.deinit_t(&self.data);

                allocator.destroy(self);
            }

            fn insert(edge: *?*Node, allocator: Allocator, data: T) Allocator.Error!?T {
                const child = edge.* orelse {
                    const new_node = try allocator.create(Node);
                    new_node.* = .{ .data = data, .height = 1 };
                    edge.* = new_node;
                    return null;
                };

                const order = Self.order_t(&data, &child.data);
                switch (order) {
                    .eq => {
                        const old_data = child.data;
                        child.data = data;
                        return old_data;
                    },
                    .lt => {
                        defer Node.update_child_height(&child.left);
                        return try Node.insert(&child.left, allocator, data);
                    },
                    .gt => {
                        defer Node.update_child_height(&child.right);
                        return try Node.insert(&child.right, allocator, data);
                    },
                }
            }

            fn get(self: *Node, key: *const T) ?*T {
                const order = Self.order_t(key, &self.data);
                return switch (order) {
                    .eq => &self.data,
                    .lt => (self.left orelse return null).get(key),
                    .gt => (self.right orelse return null).get(key),
                };
            }

            fn remove(edge: *?*Node, allocator: Allocator, key: *const T) ?T {
                const child = edge.* orelse return null;

                const order = Self.order_t(key, &child.data);
                switch (order) {
                    .eq => {
                        const data = child.data;
                        child.delete_single(edge, allocator);

                        return data;
                    },
                    .lt => {
                        defer Node.update_child_height(&child.left);
                        return Node.remove(&child.left, allocator, key);
                    },
                    .gt => {
                        defer Node.update_child_height(&child.right);
                        return Node.remove(&child.right, allocator, key);
                    },
                }
            }

            fn delete(edge: *?*Node, allocator: Allocator, key: *const T) void {
                const child = edge.* orelse return;

                const order = Self.order_t(key, &child.data);
                switch (order) {
                    .eq => {
                        Self.deinit_t(&child.data);
                        child.delete_single(edge, allocator);
                    },
                    .lt => {
                        defer Node.update_child_height(&child.left);
                        Node.delete(&child.left, allocator, key);
                    },
                    .gt => {
                        defer Node.update_child_height(&child.right);
                        Node.delete(&child.right, allocator, key);
                    },
                }
            }

            fn update_child_height(edge: *?*Node) void {
                const child = edge.* orelse return;

                const left = height: {
                    break :height (child.left orelse break :height 0).height;
                };
                const right = height: {
                    break :height (child.right orelse break :height 0).height;
                };

                if (left > right) {
                    if (left - right >= 2) {
                        Node.rotate_child_right(edge);
                        return Node.update_child_height(edge);
                    }

                    child.height = left + 1;
                } else {
                    if (right - left >= 2) {
                        Node.rotate_child_left(edge);
                        return Node.update_child_height(edge);
                    }

                    child.height = right + 1;
                }
            }

            fn rotate_child_right(edge: *?*Node) void {
                const x: *Node = edge.* orelse return;
                const y = x.left orelse return;
                const t2 = y.right;

                x.left = t2;
                y.right = x;
                edge.* = y;

                Node.update_child_height(&y.right);
                Node.update_child_height(edge);
            }

            fn rotate_child_left(edge: *?*Node) void {
                const x: *Node = edge.* orelse return;
                const y = x.right orelse return;
                const t2 = y.left;

                x.right = t2;
                y.left = x;
                edge.* = y;

                Node.update_child_height(&y.left);
                Node.update_child_height(edge);
            }

            fn delete_single(self: *Node, edge: *?*Node, allocator: Allocator) void {
                delete: {
                    const left = self.left orelse {
                        edge.* = self.right;
                        break :delete;
                    };
                    const right = self.right orelse {
                        edge.* = self.left;
                        break :delete;
                    };

                    const replacement: *Node = if (left.height > right.height) get_replacement: {
                        defer Node.update_child_height(&self.left);
                        break :get_replacement left.take_max(&self.left);
                    } else get_replacement: {
                        defer Node.update_child_height(&self.right);
                        break :get_replacement right.take_min(&self.right);
                    };

                    replacement.left = self.left;
                    replacement.right = self.right;

                    edge.* = replacement;
                }

                allocator.destroy(self);

                Node.update_child_height(edge);
            }

            fn take_min(self: *Node, edge: *?*Node) *Node {
                if (self.left) |left| {
                    defer Node.update_child_height(&self.left);
                    return left.take_min(&self.left);
                } else {
                    edge.* = self.right;
                    self.right = null;
                    return self;
                }
            }

            fn take_max(self: *Node, edge: *?*Node) *Node {
                if (self.right) |right| {
                    defer Node.update_child_height(&self.right);
                    return right.take_max(&self.right);
                } else {
                    edge.* = self.left;
                    self.left = null;
                    return self;
                }
            }
        };
    };
}

test "zig_structures.linked.avl_tree.AvlTree(_)" {
    const testing = @import("std").testing;

    interfaces.assert_deinit(AvlTree(u8));

    var tree = AvlTree(u8).init(testing.allocator);
    defer tree.deinit();

    try testing.expectEqual(0, tree.height());
    try testing.expectEqual(null, try tree.insert(32));
    try testing.expectEqual(1, tree.height());
    try testing.expectEqual(null, try tree.insert(16));
    try testing.expectEqual(2, tree.height());
    try testing.expectEqual(null, try tree.insert(8));
    try testing.expectEqual(2, tree.height());

    try testing.expectEqual(8, tree.get(&8).?.*);
    try testing.expectEqual(8, try tree.insert(8));

    try testing.expectEqual(16, tree.remove(&16));
    try testing.expectEqual(null, tree.get(&16));

    tree.delete(&8);
    try testing.expectEqual(null, tree.get(&8));
}

test "insert" {
    const testing = std.testing;

    var tree = AvlTree(u8).init(testing.allocator);
    defer tree.deinit();

    try testing.expectEqual(null, try tree.insert(0));
}
