# Template API

## Lexer
Template source tokenizer.

- `tokenize(source)` — Tokenize template source

## Parser
Template AST builder.

- `parse(tokens)` — Parse tokens into AST nodes

## Renderer
Template rendering engine.

- `TemplateEngine.init(gpa)` — Create a new engine
- `engine.load(name, source)` — Load a template
- `engine.render(name, context, writer)` — Render a template
- `engine.deinit()` — Free resources
- `Context.init(gpa)` — Create a render context
- `context.put(name, value)` — Set a variable
- `context.get(name)` — Get a variable
- `context.deinit()` — Free context

## Filters
Template filter functions.

- `apply(value, name)` — Apply a filter by name
- `applyWithArg(value, name, arg)` — Apply filter with argument

### Built-in Filters
- `upper` — Convert to uppercase
- `lower` — Convert to lowercase  
- `capitalize` — Capitalize first letter
- `title` — Title case
- `trim` — Strip whitespace
- `length` — Get string length
- `reverse` — Reverse string
- `escape` — HTML-escape a string explicitly
- `safe` — Renderer-level bypass for auto-escaping
- `join(sep)` — Join list items with a separator
- `truncate(n)` — Truncate to n characters
- `default(val)` — Default value if empty
- `date(format)` — Format an integer Unix timestamp as `YYYY-MM-DD`
