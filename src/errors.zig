/// zypher error set definitions.
/// All subsystem errors are namespaced under ZypherError.
const std = @import("std");

/// Top-level error union covering all zypher subsystem errors.
pub const ZypherError = error{
    // ── Core / HTTP errors ────────────────────────────────────────
    /// Malformed HTTP request
    BadRequest,
    /// Request body exceeds configured max_body_size
    BodyTooLarge,
    /// HTTP method not allowed for this route
    MethodNotAllowed,
    /// Route not found
    NotFound,
    /// Request timed out
    Timeout,
    /// Failed to parse request
    RequestParseFailed,
    /// Failed to write response
    ResponseWriteFailed,

    // ── Router errors ─────────────────────────────────────────────
    /// Route pattern is invalid
    InvalidRoutePattern,
    /// Route parameter could not be parsed to requested type
    ParamTypeMismatch,
    /// Ambiguous route definitions
    AmbiguousRoute,

    // ── Middleware errors ──────────────────────────────────────────
    /// Middleware short-circuited the request
    MiddlewareShortCircuit,
    /// CSRF token validation failed
    CsrfValidationFailed,
    /// Rate limit exceeded
    RateLimitExceeded,
    /// CORS origin blocked
    CorsBlocked,
    /// Path traversal detected
    PathTraversal,

    // ── Template errors ───────────────────────────────────────────
    /// Template file not found
    TemplateNotFound,
    /// Template syntax error
    TemplateSyntaxError,
    /// Template variable missing (non-fatal, renders empty)
    TemplateVarMissing,
    /// Template render failed
    TemplateRenderFailed,

    // ── ORM / Database errors ──────────────────────────────────────
    /// Database connection failed
    DbConnectionFailed,
    /// Query execution failed
    DbQueryFailed,
    /// Row not found
    DbNotFound,
    /// Constraint violation
    DbConstraintViolation,
    /// Migration failed
    MigrationFailed,
    /// Migration already applied
    MigrationAlreadyApplied,

    // ── Form / Validation errors ───────────────────────────────────
    /// Form validation failed
    ValidationFailed,
    /// Required field is empty
    FieldRequired,
    /// Field value too short
    FieldTooShort,
    /// Field value too long
    FieldTooLong,
    /// Field value out of range
    FieldOutOfRange,
    /// Invalid email format
    InvalidEmail,
    /// Invalid URL format
    InvalidUrl,
    /// Value not in allowed choices
    InvalidChoice,

    // ── Auth errors ────────────────────────────────────────────────
    /// Authentication failed (wrong credentials)
    AuthenticationFailed,
    /// Session expired or invalid
    SessionInvalid,
    /// Permission denied
    PermissionDenied,
    /// Password hashing failed
    PasswordHashFailed,
    /// Login required
    LoginRequired,

    // ── Admin errors ───────────────────────────────────────────────
    /// Model not registered in admin
    AdminModelNotRegistered,
    /// Admin access denied (not superuser)
    AdminAccessDenied,

    // ── CLI errors ─────────────────────────────────────────────────
    /// Unknown CLI command
    UnknownCommand,
    /// Invalid CLI arguments
    InvalidArguments,
};

/// Convert a ZypherError variant to a human-readable string.
pub fn errorToString(err: ZypherError) []const u8 {
    return switch (err) {
        error.BadRequest => "Bad Request",
        error.BodyTooLarge => "Body Too Large",
        error.MethodNotAllowed => "Method Not Allowed",
        error.NotFound => "Not Found",
        error.Timeout => "Timeout",
        error.RequestParseFailed => "Request Parse Failed",
        error.ResponseWriteFailed => "Response Write Failed",
        error.InvalidRoutePattern => "Invalid Route Pattern",
        error.ParamTypeMismatch => "Parameter Type Mismatch",
        error.AmbiguousRoute => "Ambiguous Route",
        error.MiddlewareShortCircuit => "Middleware Short Circuit",
        error.CsrfValidationFailed => "CSRF Validation Failed",
        error.RateLimitExceeded => "Rate Limit Exceeded",
        error.CorsBlocked => "CORS Blocked",
        error.PathTraversal => "Path Traversal Detected",
        error.TemplateNotFound => "Template Not Found",
        error.TemplateSyntaxError => "Template Syntax Error",
        error.TemplateVarMissing => "Template Variable Missing",
        error.TemplateRenderFailed => "Template Render Failed",
        error.DbConnectionFailed => "Database Connection Failed",
        error.DbQueryFailed => "Database Query Failed",
        error.DbNotFound => "Not Found",
        error.DbConstraintViolation => "Constraint Violation",
        error.MigrationFailed => "Migration Failed",
        error.MigrationAlreadyApplied => "Migration Already Applied",
        error.ValidationFailed => "Validation Failed",
        error.FieldRequired => "Field Required",
        error.FieldTooShort => "Field Too Short",
        error.FieldTooLong => "Field Too Long",
        error.FieldOutOfRange => "Field Out Of Range",
        error.InvalidEmail => "Invalid Email",
        error.InvalidUrl => "Invalid URL",
        error.InvalidChoice => "Invalid Choice",
        error.AuthenticationFailed => "Authentication Failed",
        error.SessionInvalid => "Session Invalid",
        error.PermissionDenied => "Permission Denied",
        error.PasswordHashFailed => "Password Hash Failed",
        error.LoginRequired => "Login Required",
        error.AdminModelNotRegistered => "Admin Model Not Registered",
        error.AdminAccessDenied => "Admin Access Denied",
        error.UnknownCommand => "Unknown Command",
        error.InvalidArguments => "Invalid Arguments",
    };
}

test {
    std.testing.refAllDecls(@This());
}
