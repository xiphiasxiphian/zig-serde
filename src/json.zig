const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root.zig");
const Token = root.model.Token;

pub fn serialize(value: anytype, allocator: Allocator) ![]const u8 {
    const tokens = try root.serialize(value, allocator);
    const document = try Document.parse(allocator, tokens.items);
    defer document.deinit();
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
            .sequence => |group| {
                var values = try allocator.alloc(Value, group.count);
                errdefer allocator.free(values);

                var index = 0;
                while (stream.peek() != .sequence_end) {
                    if (index >= group.count) {
                        return error.MalformedTokenStream;
                    }

                    const val = try Value.parse(allocator, stream);
                    values[index] = val;

                    index += 1;
                }

                // this should be the end of the sequence. if not, the token stream is
                // malformed
                if (stream.next() != .sequence_end) {
                    return error.MalformedTokenStream;
                }

                return .{ .array = values };
            },
            else => return error.InvalidTokenStream,
        }
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
};
