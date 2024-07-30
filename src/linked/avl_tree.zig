const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const interfaces = @import("../interfaces.zig");

const Side = enum(u1) {
    Left,
    Right,

    inline fn invert(self: @This()) @This() {
        return switch (self) {
            .Left => .Right,
            .Right => .Left,
        };
    }
};

/// An AVL tree.
///
/// If `allowDuplicates` is `true`, equal values can be inserted.
/// Note that when removing values, equal ones will be removed in an arbitrary order.
pub fn AvlTree(comptime T: type, comptime allowDuplicates: bool) type {
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
        /// If `allowDuplicates` is `false` and there is a node with equal data,
        /// it is replaced and the old data is returned.
        pub fn insert(self: *Self, data: T) Allocator.Error!if (allowDuplicates) void else ?T {
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

            fn insert(edge: *?*Node, allocator: Allocator, data: T) Allocator.Error!if (allowDuplicates) void else ?T {
                const child = edge.* orelse {
                    const new_node = try allocator.create(Node);
                    new_node.* = .{ .data = data, .height = 1 };
                    edge.* = new_node;
                    return if (!allowDuplicates) null;
                };

                const order = Self.order_t(&data, &child.data);
                // It is possible to `switch` on arbitrary expressions, however, I
                // don't think there is a way to make them optional without making the
                // input nullable, so there are two seperate `switch` statements.
                if (allowDuplicates)
                    switch (order) {
                        .lt, .eq => {
                            defer Node.update_child_height(&child.left);
                            return try Node.insert(&child.left, allocator, data);
                        },
                        .gt => {
                            defer Node.update_child_height(&child.right);
                            return try Node.insert(&child.right, allocator, data);
                        },
                    }
                else switch (order) {
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
                    if (left - right >= 2)
                        // `Node.rotate` calls `Node.update_child_height`
                        return Node.rotate(edge, .Right);

                    child.height = left + 1;
                } else {
                    if (right - left >= 2)
                        // `Node.rotate` calls `Node.update_child_height`
                        return Node.rotate(edge, .Left);

                    child.height = right + 1;
                }
            }

            inline fn get_side(self: *Node, side: Side) ?*Node {
                return switch (side) {
                    .Left => self.left,
                    .Right => self.right,
                };
            }

            inline fn get_edge(self: *Node, side: Side) *?*Node {
                return switch (side) {
                    .Left => &self.left,
                    .Right => &self.right,
                };
            }

            // fn single_rotate(edge: **Node, comptime direction: Side) void {
            //     const x: *Node = edge.*;
            //     const y = x.get_side(direction.invert()) orelse return;
            //     const t2 = y.get_side(direction);
            // }

            fn rotate_old(edge: *?*Node, comptime direction: Side) void {
                const x: *Node = edge.* orelse return;
                var y = x.get_side(direction.invert()) orelse return;

                // If `y` is heavy in the wrong direction, rotate it
                const y_correct = height: {
                    break :height (y.get_side(direction.invert()) orelse break :height 0).height;
                };
                const y_wrong = height: {
                    break :height (y.get_side(direction) orelse break :height 0).height;
                };
                if (y_wrong > y_correct)
                    // Rotations never set the child to `null`
                    Node.rotate(@ptrCast(&y), direction.invert());

                const t2 = y.get_side(direction);

                x.get_edge(direction.invert()).* = t2;
                y.get_edge(direction).* = x;
                edge.* = y;

                Node.update_child_height(y.get_edge(direction));
                Node.update_child_height(edge);
            }

            fn rotate(edge: *?*Node, comptime direction: Side) void {
                // Single left rotation example:
                //
                //    ▽x     ▽y
                //    │
                //  ┌─a──────┐
                // t1      ┌─b─┐
                //        t2   t3
                //
                // (4): Set x's right edge to y's near edge
                //
                //    ▽x   ▽y
                //    │ ┌──b─┐
                //  ┌─a─┤    t3
                // t1   t2
                //
                // (5): Set y's near edge to x
                //
                //    ▽x   ▽y
                //    │
                //    ├────b─┐
                //  ┌─a─┐    t3
                // t1   t2
                //
                // (6): Set the root edge to y
                //
                //    ▽x   ▽y
                //         │
                //    ┌────b─┐
                //  ┌─a─┐    t3
                // t1   t2

                // Double rotation example:
                //
                //    ▽x   ▽z   ▽y
                //    │
                //  ┌─a─────────┐
                // t1      ┌────b─┐
                //       ┌─c─┐    t4
                //      t2   t3
                //
                // (1): Set y's near edge to z's far edge
                //
                //    ▽x   ▽z   ▽y
                //    │
                //  ┌─a─────────┐
                // t1        ┌──b─┐
                //       ┌─c─┤    t4
                //      t2   t3
                //
                // (2): Set z's far edge to y
                //
                //    ▽x      ▽z ▽y
                //          ┌─c──┐
                //    │    t2    │
                //  ┌─a──────────┤
                // t1          ┌─b─┐
                //            t3   t4
                //
                // (3): Set y to z
                //
                //    ▽x      ▽y
                //          ┌─c─┐
                //    │    t2   │
                //  ┌─a─────────┤
                // t1         ┌─b─┐
                //           t3   t4
                //
                // (4): Set x's right edge to y's near edge
                //
                //    ▽x   ▽y
                //    │ ┌──c────┐
                //  ┌─a─┤     ┌─b─┐
                // t1   t2   t3   t4
                //
                // (5): Set y's near edge to x
                //
                //    ▽x   ▽y
                //    │
                //    ├────c────┐
                //  ┌─a─┐     ┌─b─┐
                // t1   t2   t3   t4
                //
                // (6): Set the root edge to y
                //
                //    ▽x   ▽y
                //         │
                //    ┌────c────┐
                //  ┌─a─┐     ┌─b─┐
                // t1   t2   t3   t4

                const x: *Node = edge.* orelse return;
                var y = x.get_side(direction.invert()) orelse return;

                // If `y` is heavy in the wrong direction, rotate it
                // Note that the right edge of `x` is not updated yet, only
                // the variable `y`
                const y_correct = height: {
                    break :height (y.get_side(direction.invert()) orelse break :height 0).height;
                };
                const y_wrong = height: {
                    break :height (y.get_side(direction) orelse break :height 0).height;
                };
                if (y_wrong > y_correct) {
                    const y_near_edge = y.get_edge(direction);
                    // y's wrong height is > 0
                    const z = y_near_edge.*.?;
                    const z_far_edge = z.get_edge(direction.invert());

                    // (1)
                    y_near_edge.* = z_far_edge.*;
                    // (2)
                    z_far_edge.* = y;
                    Node.update_child_height(z_far_edge);

                    // (3)
                    y = z;
                }

                const y_near_edge = y.get_edge(direction);

                // (4)
                x.get_edge(direction.invert()).* = y_near_edge.*;
                // (5)
                y_near_edge.* = x;

                // (6)
                edge.* = y;

                Node.update_child_height(y.get_edge(direction));
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

const testing = std.testing;
const TestType = interfaces.DeinitTest(u8);

test "zig_structures.linked.avl_tree" {
    testing.refAllDecls(@This());

    interfaces.assert_deinit(AvlTree(u8, false));
    interfaces.assert_deinit(AvlTree(u8, true));
}

test "zig_structures.linked.avl_tree.AvlTree(_, false).{init,is_empty,deinit}" {
    TestType.reset();

    var tree = AvlTree(TestType, false).init(testing.allocator);
    try testing.expectEqual(null, tree.sentinel);
    try testing.expect(tree.is_empty());

    tree.deinit();
    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.avl_tree.AvlTree(_, true).{init,is_empty,deinit}" {
    TestType.reset();

    var tree = AvlTree(TestType, true).init(testing.allocator);
    try testing.expectEqual(null, tree.sentinel);
    try testing.expect(tree.is_empty());

    tree.deinit();
    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.linked.avl_tree.AvlTree(_, false).insert" {
    TestType.reset();

    var tree = AvlTree(TestType, false).init(testing.allocator);
    errdefer tree.deinit();

    // 1000
    var replaced = try tree.insert(.{ .value = 0b1000 });
    try testing.expectEqual(null, replaced);
    const node_1000 = tree.sentinel.?;
    try testing.expectEqual(0b1000, node_1000.data.value);
    try testing.expectEqual(1, node_1000.height);

    //   ┌─1000
    // 100
    replaced = try tree.insert(.{ .value = 0b100 });
    try testing.expectEqual(null, replaced);
    const node_100 = node_1000.left.?;
    try testing.expectEqual(0b100, node_100.data.value);
    try testing.expectEqual(1, node_100.height);

    try testing.expectEqual(2, node_1000.height);

    //   ┌─1000─┐
    // 100      1100
    replaced = try tree.insert(.{ .value = 0b1100 });
    try testing.expectEqual(null, replaced);
    const node_1100 = node_1000.right.?;
    try testing.expectEqual(0b1100, node_1100.data.value);
    try testing.expectEqual(1, node_1100.height);

    try testing.expectEqual(2, node_1000.height);

    //   ┌─────1000─┐
    // 100─┐        1100
    //     110
    replaced = try tree.insert(.{ .value = 0b110 });
    try testing.expectEqual(null, replaced);
    const node_110 = node_100.right.?;
    try testing.expectEqual(0b110, node_110.data.value);
    try testing.expectEqual(1, node_110.height);

    try testing.expectEqual(2, node_100.height);
    try testing.expectEqual(3, node_1000.height);

    //       ┌─────1000─┐
    //   ┌─101─┐        1100
    // 100     110
    replaced = try tree.insert(.{ .value = 0b101 });
    try testing.expectEqual(null, replaced);
    const node_101 = node_1000.left.?;
    try testing.expectEqual(0b101, node_101.data.value);
    try testing.expectEqual(2, node_101.height);

    try testing.expectEqual(1, node_100.height);
    try testing.expectEqual(1, node_110.height);
    try testing.expectEqual(3, node_1000.height);

    try testing.expectEqual(node_1000, tree.sentinel);
    try testing.expectEqual(node_1100, node_1000.right);
    try testing.expectEqual(node_100, node_101.left);
    try testing.expectEqual(node_110, node_101.right);
    try testing.expectEqual(null, node_1100.left);
    try testing.expectEqual(null, node_1100.right);
    try testing.expectEqual(null, node_100.left);
    try testing.expectEqual(null, node_100.right);
    try testing.expectEqual(null, node_110.left);
    try testing.expectEqual(null, node_110.right);

    replaced = try tree.insert(.{ .value = 0b110 });
    try testing.expectEqual(0b110, replaced.?.value);

    tree.deinit();
    try testing.expect(TestType.deinit_called);
}

test "zig_structures.linked.avl_tree.AvlTree(_, true).insert" {
    TestType.reset();

    var tree = AvlTree(TestType, true).init(testing.allocator);
    errdefer tree.deinit();

    // 1000
    try tree.insert(.{ .value = 0b1000 });
    const node_1000 = tree.sentinel.?;
    try testing.expectEqual(0b1000, node_1000.data.value);
    try testing.expectEqual(1, node_1000.height);

    //   ┌─1000
    // 100
    try tree.insert(.{ .value = 0b100 });
    const node_100 = node_1000.left.?;
    try testing.expectEqual(0b100, node_100.data.value);
    try testing.expectEqual(1, node_100.height);

    try testing.expectEqual(2, node_1000.height);

    //   ┌─1000─┐
    // 100      1100
    try tree.insert(.{ .value = 0b1100 });
    const node_1100 = node_1000.right.?;
    try testing.expectEqual(0b1100, node_1100.data.value);
    try testing.expectEqual(1, node_1100.height);

    try testing.expectEqual(2, node_1000.height);

    //   ┌──────1000─┐
    // 100─┐         1100
    //     110a
    try tree.insert(.{ .value = 0b110 });
    const node_110a = node_100.right.?;
    try testing.expectEqual(0b110, node_110a.data.value);
    try testing.expectEqual(1, node_110a.height);

    try testing.expectEqual(2, node_100.height);
    try testing.expectEqual(3, node_1000.height);

    //       ┌──────1000─┐
    //   ┌─101─┐         1100
    // 100     110a
    try tree.insert(.{ .value = 0b101 });
    const node_101 = node_1000.left.?;
    try testing.expectEqual(0b101, node_101.data.value);
    try testing.expectEqual(2, node_101.height);

    try testing.expectEqual(1, node_100.height);
    try testing.expectEqual(1, node_110a.height);
    try testing.expectEqual(3, node_1000.height);

    try testing.expectEqual(node_1000, tree.sentinel);

    try testing.expectEqual(node_1100, node_1000.right);
    try testing.expectEqual(null, node_1100.left);
    try testing.expectEqual(null, node_1100.right);

    try testing.expectEqual(node_100, node_101.left);
    try testing.expectEqual(node_110a, node_101.right);
    try testing.expectEqual(null, node_100.left);
    try testing.expectEqual(null, node_100.right);
    try testing.expectEqual(null, node_110a.left);
    try testing.expectEqual(null, node_110a.right);

    //       ┌─────110a─┐
    //   ┌─101─┐        1000─┐
    // 100     110b          1100
    try tree.insert(.{ .value = 0b110 });
    const node_110b = node_101.right.?;
    try testing.expectEqual(0b110, node_110b.data.value);

    try testing.expectEqual(node_110a, tree.sentinel);

    try testing.expectEqual(node_1000, node_110a.right);
    try testing.expectEqual(node_1100, node_1000.right);
    try testing.expectEqual(null, node_1000.left);
    try testing.expectEqual(null, node_1100.left);
    try testing.expectEqual(null, node_1100.right);

    try testing.expectEqual(node_101, node_110a.left);
    try testing.expectEqual(node_100, node_101.left);
    try testing.expectEqual(node_110b, node_101.right);
    try testing.expectEqual(null, node_100.left);
    try testing.expectEqual(null, node_100.right);
    try testing.expectEqual(null, node_110b.left);
    try testing.expectEqual(null, node_110b.right);

    tree.deinit();
    try testing.expect(TestType.deinit_called);
}

test "zig_structures.linked.avl_tree.AvlTree(_, false).delete" {
    TestType.reset();

    var tree = AvlTree(TestType, false).init(testing.allocator);
    defer tree.deinit();

    //       ┌─────1000─┐
    //   ┌─101─┐        1100
    // 100     110
    _ = try tree.insert(.{ .value = 0b1000 });
    _ = try tree.insert(.{ .value = 0b100 });
    _ = try tree.insert(.{ .value = 0b1100 });
    _ = try tree.insert(.{ .value = 0b110 });
    _ = try tree.insert(.{ .value = 0b101 });

    try testing.expect(!TestType.deinit_called);

    tree.delete(&.{ .value = 0b0 });
    try testing.expect(!TestType.deinit_called);

    tree.delete(&.{ .value = 0b101 });
    try testing.expect(TestType.deinit_called);
}

test "zig_structures.linked.avl_tree.AvlTree(_, true).delete" {
    TestType.reset();

    var tree = AvlTree(TestType, true).init(testing.allocator);
    defer tree.deinit();

    //       ┌─────1000─┐
    //   ┌─101─┐        1100
    // 100     110
    try tree.insert(.{ .value = 0b1000 });
    try tree.insert(.{ .value = 0b100 });
    try tree.insert(.{ .value = 0b1100 });
    try tree.insert(.{ .value = 0b110 });
    try tree.insert(.{ .value = 0b101 });

    try testing.expect(!TestType.deinit_called);

    tree.delete(&.{ .value = 0b0 });
    try testing.expect(!TestType.deinit_called);

    tree.delete(&.{ .value = 0b101 });
    try testing.expect(TestType.deinit_called);
}
