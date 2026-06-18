const std = @import("std");
const ast = @import("../ast.zig");
const Parser = @import("../parser.zig").Parser;
const Error = @import("../parser.zig").Error;

const literals = @import("literals.zig");
const class = @import("class.zig");
const ts = @import("ts/types.zig");
const expressions = @import("expressions.zig");

//
// ArkUI struct declarations (HarmonyOS ArkTS).
//
// An ArkUI struct is a class-like container (`@Component struct Foo { ... }`)
// holding state fields and a `build()` method. It has no `extends` /
// `implements`; its body reuses the class body grammar (`class.parseClassBody`)
// so methods, properties, decorators, and modifiers all parse identically.
// Mirrors oxc's `parse_struct_declaration` (`crates/oxc_parser/src/js/arkui.rs`).
//

pub const ParseStructOpts = struct {
    // `declare struct Foo { ... }` (ambient).
    is_declare: bool = false,
};

/// Parse an ArkUI `struct` declaration. Entry is either `struct` directly, or
/// a caller-consumed modifier (`declare`) passed via `start_from_param`. When
/// reached through `parseDecoratedStatement`, `decorators` carries the leading
/// `@Component` / `@Entry` / … decorators.
pub fn parseStruct(
    parser: *Parser,
    opts: ParseStructOpts,
    start_from_param: ?u32,
    decorators: ast.IndexRange,
) Error!?ast.NodeIndex {
    std.debug.assert(start_from_param != null or parser.current_token.tag == .@"struct");
    const start = start_from_param orelse parser.current_token.span.start;
    if (!try parser.expect(.@"struct", "Expected 'struct' keyword", null)) return null;

    if (parser.context.single_statement) {
        @branchHint(.unlikely);
        try parser.report(
            .{ .start = start, .end = parser.current_token.span.end },
            "Struct declarations are not allowed in single-statement contexts",
            .{ .help = "Wrap the struct declaration in a block: { struct S {} }" },
        );
    }

    const id: ast.NodeIndex = if (parser.current_token.tag.isIdentifierLike())
        try literals.parseBindingIdentifier(parser) orelse .null
    else
        .null;

    if (id == .null) {
        try parser.report(
            parser.current_token.span,
            "Struct declaration requires a name",
            .{ .help = "Add a name after 'struct', e.g. 'struct MyComponent {}'." },
        );
        return null;
    }

    // `struct Foo<T, U extends V> ...`
    const type_parameters: ast.NodeIndex = if (parser.tree.isTs())
        try ts.parseTypeParameters(parser)
    else
        .null;

    // Reuse the class body grammar: methods, properties, decorators, modifiers.
    const body = try class.parseClassBody(parser) orelse return null;

    return try parser.tree.addNode(.{ .arkui_struct = .{
        .decorators = decorators,
        .id = id,
        .type_parameters = type_parameters,
        .body = body,
        .declare = opts.is_declare,
    } }, .{ .start = start, .end = parser.tree.span(body).end });
}

//
// ArkTS `@interface` annotation declarations.
//
// `@interface Name { prop: T; opt?: T = default; }` defines a custom
// annotation. The caller has already consumed the leading `@`; we land on
// `interface`. The body reuses the class body grammar (property definitions).
// Mirrors oxc's `parse_annotation_declaration`.
//

/// Parse an ArkTS `@interface` annotation declaration. `start` is the offset
/// of the leading `@`; `decorators` carries any decorators preceding the
/// `@interface` (rare). The cursor is on `interface`.
pub fn parseAnnotationDeclaration(
    parser: *Parser,
    opts: ParseStructOpts,
    start: u32,
    decorators: ast.IndexRange,
) Error!?ast.NodeIndex {
    if (!try parser.expect(.interface, "Expected 'interface' after '@'", null)) return null;

    const id: ast.NodeIndex = if (parser.current_token.tag.isIdentifierLike())
        try literals.parseBindingIdentifier(parser) orelse .null
    else
        .null;

    if (id == .null) {
        try parser.report(
            parser.current_token.span,
            "Annotation declaration requires a name",
            .{ .help = "Add a name after '@interface', e.g. '@interface MyAnnotation {}'." },
        );
        return null;
    }

    // Reuse the class body grammar (property definitions).
    const body = try class.parseClassBody(parser) orelse return null;

    return try parser.tree.addNode(.{ .arkui_annotation = .{
        .decorators = decorators,
        .id = id,
        .body = body,
        .declare = opts.is_declare,
    } }, .{ .start = start, .end = parser.tree.span(body).end });
}

//
// ArkUI declarative component expressions.
//
// `Column(args) { children }` — a call followed (same line) by a children
// block. Reached from `parseCallExpression` right after the call's `)`. The
// children block is a statement list (nested components are expression
// statements, control flow is `if`/`for`/…). Trailing `.method(...)` chains
// are left to the ordinary call/member loop, which wraps this node.
// Mirrors oxc's `parse_arkui_component_expression_after_args`.
//

/// Parse the `{ children }` block of a component and build the
/// `arkui_component` node. The caller has already parsed `callee(args)`;
/// the cursor is on `{`.
pub fn parseArkuiComponentAfterArgs(
    parser: *Parser,
    start: u32,
    callee: ast.NodeIndex,
    type_arguments: ast.NodeIndex,
    arguments: ast.IndexRange,
) Error!?ast.NodeIndex {
    if (!try parser.expect(
        .left_brace,
        "Expected '{' to start ArkUI component body",
        null,
    )) return null;

    // Children are statements: nested components (expression statements),
    // expressions, and control flow (`if`/`For`/…).
    const children = try parser.parseBody(.right_brace, .other);

    const end = parser.current_token.span.end; // '}' position
    if (!try parser.expect(
        .right_brace,
        "Expected '}' to close ArkUI component body",
        null,
    )) return null;

    return try parser.tree.addNode(.{ .arkui_component = .{
        .callee = callee,
        .type_arguments = type_arguments,
        .arguments = arguments,
        .children = children,
    } }, .{ .start = start, .end = end });
}

//
// ArkUI leading-dot expressions.
//
// `.method(args).chain()` — a state-style modifier with implicit `this`,
// appearing at primary position (standalone statement / component child) and
// inside state-style object literals. The leading `.` distinguishes it from a
// plain call; we wrap the resulting call/member chain so the dot round-trips.
// Mirrors oxc's `parse_leading_dot_expression`.
//

/// Parse `.method(args).chain()`. The cursor is on the leading `.`.
pub fn parseLeadingDotExpression(parser: *Parser) Error!?ast.NodeIndex {
    std.debug.assert(parser.current_token.tag == .dot);
    const start = parser.current_token.span.start;
    try parser.advance() orelse return null; // consume leading `.`

    // first `.method` as an identifier, then its `(args)` if present
    var expr = try literals.parseIdentifier(parser) orelse return null;
    if (parser.current_token.tag == .left_paren) {
        expr = try expressions.parseCallExpression(parser, expr, false, .null) orelse return null;
    }

    // remaining chain `.method(args).method(args)` …
    while (parser.current_token.tag == .dot) {
        expr = try expressions.parseStaticMemberExpression(parser, expr, false) orelse return null;
        if (parser.current_token.tag == .left_paren) {
            expr = try expressions.parseCallExpression(parser, expr, false, .null) orelse return null;
        }
    }

    return try parser.tree.addNode(
        .{ .arkui_leading_dot = .{ .expression = expr } },
        .{ .start = start, .end = parser.tree.span(expr).end },
    );
}
