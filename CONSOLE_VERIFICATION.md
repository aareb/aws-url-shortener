# AWS Console Verification Guide - URL Shortener

## Quick Navigation Links
- Region: **eu-west-2** (Ireland)
- Environment: **dev**

---

## 1. Check Lambda Function

**Path:** AWS Console → Lambda → Functions

**Steps:**
1. Go to AWS Console → Services → Lambda
2. Select Region: **eu-west-2** (top right)
3. Click on function: **dev-url-shortener**
4. Verify:
   -  Runtime: Node.js 20.x
   -  Memory: 256 MB
   -  Timeout: 30 seconds
   -  Reserved Concurrency: 100 (dev)

**Check Logs:**
- Click "Monitor" tab
- Click "View logs in CloudWatch"
- Check recent function executions

**Test Function:**
- Click "Test" button
- Create test event with JSON:
```json
{
  "requestContext": {
    "authorizer": {
      "claims": {
        "sub": "test-user-123"
      }
    }
  },
  "body": "{\"url\": \"https://example.com\"}",
  "routeKey": "POST /shorten"
}
```
- Click "Test" to execute

---

## 2. Check API Gateway

**Path:** AWS Console → API Gateway → APIs

**Steps:**
1. Go to AWS Console → Services → API Gateway
2. Select Region: **eu-west-2**
3. Click on API: **dev-url-shortener-api**

**Verify Configuration:**

### 2a. Routes
- Click "Routes" in left sidebar
- Verify two routes exist:
  -  `POST /shorten` (with JWT authorization)
  -  `GET /{code}` (public, no authorization)

### 2b. Integrations
- Click "Integrations" 
- Verify Lambda integration points to: **dev-url-shortener**

### 2c. Authorizers
- Click "Authorizers"
- Verify: **dev-jwt-authorizer**
  - Type: JWT
  - Identity source: $request.header.Authorization
  - Issuer: Cognito endpoint

### 2d. Stages
- Click "Stages"
- Click **$default**
- Copy the **Invoke URL**: https://m3w4wz01ef.execute-api.eu-west-2.amazonaws.com
- This is your base API endpoint

### 2e. Logs
- In Stage settings, verify logging is enabled
- Go to CloudWatch → Log Groups
- Check: `/aws/apigateway/dev-url-shortener`

---

## 3. Check DynamoDB Table

**Path:** AWS Console → DynamoDB → Tables

**Steps:**
1. Go to AWS Console → Services → DynamoDB
2. Select Region: **eu-west-2**
3. Click on table: **dev-urls**

**Verify Configuration:**
-  Billing mode: **On-demand**
-  Partition key: **code** (String)
-  TTL attribute: **expiresAt** (enabled)
-  Point-in-time recovery: **Enabled**

**Check Indexes:**
- Click "Indexes" tab
- Verify Global Secondary Index:
  - Name: **dev-userId-createdAt-index**
  - Partition key: **userId**
  - Sort key: **createdAt**

**View Data:**
- Click "Items" tab
- See all created short URLs
- View attributes: code, url, userId, createdAt, expiresAt, clickCount

**Monitor Metrics:**
- Click "Metrics" tab
- View:
  - Read/Write capacity consumed
  - Item count
  - Throttled requests

---

## 4. Check Cognito User Pool

**Path:** AWS Console → Cognito → User Pools

**Steps:**
1. Go to AWS Console → Services → Cognito
2. Click "User Pools" (left sidebar)
3. Select Region: **eu-west-2**
4. Click on pool: **dev-url-shortener-users**

**Verify Configuration:**
- Pool name: **dev-url-shortener-users**
- Pool ID: **eu-west-2_FPhqwNdY9**

**Check App Clients:**
- Click "App integration" → "App clients and analytics"
- Client name: **dev-url-shortener-client**
- Copy Client ID (needed for testing)

**Create Test User:**
- Click "Users and groups" (left sidebar)
- Click "Create user"
- Username: **testuser**
- Password: Set temporary password or generate
- Email: **your-email@example.com**
- Mark email as verified: YES
- Set permanent password: YES (set custom password)
- Click "Create user"

**Verify User:**
- User should appear in user list
- Status should show as confirmed/active

---

## 5. Check CloudWatch Logs

**Path:** AWS Console → CloudWatch → Log Groups

### 5a. Lambda Logs
1. Go to AWS Console → Services → CloudWatch
2. Click "Log Groups" (left sidebar)
3. Find: `/aws/lambda/dev-url-shortener`
4. Click to view logs
5. Recent log streams show function executions
6. Expand streams to see:
   - Request details
   - Error messages (if any)
   - Execution duration
   - Response status

### 5b. API Gateway Logs
1. In Log Groups, find: `/aws/apigateway/dev-url-shortener`
2. View API requests
3. See:
   - HTTP method
   - Route
   - Status code
   - Response time
   - Source IP

---

## 6. Check CloudWatch Alarms

**Path:** AWS Console → CloudWatch → Alarms

**Steps:**
1. Go to AWS Console → Services → CloudWatch
2. Click "Alarms" (left sidebar)
3. Filter by: **dev-** prefix

**Verify Alarms:**
-  `dev-lambda-errors` - Alert on function errors
-  `dev-lambda-duration-high` - Alert on slow execution
-  `dev-lambda-throttles` - Alert on throttling
-  `dev-dynamodb-consumed-write` - Alert on high write capacity
-  `dev-url-shortener-api-5xx` - Alert on API errors

**Alarm Details:**
- Click each alarm to view:
  - Threshold settings
  - Recent state changes
  - Metrics graph

---

## 7. Check WAF Rules

**Path:** AWS Console → WAF & Shield → Web ACLs

**Steps:**
1. Go to AWS Console → Services → WAF & Shield
2. Click "Web ACLs" (left sidebar)
3. Select Region: **eu-west-2**
4. Click on Web ACL: **dev-url-shortener**

**Verify Rules:**
-  Rate limiting (2000 requests per IP)
-  OWASP Top 10 (Core Rule Set)
-  SQL Injection prevention
-  XSS protection
-  Known bad inputs
-  IP reputation filtering

**Check Traffic:**
- Click on rule to view metrics
- See blocked vs allowed requests
- Monitor malicious traffic attempts

---

## 8. Test API Endpoints

### 8a. Test in AWS Console (API Gateway)

1. Go to API Gateway → dev-url-shortener-api
2. Click "Routes"
3. Click on route: `GET /{code}`
4. Click "Test" button
5. Set parameters:
   - code: **abc123**
6. Verify response (should redirect or return 404)

### 8b. Test via Browser/cURL

**Get JWT Token First:**

Option 1: Using AWS Cognito Console
1. Go to Cognito → User Pool → dev-url-shortener-users
2. Click "App integration" → "App clients and analytics"
3. Note Client ID
4. Use AWS CLI to get token:
```bash
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id <your-client-id> \
  --auth-parameters USERNAME=testuser,PASSWORD=yourpassword \
  --region eu-west-2
```

**Create Short URL:**
```bash
curl -X POST https://m3w4wz01ef.execute-api.eu-west-2.amazonaws.com/shorten \
  -H "Authorization: Bearer <jwt-token-here>" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.google.com",
    "customCode": "google"
  }'
```

**Expected Response:**
```json
{
  "shortCode": "google",
  "shortUrl": "https://m3w4wz01ef.execute-api.eu-west-2.amazonaws.com/google",
  "originalUrl": "https://www.google.com"
}
```

**Test Redirect:**
```bash
curl -i https://m3w4wz01ef.execute-api.eu-west-2.amazonaws.com/google
```

**Expected Response:**
- Status: 302 Found
- Header: Location: https://www.google.com

---

## 9. Monitor Real-time Activity

### 9a. View Active Requests
1. API Gateway → dev-url-shortener-api
2. Click "Monitor" tab
3. View real-time metrics:
   - Requests per minute
   - API latency
   - Error rates
   - Status code distribution

### 9b. View Lambda Metrics
1. Lambda → dev-url-shortener
2. Click "Monitor" tab
3. View:
   - Invocations (number of calls)
   - Duration (execution time)
   - Errors (failed calls)
   - Throttles (rate limits hit)

### 9c. View DynamoDB Metrics
1. DynamoDB → dev-urls table
2. Click "Metrics" tab
3. View:
   - Consumed read/write units
   - User errors
   - System errors
   - Item count

---

## 10. Check Deployment Status Summary

### Complete Checklist:

-  Lambda function: **dev-url-shortener** is active
-  API Gateway endpoint works: https://m3w4wz01ef.execute-api.eu-west-2.amazonaws.com
-  DynamoDB table: **dev-urls** exists with data
-  Cognito pool: **dev-url-shortener-users** has test user
-  CloudWatch logs show recent function invocations
-  5 alarms are in OK status (or no issues detected)
-  WAF is blocking malicious requests (check metrics)
-  JWT authorization works on POST /shorten
-  Public GET /{code} endpoint returns redirects
-  TTL is expiring old URLs automatically

---

## Troubleshooting in Console

### If you see Lambda errors:
1. Click Lambda → Monitor → View logs
2. Look for error stack traces
3. Common issues:
   - Missing TABLE_NAME environment variable
   - DynamoDB permission issues
   - Invalid URL format

### If API Gateway returns 401 Unauthorized:
1. Verify Cognito authorizer is configured
2. Check JWT token is valid
3. Verify Authorization header format: `Bearer <token>`

### If DynamoDB shows errors:
1. Check table status (should be ACTIVE)
2. Verify IAM role has DynamoDB permissions
3. Check consumed capacity didn't exceed limits

### If WAF blocks all requests:
1. Check WAF rules in WAF & Shield console
2. Whitelist your IP if needed
3. Verify rate limits are appropriate

---

## Performance Benchmarks

Expected metrics:
- **Lambda Duration**: < 500ms (typical)
- **API Latency**: < 1000ms (typical)
- **DynamoDB Response**: < 10ms (typical)
- **Success Rate**: > 99%

---

## Next Steps

1.  Verify all components in AWS Console (this guide)
2.  Test API endpoints
3.  Deploy to Production (when ready)
4.  Set up alerts/notifications
5.  Configure custom domain (optional)
