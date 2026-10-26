const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root.zig");
const Token = root.model.Token;
const Group = root.model.Group;

pub fn serialize(value: anytype, allocator: Allocator) ![]const u8 {
    var tokens = try root.tokenize(value, allocator);
    defer tokens.deinit(allocator);

    var document = try Document.parse(allocator, tokens.items);
    defer document.deinit();

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try document.format(&out.writer);
    return out.toOwnedSlice();
}

const Value = union(enum) {
    null,
    boolean: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: []const Value,
    object: Object,

    pub fn parse(allocator: Allocator, stream: *root.TokenStream) !Value {
        const token = stream.next() orelse return error.MissingToken;
        switch (token) {
            .boolean => |value| {
                return .{ .boolean = value };
            },
            .u8, .u16, .u32, .i8, .i16, .i32, .i64 => |value| {
                return .{ .int = @intCast(value) };
            },
            .u64 => |value| {
                // handle this integer type explicitly different,
                // as theoretically it can overflow
                if (value >= std.math.maxInt(i64)) {
                    return error.IntegerOverflow;
                }
                return .{ .int = @intCast(value) };
            },
            .f32, .f64 => |value| {
                return .{ .float = @floatCast(value) };
            },
            .sequence => |header| {
                const values = try Value.parseGroup(
                    Value,
                    allocator,
                    stream,
                    header,
                    .sequence_end,
                    Value.parse,
                );

                return .{ .array = values };
            },
            .structure => |header| {
                const fields = try Value.parseGroup(
                    Field,
                    allocator,
                    stream,
                    header,
                    .structure_end,
                    Field.parse,
                );

                return .{ .object = .{ .fields = fields } };
            },
            else => return error.MalformedTokenStream,
        }
    }

    fn parseGroup(
        comptime T: type,
        allocator: Allocator,
        stream: *root.TokenStream,
        header: Group,
        tail: Token,
        comptime func: fn(Allocator, *root.TokenStream) anyerror!T
    ) ![]const T
    {
        var values = try allocator.alloc(T, header.count);
        errdefer allocator.free(values);

        var index: usize = 0;
        while (!(stream.peek() orelse return error.MalformedTokenStream).*.eql(tail)) {
            if (index >= header.count) {
                return error.MalformedTokenStream;
            }

            const val = try func(allocator, stream);
            values[index] = val;

            index += 1;
        }

        const next = stream.next() orelse return error.MalformedTokenStream;
        if (!next.eql(tail)) {
            return error.MalformedTokenStream;
        }

        return values;
    }
};

const Field = struct {
    key: []const u8,
    value: Value,

    const Self = @This();

    pub fn parse(allocator: Allocator, stream: *root.TokenStream) !Self {
        // a field should first have a id ...
        const id_token = stream.next() orelse return error.MissingToken;
        const key = switch (id_token) {
            .id => |value| value,
            else => return error.MalformedTokenStream,
        };

        // ... then have a value
        const value = try Value.parse(allocator, stream);

        return .{
            .key = key,
            .value = value,
        };
    }
};

const Object = struct {
    fields: []const Field,
};

const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    const Self = @This();

    const indent_width = 2;

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn parse(allocator: Allocator, tokens: []const Token) !Self {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        errdefer arena.deinit();

        var stream = root.TokenStream.init(tokens);
        const value = try Value.parse(arena.allocator(), &stream);

        return .{
            .arena = arena,
            .root = value,
        };
    }

    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writeValue(writer, self.root, 0);
        try writer.writeByte('\n');
    }

    fn writeIndent(writer: *std.Io.Writer, depth: usize) !void {
        try writer.splatByteAll(' ', depth * indent_width);
    }

    fn writeValue(
        writer: *std.Io.Writer,
        value: Value,
        depth: usize,
    ) std.Io.Writer.Error!void {
        switch (value) {
            .null => try writer.writeAll("null"),
            .boolean => |val| try writer.writeAll(if (val) "true" else "false"),
            .int => |val| try writer.print("{d}", .{val}),
            .float => |val| {
                // as NaN or the +-inf arent valid json floats, filter these out
                if (std.math.isFinite(val)) {
                    try writer.print("{d}", .{val});
                } else {
                    try writer.writeAll("null");
                }
            },
            .string => |val| try writeString(writer, val),
            .array => |items| try writeArray(writer, items, depth),
            .object => |object| try writeObject(writer, object, depth),
        }
    }

    fn writeArray(writer: *std.Io.Writer, items: []const Value, depth: usize) std.Io.Writer.Error!void {
        if (items.len == 0) {
            return writer.writeAll("[]");
        }

        try writer.writeAll("[\n");
        for (items, 0..) |item, i| {
            try writeIndent(writer, depth + 1);
            try writeValue(writer, item, depth + 1);

            if (i < items.len - 1) {
                try writer.writeAll(",\n");
            }
        }

        try writer.writeByte('\n');
        try writeIndent(writer, depth);
        try writer.writeByte(']');
    }

    fn writeString(writer: *std.Io.Writer, string: []const u8) std.Io.Writer.Error!void {
        const character_start_limit = 0x20;

        try writer.writeByte('"');

        var cursor: usize = 0;
        for (string, 0..) |chr, i| {
            const escape: ?[]const u8 = switch (chr) {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                0x08 => "\\b",
                0x0c => "\\f",
                else => null,
            };

            if (escape == null and chr >= character_start_limit) { continue; }

            try writer.writeAll(string[cursor..i]);
            cursor = i + 1;

            if (escape) |e| {
                try writer.writeAll(e);
            } else {
                try writer.print("\\u{x:0>4}", .{chr});
            }
        }

        try writer.writeAll(string[cursor..]);
        try writer.writeByte('"');
    }

    fn writeObject(writer: *std.Io.Writer, object: Object, depth: usize) std.Io.Writer.Error!void {
        if (object.fields.len == 0) {
            return writer.writeAll("{}");
        }

        try writer.writeAll("{\n");
        for (object.fields, 0..) |field, i| {
            try writeIndent(writer, depth + 1);
            try writeString(writer, field.key);

            try writer.writeAll(": ");
            try writeValue(writer, field.value, depth + 1);

            if (i < object.fields.len - 1) {
                try writer.writeAll(",\n");
            }
        }

        try writer.writeByte('\n');
        try writeIndent(writer, depth);
        try writer.writeByte('}');
    }
};
