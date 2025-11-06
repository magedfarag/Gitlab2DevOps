# Error Handling & Resilience Best Practices

Comprehensive guide for implementing robust error handling and building resilient applications.

---

## 🎯 Error Handling Principles

### Core Principles

**1. Fail Fast, Fail Safe**
- Detect errors as early as possible
- Prevent cascading failures
- Provide meaningful error messages
- Never expose sensitive information

**2. Defensive Programming**
- Validate all inputs
- Check preconditions and postconditions
- Use assertions for developer errors
- Handle expected errors gracefully

**3. Error Context**
- Include relevant context in error messages
- Log correlation IDs for tracing
- Preserve stack traces
- Track error frequency and patterns

---

## 🔧 Implementation Patterns

### Try-Catch Best Practices

**✅ DO: Catch Specific Exceptions**
```csharp
// ✅ GOOD: Catch specific exceptions
try
{
    var user = await _userService.GetUserAsync(userId);
    return Ok(user);
}
catch (UserNotFoundException ex)
{
    _logger.LogWarning(ex, "User {UserId} not found", userId);
    return NotFound($"User {userId} not found");
}
catch (DatabaseException ex)
{
    _logger.LogError(ex, "Database error retrieving user {UserId}", userId);
    return StatusCode(500, "An error occurred retrieving user data");
}

// ❌ BAD: Catch generic Exception
try
{
    // code
}
catch (Exception ex)
{
    // Too broad, hides specific issues
    return StatusCode(500, "Something went wrong");
}
```

**✅ DO: Use Finally for Cleanup**
```csharp
FileStream fileStream = null;
try
{
    fileStream = new FileStream(path, FileMode.Open);
    // Process file
}
catch (FileNotFoundException ex)
{
    _logger.LogError(ex, "File not found: {Path}", path);
    throw;
}
finally
{
    fileStream?.Dispose();
}

// Better: Use using statement
using (var fileStream = new FileStream(path, FileMode.Open))
{
    // Process file
} // Automatically disposed
```

### Custom Exception Hierarchy

```csharp
// Base application exception
public class ApplicationException : Exception
{
    public string ErrorCode { get; set; }
    public Dictionary<string, object> Context { get; set; }
    
    public ApplicationException(string message, string errorCode = null) 
        : base(message)
    {
        ErrorCode = errorCode;
        Context = new Dictionary<string, object>();
    }
}

// Domain-specific exceptions
public class ValidationException : ApplicationException
{
    public Dictionary<string, string[]> Errors { get; set; }
    
    public ValidationException(Dictionary<string, string[]> errors) 
        : base("Validation failed", "VALIDATION_ERROR")
    {
        Errors = errors;
    }
}

public class EntityNotFoundException : ApplicationException
{
    public string EntityType { get; set; }
    public object EntityId { get; set; }
    
    public EntityNotFoundException(string entityType, object entityId)
        : base($"{entityType} with ID {entityId} not found", "ENTITY_NOT_FOUND")
    {
        EntityType = entityType;
        EntityId = entityId;
    }
}

public class BusinessRuleException : ApplicationException
{
    public string RuleName { get; set; }
    
    public BusinessRuleException(string ruleName, string message)
        : base(message, "BUSINESS_RULE_VIOLATION")
    {
        RuleName = ruleName;
    }
}
```

### Global Error Handler

```csharp
// ASP.NET Core middleware
public class GlobalExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionMiddleware> _logger;

    public GlobalExceptionMiddleware(RequestDelegate next, ILogger<GlobalExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        var correlationId = context.TraceIdentifier;
        
        _logger.LogError(exception, 
            "Unhandled exception. CorrelationId: {CorrelationId}", correlationId);

        var response = exception switch
        {
            ValidationException validationEx => new ErrorResponse
            {
                StatusCode = 400,
                Message = "Validation failed",
                ErrorCode = "VALIDATION_ERROR",
                Errors = validationEx.Errors,
                CorrelationId = correlationId
            },
            EntityNotFoundException notFoundEx => new ErrorResponse
            {
                StatusCode = 404,
                Message = notFoundEx.Message,
                ErrorCode = "NOT_FOUND",
                CorrelationId = correlationId
            },
            UnauthorizedException => new ErrorResponse
            {
                StatusCode = 401,
                Message = "Unauthorized",
                ErrorCode = "UNAUTHORIZED",
                CorrelationId = correlationId
            },
            BusinessRuleException businessEx => new ErrorResponse
            {
                StatusCode = 422,
                Message = businessEx.Message,
                ErrorCode = businessEx.ErrorCode,
                CorrelationId = correlationId
            },
            _ => new ErrorResponse
            {
                StatusCode = 500,
                Message = "An internal error occurred",
                ErrorCode = "INTERNAL_ERROR",
                CorrelationId = correlationId
            }
        };

        context.Response.ContentType = "application/json";
        context.Response.StatusCode = response.StatusCode;
        await context.Response.WriteAsJsonAsync(response);
    }
}

public class ErrorResponse
{
    public int StatusCode { get; set; }
    public string Message { get; set; }
    public string ErrorCode { get; set; }
    public string CorrelationId { get; set; }
    public Dictionary<string, string[]> Errors { get; set; }
}
```

---

## 🛡️ Resilience Patterns

### Retry Policy

```csharp
// Using Polly library
public class ResilientHttpClient
{
    private readonly HttpClient _httpClient;
    private readonly IAsyncPolicy<HttpResponseMessage> _retryPolicy;

    public ResilientHttpClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
        
        // Retry with exponential backoff
        _retryPolicy = Policy
            .HandleResult<HttpResponseMessage>(r => !r.IsSuccessStatusCode)
            .Or<HttpRequestException>()
            .WaitAndRetryAsync(
                retryCount: 3,
                sleepDurationProvider: retryAttempt => 
                    TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
                onRetry: (outcome, timespan, retryCount, context) =>
                {
                    Console.WriteLine($"Retry {retryCount} after {timespan.TotalSeconds}s");
                });
    }

    public async Task<HttpResponseMessage> GetAsync(string url)
    {
        return await _retryPolicy.ExecuteAsync(() => _httpClient.GetAsync(url));
    }
}
```

### Circuit Breaker

```csharp
// Circuit breaker to prevent cascading failures
public class CircuitBreakerService
{
    private readonly IAsyncPolicy<HttpResponseMessage> _circuitBreakerPolicy;

    public CircuitBreakerService()
    {
        _circuitBreakerPolicy = Policy
            .HandleResult<HttpResponseMessage>(r => !r.IsSuccessStatusCode)
            .Or<HttpRequestException>()
            .CircuitBreakerAsync(
                handledEventsAllowedBeforeBreaking: 3,
                durationOfBreak: TimeSpan.FromSeconds(30),
                onBreak: (result, duration) =>
                {
                    Console.WriteLine($"Circuit opened for {duration.TotalSeconds}s");
                },
                onReset: () => Console.WriteLine("Circuit closed"),
                onHalfOpen: () => Console.WriteLine("Circuit half-open"));
    }

    public async Task<HttpResponseMessage> ExecuteAsync(Func<Task<HttpResponseMessage>> action)
    {
        return await _circuitBreakerPolicy.ExecuteAsync(action);
    }
}
```

### Timeout Policy

```csharp
// Prevent hanging requests
public async Task<T> ExecuteWithTimeoutAsync<T>(Func<Task<T>> action, int timeoutSeconds = 30)
{
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
    
    try
    {
        return await action().WaitAsync(cts.Token);
    }
    catch (OperationCanceledException)
    {
        throw new TimeoutException($"Operation timed out after {timeoutSeconds} seconds");
    }
}
```

### Bulkhead Isolation

```csharp
// Isolate resources to prevent resource exhaustion
public class BulkheadService
{
    private readonly IAsyncPolicy _bulkheadPolicy;

    public BulkheadService()
    {
        _bulkheadPolicy = Policy
            .BulkheadAsync(
                maxParallelization: 10,
                maxQueuingActions: 20,
                onBulkheadRejectedAsync: context =>
                {
                    Console.WriteLine("Bulkhead rejected: too many concurrent operations");
                    return Task.CompletedTask;
                });
    }

    public async Task<T> ExecuteAsync<T>(Func<Task<T>> action)
    {
        return await _bulkheadPolicy.ExecuteAsync(action);
    }
}
```

### Fallback Pattern

```csharp
// Provide alternative behavior when primary fails
public async Task<User> GetUserWithFallbackAsync(int userId)
{
    try
    {
        // Try primary data source
        return await _primaryUserService.GetUserAsync(userId);
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Primary service failed, trying cache");
        
        try
        {
            // Fallback to cache
            return await _cacheService.GetUserAsync(userId);
        }
        catch (Exception cacheEx)
        {
            _logger.LogError(cacheEx, "Cache also failed, returning default");
            
            // Final fallback: return default/degraded response
            return new User { Id = userId, Name = "Unknown User" };
        }
    }
}
```

---

## 📝 Logging Best Practices

### Structured Logging

```csharp
// ✅ DO: Use structured logging
_logger.LogInformation(
    "User {UserId} created order {OrderId} with {ItemCount} items. Total: {TotalAmount:C}",
    userId, orderId, items.Count, totalAmount);

// ❌ DON'T: Use string concatenation
_logger.LogInformation($"User {userId} created order {orderId}");
```

### Log Levels

```csharp
// Trace: Very detailed, usually disabled in production
_logger.LogTrace("Entering method GetUser with userId: {UserId}", userId);

// Debug: Detailed information for debugging
_logger.LogDebug("Cache miss for user {UserId}", userId);

// Information: General flow of application
_logger.LogInformation("User {UserId} logged in successfully", userId);

// Warning: Unexpected but handled situations
_logger.LogWarning("Rate limit approaching for user {UserId}: {RequestCount}/100", userId, requestCount);

// Error: Error occurred but application continues
_logger.LogError(ex, "Failed to process payment for order {OrderId}", orderId);

// Critical: Fatal errors, application may terminate
_logger.LogCritical(ex, "Database connection pool exhausted");
```

### Correlation IDs

```csharp
public class CorrelationIdMiddleware
{
    private readonly RequestDelegate _next;
    private const string CorrelationIdHeader = "X-Correlation-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault() 
            ?? Guid.NewGuid().ToString();
        
        context.Items["CorrelationId"] = correlationId;
        context.Response.Headers[CorrelationIdHeader] = correlationId;
        
        using (_logger.BeginScope(new Dictionary<string, object>
        {
            ["CorrelationId"] = correlationId
        }))
        {
            await _next(context);
        }
    }
}
```

---

## ✅ Error Handling Checklist

### Development
- [ ] Use specific exception types, not generic `Exception`
- [ ] Include meaningful error messages
- [ ] Add context data to exceptions
- [ ] Validate all inputs at boundaries
- [ ] Use custom exception hierarchy
- [ ] Implement global error handler

### Resilience
- [ ] Implement retry logic for transient failures
- [ ] Add circuit breaker for external dependencies
- [ ] Set appropriate timeouts on all operations
- [ ] Use bulkhead isolation for resource pools
- [ ] Provide fallback mechanisms

### Logging & Monitoring
- [ ] Use structured logging with context
- [ ] Include correlation IDs in all logs
- [ ] Log at appropriate levels
- [ ] Set up alerts for error thresholds
- [ ] Monitor error rates and patterns
- [ ] Track error resolution time

### Security
- [ ] Never expose stack traces to users
- [ ] Don't log sensitive data (passwords, tokens, PII)
- [ ] Sanitize error messages
- [ ] Implement rate limiting on errors
- [ ] Monitor for unusual error patterns

---

## 📚 Resources

- [Polly - Resilience Framework](https://github.com/App-vNext/Polly)
- [Microsoft Error Handling Guidance](https://docs.microsoft.com/en-us/dotnet/standard/exceptions/)
- [Azure Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Structured Logging with Serilog](https://serilog.net/)

---

*Last updated: 2025-11-06*


---

## 📚 References

- [Error Handling Best Practices (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions)
- [HTTP Status Codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status)
- [Application Insights Exception Tracking](https://learn.microsoft.com/en-us/azure/azure-monitor/app/asp-net-exceptions)
- [Polly - .NET Resilience Library](https://github.com/App-vNext/Polly)
- [REST API Error Handling](https://www.rfc-editor.org/rfc/rfc7807)