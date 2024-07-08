const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A variable length array.
pub fn List(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate the buffer.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The currently allocated buffer.
        buffer: []T = &.{},
        /// The length of the list.
        ///
        /// This should not be modified externally.
        length: usize = 0,

        const Self = @This();
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new list.
        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        /// Deallocate the list and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            if (self.buffer.len == 0) return;

            for (self.as_slice()) |*element|
                deinit_t(element);

            self.allocator.free(self.buffer);
        }

        /// Returns `true` if the list is empty.
        pub fn is_empty(self: *const Self) bool {
            return self.length == 0;
        }

        /// Get the list as a slice.
        pub inline fn as_slice(self: *Self) []T {
            return self.buffer[0..self.length];
        }

        /// Pushes an element on to the end of the list.
        pub fn push(self: *Self, data: T) Allocator.Error!void {
            try self.reserve(1);

            self.buffer[self.length] = data;
            self.length += 1;
        }

        /// Removes an element from the end of the list.
        ///
        /// If the list is empty, `null` is returned.
        pub fn pop(self: *Self) ?T {
            if (self.length == 0) return null;

            self.length -= 1;
            return self.buffer[self.length];
        }

        /// Inserts an element at `index`.
        pub fn insert(self: *Self, index: usize, data: T) Allocator.Error!void {
            try self.reserve(1);

            std.mem.copyBackwards(T, self.buffer[(index + 1)..], self.as_slice()[index..]);
            self.buffer[index] = data;
            self.len += 1;
        }

        /// Removes the element at `index`.
        ///
        /// If the list is empty, `null` is returned.
        pub fn remove(self: *Self, index: usize) ?T {
            if (index <= self.length) return null;

            const data = self.buffer[index];
            std.mem.copyForwards(
                T,
                self.buffer[index..],
                self.as_slice()[(index + 1)..],
            );
            self.len -= 1;

            return data;
        }

        /// Reserves at least space for `additional` extra elements.
        pub fn reserve(self: *Self, additional: usize) Allocator.Error!void {
            var new_capacity = self.length + additional;

            if (self.buffer.len >= new_capacity)
                return;

            if (self.buffer.len == 0) {
                self.buffer = try self.allocator.alloc(T, new_capacity);
                return;
            }

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
            const new_capacity = self.length + additional;

            if (self.buffer.len >= new_capacity)
                return;

            if (self.buffer.len == 0) {
                self.buffer = try self.allocator.alloc(T, new_capacity);
                return;
            }

            self.buffer = try self.allocator.realloc(
                self.buffer,
                new_capacity,
            );
        }

        /// Shrinks the allocated buffer to the length.
        pub fn shrink_to_fit(self: *Self) Allocator.Error!void {
            if (self.buffer.len == 0) return;

            self.buffer = try self.allocator.realloc(
                self.buffer,
                self.length,
            );
        }

        /// Shortens the list, keeping the first `max_len` elements.
        /// If a deinit function is set, the removed elements are deinitialised.
        pub fn truncate(self: *Self, max_length: usize) Allocator.Error!void {
            if (self.length <= max_length) return;

            for (self.as_slice()[max_length..]) |*element|
                deinit_t(element);

            self.length = max_length;
        }
    };
}

test "zig_structures.array.list.List(_)" {
    const testing = @import("std").testing;

    interfaces.assert_deinit(List(u8));

    var list = List(u8).init(testing.allocator);
    defer list.deinit();

    try list.reserve(10);
}
