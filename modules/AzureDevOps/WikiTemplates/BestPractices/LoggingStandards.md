# Logging Standards & Best Practices

Comprehensive guide for implementing consistent, effective logging across your applications.

---

## 🎯 Logging Principles

### Why We Log

**Observability Goals**
1. **Debugging**: Understand what happened when issues occur
2. **Monitoring**: Track application health and performance
3. **Auditing**: Record important business events
4. **Security**: Detect and investigate security incidents
5. **Analytics**: Understand usage patterns and behavior

### Core Principles

**1. Structured Logging**
- Use key-value pairs, not string concatenation
- Makes logs searchable and filterable
- Enables better analytics and alerting

**2. Appropriate Detail**
- Include enough context to understand the event
- Don't log sensitive information
- Balance detail with volume

**3. Consistent Format**
- Use standard log levels consistently
- Follow naming conventions
- Include standard fields (timestamp, correlation ID, etc.)

---

## 📊 Log Levels

### Standard Levels

```csharp
// TRACE: Very detailed diagnostic information
_logger.LogTrace("Entering ProcessOrder method with orderId: {OrderId}", orderId);

// DEBUG: Detailed information for debugging
_logger.LogDebug("Cache miss for key {CacheKey}, fetching from database", cacheKey);
_logger.LogDebug("Query executed in {ElapsedMs}ms: {Query}", elapsed, query);

// INFORMATION: General application flow
_logger.LogInformation("User {UserId} successfully logged in from {IpAddress}", userId, ipAddress);
_logger.LogInformation("Order {OrderId} created with {ItemCount} items, total: {Total:C}", orderId, count, total);

// WARNING: Unexpected but handled situations
_logger.LogWarning("Rate limit of {Limit} requests approaching for API key {ApiKey}: {Current} requests", limit, apiKey, current);
_logger.LogWarning("Slow query detected: {Query} took {ElapsedMs}ms", query, elapsed);

// ERROR: Error occurred but application continues
_logger.LogError(exception, "Failed to process payment for order {OrderId}", orderId);
_logger.LogError(exception, "External API call failed: {Endpoint}, attempt {Attempt} of {MaxAttempts}", endpoint, attempt, maxAttempts);

// CRITICAL: Fatal errors requiring immediate attention
_logger.LogCritical(exception, "Database connection pool exhausted");
_logger.LogCritical(exception, "Out of memory, application shutting down");
```

### Level Guidelines

| Level | When to Use | Production Volume | Retention |
|-------|-------------|-------------------|-----------|
| Trace | Detailed code flow | Disabled | N/A |
| Debug | Debugging info | Disabled | N/A |
| Info | Normal operations | Low-Medium | 7-30 days |
| Warning | Recoverable issues | Low | 30-90 days |
| Error | Errors need attention | Very Low | 90+ days |
| Critical | System-wide failures | Extremely Rare | 1+ year |

---

## 🔧 Implementation Patterns

### Structured Logging

**✅ DO: Use Structured Logging**
```csharp
// ✅ GOOD: Structured logging with named parameters
_logger.LogInformation(
    "Order {OrderId} shipped to {CustomerName} at {ShippingAddress}. Tracking: {TrackingNumber}",
    order.Id,
    order.CustomerName,
    order.ShippingAddress,
    trackingNumber);

// Query in Application Insights:
// traces | where customDimensions.OrderId == "12345"

// ❌ BAD: String concatenation/interpolation
_logger.LogInformation($"Order {order.Id} shipped to {order.CustomerName}");
```

**Complex Objects**
```csharp
// ✅ DO: Serialize complex objects
_logger.LogInformation(
    "Order created: {@Order}",
    new {
        OrderId = order.Id,
        CustomerId = order.CustomerId,
        ItemCount = order.Items.Count,
        Total = order.Total
    });

// ❌ DON'T: Log entire objects (may contain sensitive data)
_logger.LogInformation("Order created: {@Order}", order); // May include passwords, tokens, etc.
```

### Correlation & Context

**Correlation IDs**
```csharp
public class CorrelationIdMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<CorrelationIdMiddleware> _logger;
    private const string CorrelationIdHeader = "X-Correlation-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = GetOrCreateCorrelationId(context);
        
        // Add to response headers
        context.Response.Headers[CorrelationIdHeader] = correlationId;
        
        // Add to all logs in this request scope
        using (_logger.BeginScope(new Dictionary<string, object>
        {
            ["CorrelationId"] = correlationId,
            ["RequestPath"] = context.Request.Path,
            ["RequestMethod"] = context.Request.Method,
            ["UserId"] = context.User?.FindFirst("sub")?.Value
        }))
        {
            await _next(context);
        }
    }

    private string GetOrCreateCorrelationId(HttpContext context)
    {
        if (context.Request.Headers.TryGetValue(CorrelationIdHeader, out var correlationId))
        {
            return correlationId.ToString();
        }
        return Guid.NewGuid().ToString();
    }
}
```

**Log Scopes**
```csharp
// Add context to all logs within a scope
public async Task ProcessOrderAsync(int orderId)
{
    using (_logger.BeginScope("Processing order {OrderId}", orderId))
    {
        _logger.LogInformation("Validating order");
        await ValidateOrderAsync(orderId);
        
        _logger.LogInformation("Processing payment");
        await ProcessPaymentAsync(orderId);
        
        _logger.LogInformation("Sending confirmation");
        await SendConfirmationAsync(orderId);
    }
}
```

### Performance Considerations

**Log Guards**
```csharp
// ✅ DO: Use log level checks for expensive operations
if (_logger.IsEnabled(LogLevel.Debug))
{
    var detailedInfo = GenerateExpensiveDebugInfo(); // Only called if Debug enabled
    _logger.LogDebug("Detailed info: {Info}", detailedInfo);
}

// ✅ DO: Use LoggerMessage for high-performance logging
private static readonly Action<ILogger, int, string, Exception> _orderProcessed =
    LoggerMessage.Define<int, string>(
        LogLevel.Information,
        new EventId(1, "OrderProcessed"),
        "Order {OrderId} processed by {ProcessorName}");

public void LogOrderProcessed(int orderId, string processorName)
{
    _orderProcessed(_logger, orderId, processorName, null);
}
```

**Sampling**
```csharp
// For very high-volume logs, implement sampling
private readonly Random _random = new Random();
private const double SamplingRate = 0.1; // Log 10% of requests

public void LogHighVolumeEvent(string eventName, object data)
{
    if (_random.NextDouble() < SamplingRate)
    {
        _logger.LogInformation("{EventName}: {@Data}", eventName, data);
    }
}
```

---

## 🔒 Security & Compliance

### Sensitive Data

**Never Log**
- Passwords or password hashes
- API keys, tokens, secrets
- Credit card numbers (full PAN)
- Social Security Numbers
- Personal health information
- Encryption keys

**Sanitization**
```csharp
public class SanitizingLogger
{
    private readonly ILogger _logger;
    private static readonly Regex _creditCardPattern = new Regex(@"\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}");
    private static readonly Regex _emailPattern = new Regex(@"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}");

    public void LogSanitized(LogLevel level, string message, params object[] args)
    {
        var sanitizedMessage = SanitizeMessage(message);
        var sanitizedArgs = args.Select(SanitizeValue).ToArray();
        _logger.Log(level, sanitizedMessage, sanitizedArgs);
    }

    private string SanitizeMessage(string message)
    {
        message = _creditCardPattern.Replace(message, "****-****-****-####");
        message = _emailPattern.Replace(message, "***@***.***");
        return message;
    }

    private object SanitizeValue(object value)
    {
        if (value == null) return null;
        
        var str = value.ToString();
        if (IsSensitiveField(str))
        {
            return "***REDACTED***";
        }
        return value;
    }

    private bool IsSensitiveField(string fieldName)
    {
        var sensitiveFields = new[] { "password", "token", "secret", "key", "ssn", "creditcard" };
        return sensitiveFields.Any(f => fieldName.ToLower().Contains(f));
    }
}
```

### Audit Logging

```csharp
public class AuditLogger
{
    private readonly ILogger<AuditLogger> _logger;

    // Log important business events
    public void LogUserAction(string userId, string action, object details)
    {
        _logger.LogInformation(
            "AUDIT: User {UserId} performed {Action}. Details: {@Details}. Timestamp: {Timestamp:O}",
            userId,
            action,
            details,
            DateTimeOffset.UtcNow);
    }

    public void LogDataAccess(string userId, string entityType, string entityId, string operation)
    {
        _logger.LogInformation(
            "AUDIT: User {UserId} {Operation} {EntityType} {EntityId}",
            userId,
            operation,
            entityType,
            entityId);
    }

    public void LogSecurityEvent(string eventType, string userId, string ipAddress, bool success)
    {
        _logger.LogWarning(
            "SECURITY: {EventType} - User: {UserId}, IP: {IpAddress}, Success: {Success}",
            eventType,
            userId,
            ipAddress,
            success);
    }
}
```

---

## 📈 Monitoring & Alerting

### Application Insights

**Configuration**
```json
{
  "ApplicationInsights": {
    "InstrumentationKey": "your-key-here",
    "EnableAdaptiveSampling": true,
    "EnablePerformanceCounterCollectionModule": true,
    "SamplingSettings": {
      "MaxTelemetryItemsPerSecond": 5
    }
  },
  "Logging": {
    "ApplicationInsights": {
      "LogLevel": {
        "Default": "Information",
        "Microsoft": "Warning"
      }
    }
  }
}
```

**Custom Metrics**
```csharp
public class MetricsLogger
{
    private readonly TelemetryClient _telemetry;

    public void TrackOrderProcessing(int orderId, TimeSpan duration, bool success)
    {
        // Track custom event
        _telemetry.TrackEvent("OrderProcessed", 
            properties: new Dictionary<string, string>
            {
                { "OrderId", orderId.ToString() },
                { "Success", success.ToString() }
            },
            metrics: new Dictionary<string, double>
            {
                { "ProcessingTimeMs", duration.TotalMilliseconds },
                { "OrderValue", 149.99 }
            });

        // Track metric
        _telemetry.TrackMetric("OrderProcessingTime", duration.TotalMilliseconds);
    }

    public void TrackDependency(string dependencyName, TimeSpan duration, bool success)
    {
        _telemetry.TrackDependency(
            dependencyTypeName: "External API",
            target: dependencyName,
            dependencyName: dependencyName,
            data: null,
            startTime: DateTimeOffset.UtcNow - duration,
            duration: duration,
            resultCode: success ? "200" : "500",
            success: success);
    }
}
```

### Alert Rules

**Example KQL Queries**
```kusto
// High error rate
traces
| where severityLevel >= 3 // Error or Critical
| summarize ErrorCount = count() by bin(timestamp, 5m)
| where ErrorCount > 10

// Slow requests
requests
| where duration > 3000 // > 3 seconds
| summarize SlowRequestCount = count() by bin(timestamp, 5m)
| where SlowRequestCount > 5

// Failed dependencies
dependencies
| where success == false
| summarize FailureCount = count() by target, bin(timestamp, 5m)
| where FailureCount > 3
```

---

## ✅ Logging Checklist

### Setup
- [ ] Structured logging library configured (Serilog, NLog, etc.)
- [ ] Application Insights or similar APM tool integrated
- [ ] Log levels configured appropriately per environment
- [ ] Correlation ID middleware implemented
- [ ] Log sampling for high-volume scenarios

### Development
- [ ] Use structured logging (not string concatenation)
- [ ] Include correlation IDs in all logs
- [ ] Add appropriate context with log scopes
- [ ] Use correct log levels
- [ ] Sanitize sensitive data
- [ ] Log at application boundaries (entry/exit)

### Operations
- [ ] Centralized log aggregation configured
- [ ] Log retention policies defined
- [ ] Alerts configured for critical errors
- [ ] Dashboards created for key metrics
- [ ] Log queries documented
- [ ] On-call runbooks reference logs

### Security
- [ ] No passwords, tokens, or secrets logged
- [ ] PII properly redacted or anonymized
- [ ] Audit logs for security events
- [ ] Log access restricted to authorized personnel
- [ ] Log integrity protected (immutable storage)

---

## 📚 Resources

- [Serilog - Structured Logging](https://serilog.net/)
- [Application Insights Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/app/best-practices)
- [.NET Logging Guidance](https://docs.microsoft.com/en-us/dotnet/core/extensions/logging)
- [Twelve-Factor App: Logs](https://12factor.net/logs)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)

---

*Last updated: 2025-11-06*
