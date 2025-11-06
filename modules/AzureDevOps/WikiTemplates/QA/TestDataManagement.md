# Test Data Management

Best practices for creating, managing, and maintaining test data across all testing phases.

---

## 🎯 Test Data Strategy

### Principles

**1. Realistic**: Data should mirror production scenarios
**2. Consistent**: Repeatable test results
**3. Secure**: No real customer data in non-production
**4. Manageable**: Easy to create, update, and clean up
**5. Isolated**: Tests don't interfere with each other

---

## 📊 Test Data Types

### Master Data
**Purpose**: Reference data used across tests
**Examples**: Countries, currencies, product categories, user roles

```sql
-- Master data setup
INSERT INTO Roles (RoleId, RoleName) VALUES
(1, 'Admin'),
(2, 'Manager'),
(3, 'User');

INSERT INTO Countries (Code, Name) VALUES
('US', 'United States'),
('CA', 'Canada'),
('MX', 'Mexico');
```

### Transactional Data
**Purpose**: Test-specific data for scenarios
**Examples**: Orders, payments, user sessions

```csharp
public class TestDataBuilder
{
    public static Order CreateTestOrder(int customerId = 1)
    {
        return new Order
        {
            CustomerId = customerId,
            OrderDate = DateTime.UtcNow,
            Status = "Pending",
            Items = new List<OrderItem>
            {
                new() { ProductId = 101, Quantity = 2, Price = 19.99m }
            }
        };
    }
}
```

### Boundary Data
**Purpose**: Test edge cases and limits
**Examples**: Max/min values, empty strings, null values

```csharp
[Theory]
[InlineData("")]           // Empty
[InlineData(null)]         // Null
[InlineData("A")]          // Minimum length
[InlineData("A very long string...")] // Maximum length
[InlineData("Special!@#$")] // Special characters
public void ValidateInput_BoundaryValues_HandlesCorrectly(string input)
{
    // Test implementation
}
```

---

## 🔧 Data Generation Strategies

### Inline Test Data
**When**: Simple, one-off tests
**Pros**: Self-contained, easy to understand
**Cons**: Not reusable, can clutter tests

```csharp
[Fact]
public void ProcessOrder_ValidOrder_ReturnsSuccess()
{
    var order = new Order 
    { 
        CustomerId = 123,
        Total = 99.99m,
        Items = new[] { new OrderItem { ProductId = 1, Quantity = 2 } }
    };
    
    var result = _service.ProcessOrder(order);
    Assert.True(result.Success);
}
```

### Data Builders Pattern
**When**: Complex objects, multiple variations
**Pros**: Flexible, readable, reusable
**Cons**: Requires maintenance

```csharp
public class OrderBuilder
{
    private int _customerId = 1;
    private List<OrderItem> _items = new();
    private string _status = "Pending";

    public OrderBuilder WithCustomer(int customerId)
    {
        _customerId = customerId;
        return this;
    }

    public OrderBuilder WithItem(int productId, int qty, decimal price)
    {
        _items.Add(new OrderItem { ProductId = productId, Quantity = qty, Price = price });
        return this;
    }

    public OrderBuilder Completed()
    {
        _status = "Completed";
        return this;
    }

    public Order Build() => new Order
    {
        CustomerId = _customerId,
        Items = _items,
        Status = _status
    };
}

// Usage
var order = new OrderBuilder()
    .WithCustomer(123)
    .WithItem(productId: 1, qty: 2, price: 19.99m)
    .Completed()
    .Build();
```

### Fixture Data
**When**: Shared across multiple tests
**Pros**: Reduces duplication, consistent setup
**Cons**: Can hide dependencies

```csharp
public class OrderTestFixture : IDisposable
{
    public AppDbContext Context { get; private set; }
    public Customer TestCustomer { get; private set; }
    public List<Product> TestProducts { get; private set; }

    public OrderTestFixture()
    {
        Context = CreateInMemoryDatabase();
        SeedTestData();
    }

    private void SeedTestData()
    {
        TestCustomer = new Customer { Id = 1, Name = "Test User", Email = "test@example.com" };
        Context.Customers.Add(TestCustomer);

        TestProducts = new List<Product>
        {
            new() { Id = 1, Name = "Product A", Price = 19.99m },
            new() { Id = 2, Name = "Product B", Price = 29.99m }
        };
        Context.Products.AddRange(TestProducts);
        Context.SaveChanges();
    }

    public void Dispose() => Context?.Dispose();
}
```

### External Data Files
**When**: Large datasets, data-driven testing
**Pros**: Separates data from code, easy to update
**Cons**: Harder to debug, versioning challenges

```csharp
[Theory]
[JsonFileData("TestData/orders.json")]
public void ProcessOrder_VariousScenarios_HandlesCorrectly(OrderTestCase testCase)
{
    var result = _service.ProcessOrder(testCase.Order);
    Assert.Equal(testCase.ExpectedResult, result);
}

// orders.json
[
  {
    "order": { "customerId": 1, "items": [...] },
    "expectedResult": "Success"
  },
  {
    "order": { "customerId": 2, "items": [] },
    "expectedResult": "ValidationError"
  }
]
```

---

## 🔒 Data Security & Privacy

### Anonymization Strategies

**Never use production data directly in test environments!**

**Masking Technique**
```sql
-- Anonymize customer data for testing
UPDATE Customers SET
    Email = CONCAT('test_', CustomerId, '@example.com'),
    FirstName = 'Test',
    LastName = CONCAT('User_', CustomerId),
    Phone = CONCAT('555-01', LPAD(CustomerId, 5, '0')),
    SSN = NULL,
    CreditCardNumber = NULL
WHERE Environment = 'Test';
```

**Synthetic Data Generation**
```csharp
public class SyntheticDataGenerator
{
    private readonly Faker<Customer> _customerFaker;

    public SyntheticDataGenerator()
    {
        _customerFaker = new Faker<Customer>()
            .RuleFor(c => c.FirstName, f => f.Name.FirstName())
            .RuleFor(c => c.LastName, f => f.Name.LastName())
            .RuleFor(c => c.Email, (f, c) => f.Internet.Email(c.FirstName, c.LastName))
            .RuleFor(c => c.Phone, f => f.Phone.PhoneNumber())
            .RuleFor(c => c.DateOfBirth, f => f.Date.Past(50, DateTime.Now.AddYears(-18)));
    }

    public List<Customer> GenerateCustomers(int count)
    {
        return _customerFaker.Generate(count);
    }
}
```

---

## 🗄️ Database Test Data Management

### Test Database Strategies

**1. In-Memory Database**
```csharp
// Fast, isolated, no cleanup needed
var options = new DbContextOptionsBuilder<AppDbContext>()
    .UseInMemoryDatabase(databaseName: "TestDb")
    .Options;

using var context = new AppDbContext(options);
```

**2. Test Container (Docker)**
```csharp
// Real database, isolated, automatic cleanup
public class DatabaseFixture : IAsyncLifetime
{
    private PostgreSqlContainer _container;
    public string ConnectionString { get; private set; }

    public async Task InitializeAsync()
    {
        _container = new PostgreSqlBuilder().Build();
        await _container.StartAsync();
        ConnectionString = _container.GetConnectionString();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}
```

**3. Shared Test Database**
```sql
-- Schema per test run
CREATE SCHEMA test_run_abc123;
SET search_path TO test_run_abc123;
-- Run tests
DROP SCHEMA test_run_abc123 CASCADE;
```

### Data Cleanup Strategies

**Rollback Transactions**
```csharp
[Fact]
public async Task TestWithRollback()
{
    using var transaction = await _context.Database.BeginTransactionAsync();
    try
    {
        // Test code that modifies data
        await _service.CreateOrderAsync(testOrder);
        
        // Assertions
        Assert.True(result.Success);
    }
    finally
    {
        await transaction.RollbackAsync(); // Data changes undone
    }
}
```

**Explicit Cleanup**
```csharp
public class OrderServiceTests : IDisposable
{
    private List<int> _createdOrderIds = new();

    [Fact]
    public async Task TestMethod()
    {
        var order = await _service.CreateOrderAsync(testData);
        _createdOrderIds.Add(order.Id);
        
        // Test assertions
    }

    public void Dispose()
    {
        foreach (var orderId in _createdOrderIds)
        {
            _service.DeleteOrderAsync(orderId).Wait();
        }
    }
}
```

---

## 📦 Test Data Versioning

### Schema Changes

**Migration Strategy**
```bash
# Version test data with schema
migrations/
├── v1.0/
│   ├── schema.sql
│   └── test-data.sql
├── v1.1/
│   ├── migration.sql
│   └── test-data.sql
└── v2.0/
    ├── migration.sql
    └── test-data.sql
```

**Backward Compatibility**
```csharp
public class TestDataVersionManager
{
    public async Task SeedDataForVersion(string version)
    {
        var seedFile = $"TestData/v{version}/seed.sql";
        var sql = await File.ReadAllTextAsync(seedFile);
        await _context.Database.ExecuteSqlRawAsync(sql);
    }
}
```

---

## ✅ Test Data Checklist

### Setup
- [ ] Test data strategy documented
- [ ] Data builders created for complex objects
- [ ] Master/reference data seeded
- [ ] Test database provisioned
- [ ] Data generation tools configured

### Security
- [ ] No production data in test environments
- [ ] Sensitive data anonymized
- [ ] Synthetic data generators implemented
- [ ] Access controls on test data

### Maintenance
- [ ] Test data versioned with code
- [ ] Cleanup strategy implemented
- [ ] Data refresh process documented
- [ ] Test data reviewed quarterly

### Best Practices
- [ ] Tests use isolated test data
- [ ] Data is realistic and representative
- [ ] Boundary and edge cases covered
- [ ] Data builders used for readability

---

## 📚 Resources

- [Bogus - Fake Data Generator](https://github.com/bchavez/Bogus)
- [Testcontainers](https://www.testcontainers.org/)
- [SQL Data Generator](https://www.red-gate.com/products/sql-development/sql-data-generator/)

---

*Last updated: 2025-11-06*
