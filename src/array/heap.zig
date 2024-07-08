const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Order = std.math.Order;

const interfaces = @import("../interfaces.zig");

inline fn index_parent(i: usize) ?usize {
    return if (i == 0)
        null
    else
        (i - 1) / 2;
}

inline fn index_left_child(i: usize, len: usize) ?usize {
    const child = 2 * i + 1;

    return if (child < len)
        child
    else
        null;
}

inline fn index_right_child(i: usize, len: usize) ?usize {
    const child = 2 * i + 2;

    return if (child < len)
        child
    else
        null;
}

pub const HeapType = enum(u1) {
    Min,
    Max,

    inline fn should_switch(
        comptime self: @This(),
        parent_child_order: Order,
    ) bool {
        return parent_child_order == switch (self) {
            inline .Min => .gt,
            inline .Max => .lt,
        };
    }

    inline fn inverse(comptime self: @This()) @This() {
        return switch (self) {
            inline .Min => .Max,
            inline .Max => .Min,
        };
    }
};

/// A heap backed by an array.
pub fn Heap(comptime T: type, comptime heap_type: HeapType) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate the buffer.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The allocated buffer.
        buffer: []T,
        /// The size of the heap.
        ///
        /// This should not be modified externally.
        size: usize = 0,

        const Self = @This();
        pub const Error = error{HeapFull};
        const deinit_t = interfaces.Deinit(T).deinit;
        const order_t = interfaces.Order(T).order;

        /// Create a new heap.
        pub fn init(allocator: Allocator, size: usize) Allocator.Error!Self {
            return .{
                .allocator = allocator,
                .buffer = try allocator.alloc(T, size),
            };
        }

        /// Deallocate the heap and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            for (self.buffer[0..self.size]) |*element| {
                deinit_t(element);
            }

            self.allocator.free(self.buffer);
        }

        /// Returns `true` if the heap is empty.
        pub inline fn is_empty(self: *const Self) bool {
            return self.size == 0;
        }

        /// Returns `true` if the heap is full.
        pub inline fn is_full(self: *const Self) bool {
            return self.size == self.buffer.len;
        }

        /// Get the heap's capacity.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        fn bubble(self: *Self, i: usize) void {
            const parent_index = index_parent(i) orelse return;

            const parent = &self.buffer[parent_index];
            const child = &self.buffer[i];

            const order = Self.order_t(
                parent,
                child,
            );
            if (!heap_type.should_switch(order)) return;

            mem.swap(T, parent, child);
            self.bubble(parent_index);
        }

        fn sink(self: *Self, i: usize) void {
            const current = &self.buffer[i];

            const left_index = index_left_child(i, self.size) orelse return;
            const left = &self.buffer[left_index];

            const left_ord = Self.order_t(current, left);

            const right_index = index_right_child(i, self.size) orelse {
                if (heap_type.should_switch(left_ord))
                    mem.swap(T, current, left);
                return;
            };
            const right = &self.buffer[right_index];

            const replacement_i = if (heap_type.should_switch(left_ord))
                (if (heap_type.should_switch(
                    Self.order_t(left, right),
                ))
                    right_index
                else
                    left_index)
            else
                (if (heap_type.should_switch(
                    Self.order_t(current, right),
                ))
                    right_index
                else
                    return);

            mem.swap(T, current, &self.buffer[replacement_i]);
            self.sink(replacement_i);
        }

        /// Insert data into the heap.
        pub fn insert(self: *Self, data: T) Error!void {
            if (self.is_full())
                return Error.HeapFull;

            self.buffer[self.size] = data;
            self.bubble(self.size);
            self.size += 1;
        }

        /// Remove the data at the top of the heap and return it.
        ///
        /// Returns `null` if the heap is empty.
        pub fn remove_top(self: *Self) ?T {
            if (self.size == 0) return null;
            const top = self.buffer[0];

            self.size -= 1;
            if (self.size == 0)
                return top;

            self.buffer[0] = self.buffer[self.size];
            self.sink(0);

            return top;
        }

        /// Deletes the data at the top of the heap after deinitialising
        /// it if a deinit function is set.
        ///
        /// Returns `null` if the heap is empty.
        pub fn delete_top(self: *Self) void {
            if (self.size == 0) return;
            Self.deinit_t(&self.buffer[0]);

            self.size -= 1;
            if (self.size == 0) return;

            self.buffer[0] = self.buffer[self.size];
            self.sink(0);
        }

        /// Reserves at least space for `additional` extra elements.
        pub fn reserve(self: *Self, additional: usize) Allocator.Error!void {
            var new_capacity = self.size + additional;

            if (self.buffer.len >= new_capacity)
                return;

            const min_new_capacity = self.buffer.len * 2;
            new_capacity = @max(new_capacity, min_new_capacity);

            self.buffer = try self.allocator.realloc(
                self.buffer,
                new_capacity,
            );
        }

        /// Reserves exactly enough space for `additional` extra elements.
        /// Unless you have good reason to use this method, use `reserve` instead!
        pub fn reserve_exact(self: *Self, additional: usize) Allocator.Error!void {
            const new_capacity = self.size + additional;

            if (self.buffer.len >= new_capacity)
                return;

            self.buffer = try self.allocator.realloc(
                self.buffer,
                new_capacity,
            );
        }

        /// Shrinks the allocated buffer to the size.
        pub fn shrink_to_fit(self: *Self) Allocator.Error!void {
            self.buffer = try self.allocator.realloc(
                self.buffer,
                self.size,
            );
        }

        /// Finds data in the heap by using `f` to determine which direction
        /// the target is in.
        ///
        /// `ctx` is also passed to `f`. If no context is needed, this can be
        /// set to `void{}`.
        pub inline fn find(self: *Self, ctx: anytype, f: *const fn (*const T, @TypeOf(ctx)) Order) ?*T {
            return self.find_from(0, ctx, f);
        }

        fn find_from(self: *Self, i: usize, ctx: anytype, f: *const fn (*const T, @TypeOf(ctx)) Order) ?*T {
            if (i >= self.size) return null;

            const element = &self.buffer[i];
            const order = f(element, ctx);
            return switch (order) {
                .eq => element,

                if (heap_type == .Max)
                    .gt
                else
                    .lt => self.find_from(2 * i + 1, ctx, f) orelse
                    self.find_from(2 * i + 2, ctx, f),

                else => null,
            };
        }

        /// Finds data in the heap by comparing to `item`.
        pub inline fn contains(self: *const Self, item: *const T) bool {
            return @constCast(self).find(item, interfaces.Order(T).order_wrapped) != null;
        }
    };
}

/// Sort a slice using the heapsort algorithm.
///
/// If `first == .Min`, the slice will end up in increasing order.
/// If `first == .Max`, the slice will end up in decreasing order.
pub fn heapsort(comptime T: type, comptime first: HeapType, array: []T) void {
    var heap = Heap(T, first.inverse()){
        .allocator = undefined,
        .buffer = array,
        .size = array.len,
    };

    var i = array.len;
    while (i > 0) {
        i -= 1;
        heap.sink(i);
    }

    while (heap.size > 1) {
        heap.size -= 1;
        mem.swap(T, &array[0], &array[heap.size]);
        heap.sink(0);
    }
}

const testing = std.testing;
const TestType = interfaces.DeinitTest(u8);

test "zig_structures.array.heap" {
    testing.refAllDecls(@This());

    interfaces.assert_deinit(Heap(u8, .Min));
    interfaces.assert_deinit(Heap(u8, .Max));
}

test "zig_structures.array.heap.Heap(_, .Max).{init,is_empty,deinit}" {
    TestType.reset();

    var heap = try Heap(TestType, .Max).init(testing.allocator, 10);
    try testing.expectEqual(10, heap.buffer.len);
    try testing.expectEqual(0, heap.size);
    try testing.expect(heap.is_empty());

    heap.deinit();
    try testing.expect(!TestType.deinit_called);
}

test "zig_structures.array.heap.Heap(_, .Max).insert" {
    var heap = try Heap(u8, .Max).init(testing.allocator, 10);
    defer heap.deinit();

    try heap.insert(1);
    try testing.expectEqual(1, heap.size);
    try testing.expectEqualSlices(u8, &.{1}, heap.buffer[0..1]);

    try heap.insert(3);
    try testing.expectEqual(2, heap.size);
    try testing.expectEqualSlices(u8, &.{ 3, 1 }, heap.buffer[0..2]);

    try heap.insert(2);
    try testing.expectEqual(3, heap.size);
    try testing.expectEqualSlices(u8, &.{ 3, 1, 2 }, heap.buffer[0..3]);
}

test "zig_structures.array.heap.Heap(_, .Max).deinit" {
    TestType.reset();

    var heap = try Heap(TestType, .Max).init(testing.allocator, 10);

    try heap.insert(.{ .value = 1 });
    try heap.insert(.{ .value = 3 });
    try heap.insert(.{ .value = 2 });

    try testing.expect(!TestType.deinit_called);
    heap.deinit();
    try testing.expect(TestType.deinit_called);
}

test "zig_structures.array.heap.Heap(_, .Max).contains" {
    var heap = try Heap(u8, .Max).init(testing.allocator, 10);
    defer heap.deinit();

    try heap.insert(1);
    try heap.insert(3);
    try heap.insert(2);

    try testing.expect(heap.contains(&1));
    try testing.expect(heap.contains(&2));
    try testing.expect(heap.contains(&3));

    try testing.expect(!heap.contains(&0));
    try testing.expect(!heap.contains(&4));
}

test "zig_structures.array.heap.heapsort" {
    var array = [_]u8{ 5, 7, 3, 4, 1, 8, 5, 6, 3 };
    heapsort(u8, .Min, &array);

    try testing.expectEqualSlices(
        u8,
        &.{ 1, 3, 3, 4, 5, 5, 6, 7, 8 },
        &array,
    );
}
