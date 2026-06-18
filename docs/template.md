# Template API

Zypher's template engine is a custom implementation with:
- Auto-escaping of HTML (use `|safe` filter to bypass)
- Dot notation for field access (`{{ user.name }}`)
- List index access (`{{ items.0 }}`)
- `{% include %}` directive
- `{% extends %}` / `{% block %}` inheritance
- `{% if %}` / `{% elif %}` / `{% else %}` conditionals
- `{% for %}` loops with `forloop` context
- Pipe filters (`{{ name|upper|truncate(10) }}`)

## Value
Union type representing template values.

### Variants
- `string: []const u8`
- `int: i64`
- `float: f64`
- `bool: bool`
- `list: []const Value`
- `map: *Context`
- `null_val: void`

### Methods
- `value.format(writer)` — format value to writer (formats lists as comma-separated, maps as key: value pairs)
- `value.isTruthy() bool` — string: non-empty, int/float: non-zero, bool: true, list: non-empty, map: always true, null: false

## Context
Template variable context — a string-keyed map of `Value`s.

### Methods
- `Context.init(allocator) Context` — create a new context
- `context.deinit()` — free resources
- `context.put(key, value) !void` — set a variable
- `context.get(key) ?Value` — get a variable

## Template
A parsed template with cached AST.

### Methods
- `Template.fromSource(allocator, source) !Template` — parse template source into an AST (tokenizes, parses, takes ownership of nodes)
- `template.deinit()` — free all nodes and source
- `template.render(ctx, writer) !void` — render the template with the given context; handles `{% extends %}`, `{% include %}`, variables, filters, conditionals, and loops

### Rendering Features
- `{% extends "base.html" %}` — must be the first node; loads the base template and fills `{% block %}` slots
- `{% include "partial.html" %}` — includes another template (requires engine reference)
- `{{ var.field }}` — dot notation for nested field access on maps
- `{{ list.0 }}` — numeric index access on lists
- `{{ var|upper|truncate(10) }}` — filter pipeline
- `{% if condition %}...{% elif other %}...{% else %}...{% endif %}` — conditionals (checks truthiness)
- `{% for item in list %}...{% endfor %}` — loops with `forloop` context: `counter0`, `counter`, `first`, `last`

## TemplateEngine
Template cache with load and render operations.

### Methods
- `TemplateEngine.init(allocator) TemplateEngine` — create a new engine
- `engine.deinit()` — free all cached templates
- `engine.load(name, source) !*Template` — parse and cache a template; returns pointer to cached template
- `engine.render(name, ctx, writer) !void` — render a cached template by name
- `engine.getTemplate(name) ?*Template` — get a cached template by name

## Lexer
Template source tokenizer.

### Lexer.init(allocator, source) Lexer
Create a new lexer.

### lexer.tokenize() !void
Tokenize the source into internal token list.

### lexer.deinit()
Free tokens.

## Parser
Template AST builder.

### Parser.init(allocator, tokens) Parser
Create a parser from a token list.

### parser.parse() !void
Parse tokens into AST nodes.

### parser.deinit()
Free AST nodes.

## Filters
Template filter functions for transforming values in expressions.

### FilterResult
- `value: Value` — the filtered value
- `owned: bool` — whether the result owns allocated memory (must be freed)
- `filterResult.deinit(gpa)` — free owned memory

### Application Functions
- `apply(gpa, name, value) !FilterResult` — apply a filter by name (no argument)
- `applyWithArg(gpa, name, value, arg) !FilterResult` — apply a filter with a string argument

### Built-in Filters
| Filter | Description | Example |
|--------|-------------|---------|
| `upper` | Convert to uppercase | `{{ name|upper }}` |
| `lower` | Convert to lowercase | `{{ name|lower }}` |
| `capitalize` | Capitalize first letter | `{{ name|capitalize }}` |
| `title` | Title case (capitalize each word) | `{{ name|title }}` |
| `trim` | Strip whitespace (spaces, tabs, newlines, carriage returns) | `{{ name|trim }}` |
| `length` | Get string length or list count | `{{ name|length }}` |
| `reverse` | Reverse string | `{{ name|reverse }}` |
| `escape` | HTML-escape a string explicitly (`<>&"'`) | `{{ raw|escape }}` |
| `safe` | Mark value as safe (bypass auto-escaping) | `{{ html_content|safe }}` |
| `join(sep)` | Join list items with separator | `{{ list|join(", ") }}` |
| `truncate(n)` | Truncate to n characters with `...` | `{{ text|truncate(50) }}` |
| `default(val)` | Default value if empty/null | `{{ name|default("Guest") }}` |
| `date(format)` | Format Unix timestamp as `YYYY-MM-DD` | `{{ timestamp|date }}` |

## Full Example
```zig
const std = @import("std");
const zypher = @import("zypher");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var engine = zypher.template.renderer.TemplateEngine.init(gpa.allocator());
    defer engine.deinit();

    _ = try engine.load("hello.html", "<h1>Hello, {{ name|upper }}!</h1>");

    var ctx = zypher.core.Context.init(gpa.allocator());
    defer ctx.deinit();
    try ctx.put("name", .{ .string = "world" });

    var buf = std.ArrayList(u8).init(gpa.allocator());
    defer buf.deinit();
    try engine.render("hello.html", &ctx, buf.writer());
    // buf.items == "<h1>Hello, WORLD!</h1>"
}
```
