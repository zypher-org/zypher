# Forms API

## Form
Comptime form definition with validation.

- `Form(name, FieldsType)` — Generate a Form type
- `Form.bind(gpa, data)` — Bind form data from a string map
- `Form.bindRequest(gpa, req)` — Bind text fields from request form/query values and file fields from `req.file(name)`

### Fields
- `Field(name, kind, options)` — Define a form field
- `FieldKind`: `text`, `integer`, `boolean`, `file`
- Options: `required`, `validator`

### BoundForm
- `getValue(field_name)` — Get raw string value
- `validate()` — Validate all fields, returns bool
- `cleanedData()` — Return typed data after validation
- `csrfField()` — Get CSRF hidden input HTML
- `csrfFieldForRequest(req)` — Get an owned CSRF hidden input backed by the request session when present
- `deinit()` — Free resources

## Validators
Built-in validation functions.

- `email(value)` — Validate email format
- `minLength(n)` — Minimum length validator
- `maxLength(n)` — Maximum length validator
- `matches(pattern)` — Regex pattern validator
- `integer()` — Validate integer
- `url()` — Validate URL format
