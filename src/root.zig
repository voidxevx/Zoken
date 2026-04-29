//! Zoken
//! 4/27/2026 - Nyx

// INCLUDES -----
const std = @import("std");

// MODULES -----
pub const SearchTree = @import("search-tree.zig").SearchTree;

/// Shorthands for deeply nested structs
pub fn aliases(comptime Token: type) type {
    return struct {
        pub const State = SearchTree(Token).State;
        pub const KeywordToken = SearchTree(Token).Generator.KeywordToken;
        pub const CustomState = SearchTree(Token).Generator.CustomState;
        pub const EntryStateRule = SearchTree(Token).EntryState.EntryStateRule;
    };
}

/// A stream of tokens that can be parsed.
pub fn TokenStream(comptime Token: type) type {
    return struct {
        tokens: []Token,

        /// Object that converts a string of characters into a token stream
        const Tokenizer = struct {

            /// The default allocated buffer size for the token buffer
            const DEFAULT_TOKEN_BUFFER_CAPACITY: usize = 16;
            /// Allocated token string buffer size
            const BUFFER_SIZE: usize = 128;

            /// General purpose allocator
            gpa: std.mem.Allocator,

            /// The buffer of tokens
            tokens: []Token,
            /// the current count of tokens
            token_count: usize = 0,
            /// the current capacity for the token buffer
            token_capacity: usize = DEFAULT_TOKEN_BUFFER_CAPACITY,

            /// The search tree used to tokenize the string
            search_tree: SearchTree(Token),
            /// the current node/state in the search tree
            current_state: *SearchTree(Token).State,

            /// the string being parsed
            string: []const u8,
            /// the current index within the string
            idx: usize = 0,

            /// the buffer for the substring string being tokenized
            buffer: []u8,
            /// the current size of the buffer 
            buffer_size: usize = 0,

            fn init(
                gpa: std.mem.Allocator, 
                tree: SearchTree(Token), 
                string: []const u8
            ) !Tokenizer {
                return .{
                    .gpa = gpa,
                    .tokens = try gpa.alloc(Token, DEFAULT_TOKEN_BUFFER_CAPACITY),
                    .search_tree = tree,
                    .current_state = tree.keywords,
                    .string = string,
                    .buffer = try gpa.alloc(u8, BUFFER_SIZE),
                };
            }

            /// Ends the tokenizer freeing the allocated resources and creating a token stream
            fn finish(self: *Tokenizer) !TokenStream(Token) {
                self.gpa.free(self.buffer);

                return .{
                    .tokens = try self.gpa.realloc(self.tokens, self.token_count),
                };
            }

            /// Pushes a token to the buffer
            fn push_token(self: *Tokenizer, token: Token) !void {
                if (self.token_count >= self.token_capacity) {
                    self.*.token_capacity *= 2;
                    self.*.tokens = try self.gpa.realloc(self.tokens, self.token_capacity);
                }

                self.*.tokens[self.token_count] = token;
                self.*.token_count += 1;
            }

            /// Resets the state back to the head of the search tree
            fn reset_state(self: *Tokenizer) void {
                self.*.current_state = self.search_tree.keywords;
            }

            /// consumes the current character filling the string buffer
            fn consume(self: *Tokenizer) void {
                self.*.buffer[self.buffer_size] = self.string[self.idx];
                self.*.buffer_size += 1;
            }

            /// evokes the current state to generate a token from the buffer
            fn construct_buffer(self: *Tokenizer) !?Token {
                return self.current_state.construct(self.buffer[0..self.buffer_size]);
            }

            /// evokes the fallback state to generate a token from the buffer
            fn construct_fallback(self: *Tokenizer) !Token {
                return self.search_tree.fallback_state.fallback(self.buffer[0..self.buffer_size]);
            }

            /// pushes the current state's token to the token buffer
            fn push_current(self: *Tokenizer) !void {
                if (try self.construct_buffer()) |token| {
                    try self.push_token(token);
                } else {
                    try self.push_token(try self.construct_fallback());
                }
            }

            /// The main tokenization loop
            fn tokenize(self: *Tokenizer) !void {
                while (self.idx < self.string.len) {
                    defer self.*.idx += 1;
                    const ch = self.string[self.idx];

                    // Traverses the search tree
                    switch (self.current_state.traverse(ch)) {
                        .Exited => {
                            self.*.current_state = self.search_tree.fallback_state.interface();
                        },
                        .Break => {
                            try self.push_current();
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

                // pushes any remaining tokens
                try self.push_current();
            }

        };

        pub fn init(
            gpa: std.mem.Allocator, 
            tree: SearchTree(Token), 
            string: []const u8
        ) !TokenStream(Token) {
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