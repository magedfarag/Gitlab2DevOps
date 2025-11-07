# API Documentation

Comprehensive guide to the project's APIs and integration contracts.

## API Overview

### Base URLs

| Environment | URL |
|-------------|-----|
| **Development** | http://localhost:5000 |
| **Staging** | https://staging-api.example.com |
| **Production** | https://api.example.com |

### Authentication

**Type**: Bearer Token (JWT)

````````````http
Authorization: Bearer <your-jwt-token>
````````````

### Common Headers

````````````http
Content-Type: application/json
Accept: application/json
X-API-Version: 1.0
````````````

## API Endpoints

### User Management

#### GET /api/users

Get list of users.

**Request**:
````````````http
GET /api/users?page=1&size=20
Authorization: Bearer <token>
````````````

**Response** (200 OK):
````````````json
{
  "data": [
    {
      "id": "123",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "developer"
    }
  ],
  "pagination": {
    "page": 1,
    "size": 20,
    "total": 100
  }
}
````````````

#### POST /api/users

Create new user.

**Request**:
````````````json
{
  "name": "Jane Smith",
  "email": "jane@example.com",
  "role": "developer"
}
````````````

**Response** (201 Created):
````````````json
{
  "id": "124",
  "name": "Jane Smith",
  "email": "jane@example.com",
  "role": "developer",
  "createdAt": "2024-01-15T10:30:00Z"
}
````````````

## Error Handling

### Standard Error Response

````````````json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": [
      {
        "field": "email",
        "message": "Email format is invalid"
      }
    ]
  }
}
````````````

### HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET request |
| 201 | Created | Successful POST (resource created) |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input data |
| 401 | Unauthorized | Missing or invalid token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists |
| 500 | Internal Server Error | Server error |

## Rate Limiting

- **Rate**: 1000 requests per hour per user
- **Header**: \``X-RateLimit-Remaining\``
- **Reset**: \``X-RateLimit-Reset\`` (Unix timestamp)

## Webhooks

### Subscribing to Events

````````````http
POST /api/webhooks
Content-Type: application/json

{
  "url": "https://your-app.com/webhook",
  "events": ["user.created", "user.updated"],
  "secret": "your-webhook-secret"
}
````````````

### Webhook Payload

````````````json
{
  "event": "user.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "id": "124",
    "name": "Jane Smith"
  }
}
````````````

## OpenAPI Specification

Full OpenAPI (Swagger) specification available at:
- **Development**: http://localhost:5000/swagger
- **Staging**: https://staging-api.example.com/swagger

## Testing APIs

### Using cURL

````````````bash
curl -X GET "http://localhost:5000/api/users" \
  -H "Authorization: Bearer <token>" \
  -H "Accept: application/json"
````````````

### Using Postman

1. Import collection: \``docs/postman/collection.json\``
2. Set environment variables
3. Run requests

### Using REST Client (VS Code)

Create \``.http\`` files:

````````````http
### Get Users
GET http://localhost:5000/api/users
Authorization: Bearer {{token}}

### Create User
POST http://localhost:5000/api/users
Content-Type: application/json

{
  "name": "Test User",
  "email": "test@example.com"
}
````````````

## Integration Patterns

### Pagination

All list endpoints support pagination:
- \``page\``: Page number (1-based)
- \``size\``: Items per page (max 100)

### Filtering

Use query parameters:
````````````
GET /api/users?role=developer&status=active
````````````

### Sorting

Use \``sort\`` parameter:
````````````
GET /api/users?sort=name:asc,createdAt:desc
````````````

## Versioning Strategy

- **URL Versioning**: \``/api/v1/users\``
- **Header Versioning**: \``X-API-Version: 1.0\``
- **Deprecation Notice**: 6 months before removal

---

**Next Steps**: Update this page as APIs evolve. Link API changes to ADRs.

---

## 📚 References

- [OpenAPI Specification](https://swagger.io/specification/)
- [API Design Guidelines (Microsoft)](https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design)
- [REST API Tutorial](https://restfulapi.net/)
- [Swagger/OpenAPI Tools](https://swagger.io/tools/)
- [API Documentation Best Practices](https://swagger.io/blog/api-documentation/best-practices-in-api-documentation/)