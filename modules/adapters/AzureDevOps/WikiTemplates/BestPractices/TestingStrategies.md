# Testing Strategies & Best Practices

Comprehensive guide for implementing effective testing strategies across all application layers.

---

## 🎯 Testing Philosophy

### Testing Pyramid

```
           /\
          /  \  E2E Tests (10%)
         /----\
        /      \  Integration Tests (20%)
       /--------\
      /          \  Unit Tests (70%)
     /------------\
```

**Principles**
1. **Fast Feedback**: Unit tests run in milliseconds
2. **Test Independence**: Each test should be isolated
3. **Maintainability**: Tests should be easy to understand and update
4. **Confidence**: Tests should catch regressions effectively

---

## 🔬 Unit Testing

### Best Practices

**✅ DO: Follow AAA Pattern**
```csharp
[Fact]
public async Task CreateOrder_ValidInput_ReturnsOrderId()
{
    // Arrange
    var orderService = new OrderService(_mockRepository.Object, _mockValidator.Object);
    var orderRequest = new CreateOrderRequest
    {
        CustomerId = 123,
        Items = new[] { new OrderItem { ProductId = 1, Quantity = 2 } }
    };

    // Act
    var result = await orderService.CreateOrderAsync(orderRequest);

    // Assert
    Assert.NotNull(result);
    Assert.True(result.OrderId > 0);
    _mockRepository.Verify(r => r.SaveAsync(It.IsAny<Order>()), Times.Once);
}
```

**✅ DO: One Assert Per Test (Generally)**
```csharp
// ✅ GOOD: Single logical assertion
[Fact]
public void CalculateTotal_WithDiscount_ReturnsDiscountedAmount()
{
    var order = new Order { Subtotal = 100, DiscountPercent = 10 };
    
    var total = order.CalculateTotal();
    
    Assert.Equal(90, total);
}

// ✅ ACCEPTABLE: Multiple asserts for single logical concept
[Fact]
public void CreateUser_ValidData_ReturnsCreatedUser()
{
    var user = _userService.CreateUser("john@example.com", "John Doe");
    
    Assert.NotNull(user);
    Assert.NotEqual(0, user.Id);
    Assert.Equal("john@example.com", user.Email);
    Assert.Equal("John Doe", user.Name);
}
```

**✅ DO: Test Edge Cases**
```csharp
[Theory]
[InlineData(0)]     // Zero
[InlineData(-1)]    // Negative
[InlineData(int.MaxValue)] // Maximum
[InlineData(null)]  // Null (if applicable)
public void Divide_EdgeCases_HandlesCorrectly(int value)
{
    // Test implementation
}
```

**❌ DON'T: Test Implementation Details**
```csharp
// ❌ BAD: Testing private methods or implementation
[Fact]
public void InternalCalculation_ReturnsExpectedValue()
{
    var service = new Service();
    var result = service.GetType()
        .GetMethod("InternalCalculate", BindingFlags.NonPublic | BindingFlags.Instance)
        .Invoke(service, new object[] { 10 });
    Assert.Equal(20, result);
}

// ✅ GOOD: Test public behavior
[Fact]
public void ProcessOrder_CalculatesCorrectTotal()
{
    var order = _service.ProcessOrder(orderData);
    Assert.Equal(expectedTotal, order.Total);
}
```

### Mocking & Test Doubles

**Using Moq**
```csharp
public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _mockRepository;
    private readonly Mock<IEmailService> _mockEmailService;
    private readonly OrderService _sut; // System Under Test

    public OrderServiceTests()
    {
        _mockRepository = new Mock<IOrderRepository>();
        _mockEmailService = new Mock<IEmailService>();
        _sut = new OrderService(_mockRepository.Object, _mockEmailService.Object);
    }

    [Fact]
    public async Task CreateOrder_ValidOrder_SendsConfirmationEmail()
    {
        // Arrange
        var order = new Order { Id = 1, CustomerEmail = "customer@example.com" };
        _mockRepository.Setup(r => r.SaveAsync(It.IsAny<Order>()))
            .ReturnsAsync(order);

        // Act
        await _sut.CreateOrderAsync(order);

        // Assert
        _mockEmailService.Verify(
            e => e.SendEmailAsync(
                "customer@example.com",
                "Order Confirmation",
                It.IsAny<string>()),
            Times.Once);
    }

    [Fact]
    public async Task GetOrder_RepositoryThrowsException_ThrowsServiceException()
    {
        // Arrange
        _mockRepository.Setup(r => r.GetByIdAsync(It.IsAny<int>()))
            .ThrowsAsync(new DatabaseException("Connection failed"));

        // Act & Assert
        await Assert.ThrowsAsync<ServiceException>(
            () => _sut.GetOrderAsync(123));
    }
}
```

**Test Data Builders**
```csharp
public class OrderBuilder
{
    private int _customerId = 1;
    private List<OrderItem> _items = new List<OrderItem>();
    private decimal _discount = 0;

    public OrderBuilder WithCustomer(int customerId)
    {
        _customerId = customerId;
        return this;
    }

    public OrderBuilder WithItem(int productId, int quantity, decimal price)
    {
        _items.Add(new OrderItem 
        { 
            ProductId = productId, 
            Quantity = quantity, 
            Price = price 
        });
        return this;
    }

    public OrderBuilder WithDiscount(decimal discount)
    {
        _discount = discount;
        return this;
    }

    public Order Build()
    {
        return new Order
        {
            CustomerId = _customerId,
            Items = _items,
            Discount = _discount
        };
    }
}

// Usage
var order = new OrderBuilder()
    .WithCustomer(123)
    .WithItem(productId: 1, quantity: 2, price: 19.99m)
    .WithItem(productId: 2, quantity: 1, price: 39.99m)
    .WithDiscount(0.1m)
    .Build();
```

---

## 🔗 Integration Testing

### Database Integration Tests

```csharp
public class OrderRepositoryIntegrationTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _fixture;

    public OrderRepositoryIntegrationTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task SaveOrder_ValidOrder_PersistsToDatabase()
    {
        // Arrange
        using var context = _fixture.CreateContext();
        var repository = new OrderRepository(context);
        var order = new Order
        {
            CustomerId = 1,
            OrderDate = DateTime.UtcNow,
            Total = 99.99m
        };

        // Act
        var savedOrder = await repository.SaveAsync(order);
        await context.SaveChangesAsync();

        // Assert
        var retrievedOrder = await repository.GetByIdAsync(savedOrder.Id);
        Assert.NotNull(retrievedOrder);
        Assert.Equal(order.CustomerId, retrievedOrder.CustomerId);
        Assert.Equal(order.Total, retrievedOrder.Total);
    }
}

public class DatabaseFixture : IDisposable
{
    private readonly DbConnection _connection;

    public DatabaseFixture()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        using var context = CreateContext();
        context.Database.EnsureCreated();
    }

    public AppDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(_connection)
            .Options;
        return new AppDbContext(options);
    }

    public void Dispose()
    {
        _connection?.Dispose();
    }
}
```

### API Integration Tests

```csharp
public class OrdersApiTests : IClassFixture<WebApplicationFactory<Startup>>
{
    private readonly WebApplicationFactory<Startup> _factory;
    private readonly HttpClient _client;

    public OrdersApiTests(WebApplicationFactory<Startup> factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetOrder_ExistingOrder_ReturnsOk()
    {
        // Arrange
        var orderId = await CreateTestOrderAsync();

        // Act
        var response = await _client.GetAsync($"/api/orders/{orderId}");

        // Assert
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync();
        var order = JsonSerializer.Deserialize<Order>(content);
        Assert.NotNull(order);
        Assert.Equal(orderId, order.Id);
    }

    [Fact]
    public async Task CreateOrder_ValidData_ReturnsCreated()
    {
        // Arrange
        var orderRequest = new CreateOrderRequest
        {
            CustomerId = 1,
            Items = new[] { new OrderItem { ProductId = 1, Quantity = 2 } }
        };
        var content = new StringContent(
            JsonSerializer.Serialize(orderRequest),
            Encoding.UTF8,
            "application/json");

        // Act
        var response = await _client.PostAsync("/api/orders", content);

        // Assert
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
    }
}
```

---

## 🌐 End-to-End Testing

### Playwright Example

```csharp
[Parallelizable(ParallelScope.Self)]
public class CheckoutE2ETests : PageTest
{
    [SetUp]
    public async Task Setup()
    {
        await Page.GotoAsync("https://example.com");
    }

    [Test]
    public async Task CompleteCheckout_ValidUser_ShowsConfirmation()
    {
        // Navigate to product page
        await Page.ClickAsync("text=Shop Now");
        await Page.ClickAsync("text=Add to Cart");
        
        // Go to cart
        await Page.ClickAsync("text=Cart");
        await Expect(Page.Locator(".cart-item")).ToHaveCountAsync(1);
        
        // Proceed to checkout
        await Page.ClickAsync("text=Checkout");
        
        // Fill shipping info
        await Page.FillAsync("#email", "test@example.com");
        await Page.FillAsync("#name", "John Doe");
        await Page.FillAsync("#address", "123 Main St");
        
        // Fill payment info
        await Page.FillAsync("#card-number", "4242424242424242");
        await Page.FillAsync("#expiry", "12/25");
        await Page.FillAsync("#cvc", "123");
        
        // Submit order
        await Page.ClickAsync("text=Place Order");
        
        // Verify confirmation
        await Expect(Page.Locator("text=Order Confirmed")).ToBeVisibleAsync();
        await Expect(Page.Locator(".order-number")).Not.ToBeEmptyAsync();
    }
}
```

---

## 🧪 Test Organization

### File Structure

```
tests/
├── Unit/
│   ├── Services/
│   │   ├── OrderServiceTests.cs
│   │   └── UserServiceTests.cs
│   ├── Validators/
│   │   └── OrderValidatorTests.cs
│   └── Utilities/
│       └── DateHelperTests.cs
├── Integration/
│   ├── Repositories/
│   │   └── OrderRepositoryTests.cs
│   ├── Api/
│   │   └── OrdersControllerTests.cs
│   └── Fixtures/
│       └── DatabaseFixture.cs
├── E2E/
│   ├── Checkout/
│   │   └── CheckoutFlowTests.cs
│   └── Admin/
│       └── AdminDashboardTests.cs
└── TestUtilities/
    ├── Builders/
    │   └── OrderBuilder.cs
    └── Helpers/
        └── TestDataHelper.cs
```

### Naming Conventions

```csharp
// Pattern: MethodName_Scenario_ExpectedBehavior
[Fact]
public void CalculateDiscount_ValidCoupon_AppliesCorrectDiscount() { }

[Fact]
public void CreateUser_EmailAlreadyExists_ThrowsValidationException() { }

[Fact]
public void ProcessPayment_InsufficientFunds_ReturnsFailureResult() { }

// Theory for multiple test cases
[Theory]
[InlineData(0, 0)]
[InlineData(100, 10)]
[InlineData(1000, 100)]
public void CalculateTax_VariousAmounts_ReturnsCorrectTax(decimal amount, decimal expectedTax) { }
```

---

## 📊 Test Coverage

### Coverage Targets

| Layer | Target Coverage | Critical Path |
|-------|----------------|---------------|
| Business Logic | 80-90% | 100% |
| Controllers | 70-80% | 90% |
| Repositories | 70-80% | 90% |
| Utilities | 90-100% | 100% |

**Measure Coverage**
```bash
# .NET
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura

# View report
reportgenerator -reports:coverage.cobertura.xml -targetdir:coverage-report
```

### What to Test

**✅ DO Test**
- Business logic and rules
- Edge cases and boundary conditions
- Error handling and validation
- Security checks and authorization
- Critical user paths
- Complex algorithms

**❌ DON'T Test**
- Third-party libraries
- Simple getters/setters
- Framework code
- Auto-generated code
- Trivial methods

---

## ✅ Testing Checklist

### Development
- [ ] Unit tests for all business logic
- [ ] Tests follow AAA pattern
- [ ] One logical assertion per test
- [ ] Tests are independent and isolated
- [ ] Test data builders for complex objects
- [ ] Mock external dependencies

### Integration
- [ ] Database integration tests with test database
- [ ] API integration tests with WebApplicationFactory
- [ ] External service integration tests
- [ ] Test cleanup after each test
- [ ] Use test fixtures for setup/teardown

### E2E
- [ ] Critical user journeys tested
- [ ] Tests run in isolated environment
- [ ] Stable selectors used
- [ ] Proper waits for async operations
- [ ] Screenshots on failure

### CI/CD
- [ ] Tests run on every PR
- [ ] Unit tests run fast (< 30 seconds)
- [ ] Integration tests run separately
- [ ] E2E tests run nightly or pre-release
- [ ] Code coverage reports generated
- [ ] Failed tests block deployment

---

## 📚 Resources

- [xUnit Documentation](https://xunit.net/)
- [Moq Framework](https://github.com/moq/moq4)
- [Playwright for .NET](https://playwright.dev/dotnet/)
- [Test-Driven Development](https://martinfowler.com/bliki/TestDrivenDevelopment.html)
- [Testing Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)

---

*Last updated: 2025-11-06*


---

## 📚 References

- [Testing Best Practices (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/core/testing/)
- [Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
- [xUnit Documentation](https://xunit.net/)
- [Jest Testing Framework](https://jestjs.io/)
- [Azure DevOps Test Plans](https://learn.microsoft.com/en-us/azure/devops/test/)
- [Testing Library](https://testing-library.com/)