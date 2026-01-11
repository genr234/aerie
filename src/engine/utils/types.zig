pub inline fn F32(value: anytype) f32 {
    // Accept both ints and floats.
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @floatFromInt(value),
        .float, .comptime_float => @floatCast(value),
        else => @floatFromInt(@as(i64, @intCast(value))),
    };
}

pub inline fn I32(value: anytype) i32 {
    // Accept both ints and floats.
    return switch (@typeInfo(@TypeOf(value))) {
        .float, .comptime_float => @intFromFloat(value),
        else => @intCast(value),
    };
}