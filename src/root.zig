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

            gpa: std.mem.Allocator,

            tokens: []Token,
            token_count: usize = 0,
            token_capacity: usize = DEFAULT_TOKEN_BUFFER_CAPACITY,

            string: []const u8,
            idx: usize = 0,


            fn finish(self: *Tokenizer) !TokenStream(Token) {
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


        };

        pub fn init(gpa: std.mem.Allocator, string: []const u8) !TokenStream(Token) {
            _ = gpa; _ = string;
            return .{
                .tokens = &[_]Token {},
            };
        }
    };
}