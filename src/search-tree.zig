//! Search Tree
//! 4/27/2026 - Nyx

// INCLUDES -----
const std = @import("std");

pub fn SearchTree(comptime Token: type) type {
    return struct {

        keywords: *State,

        pub const State = struct {
            vtable: *const VTable,

            const ReturnStatus = union(enum) {
                Exited,
                Changed: *State,
            };

            const VTable = struct {
                construct: *const fn(*anyopaque, []const u8) anyerror!Token,
                traverse: *const fn(*anyopaque, u8) ReturnStatus,
                deinit: *const fn(*anyopaque, std.mem.Allocator) void,
            };

            pub fn construct(self: *State, buffer: []const u8) anyerror!Token {
                return self.vtable.construct(self, buffer);
            }

            pub fn traverse(self: *State, ch: u8) ReturnStatus {
                return self.vtable.traverse(self, ch);
            }

            pub fn deinit(self: *State, gpa: std.mem.Allocator) void {
                self.vtable.deinit(self, gpa);
            }
        };

        pub const KeywordState = struct {
            const __vtable: State.VTable = .{
                .construct = KeywordState.__construct,
                .traverse = KeywordState.__traverse,
                .deinit = KeywordState.__deinit,
            };

            vtable: *const State.VTable = &__vtable,
            token: ?Token,
            children: [256]?*KeywordState,

            const Error = error {
                CannotConstructToken,
                TokenAlreadyBound,
            };

            fn __construct(ptr: *anyopaque, _: []const u8) anyerror!Token {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                if (self.token) |token| {
                    return token;
                } else {
                    return Error.CannotConstructToken;
                }
            }

            fn __traverse(ptr: *anyopaque, ch: u8) State.ReturnStatus {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                if (self.children[ch]) |child| {
                    return .{ .Changed = child.interface() };
                } else {
                    return .Exited;
                }
            }

            fn __deinit(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                for (self.children) |child| if (child) |child_ptr| {
                    child_ptr.interface().deinit(gpa);
                };

                gpa.destroy(self);
            }

            pub fn new(gpa: std.mem.Allocator, token: ?Token) !*KeywordState {
                const state = try gpa.create(KeywordState);
                state.*.vtable = &__vtable;
                state.*.token = token;
                state.*.children = [_]?*KeywordState{null} ** 256;

                return state;
            }

            pub fn attach_child(self: *KeywordState, gpa: std.mem.Allocator, character: u8, token: ?Token) !*KeywordState {
                if (self.children[character]) |child| {
                    if (child.token == null) {
                        child.*.token = token;
                    } else {
                        return Error.TokenAlreadyBound;
                    }
                    return child;
                } else {
                    const child = try KeywordState.new(gpa, token);
                    self.*.children[character] = child;
                    return child;
                }
            }

            pub fn interface(self: *KeywordState) *State {
                return @ptrCast(@alignCast(self));
            }
        };

        pub const Generator = struct {

            gpa: std.mem.Allocator,

            keywords: []const []const u8,
            tokens: []const Token,

            keyword_head: *KeywordState,
            current: *KeywordState,

            const Error = error {
                MismatchingKeywordTokenArrays,
            };

            pub fn init(gpa: std.mem.Allocator, keywords: []const []const u8, tokens: []const Token) !Generator {
                const head = try KeywordState.new(gpa, null);
                return .{
                    .gpa = gpa,
                    .keywords = keywords,
                    .tokens = tokens,
                    .keyword_head = head,
                    .current = head,
                };
            }

            pub fn generate(self: *Generator) !void {
                if (self.keywords.len != self.tokens.len)
                    return Error.MismatchingKeywordTokenArrays;

                for (0..self.keywords.len) |i| {
                    const kw: []const u8 = self.keywords[i];
                    const tk: Token = self.tokens[i];
                    try self.trace_branch(kw, tk);
                }
            }

            pub fn finish(self: *Generator) SearchTree(Token) {
                return .{
                    .keywords = self.keyword_head.interface(),
                };
            }

            fn trace_branch(self: *Generator, keyword: []const u8, token: Token) !void {
                for (0..keyword.len - 1) |i| {
                    const ch: u8 = keyword[i];
                    self.*.current = try self.*.current.attach_child(self.gpa, ch, null);
                }

                const ch: u8 = keyword[keyword.len - 1];
                _ = try self.*.current.attach_child(self.gpa, ch, token);
                self.*.current = self.keyword_head;
            }
        };


        pub fn init(gpa: std.mem.Allocator, keywords: []const []const u8, tokens: []const Token) !SearchTree(Token) {
            var gen: Generator = try .init(gpa, keywords, tokens);
            try gen.generate();
            return gen.finish();
        }

        pub fn deinit(self: *SearchTree(Token), gpa: std.mem.Allocator) void {
            self.keywords.deinit(gpa);
        }

    };
}

