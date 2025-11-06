# Documentation Guidelines

Best practices for creating and maintaining effective technical documentation.

---

## 🎯 Documentation Principles

### Core Values

**1. Clarity Over Cleverness**
- Write for your audience, not to impress
- Use simple language when possible
- Define technical terms on first use

**2. Completeness & Context**
- Explain the "why" not just the "how"
- Include prerequisites and assumptions
- Provide examples and use cases

**3. Maintainability**
- Keep docs close to code (docs-as-code)
- Version control all documentation
- Review and update regularly

**4. Discoverability**
- Organize logically with clear navigation
- Use consistent structure and templates
- Implement search functionality

---

## 📝 Types of Documentation

### README Files

**Project README Template**
```markdown
# Project Name

Brief one-paragraph description of what the project does.

## Features

- Feature 1
- Feature 2
- Feature 3

## Prerequisites

- Node.js 18+
- Docker Desktop
- Azure CLI

## Quick Start

\`\`\`bash
# Clone and install
git clone <repository-url>
cd project-name
npm install

# Run locally
npm run dev
\`\`\`

## Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| API_URL | Backend API endpoint | http://localhost:3000 | Yes |
| LOG_LEVEL | Logging verbosity | info | No |

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

MIT License - see [LICENSE](LICENSE) file.
```

### API Documentation

**Endpoint Documentation Template**
```markdown
### POST /api/orders

Create a new order.

**Authentication**: Required (Bearer token)

**Request Body**:
\`\`\`json
{
  "customerId": 123,
  "items": [
    {
      "productId": 456,
      "quantity": 2,
      "price": 19.99
    }
  ],
  "shippingAddress": {
    "street": "123 Main St",
    "city": "Springfield",
    "zipCode": "12345"
  }
}
\`\`\`

**Response** (201 Created):
\`\`\`json
{
  "orderId": 789,
  "status": "pending",
  "total": 39.98,
  "createdAt": "2025-11-06T10:30:00Z"
}
\`\`\`

**Error Responses**:
- `400 Bad Request`: Invalid request data
- `401 Unauthorized`: Missing or invalid authentication
- `422 Unprocessable Entity`: Business rule violation

**Example**:
\`\`\`bash
curl -X POST https://api.example.com/orders \\
  -H "Authorization: Bearer <token>" \\
  -H "Content-Type: application/json" \\
  -d '{"customerId": 123, "items": [...]}'
\`\`\`
```

### Code Documentation

**Function/Method Documentation**
```csharp
/// <summary>
/// Calculates the total price for an order including tax and shipping.
/// </summary>
/// <param name="order">The order to calculate the total for.</param>
/// <param name="shippingMethod">The shipping method to use. Defaults to Standard.</param>
/// <returns>
/// An <see cref="OrderTotal"/> containing the subtotal, tax, shipping, and grand total.
/// </returns>
/// <exception cref="ArgumentNullException">Thrown when order is null.</exception>
/// <exception cref="ValidationException">Thrown when order has no items.</exception>
/// <remarks>
/// Tax calculation uses the shipping address zip code to determine tax rate.
/// Shipping cost is based on total weight and selected shipping method.
/// </remarks>
/// <example>
/// <code>
/// var order = new Order { Items = [...] };
/// var total = CalculateTotal(order, ShippingMethod.Express);
/// Console.WriteLine($"Total: {total.GrandTotal:C}");
/// </code>
/// </example>
public OrderTotal CalculateTotal(Order order, ShippingMethod shippingMethod = ShippingMethod.Standard)
{
    // Implementation
}
```

**Class Documentation**
```csharp
/// <summary>
/// Manages order processing including validation, payment, and fulfillment.
/// </summary>
/// <remarks>
/// This service coordinates multiple dependencies:
/// - <see cref="IOrderRepository"/> for data persistence
/// - <see cref="IPaymentService"/> for payment processing
/// - <see cref="IInventoryService"/> for stock management
/// - <see cref="INotificationService"/> for customer notifications
/// 
/// Thread-safe for concurrent order processing.
/// </remarks>
public class OrderService : IOrderService
{
    // Implementation
}
```

---

## 📐 Documentation Structure

### Architecture Decision Records (ADR)

**Template**
```markdown
# ADR-001: Use PostgreSQL for Primary Database

## Status
Accepted

## Context
We need a database that supports:
- ACID transactions
- Complex queries with joins
- JSON data types for flexibility
- High availability and replication
- Strong community support

Our team has experience with both PostgreSQL and MySQL.

## Decision
We will use PostgreSQL 15 as our primary database.

## Consequences

### Positive
- Excellent JSON support (JSONB)
- Advanced features (CTEs, window functions)
- Strong consistency guarantees
- Mature ecosystem and tooling

### Negative
- Slightly more complex setup than MySQL
- Team needs training on PostgreSQL-specific features

### Neutral
- Must maintain connection pooling (PgBouncer)
- Need monitoring setup (pg_stat_statements)

## Implementation
- Migration from existing MySQL in Q1 2026
- Use Entity Framework Core with Npgsql provider
- Set up streaming replication for HA
```

### Runbooks

**Template**
```markdown
# Runbook: Database Backup Restore

## Overview
Procedure for restoring database from backup in emergency situations.

## Prerequisites
- Access to Azure Portal
- Azure CLI installed
- Permissions: Contributor on resource group
- Backup file location or point-in-time

## Steps

### 1. Verify Backup Availability
\`\`\`bash
az postgres flexible-server backup list \\
  --resource-group prod-rg \\
  --server-name prod-db-server
\`\`\`

### 2. Stop Application
\`\`\`bash
kubectl scale deployment api-deployment --replicas=0
\`\`\`

### 3. Restore Database
\`\`\`bash
az postgres flexible-server restore \\
  --resource-group prod-rg \\
  --name prod-db-restore \\
  --source-server prod-db-server \\
  --restore-time "2025-11-06T10:00:00Z"
\`\`\`

**Expected Duration**: 15-30 minutes

### 4. Verify Data Integrity
\`\`\`sql
-- Check row counts
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM customers;

-- Check latest records
SELECT MAX(created_at) FROM orders;
\`\`\`

### 5. Update Connection Strings
Update app configuration to point to restored database.

### 6. Restart Application
\`\`\`bash
kubectl scale deployment api-deployment --replicas=3
\`\`\`

### 7. Monitor
Watch application logs and metrics for 30 minutes.

## Rollback
If restore fails, revert connection strings to original database.

## Post-Incident
- Document what caused the need for restore
- Update backup procedures if needed
- Conduct post-mortem meeting
```

---

## ✅ Documentation Checklist

### For Every Feature
- [ ] README updated if user-facing changes
- [ ] API documentation updated (if API changes)
- [ ] Code comments for complex logic
- [ ] Architecture diagrams updated
- [ ] Configuration examples provided
- [ ] Migration guide (if breaking changes)

### For New Projects
- [ ] Comprehensive README with quick start
- [ ] Architecture overview document
- [ ] Setup and installation guide
- [ ] Development workflow documented
- [ ] Deployment procedures
- [ ] Troubleshooting section

### Regular Maintenance
- [ ] Review docs quarterly
- [ ] Remove outdated information
- [ ] Fix broken links
- [ ] Update screenshots if UI changed
- [ ] Verify examples still work
- [ ] Check for security issues in examples

---

## 🎨 Writing Style Guide

### General Guidelines

**Use Active Voice**
- ✅ "Click the Submit button"
- ❌ "The Submit button should be clicked"

**Be Concise**
- ✅ "Install dependencies: `npm install`"
- ❌ "In order to install the project dependencies, you need to run the npm install command in your terminal"

**Use Examples**
```markdown
### Configuration

Set the API URL in your environment:

\`\`\`bash
export API_URL=https://api.example.com
\`\`\`

For Windows PowerShell:

\`\`\`powershell
$env:API_URL="https://api.example.com"
\`\`\`
```

### Formatting

**Code Blocks**: Always specify language
```markdown
\`\`\`javascript
const result = calculateTotal(items);
\`\`\`
```

**Emphasis**
- **Bold** for UI elements: "Click the **Save** button"
- *Italic* for emphasis: "This is *not* recommended"
- `Code` for values: "Set `DEBUG=true`"

**Lists**
- Use bullets for unordered items
- Use numbers for sequential steps
- Keep items parallel in structure

---

## 📚 Tools & Resources

### Documentation Tools
- **Wiki**: Azure DevOps Wiki (this wiki!)
- **API Docs**: Swagger/OpenAPI, Redoc
- **Diagrams**: Draw.io, Mermaid, PlantUML
- **Screenshots**: Snagit, Greenshot
- **Screen Recording**: OBS Studio, Loom

### Documentation as Code
```yaml
# .github/workflows/docs.yml
name: Documentation
on:
  push:
    paths:
      - 'docs/**'
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build docs
        run: mkdocs build
      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
```

---

## 📖 Resources

- [Write the Docs](https://www.writethedocs.org/)
- [Google Developer Documentation Style Guide](https://developers.google.com/style)
- [Microsoft Writing Style Guide](https://docs.microsoft.com/en-us/style-guide/)
- [Diátaxis Documentation Framework](https://diataxis.fr/)

---

*Last updated: 2025-11-06*


---

## 📚 References

- [Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)
- [README Best Practices](https://github.com/matiassingers/awesome-readme)
- [Markdown Guide](https://www.markdownguide.org/)
- [API Documentation with OpenAPI](https://swagger.io/specification/)
- [Write the Docs](https://www.writethedocs.org/)