//! Zoken
//! 4/27/2026 - Nyx

// INCLUDES -----
const std = @import("std");

// MODULES -----
pub const SearchTree = @import("search-tree.zig").SearchTree;

pub fn TokenStream(comptime Token: type) type {
    switch (@typeInfo(Token)) {
        .@"enum", .@"union" => {},
        else => @compileError("Tokens must be of type enum or union"),
    }

    return struct {
        tokens: []Token,

        const Tokenizer = struct {
            const DEFAULT_TOKEN_BUFFER_CAPACITY: usize = 16;
            const BUFFER_SIZE: usize = 128;

            gpa: std.mem.Allocator,

            tokens: []Token,
            token_count: usize = 0,
            token_capacity: usize = DEFAULT_TOKEN_BUFFER_CAPACITY,

            search_tree: SearchTree(Token),
            current_state: *SearchTree(Token).State,

            string: []const u8,
            idx: usize = 0,

            buffer: []u8,
            buffer_size: usize = 0,

            fn init(gpa: std.mem.Allocator, tree: SearchTree(Token), string: []const u8) !Tokenizer {
                return .{
                    .gpa = gpa,
                    .tokens = try gpa.alloc(Token, DEFAULT_TOKEN_BUFFER_CAPACITY),
                    .search_tree = tree,
                    .current_state = tree.keywords,
                    .string = string,
                    .buffer = try gpa.alloc(u8, BUFFER_SIZE),
                };
            }

            fn finish(self: *Tokenizer) !TokenStream(Token) {
                self.gpa.free(self.buffer);

                return .{
                    .tokens = try self.gpa.realloc(self.tokens, self.token_count),
                };
            }

            fn push_token(self: *Tokenizer, token: Token) !void {
                if (self.token_count >= self.token_capacity) {
                    self.*.token_capacity *= 2;
                    self.*.tokens = try self.gpa.realloc(self.tokens, self.token_capacity);
                }

                self.*.tokens[self.token_count] = token;
                self.*.token_count += 1;
            }

            fn reset_state(self: *Tokenizer) void {
                self.*.current_state = self.search_tree.keywords;
            }

            fn consume(self: *Tokenizer) void {
                self.*.buffer[self.buffer_size] = self.string[self.idx];
                self.*.buffer_size += 1;
            }

            fn construct_buffer(self: *Tokenizer) !?Token {
                return self.current_state.construct(self.buffer[0..self.buffer_size]);
            }

            fn construct_fallback(self: *Tokenizer) !Token {
                return self.search_tree.fallback_state.fallback(self.buffer[0..self.buffer_size]);
            }

            fn push_current(self: *Tokenizer) !void {
                if (try self.construct_buffer()) |token| {
                    try self.push_token(token);
                } else {
                    try self.push_token(try self.construct_fallback());
                }
            }

            fn tokenize(self: *Tokenizer) !void {
                while (self.idx < self.string.len) {
                    defer self.*.idx += 1;
                    const ch = self.string[self.idx];

                    if (std.ascii.isWhitespace(ch)) {
                        try self.push_current();
                        self.*.buffer_size = 0;
                        self.reset_state();
                    }

                    switch (self.current_state.traverse(ch)) {
                        .Exited => {
                            self.*.current_state = self.search_tree.fallback_state.interface();
                        },
                        .Break => {
                            if (try self.construct_buffer()) |token| {
                                try self.push_token(token);
                            }
                            self.reset_state();
                            self.*.buffer_size = 0;
                        },
                        .Changed => |new_state| {
                            self.*.current_state = new_state;
                        },
                        .Stays => {}
                    }

                    self.consume();
                }

                try self.push_current();
            }

        };

        pub fn init(gpa: std.mem.Allocator, tree: SearchTree(Token), string: []const u8) !TokenStream(Token) {
            var tokenizer: Tokenizer = try .init(gpa, tree, string);
            try tokenizer.tokenize();
            return try tokenizer.finish();
        }

        pub fn format(self: *const TokenStream(Token), writer: *std.io.Writer) std.io.Writer.Error!void {
            for (self.tokens) |token| {
                try writer.print("{f} ", .{token});
            }
        }
    };
}