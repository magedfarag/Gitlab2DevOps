# Automation Framework & Best Practices

Guide for building and maintaining effective test automation frameworks.

---

## 🎯 Automation Strategy

### When to Automate

**✅ Good Candidates**
- Regression tests (run frequently)
- Smoke/sanity tests
- Data-driven tests (many variations)
- API/integration tests
- Performance tests
- Cross-browser/platform tests

**❌ Poor Candidates**
- One-time tests
- Exploratory testing
- UI with frequent changes
- Tests requiring human judgment
- Tests harder to automate than run manually

### Automation Pyramid

```
       /\
      /UI\ (10% - E2E)
     /----\
    / API \ (30% - Integration)
   /------\
  / Unit  \ (60% - Fast, Isolated)
 /--------\
```

---

## 🏗️ Framework Architecture

### Layered Architecture

```
┌─────────────────────────────────┐
│   Test Layer (Test Cases)       │
├─────────────────────────────────┤
│   Business Logic Layer (Steps)  │
├─────────────────────────────────┤
│   Page Object Layer (UI)        │
├─────────────────────────────────┤
│   Core Framework (Utils, Config)│
└─────────────────────────────────┘
```

### Page Object Model (POM)

**Structure**
```csharp
public class LoginPage
{
    private readonly IWebDriver _driver;
    
    // Locators
    private By UsernameInput => By.Id("username");
    private By PasswordInput => By.Id("password");
    private By LoginButton => By.CssSelector("button[type='submit']");
    private By ErrorMessage => By.ClassName("error-message");
    
    public LoginPage(IWebDriver driver)
    {
        _driver = driver;
    }
    
    // Actions
    public LoginPage EnterUsername(string username)
    {
        _driver.FindElement(UsernameInput).SendKeys(username);
        return this;
    }
    
    public LoginPage EnterPassword(string password)
    {
        _driver.FindElement(PasswordInput).SendKeys(password);
        return this;
    }
    
    public DashboardPage ClickLogin()
    {
        _driver.FindElement(LoginButton).Click();
        return new DashboardPage(_driver);
    }
    
    public string GetErrorMessage()
    {
        return _driver.FindElement(ErrorMessage).Text;
    }
    
    // Validations
    public bool IsDisplayed()
    {
        return _driver.FindElement(LoginButton).Displayed;
    }
}

// Test usage
[Test]
public void Login_ValidCredentials_Success()
{
    var loginPage = new LoginPage(_driver);
    var dashboardPage = loginPage
        .EnterUsername("testuser@example.com")
        .EnterPassword("SecurePass123!")
        .ClickLogin();
    
    Assert.That(dashboardPage.IsDisplayed(), Is.True);
}
```

### Fluent Interface Pattern

```csharp
public class OrderFluentBuilder
{
    private readonly TestContext _context;
    private Order _order;
    
    public OrderFluentBuilder(TestContext context)
    {
        _context = context;
        _order = new Order();
    }
    
    public OrderFluentBuilder ForCustomer(string email)
    {
        _order.CustomerId = _context.GetCustomerByEmail(email).Id;
        return this;
    }
    
    public OrderFluentBuilder WithProduct(string productName, int quantity)
    {
        var product = _context.GetProductByName(productName);
        _order.Items.Add(new OrderItem 
        { 
            ProductId = product.Id, 
            Quantity = quantity,
            Price = product.Price
        });
        return this;
    }
    
    public OrderFluentBuilder WithShipping(string method)
    {
        _order.ShippingMethod = method;
        return this;
    }
    
    public async Task<Order> CreateAsync()
    {
        return await _context.OrderService.CreateOrderAsync(_order);
    }
}

// Usage
var order = await new OrderFluentBuilder(_context)
    .ForCustomer("john@example.com")
    .WithProduct("Widget Pro", quantity: 2)
    .WithProduct("Gadget Lite", quantity: 1)
    .WithShipping("Express")
    .CreateAsync();
```

---

## 🔧 Framework Components

### Configuration Management

**appsettings.json**
```json
{
  "TestSettings": {
    "BaseUrl": "https://test.example.com",
    "Browser": "Chrome",
    "Headless": false,
    "Timeout": 30,
    "RetryCount": 2,
    "ScreenshotOnFailure": true,
    "VideoRecording": false
  },
  "TestData": {
    "DefaultEmail": "testuser@example.com",
    "DefaultPassword": "Test123!",
    "ApiKey": "test-api-key-12345"
  }
}
```

**Configuration Class**
```csharp
public class TestConfiguration
{
    private readonly IConfiguration _config;
    
    public TestConfiguration()
    {
        _config = new ConfigurationBuilder()
            .AddJsonFile("appsettings.json")
            .AddJsonFile($"appsettings.{Environment}.json", optional: true)
            .AddEnvironmentVariables()
            .Build();
    }
    
    public string BaseUrl => _config["TestSettings:BaseUrl"];
    public string Browser => _config["TestSettings:Browser"];
    public bool Headless => bool.Parse(_config["TestSettings:Headless"]);
    public int Timeout => int.Parse(_config["TestSettings:Timeout"]);
}
```

### WebDriver Factory

```csharp
public class WebDriverFactory
{
    public static IWebDriver CreateDriver(string browser, bool headless = false)
    {
        return browser.ToLower() switch
        {
            "chrome" => CreateChromeDriver(headless),
            "firefox" => CreateFirefoxDriver(headless),
            "edge" => CreateEdgeDriver(headless),
            _ => throw new ArgumentException($"Unsupported browser: {browser}")
        };
    }
    
    private static IWebDriver CreateChromeDriver(bool headless)
    {
        var options = new ChromeOptions();
        if (headless) options.AddArgument("--headless");
        options.AddArgument("--no-sandbox");
        options.AddArgument("--disable-dev-shm-usage");
        options.AddArgument("--window-size=1920,1080");
        
        return new ChromeDriver(options);
    }
}
```

### Wait Strategies

```csharp
public static class WaitHelper
{
    public static void WaitForElement(this IWebDriver driver, By locator, int timeoutSeconds = 10)
    {
        var wait = new WebDriverWait(driver, TimeSpan.FromSeconds(timeoutSeconds));
        wait.Until(d => d.FindElement(locator).Displayed);
    }
    
    public static void WaitForElementToBeClickable(this IWebDriver driver, By locator, int timeoutSeconds = 10)
    {
        var wait = new WebDriverWait(driver, TimeSpan.FromSeconds(timeoutSeconds));
        wait.Until(ExpectedConditions.ElementToBeClickable(locator));
    }
    
    public static void WaitForTextToAppear(this IWebDriver driver, By locator, string text, int timeoutSeconds = 10)
    {
        var wait = new WebDriverWait(driver, TimeSpan.FromSeconds(timeoutSeconds));
        wait.Until(d => d.FindElement(locator).Text.Contains(text));
    }
}
```

---

## 📊 Reporting & Logging

### Extent Reports Integration

```csharp
public class TestBase
{
    protected static ExtentReports _extent;
    protected ExtentTest _test;
    
    [OneTimeSetUp]
    public void GlobalSetup()
    {
        var reporter = new ExtentHtmlReporter("TestResults/report.html");
        _extent = new ExtentReports();
        _extent.AttachReporter(reporter);
    }
    
    [SetUp]
    public void TestSetup()
    {
        var testName = TestContext.CurrentContext.Test.Name;
        _test = _extent.CreateTest(testName);
    }
    
    [TearDown]
    public void TestTeardown()
    {
        var status = TestContext.CurrentContext.Result.Outcome.Status;
        if (status == TestStatus.Failed)
        {
            _test.Fail(TestContext.CurrentContext.Result.Message);
            var screenshot = ((ITakesScreenshot)_driver).GetScreenshot();
            _test.AddScreenCaptureFromBase64String(screenshot.AsBase64EncodedString);
        }
        else if (status == TestStatus.Passed)
        {
            _test.Pass("Test passed");
        }
    }
    
    [OneTimeTearDown]
    public void GlobalTeardown()
    {
        _extent.Flush();
    }
}
```

### Structured Logging

```csharp
public class TestLogger
{
    private readonly ILogger _logger;
    
    public TestLogger()
    {
        _logger = new LoggerConfiguration()
            .WriteTo.Console()
            .WriteTo.File("logs/test-.log", rollingInterval: RollingInterval.Day)
            .CreateLogger();
    }
    
    public void LogTestStep(string stepDescription)
    {
        _logger.Information("[TEST STEP] {Step}", stepDescription);
    }
    
    public void LogAssertion(string assertion, bool passed)
    {
        if (passed)
            _logger.Information("[ASSERTION PASSED] {Assertion}", assertion);
        else
            _logger.Error("[ASSERTION FAILED] {Assertion}", assertion);
    }
}
```

---

## 🔄 CI/CD Integration

### Azure Pipelines

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseDotNet@2
  inputs:
    version: '7.x'

- script: dotnet restore
  displayName: 'Restore dependencies'

- script: dotnet build --no-restore
  displayName: 'Build'

- script: |
    dotnet test \
      --no-build \
      --logger "trx;LogFileName=test-results.trx" \
      --logger "html;LogFileName=test-results.html" \
      --collect:"XPlat Code Coverage"
  displayName: 'Run automated tests'

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '**/*.trx'
    testRunTitle: 'Automated Test Results'

- task: PublishCodeCoverageResults@1
  inputs:
    codeCoverageTool: 'Cobertura'
    summaryFileLocation: '**/coverage.cobertura.xml'
```

---

## ✅ Automation Best Practices

### Code Quality
- [ ] Follow DRY principle (Don't Repeat Yourself)
- [ ] Use meaningful variable and method names
- [ ] Keep methods small and focused
- [ ] Implement proper exception handling
- [ ] Add comments for complex logic

### Maintainability
- [ ] Use Page Object Model
- [ ] Externalize test data
- [ ] Centralize configuration
- [ ] Implement proper logging
- [ ] Version control all test code

### Reliability
- [ ] Implement smart waits (no hard sleeps)
- [ ] Handle flaky tests appropriately
- [ ] Use retry mechanism for transient failures
- [ ] Clean up test data after execution
- [ ] Run tests in parallel where possible

### Reporting
- [ ] Generate HTML reports
- [ ] Capture screenshots on failure
- [ ] Log test execution details
- [ ] Track metrics (pass rate, duration)
- [ ] Integrate with test management tools

---

## 📚 Resources

- [Selenium Documentation](https://www.selenium.dev/documentation/)
- [Playwright](https://playwright.dev/)
- [RestSharp - API Testing](https://restsharp.dev/)
- [Extent Reports](https://www.extentreports.com/)

---

*Last updated: 2025-11-06*
