# Performance Optimization Best Practices

This guide provides strategies and best practices for optimizing application performance in Azure DevOps projects.

---

## 📊 Performance Metrics

### Key Performance Indicators (KPIs)

**Response Time Metrics**
- **Page Load Time**: < 3 seconds for 95th percentile
- **API Response Time**: < 200ms for 90th percentile
- **Time to First Byte (TTFB)**: < 600ms
- **Time to Interactive (TTI)**: < 5 seconds

**Resource Metrics**
- **CPU Utilization**: < 70% average
- **Memory Usage**: < 80% of available
- **Database Query Time**: < 100ms for simple queries
- **Network Latency**: < 100ms regional, < 300ms global

**Throughput Metrics**
- **Requests per Second (RPS)**: Track baseline and peaks
- **Concurrent Users**: Define target capacity
- **Error Rate**: < 0.1% of total requests

---

## 🚀 Frontend Performance

### Code Optimization

**JavaScript Best Practices**
```javascript
// ✅ DO: Debounce frequent events
const debouncedSearch = debounce((query) => {
  fetchSearchResults(query);
}, 300);

// ✅ DO: Use efficient selectors
const element = document.getElementById('myId'); // Fast
// ❌ DON'T: Inefficient selectors
const element = document.querySelectorAll('div.class span')[0]; // Slow

// ✅ DO: Cache DOM references
const container = document.getElementById('container');
for (let i = 0; i < items.length; i++) {
  container.appendChild(createItem(items[i]));
}
```

**CSS Optimization**
```css
/* ✅ DO: Use efficient selectors */
.btn-primary { /* Fast */ }
#header .nav-item { /* Reasonable */ }

/* ❌ DON'T: Avoid overly specific selectors */
html body div.container ul li a span { /* Very slow */ }

/* ✅ DO: Use CSS containment */
.card {
  contain: layout style paint;
}
```

### Asset Optimization

**Image Optimization**
- Use WebP format with JPEG/PNG fallbacks
- Implement responsive images with `srcset`
- Lazy load images below the fold
- Compress images (aim for < 100KB per image)
- Use SVG for icons and simple graphics

**Bundle Optimization**
- **Code Splitting**: Split vendor and app bundles
- **Tree Shaking**: Remove unused code
- **Minification**: Always minify JS, CSS, HTML
- **Compression**: Enable gzip/brotli (70-80% reduction)

```javascript
// Webpack example
module.exports = {
  optimization: {
    splitChunks: {
      chunks: 'all',
      cacheGroups: {
        vendor: {
          test: /[\\/]node_modules[\\/]/,
          name: 'vendors',
          priority: 10
        }
      }
    }
  }
};
```

### Caching Strategy

**Browser Caching**
```
# .htaccess or server config
<FilesMatch "\.(html|htm)$">
  Header set Cache-Control "no-cache, must-revalidate"
</FilesMatch>

<FilesMatch "\.(js|css|png|jpg|gif|svg|woff2)$">
  Header set Cache-Control "public, max-age=31536000, immutable"
</FilesMatch>
```

**Service Workers**
```javascript
// Cache-first strategy for assets
self.addEventListener('fetch', (event) => {
  if (event.request.destination === 'image') {
    event.respondWith(
      caches.match(event.request).then((response) => {
        return response || fetch(event.request);
      })
    );
  }
});
```

---

## 🔧 Backend Performance

### Database Optimization

**Query Optimization**
```sql
-- ✅ DO: Use indexes effectively
CREATE INDEX idx_user_email ON users(email);
CREATE INDEX idx_created_at ON orders(created_at DESC);

-- ✅ DO: Use specific columns instead of SELECT *
SELECT id, name, email FROM users WHERE status = 'active';

-- ✅ DO: Use EXPLAIN to analyze queries
EXPLAIN ANALYZE SELECT * FROM orders 
WHERE user_id = 123 AND created_at > '2025-01-01';

-- ❌ DON'T: Use N+1 queries
-- Instead, use JOIN or include related data
SELECT orders.*, users.name FROM orders
JOIN users ON orders.user_id = users.id
WHERE orders.status = 'pending';
```

**Connection Pooling**
```csharp
// ✅ DO: Use connection pooling
var connectionString = "Server=myServer;Database=myDB;Max Pool Size=100;Min Pool Size=10;";

// ✅ DO: Use async operations
using (var connection = new SqlConnection(connectionString))
{
    await connection.OpenAsync();
    var command = new SqlCommand("SELECT * FROM Users WHERE Id = @Id", connection);
    command.Parameters.AddWithValue("@Id", userId);
    var result = await command.ExecuteReaderAsync();
}
```

**Caching Strategies**
```csharp
// ✅ DO: Implement multi-level caching
// L1: In-memory cache (fast, small)
// L2: Distributed cache (Redis)
// L3: Database

public async Task<User> GetUserAsync(int userId)
{
    // L1: Memory cache
    if (_memoryCache.TryGetValue($"user:{userId}", out User user))
        return user;
    
    // L2: Redis cache
    var cached = await _distributedCache.GetStringAsync($"user:{userId}");
    if (cached != null)
    {
        user = JsonSerializer.Deserialize<User>(cached);
        _memoryCache.Set($"user:{userId}", user, TimeSpan.FromMinutes(5));
        return user;
    }
    
    // L3: Database
    user = await _dbContext.Users.FindAsync(userId);
    await CacheUserAsync(user);
    return user;
}
```

### API Optimization

**Pagination**
```csharp
// ✅ DO: Always paginate large result sets
[HttpGet("api/orders")]
public async Task<ActionResult<PagedResult<Order>>> GetOrders(
    [FromQuery] int page = 1, 
    [FromQuery] int pageSize = 20)
{
    if (pageSize > 100) pageSize = 100; // Limit max page size
    
    var query = _dbContext.Orders.AsQueryable();
    var total = await query.CountAsync();
    var items = await query
        .Skip((page - 1) * pageSize)
        .Take(pageSize)
        .ToListAsync();
    
    return new PagedResult<Order>
    {
        Items = items,
        Page = page,
        PageSize = pageSize,
        TotalCount = total
    };
}
```

**Response Compression**
```csharp
// Startup.cs
public void ConfigureServices(IServiceCollection services)
{
    services.AddResponseCompression(options =>
    {
        options.EnableForHttps = true;
        options.Providers.Add<GzipCompressionProvider>();
        options.Providers.Add<BrotliCompressionProvider>();
    });
}
```

**Async Operations**
```csharp
// ✅ DO: Use async/await throughout the stack
public async Task<IActionResult> ProcessOrderAsync(int orderId)
{
    var order = await _orderService.GetOrderAsync(orderId);
    await _inventoryService.ReserveItemsAsync(order.Items);
    await _paymentService.ProcessPaymentAsync(order.Payment);
    await _notificationService.SendConfirmationAsync(order.CustomerId);
    return Ok();
}

// ❌ DON'T: Block on async operations
var result = SomeAsyncMethod().Result; // Deadlock risk!
```

---

## 📈 Monitoring & Profiling

### Application Insights

**Custom Metrics**
```csharp
// Track custom performance metrics
var telemetry = new TelemetryClient();

using (var operation = telemetry.StartOperation<RequestTelemetry>("ComplexOperation"))
{
    // Track custom metric
    telemetry.TrackMetric("ItemsProcessed", items.Count);
    
    // Track dependency
    using (var depOperation = telemetry.StartOperation<DependencyTelemetry>("ExternalAPI"))
    {
        await _externalService.CallApiAsync();
    }
}
```

**Performance Alerts**
- Alert when response time > 3 seconds for 5 consecutive minutes
- Alert when error rate > 1% of requests
- Alert when CPU > 80% for 10 minutes
- Alert when memory > 85% for 5 minutes

### Profiling Tools

**Recommended Tools**
- **Chrome DevTools**: Performance tab, Lighthouse
- **Application Insights**: Azure native monitoring
- **SQL Profiler**: Database query analysis
- **dotTrace/ANTS**: .NET application profiling
- **New Relic/Datadog**: APM solutions

**Performance Testing**
```bash
# Load testing with k6
k6 run --vus 100 --duration 30s performance-test.js

# Artillery for HTTP testing
artillery quick --count 10 --num 50 https://api.example.com/endpoint
```

---

## ✅ Performance Checklist

### Pre-Deployment
- [ ] All images optimized and compressed
- [ ] Code bundles split and minified
- [ ] Database queries have appropriate indexes
- [ ] API responses are paginated
- [ ] Caching strategy implemented
- [ ] Response compression enabled
- [ ] Lazy loading implemented for images/components
- [ ] Performance budget defined and met

### Monitoring
- [ ] Application Insights configured
- [ ] Performance alerts set up
- [ ] Baseline metrics established
- [ ] Load testing completed
- [ ] CDN configured for static assets
- [ ] Database slow query log enabled

### Optimization Goals
- [ ] Page load < 3 seconds
- [ ] API response < 200ms (95th percentile)
- [ ] First Contentful Paint < 1.5 seconds
- [ ] Time to Interactive < 5 seconds
- [ ] No memory leaks detected
- [ ] CPU usage < 70% under normal load

---

## 📚 Resources

- [Web Vitals](https://web.dev/vitals/)
- [Azure Application Insights Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/app/best-practices)
- [HTTP Caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)
- [Database Indexing Strategies](https://use-the-index-luke.com/)

---

*Last updated: 2025-11-06*


## 📚 References

- [Web Vitals](https://web.dev/vitals/)
- [Azure Application Insights Best Practices](https://learn.microsoft.com/en-us/azure/azure-monitor/app/best-practices)
- [HTTP Caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)
- [Database Indexing Strategies](https://use-the-index-luke.com/)
- [Performance Budget Calculator](https://www.performancebudget.io/)
- [Lighthouse Performance Audits](https://developer.chrome.com/docs/lighthouse/performance/)