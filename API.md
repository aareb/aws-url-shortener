# URL Shortener API Documentation

## Overview

This is a RESTful API for creating and managing shortened URLs. The API provides public endpoints for redirecting to original URLs and authenticated endpoints for creating new short URLs.

## Base URL

```
https://{api_endpoint}
```

## Authentication

The API uses JWT (JSON Web Tokens) for authentication. Tokens are issued by AWS Cognito and must be included in the `Authorization` header for protected endpoints.

### Getting a Token

Users must authenticate with Cognito to obtain a JWT token:

```bash
curl -X POST https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id={client_id}&client_secret={client_secret}"
```

## Endpoints

### 1. Create a Shortened URL

**POST** `/shorten`

Creates a new shortened URL mapping.

#### Authentication
- **Required**: Yes (JWT Bearer Token)
- **Header**: `Authorization: Bearer {token}`

#### Request Body

```json
{
  "url": "https://example.com/very/long/url/path",
  "customCode": "my-code",  // Optional: custom short code (3-20 alphanumeric)
  "tags": ["example", "test"]  // Optional: for organization
}
```

#### Request Validation

- `url` (required): Must be a valid HTTP/HTTPS URL
- `url`: Cannot point to internal IP addresses (127.0.0.0/8, 169.254.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- `customCode` (optional): Must be 3-20 characters, alphanumeric with hyphens/underscores
- `tags` (optional): Array of strings for metadata

#### Success Response (201)

```json
{
  "shortUrl": "https://short.example.com/abc1d2e3",
  "code": "abc1d2e3",
  "originalUrl": "https://example.com/very/long/url/path",
  "expiresAt": 1734595200
}
```

#### Error Responses

**400 Bad Request** - Invalid URL or request body
```json
{
  "error": "Invalid or unsafe URL",
  "details": "URL must be http/https and not point to internal IPs"
}
```

**401 Unauthorized** - Missing or invalid JWT token
```json
{
  "error": "Unauthorized"
}
```

**409 Conflict** - Custom code already exists
```json
{
  "error": "Short code already in use"
}
```

**500 Internal Server Error** - Server error
```json
{
  "error": "Internal server error"
}
```

---

### 2. Redirect to Original URL

**GET** `/{code}`

Retrieves and redirects to the original URL associated with the short code.

#### Authentication
- **Required**: No

#### Path Parameters

- `code` (required): The shortened code (e.g., `abc1d2e3`)

#### Success Response (302)

Returns a `302 Found` redirect to the original URL.

```
Location: https://example.com/very/long/url/path
Cache-Control: no-cache
```

#### Error Responses

**404 Not Found** - Short code does not exist
```json
{
  "error": "Short URL not found"
}
```

**410 Gone** - URL has expired or been deactivated
```json
{
  "error": "Short URL no longer available"
}
```

**500 Internal Server Error** - Server error
```json
{
  "error": "Internal server error"
}
```

---

## Rate Limiting

The API implements rate limiting at the WAF level:

- **Per IP**: 2,000 requests per 5 minutes
- **Response**: HTTP 429 (Too Many Requests) when limit exceeded

---

## Error Handling

All error responses follow this format:

```json
{
  "error": "Error message",
  "details": "Additional error details (optional)"
}
```

### Common HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | OK - Request successful |
| 201 | Created - Resource created successfully |
| 302 | Found - Redirect response |
| 400 | Bad Request - Invalid input |
| 401 | Unauthorized - Authentication required |
| 404 | Not Found - Resource not found |
| 409 | Conflict - Resource already exists |
| 410 | Gone - Resource no longer available |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error - Server error |

---

## Security Considerations

### HTTPS Only
All endpoints require HTTPS. HTTP requests will be rejected.

### JWT Security
- Tokens are issued by AWS Cognito with standard OAuth 2.0 flow
- Tokens contain user ID (sub) for audit trails
- Token expiration should be configured in Cognito settings

### URL Validation
- Only HTTP/HTTPS URLs are allowed
- Internal/private IP ranges are blocked to prevent SSRF attacks
- Domain reputation is checked via AWS WAF managed rules

### DDoS Protection
- AWS WAF provides rate limiting and bot protection
- Geo-blocking can be configured if needed
- SQL injection and XSS protection via managed rules

---

## Examples

### cURL

#### Create a short URL
```bash
curl -X POST https://api.example.com/shorten \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -d '{
    "url": "https://example.com/very/long/url",
    "customCode": "mylink",
    "tags": ["important"]
  }'
```

#### Use a short URL
```bash
curl -L https://short.example.com/mylink
# Redirects to: https://example.com/very/long/url
```

### Python

```python
import requests

# Create short URL
response = requests.post(
  'https://api.example.com/shorten',
  headers={'Authorization': 'Bearer {token}'},
  json={
    'url': 'https://example.com/very/long/url',
    'customCode': 'mylink'
  }
)
print(response.json())

# Redirect
response = requests.get('https://short.example.com/mylink', allow_redirects=True)
print(response.url)
```

---

## Performance

### Latency Targets
- **Redirect (GET)**: < 100ms (p99)
- **Create (POST)**: < 1 second (p99)

### Scalability
- Lambda auto-scales to handle traffic spikes
- DynamoDB on-demand pricing scales with usage
- CloudFront caching can be added for read-heavy workloads

---

## Monitoring

### Key Metrics

- **Invocations**: Total API calls
- **Errors**: 4xx and 5xx responses
- **Duration**: Lambda execution time
- **Latency**: API Gateway latency
- **Throttles**: Rate limit hit count

### CloudWatch Alarms

- Lambda errors > 5 in 5 minutes
- API Gateway 5xx errors > 5 in 5 minutes
- API latency (average) > 1 second
- DynamoDB user errors > 10 in 5 minutes

---

## Data Model

### URL Mapping Item

```json
{
  "code": "abc1d2e3",           // Partition key
  "userId": "user-123",          // User who created it
  "originalUrl": "https://...",  // Target URL
  "createdAt": 1703001600000,    // Unix timestamp
  "expiresAt": 1734595200,       // TTL attribute (unix seconds)
  "status": "active",            // active | archived | deleted
  "clickCount": 42,              // Number of times accessed
  "lastAccessedAt": 1703002000000, // Last redirect timestamp
  "tags": ["example", "test"]    // User metadata
}
```

---

## Support

For issues or questions, please contact: support@example.com
