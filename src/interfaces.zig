//! Defines interfaces used in this library.

const std = @import("std");
const Type = std.builtin.Type;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

const meta_match = @import("meta_match");
const ContainerMatch = meta_match.ContainerMatch;
const DeclarationMatch = meta_match.DeclarationMatch;
const FnMatch = meta_match.FnMatch;
const ParamMatch = meta_match.ParamMatch;
const PointerMatch = meta_match.PointerMatch;
const StructFieldMatch = meta_match.StructFieldMatch;
const StructMatch = meta_match.StructMatch;
const TypeMatch = meta_match.TypeMatch;

/// An interface for deinitialising.
///
/// If the type does not have a `deinit` function, the `deinit` function
/// does nothing.
pub fn Deinit(comptime T: type) type {
    return struct {
        // This matches a compatable 'deinit' function
        const DeinitMatch = FnMatch{
            // Only accept zig and C functions
            .calling_convention = .{ .options = &.{ .Unspecified, .C, .Inline } },
            // Don't accept C variadic functions
            .is_var_args = false,
            // It must return void
            .return_type = TypeMatch{ .Void = {} },
            .params = &.{
                // It must have a single pointer parameter
                // Note that the 'constness' of this pointer is not specified,
                // so functions that take '*const T' will also be accepted.
                ParamMatch{
                    .type = TypeMatch{
                        .Pointer = &PointerMatch{
                            // The pointer must point to one value
                            .size = .{ .options = &.{Type.Pointer.Size.One} },
                            // It must not be volatile
                            .is_volatile = false,
                            // It must be pointing to a 'T'
                            .child = TypeMatch{ .by_type = T },
                            // It must not have a sentinel
                            // Note that if this was just 'null', meta_match would not
                            // check it.
                            .sentinel = @as(?*const anyopaque, null),
                        },
                    },
                },
            },
        };

        /// The MetaMatch expression used to determine 'has_deinit'.
        pub const MetaMatch = TypeMatch{
            .container = &ContainerMatch{
                // It must be a container with a 'deinit' function matching 'DeinitMatch' above
                .decls = &.{DeclarationMatch{
                    .name = "deinit",
                    .type = .{ .Fn = &DeinitMatch },
                }},
            },
        };

        /// `true` if `T` has a `deinit` function.
        pub const has_deinit: bool = MetaMatch.match(T);
        pub const deinit_wrapped: *const fn (*T) void =
            &@This().wrapper;

        /// Deinitialise a value.
        pub inline fn deinit(value: *T) void {
            if (has_deinit) {
                T.deinit(value);
            }
        }

        fn wrapper(value: *T) void {
            @This().deinit(value);
        }
    };
}

const DeinitTests = struct {
    test "zig_structures.interfaces.Deinit" {
        const TypeA = struct {
            pub fn deinit(_: *@This()) void {}
        };
        const TypeB = enum {
            b,
            pub inline fn deinit(_: *@This()) void {}
        };
        const TypeC = union {
            c: void,
            pub fn deinit(_: *const @This()) void {}
        };
        const TypeD = struct {
            pub fn deinit(_: *@This()) callconv(.C) void {}
        };

        try testing.expect(Deinit(TypeA).has_deinit);
        var type_a = TypeA{};
        Deinit(TypeA).deinit(&type_a);
        try testing.expect(Deinit(TypeB).has_deinit);
        var type_b = TypeB.b;
        Deinit(TypeB).deinit(&type_b);
        try testing.expect(Deinit(TypeC).has_deinit);
        var type_c = TypeC{ .c = {} };
        Deinit(TypeC).deinit(&type_c);
        try testing.expect(Deinit(TypeD).has_deinit);
        var type_d = TypeD{};
        Deinit(TypeD).deinit(&type_d);

        const TypeE = struct {
            pub fn deinit(_: @This()) void {}
        };
        const TypeF = struct {
            pub fn deinit(_: [*]@This()) void {}
        };
        const TypeG = struct {
            pub fn deinit(_: *volatile @This()) void {}
        };
        const TypeH = struct {
            pub fn deinit(_: @This()) u8 {
                unreachable;
            }
        };

        try testing.expect(!Deinit(TypeE).has_deinit);
        try testing.expect(!Deinit(TypeF).has_deinit);
        try testing.expect(!Deinit(TypeG).has_deinit);
        try testing.expect(!Deinit(TypeH).has_deinit);
        var type_h = TypeH{};
        Deinit(TypeH).deinit(&type_h);

        try testing.expect(!Deinit(u8).has_deinit);
    }
};

/// Assert that a type has a `deinit` function at compile time.
///
/// The function must be public.
pub fn assert_deinit(comptime T: type) void {
    if (!Deinit(T).has_deinit) {
        @compileError(std.fmt.comptimePrint("type '{s}' does not have a 'deinit' function", .{@typeName(T)}));
    }
}

/// A type for testing if `deinit` is being called correctly on values.
pub fn DeinitTest(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();
        pub var deinit_called = false;
        const deinit_t = Deinit(T).deinit;

        pub fn deinit(value: *Self) void {
            deinit_t(&value.value);
            deinit_called = true;
        }

        pub inline fn reset() void {
            Self.deinit_called = false;
        }

        pub inline fn order(a: *const Self, b: *const Self) math.Order {
            if (!Order(T).has_order)
                @compileError("Order(_).order called on a DeinitTest, where the subtype does not implement Order");
            return Order(T).order(&a.value, &b.value);
        }
    };
}

const DeinitTestTests = struct {
    test "zig_structures.interfaces.DeinitTest" {
        try testing.expect(!Deinit(u8).has_deinit);
        var n: u8 = 5;
        // This will do nothing
        Deinit(u8).deinit(&n);

        const S = struct {
            pub fn deinit(_: *@This()) void {}
        };
        try testing.expect(Deinit(S).has_deinit);
        var s = S{};
        // This will run the deinit function
        Deinit(S).deinit(&s);

        assert_deinit(DeinitTest(u8));
        try testing.expect(Deinit(DeinitTest(u8)).has_deinit);

        DeinitTest(u8).deinit_called = false;
        var test_value = DeinitTest(u8){ .value = 5 };
        test_value.deinit();
        try testing.expect(DeinitTest(u8).deinit_called);
    }
};

fn OrderCommon(comptime T: type, comptime Order_: type) type {
    return struct {
        pub const order_wrapped: *const fn (*const T, *const T) math.Order =
            &@This().wrapper;

        fn wrapper(a: *const T, b: *const T) math.Order {
            return Order_.order(a, b);
        }
    };
}

/// An interface for ordering.
///
/// If the type does not have an `order` function, the `order` function
/// compares lexicographically by bytes.
pub fn Order(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Int, .Float => return struct {
            /// `true` if `T` has a custom `order` function.
            pub const has_order = true;

            /// Returns the order of the values with respect to eachother.
            pub inline fn order(a: *const T, b: *const T) math.Order {
                return math.order(a.*, b.*);
            }

            pub usingnamespace OrderCommon(T, @This());
        },

        else => {},
    }

    // A single const pointer to a 'T'
    const ConstPointerT = PointerMatch{
        .size = .{ .options = &.{Type.Pointer.Size.One} },
        .is_const = true,
        .is_volatile = false,
        .child = .{ .by_type = T },
        .sentinel = @as(?*const anyopaque, null),
    };

    // This matches the 'order' function.
    const OrderMatch = FnMatch{
        // Only accept zig and C functions
        .calling_convention = .{ .options = &.{ .Unspecified, .C, .Inline } },
        // Don't accept C variadic functions
        .is_var_args = false,
        // It must return an order
        .return_type = .{ .by_type = math.Order },
        // It must take two const pointers to 'T'
        .params = &.{
            .{ .type = .{ .Pointer = &ConstPointerT } },
            .{ .type = .{ .Pointer = &ConstPointerT } },
        },
    };

    // The MetaMatch expression used to determine 'has_order'.
    const MetaMatch = TypeMatch{ .container = &.{
        .decls = &.{.{ .name = "order", .type = .{ .Fn = &OrderMatch } }},
    } };

    return struct {
        /// `true` if `T` has a custom `order` function.
        pub const has_order: bool = MetaMatch.match(T);

        /// Returns the order of the values with respect to eachother.
        pub inline fn order(a: *const T, b: *const T) math.Order {
            if (has_order) {
                return T.order(a, b);
            } else {
                return std.mem.order(u8, mem.asBytes(a), mem.asBytes(b));
            }
        }

        pub usingnamespace OrderCommon(T, @This());
    };
}

/// Assert that a type has an `order` function at compile time.
///
/// The function must be public.
pub fn assert_order(comptime T: type) void {
    if (!Order(T).has_order) {
        @compileError(std.fmt.comptimePrint("type '{s}' does not have an 'order' function", .{@typeName(T)}));
    }
}

const OrderTests = struct {
    test "zig_structures.interfaces.Order" {
        const TypeA = struct {
            pub fn order(_: *const @This(), _: *const @This()) math.Order {
                unreachable;
            }
        };
        const TypeB = enum {
            b,
            pub inline fn order(_: *const @This(), _: *const @This()) math.Order {
                unreachable;
            }
        };

        try testing.expect(Order(TypeA).has_order);
        try testing.expect(Order(TypeB).has_order);

        const TypeC = struct {
            pub fn order(_: @This(), _: *const @This()) math.Order {
                unreachable;
            }
        };
        const TypeD = struct {
            pub fn order(_: *const @This(), _: @This()) math.Order {
                unreachable;
            }
        };
        const TypeE = struct {
            pub fn order(_: *const @This(), _: *const @This()) void {}
        };

        try testing.expect(!Order(TypeC).has_order);
        try testing.expect(!Order(TypeD).has_order);
        try testing.expect(!Order(TypeE).has_order);
    }
};

test "zig_structures.interfaces" {
    testing.refAllDecls(@This());

    // These tests are wrapped in structs so that their
    // declarations do not show up in the documentation.
    testing.refAllDecls(DeinitTests);
    testing.refAllDecls(DeinitTestTests);
    testing.refAllDecls(OrderTests);
}
