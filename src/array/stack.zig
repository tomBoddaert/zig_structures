const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A stack backed by an array.
pub fn Stack(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate the buffer.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The slice backing the stack.
        buffer: []T,
        /// The length of the stack.
        ///
        /// This should not be modified externally.
        length: usize = 0,

        const Self = @This();
        /// The error returned by stack operations.
        pub const Error = error{StackFull};
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new stack.
        pub fn init(allocator: Allocator, size: usize) Allocator.Error!Self {
            return .{
                .allocator = allocator,
                .buffer = try allocator.alloc(T, size),
            };
        }

        /// Deallocate the stack and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            for (self.as_slice()) |*element|
                deinit_t(element);

            self.allocator.free(self.buffer);
        }

        /// Returns `true` if the stack is empty.
        pub inline fn is_empty(self: *const Self) bool {
            return self.length == 0;
        }

        /// Returns `true` if the stack is full.
        pub inline fn is_full(self: *const Self) bool {
            return self.length == self.buffer.len;
        }

        /// Get the stack's capacity.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Get the stack as a slice.
        pub fn as_slice(self: *Self) []T {
            return self.buffer[0..self.length];
        }

        /// Get a pointer to the data at the top of the stack.
        ///
        /// Returns `null` if the stack is empty.
        pub fn get_top(self: *Self) ?*T {
            if (self.is_empty()) return null;

            return &self.buffer[self.length - 1];
        }

        /// Push data to the top of the stack.
        pub fn push(self: *Self, data: T) Error!void {
            if (self.is_full()) return Error.StackFull;

            self.buffer[self.length] = data;
            self.length += 1;
        }

        /// Removes the data at the top of the stack and returns it.
        ///
        /// Returns `null` if the stack is empty.
        pub fn pop(self: *Self) ?T {
            if (self.is_empty()) return null;

            self.length -= 1;
            return self.buffer[self.length];
        }

        /// Deletes the data at the top of the stack after deinitialising
        /// it if a deinit function is set.
        ///
        /// If the stack is empty, this does nothing.
        pub fn delete_top(self: *Self) void {
            if (self.is_empty()) return;

            self.length -= 1;
            deinit_t(&self.buffer[self.length]);
        }

        /// Reserves at least space for `additional` extra elements.
        pub fn reserve(self: *Self, additional: usize) Allocator.Error!void {
            var new_capacity = self.length + additional;

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
            const new_capacity = self.length + additional;

            if (self.buffer.len >= new_capacity)
                return;

            self.buffer = try self.allocator.realloc(
                self.buffer,
                new_capacity,
            );
        }

        /// Shrinks the allocated buffer to the length.
        pub fn shrink_to_fit(self: *Self) Allocator.Error!void {
            self.buffer = try self.allocator.realloc(
                self.buffer,
                self.length,
            );
        }
    };
}

test "zig_structures.array.stack.Stack(_)" {
    const testing = @import("std").testing;

    interfaces.assert_deinit(Stack(u8));

    var queue = try Stack(u8).init(testing.allocator, 4);
    defer queue.deinit();

    try queue.push(1);
    try queue.push(2);
    try queue.push(3);
    try queue.push(4);
    try testing.expectError(Stack(u8).Error.StackFull, queue.push(5));

    try testing.expectEqual(queue.pop().?, 4);
    try testing.expectEqual(queue.pop().?, 3);
    try testing.expectEqual(queue.pop().?, 2);
    try testing.expectEqual(queue.pop().?, 1);
    try testing.expectEqual(@as(?u8, null), queue.pop());
}
