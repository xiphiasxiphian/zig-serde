const std = @import("std");
const Allocator = std.mem.Allocator;
const Type = std.builtin.Type;

pub const Group = struct { name: []const u8, count: usize };
pub const Token = union(enum) {
    // primitives
    boolean: bool,
    i8: i8,
    i16: i16,
    i32: i32,
    i64: i64,
    u8: u8,
    u16: u16,
    u32: u32,
    u64: u64,
    f32: f32,
    f64: f64,

    id: []const u8,

    sequence: Group,
    sequence_end,

    tuple: Group,
    tuple_end,

    map: Group,
    map_end,

    structure: Group,
    structure_end,

    pub fn format(self: Token, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            inline else => |val, tag| {
                const T = @TypeOf(val);
                if (T == Group) {
                    try writer.print(
                        ".{s} = {{ .name = \"{s}\", .count = {d} }}",
                        .{ @tagName(tag), val.name, val.count },
                    );
                } else if (T == []const u8) {
                    try writer.print(".{s} = \"{s}\"", .{@tagName(tag), val});
                } else if (T == void) {
                    try writer.print(".{s}", .{@tagName(tag)});
                } else {
                    try writer.print(".{s} = {any}", .{ @tagName(tag), val });
                }
            },
        }
    }
};

pub fn serializeValue(value: anytype, allocator: Allocator, tokens: *std.ArrayList(Token)) !void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .bool => try tokens.append(allocator, .{ .boolean = value }),
        .int => |info| {
            try serializeInt(value, info, allocator, tokens);
        },
        .float => |info| {
            try serializeFloat(value, info, allocator, tokens);
        },
        .@"struct" => |info| {
            try serializeStruct(value, info, allocator, tokens);
        },
        .array => try serializeArray(value, allocator, tokens),
        else => @compileError("Unsupported value for serialization: " ++ getShortTypeName(T)),
    }
}

fn serializeInt(value: anytype, comptime info: Type.Int, allocator: Allocator, tokens: *std.ArrayList(Token)) !void {
    switch (info.bits) {
        8 => try tokens.append(allocator, if (info.signedness == .signed) .{ .i8 = @intCast(value) } else .{ .u8 = @intCast(value) }),
        16 => try tokens.append(allocator, if (info.signedness == .signed) .{ .i16 = @intCast(value) } else .{ .u16 = @intCast(value) }),
        32 => try tokens.append(allocator, if (info.signedness == .signed) .{ .i32 = @intCast(value) } else .{ .u32 = @intCast(value) }),
        64 => try tokens.append(allocator, if (info.signedness == .signed) .{ .i64 = @intCast(value) } else .{ .u64 = @intCast(value) }),
        else => @compileError("Unsupported integer bit-width: " ++ @typeName(@TypeOf(value))),
    }
}

fn serializeFloat(value: anytype, comptime info: Type.Float, allocator: Allocator, tokens: *std.ArrayList(Token)) !void {
    switch (info.bits) {
        32 => try tokens.append(allocator, .{ .f32 = @floatCast(value) }),
        64 => try tokens.append(allocator, .{ .f64 = value }),
        else => @compileError("Unsupported float bit-width: " ++ @typeName(@TypeOf(value))),
    }
}

fn serializeStruct(value: anytype, comptime info: Type.Struct, allocator: Allocator, tokens: *std.ArrayList(Token)) !void {
    const T = @TypeOf(value);

    if (info.is_tuple) {
        try tokens.append(allocator, .{ .tuple = .{ .name = getShortTypeName(T), .count = info.field_names.len } });
        inline for (info.field_names) |field_name| {
            try serializeValue(@field(value, field_name), allocator, tokens);
        }
        try tokens.append(allocator, .tuple_end);
    } else {
        try tokens.append(allocator, .{ .structure = .{ .name = getShortTypeName(T), .count = info.field_names.len } });
        inline for (info.field_names) |field_name| {
            try tokens.append(allocator, .{ .id = field_name });
            try serializeValue(@field(value, field_name), allocator, tokens);
        }
        try tokens.append(allocator, .structure_end);
    }
}

fn serializeArray(value: anytype, allocator: Allocator, tokens: *std.ArrayList(Token)) !void {
    const T = @TypeOf(value);

    try tokens.append(allocator, .{ .sequence = .{
        .name = getShortTypeName(T),
        .count = value.len,
    } });

    for (value) |item| {
        try serializeValue(item, allocator, tokens);
    }

    try tokens.append(allocator, .sequence_end);
}

fn getShortTypeName(comptime T: type) []const u8 {
    const full_name = @typeName(T);

    if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |idx| {
        return full_name[idx + 1 ..];
    }

    return full_name;
}
