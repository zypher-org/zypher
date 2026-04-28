/// Unit tests for zypher error set definitions.
const std = @import("std");
const errors = @import("zypher").errors;

test "error sets are correctly namespaced — ZypherError is accessible" {
    const e: errors.ZypherError = error.BadRequest;
    try std.testing.expectEqualStrings("Bad Request", errors.errorToString(e));
}

test "error-to-string conversion for all error variants" {
    // Core / HTTP errors
    try std.testing.expectEqualStrings("Bad Request", errors.errorToString(error.BadRequest));
    try std.testing.expectEqualStrings("Body Too Large", errors.errorToString(error.BodyTooLarge));
    try std.testing.expectEqualStrings("Method Not Allowed", errors.errorToString(error.MethodNotAllowed));
    try std.testing.expectEqualStrings("Not Found", errors.errorToString(error.NotFound));
    try std.testing.expectEqualStrings("Timeout", errors.errorToString(error.Timeout));
    try std.testing.expectEqualStrings("Request Parse Failed", errors.errorToString(error.RequestParseFailed));
    try std.testing.expectEqualStrings("Response Write Failed", errors.errorToString(error.ResponseWriteFailed));

    // Router errors
    try std.testing.expectEqualStrings("Invalid Route Pattern", errors.errorToString(error.InvalidRoutePattern));
    try std.testing.expectEqualStrings("Parameter Type Mismatch", errors.errorToString(error.ParamTypeMismatch));
    try std.testing.expectEqualStrings("Ambiguous Route", errors.errorToString(error.AmbiguousRoute));

    // Middleware errors
    try std.testing.expectEqualStrings("Middleware Short Circuit", errors.errorToString(error.MiddlewareShortCircuit));
    try std.testing.expectEqualStrings("CSRF Validation Failed", errors.errorToString(error.CsrfValidationFailed));
    try std.testing.expectEqualStrings("Rate Limit Exceeded", errors.errorToString(error.RateLimitExceeded));
    try std.testing.expectEqualStrings("CORS Blocked", errors.errorToString(error.CorsBlocked));
    try std.testing.expectEqualStrings("Path Traversal Detected", errors.errorToString(error.PathTraversal));

    // Template errors
    try std.testing.expectEqualStrings("Template Not Found", errors.errorToString(error.TemplateNotFound));
    try std.testing.expectEqualStrings("Template Syntax Error", errors.errorToString(error.TemplateSyntaxError));
    try std.testing.expectEqualStrings("Template Variable Missing", errors.errorToString(error.TemplateVarMissing));
    try std.testing.expectEqualStrings("Template Render Failed", errors.errorToString(error.TemplateRenderFailed));

    // ORM / Database errors
    try std.testing.expectEqualStrings("Database Connection Failed", errors.errorToString(error.DbConnectionFailed));
    try std.testing.expectEqualStrings("Database Query Failed", errors.errorToString(error.DbQueryFailed));
    try std.testing.expectEqualStrings("Not Found", errors.errorToString(error.DbNotFound));
    try std.testing.expectEqualStrings("Constraint Violation", errors.errorToString(error.DbConstraintViolation));
    try std.testing.expectEqualStrings("Migration Failed", errors.errorToString(error.MigrationFailed));
    try std.testing.expectEqualStrings("Migration Already Applied", errors.errorToString(error.MigrationAlreadyApplied));

    // Form / Validation errors
    try std.testing.expectEqualStrings("Validation Failed", errors.errorToString(error.ValidationFailed));
    try std.testing.expectEqualStrings("Field Required", errors.errorToString(error.FieldRequired));
    try std.testing.expectEqualStrings("Field Too Short", errors.errorToString(error.FieldTooShort));
    try std.testing.expectEqualStrings("Field Too Long", errors.errorToString(error.FieldTooLong));
    try std.testing.expectEqualStrings("Field Out Of Range", errors.errorToString(error.FieldOutOfRange));
    try std.testing.expectEqualStrings("Invalid Email", errors.errorToString(error.InvalidEmail));
    try std.testing.expectEqualStrings("Invalid URL", errors.errorToString(error.InvalidUrl));
    try std.testing.expectEqualStrings("Invalid Choice", errors.errorToString(error.InvalidChoice));

    // Auth errors
    try std.testing.expectEqualStrings("Authentication Failed", errors.errorToString(error.AuthenticationFailed));
    try std.testing.expectEqualStrings("Session Invalid", errors.errorToString(error.SessionInvalid));
    try std.testing.expectEqualStrings("Permission Denied", errors.errorToString(error.PermissionDenied));
    try std.testing.expectEqualStrings("Password Hash Failed", errors.errorToString(error.PasswordHashFailed));
    try std.testing.expectEqualStrings("Login Required", errors.errorToString(error.LoginRequired));

    // Admin errors
    try std.testing.expectEqualStrings("Admin Model Not Registered", errors.errorToString(error.AdminModelNotRegistered));
    try std.testing.expectEqualStrings("Admin Access Denied", errors.errorToString(error.AdminAccessDenied));

    // CLI errors
    try std.testing.expectEqualStrings("Unknown Command", errors.errorToString(error.UnknownCommand));
    try std.testing.expectEqualStrings("Invalid Arguments", errors.errorToString(error.InvalidArguments));
}

test "error can be used in error union" {
    const result: errors.ZypherError!u32 = error.NotFound;
    const val = result catch |err| {
        try std.testing.expectEqual(error.NotFound, err);
        return;
    };
    _ = val;
    unreachable;
}
