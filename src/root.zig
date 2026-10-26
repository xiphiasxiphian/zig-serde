const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const model = @import("model.zig");
pub const json = @import("json.zig");

const Token = model.Token;

pub fn tokenize(value: anytype, allocator: Allocator) !std.ArrayList(Token) {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);

    try model.serializeValue(value, allocator, &tokens);

    return tokens;
}

pub const TokenStream = struct {
    inner: []const Token,
    cursor: usize,

    const Self = @This();

    pub fn init(inner: []const Token) Self {
        return .{
            .inner = inner,
            .cursor = 0,
        };
    }

    pub fn remaining(self: *const Self) ?[]const Token {
        if (self.cursor >= self.inner.items.len) {
            return null;
        }
        return self.inner[self.cursor..];
    }

    pub fn peek(self: *const Self) ?*const Token {
        if (self.cursor >= self.inner.len) {
            return null;
        }

        return &self.inner[self.cursor];
    }

    pub fn next(self: *Self) ?Token {
        if (self.cursor >= self.inner.len) {
            return null;
        }

        const value = self.inner[self.cursor];
        self.cursor += 1;

        return value;
    }

    pub fn consume(self: *Self, count: usize) ?[]const Token {
        if (self.cursor + count - 1 >= self.inner.len) {
            return null;
        }

        const value = self.inner[self.cursor..(self.cursor + count)];
        self.cursor += count;

        return value;
    }
};
