const std = @import("std");
const Allocator = std.mem.Allocator;

const interfaces = @import("../interfaces.zig");

/// A queue backed by an array.
pub fn Queue(comptime T: type) type {
    return struct {
        /// Private: this is not part of the public API.
        ///
        /// The allocator used to allocate the buffer.
        /// This MUST NOT be changed!
        allocator: Allocator,
        /// Private: this is not part of the public API.
        ///
        /// The slice backing the queue.
        buffer: []T,
        /// The start index of the queue.
        ///
        /// This should not be modified externally.
        start: usize = 0,
        /// The end index of the queue.
        ///
        /// This should not be modified externally.
        end: usize = 0,

        const Self = @This();
        /// The error returned by queue operations.
        pub const Error = error{QueueFull};
        const deinit_t = interfaces.Deinit(T).deinit;

        /// Create a new queue.
        pub fn init(allocator: Allocator, size: usize) Allocator.Error!Self {
            return .{
                .allocator = allocator,
                .buffer = try allocator.alloc(T, size + 1),
            };
        }

        /// Deallocate the queue and deinit the data if a deinit function is set.
        pub fn deinit(self: *Self) void {
            const slices = self.as_slices();
            for (slices[0]) |*element|
                deinit_t(element);
            for (slices[1]) |*element|
                deinit_t(element);

            self.allocator.free(self.buffer);
        }

        /// Returns `true` if the queue is empty.
        pub inline fn is_empty(self: *const Self) bool {
            return self.start == self.end;
        }

        /// Returns `true` if the queue is full.
        pub inline fn is_full(self: *const Self) bool {
            return (self.end + 1) % self.buffer.len == self.start;
        }

        /// Get the queue's length.
        pub inline fn length(self: *const Self) usize {
            return (self.end + self.buffer.len - self.start) % self.buffer.len;
        }

        /// Get the queue's capacity.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len - 1;
        }

        /// Get the queue as two slices.
        ///
        /// One or both of them may be empty.
        pub fn as_slices(self: *Self) struct { []T, []T } {
            return if (self.end >= self.start)
                .{
                    self.buffer[self.start..self.end],
                    &.{},
                }
            else
                .{
                    self.buffer[self.start..],
                    self.buffer[0..self.end],
                };
        }

        /// Get a pointer to the data at the front of the queue.
        ///
        /// Returns `null` if the queue is empty.
        pub fn get_front(self: *Self) ?*T {
            if (self.is_empty()) return null;

            return &self.buffer[self.start];
        }

        /// Push data to the back of the queue.
        pub fn push(self: *Self, data: T) Error!void {
            if (self.is_full()) return Error.QueueFull;

            self.buffer[self.end] = data;
            self.end = (self.end + 1) % self.buffer.len;
        }

        /// Removes the data at the front of the queue and returns it.
        ///
        /// Returns `null` if the list is empty.
        pub fn pop(self: *Self) ?T {
            if (self.is_empty()) return null;

            const data = self.buffer[self.start];
            self.start = (self.start + 1) % self.buffer.len;

            return data;
        }

        /// Deletes the data at the front of the queue after deinitialising it
        /// if a deinit function is set.
        ///
        /// If the queue is empty, this does nothing.
        pub fn delete_front(self: *Self) void {
            if (self.is_empty()) return;

            deinit_t(&self.buffer[self.start]);

            self.start = (self.start + 1) % self.buffer.len;
        }

        inline fn grow(self: *Self, new_capacity: usize) Allocator.Error!void {
            const slices: struct { []T, struct {
                slice: ?[]T,
                new_start: usize,
            } } = if (self.end >= self.start)
                .{ self.buffer[self.start..self.end], null }
            else
                .{ self.buffer[0..self.end], .{
                    .slice = self.buffer[self.start..],
                    .new_start = new_start: {
                        const second_slice_len = self.buffer.len - self.start;
                        break :new_start new_capacity - second_slice_len;
                    },
                } };

            if (self.allocator.resize(self.buffer, new_capacity)) {
                const second_slice = slices[1] orelse {
                    self.buffer.len = new_capacity;
                    return;
                };

                self.buffer.len = new_capacity;

                std.mem.copyBackwards(
                    T,
                    self.buffer[second_slice.new_start..],
                    second_slice.slice,
                );
                return;
            }

            const old_buffer = self.buffer;
            self.buffer = try self.allocator.alloc(
                T,
                new_capacity,
            );

            std.mem.copyForwards(T, self.buffer, slices[0]);

            if (slices[1]) |second_slice|
                std.mem.copyBackwards(
                    T,
                    self.buffer[second_slice.new_start..],
                    second_slice.slice,
                );

            self.allocator.free(old_buffer);
        }

        /// Reserves at least space for `additional` extra elements.
        pub fn reserve(self: *Self, additional: usize) Allocator.Error!void {
            var new_capacity = self.length() + additional;

            if (self.buffer.len >= new_capacity)
                return;

            const min_new_capacity = self.buffer.len * 2;
            new_capacity = @max(new_capacity, min_new_capacity);

            try self.grow(new_capacity);
        }

        /// Reserves exactly enough space for `additional` extra elements.
        /// Unless you have good reason to use this method, use `reserve` instead!
        pub fn reserve_exact(self: *Self, additional: usize) Allocator.Error!void {
            const new_capacity = self.length() + additional;

            if (self.buffer.len >= new_capacity)
                return;

            try self.grow(new_capacity);
        }

        // /// Assumes split (non-empty) queue.
        // ///
        // /// Conditions: `end < start`
        // fn shift_align(self: *Self) void {
        //     const space = self.start - self.end;

        //     var completed: usize = 0;
        //     var pos = self.start;
        //     while (pos < self.buffer.len) : (pos = self.start + completed) {
        //         const remaining = self.buffer.len - pos;
        //         const move = @min(space, remaining);

        //         std.mem.copyBackwards(
        //             T,
        //             self.buffer[completed + move ..],
        //             self.buffer[completed .. completed + self.end],
        //         );

        //         std.mem.copyForwards(
        //             T,
        //             self.buffer[completed..],
        //             self.buffer[pos .. pos + move],
        //         );

        //         completed += move;
        //     }

        //     self.end += self.buffer.len - self.start;
        //     self.start = 0;
        // }

        /// Assumes split (non-empty) queue.
        fn reverse_align(self: *Self) void {
            // Reverse the first part of the buffer
            // (second part of the queue)
            for (0..(@max(
                self.end,
                (self.end + 1) / 2,
            ))) |i| {
                const j = self.start - 1 - i;

                // If the item at j is undefined, just replace it
                if (j >= self.end) {
                    self.buffer[j] = self.buffer[i];
                } else {
                    std.mem.swap(
                        T,
                        &self.buffer[i],
                        &self.buffer[j],
                    );
                }
            }

            // Reverse the second part of the buffer
            // (first part of the queue)
            std.mem.reverse(T, self.buffer[self.start..]);

            // Reverse the whole array
            const ignore = self.start - self.end;
            for (0..(self.buffer.len / 2)) |i| {
                const j = self.buffer.len - 1 - i;

                if (i < ignore) {
                    self.buffer[i] = self.buffer[j];
                } else {
                    std.mem.swap(
                        T,
                        &self.buffer[i],
                        &self.buffer[j],
                    );
                }
            }

            self.start = 0;
            self.end = self.buffer.len - ignore;
        }

        pub fn shrink_to_fit(self: *Self) Allocator.Error!void {
            if (self.start == 0) {
                // do nothing
            } else if (self.start == self.end) {
                self.start = 0;
                self.end = 0;
            } else if (self.end >= self.start or
                self.end == 0)
            {
                std.mem.copyForwards(
                    T,
                    self.buffer,
                    if (self.end == 0)
                        self.buffer[self.start..]
                    else
                        self.buffer[self.start..self.end],
                );

                self.end -= self.start;
                self.start = 0;
            } else self.shift_align();

            const new_len = self.end + 1;
            if (self.buffer.len == new_len)
                return;

            self.buffer =
                try self.allocator.realloc(self.buffer, new_len);
        }
    };
}

test "zig_structures.array.queue.Queue(_)" {
    const testing = @import("std").testing;

    interfaces.assert_deinit(Queue(u8));

    var queue = try Queue(u8).init(testing.allocator, 4);
    defer queue.deinit();

    try queue.push(1);
    try queue.push(2);
    try queue.push(3);
    try queue.push(4);
    try testing.expectError(Queue(u8).Error.QueueFull, queue.push(5));

    try testing.expectEqual(queue.pop().?, 1);
    try testing.expectEqual(queue.pop().?, 2);
    try testing.expectEqual(queue.pop().?, 3);
    try testing.expectEqual(queue.pop().?, 4);
    try testing.expectEqual(@as(?u8, null), queue.pop());
}

// test "zig_structures.array.queue.Queue(_).shift_align" {
//     const testing = std.testing;

//     var buffer: [8]u8 = .{ 5, 255, 255, 255, 1, 2, 3, 4 };
//     var queue = Queue(u8){
//         .allocator = undefined,
//         .buffer = &buffer,
//         .start = 4,
//         .end = 1,
//     };
//     queue.shift_align();

//     try testing.expectEqual(0, queue.start);
//     try testing.expectEqual(5, queue.end);
//     try testing.expectEqualSlices(
//         u8,
//         &[8]u8{ 1, 2, 3, 4, 5, 2, 3, 4 },
//         &buffer,
//     );

//     buffer = .{ 4, 5, 255, 255, 255, 1, 2, 3 };
//     queue = Queue(u8){
//         .allocator = undefined,
//         .buffer = &buffer,
//         .start = 5,
//         .end = 2,
//     };
//     queue.shift_align();

//     try testing.expectEqual(0, queue.start);
//     try testing.expectEqual(5, queue.end);
//     try testing.expectEqualSlices(
//         u8,
//         &[8]u8{ 1, 2, 3, 4, 5, 1, 2, 3 },
//         &buffer,
//     );

//     buffer = .{ 3, 4, 5, 255, 255, 255, 1, 2 };
//     queue = Queue(u8){
//         .allocator = undefined,
//         .buffer = &buffer,
//         .start = 6,
//         .end = 3,
//     };
//     queue.shift_align();

//     try testing.expectEqual(0, queue.start);
//     try testing.expectEqual(5, queue.end);
//     try testing.expectEqualSlices(
//         u8,
//         &[8]u8{ 1, 2, 3, 4, 5, 255, 1, 2 },
//         &buffer,
//     );

//     buffer = .{ 2, 3, 4, 5, 255, 255, 255, 1 };
//     queue = Queue(u8){
//         .allocator = undefined,
//         .buffer = &buffer,
//         .start = 7,
//         .end = 4,
//     };
//     queue.shift_align();

//     try testing.expectEqual(0, queue.start);
//     try testing.expectEqual(5, queue.end);
//     try testing.expectEqualSlices(
//         u8,
//         &[8]u8{ 1, 2, 3, 4, 5, 255, 255, 1 },
//         &buffer,
//     );
// }

test "zig_structures.array.queue.Queue(_).reverse_align" {
    const testing = std.testing;

    const expected: *const [8]u8 = &.{ 1, 2, 3, 4, 5, 3, 2, 1 };

    var buffer: [8]u8 = .{ 5, 255, 255, 255, 1, 2, 3, 4 };
    var queue = Queue(u8){
        .allocator = undefined,
        .buffer = &buffer,
        .start = 4,
        .end = 1,
    };
    queue.reverse_align();

    try testing.expectEqual(0, queue.start);
    try testing.expectEqual(5, queue.end);
    try testing.expectEqualSlices(u8, expected, &buffer);

    buffer = .{ 4, 5, 255, 255, 255, 1, 2, 3 };
    queue = Queue(u8){
        .allocator = undefined,
        .buffer = &buffer,
        .start = 5,
        .end = 2,
    };
    queue.reverse_align();

    try testing.expectEqual(0, queue.start);
    try testing.expectEqual(5, queue.end);
    try testing.expectEqualSlices(u8, expected, &buffer);

    buffer = .{ 3, 4, 5, 255, 255, 255, 1, 2 };
    queue = Queue(u8){
        .allocator = undefined,
        .buffer = &buffer,
        .start = 6,
        .end = 3,
    };
    queue.reverse_align();

    try testing.expectEqual(0, queue.start);
    try testing.expectEqual(5, queue.end);
    try testing.expectEqualSlices(u8, expected, &buffer);

    buffer = .{ 2, 3, 4, 5, 255, 255, 255, 1 };
    queue = Queue(u8){
        .allocator = undefined,
        .buffer = &buffer,
        .start = 7,
        .end = 4,
    };
    queue.reverse_align();

    try testing.expectEqual(0, queue.start);
    try testing.expectEqual(5, queue.end);
    try testing.expectEqualSlices(u8, expected, &buffer);
}
