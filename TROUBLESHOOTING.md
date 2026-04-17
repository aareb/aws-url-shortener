# Troubleshooting Guide

Common issues and solutions for the URL Shortener application.

## Table of Contents

1. [Deployment Issues](#deployment-issues)
2. [Runtime Issues](#runtime-issues)
3. [Performance Issues](#performance-issues)
4. [Authentication Issues](#authentication-issues)
5. [Data/Database Issues](#databatabase-issues)
6. [Monitoring & Debugging](#monitoring--debugging)
7. [Common Errors](#common-errors)

---

## Deployment Issues

### Terraform Init Fails

**Error**: `Error reading S3 Bucket in account`

**Causes**:
- S3 backend bucket doesn't exist
- IAM user lacks S3 permissions
- Bucket name is incorrect in backend.tf

**Solution**:
```bash
# 1. Verify bucket exists
aws s3 ls s3://your-bucket-name

# 2. Check permissions
aws s3api get-bucket-versioning --bucket your-bucket-name

# 3. If bucket missing, create it
aws s3 mb s3://url-shortener-tf-state-$(date +%s) --region eu-west-2

# 4. Update backend.tf with correct bucket name
# 5. Retry terraform init
```

### Terraform Validate Fails

**Error**: `Error: Missing required argument: "variable_name"`

**Causes**:
- Variables defined in variables.tf but missing from tfvars file
- Typo in variable name

**Solution**:
```bash
# Check what variables are required
terraform console
> var.

# Compare with tfvars file
diff <(grep "variable " variables.tf) <(grep "=" env/dev.tfvars)

# Add missing variables to tfvars
```

### Lambda Package Too Large

**Error**: `An error occurred (RequestEntityTooLargeException) when calling the PutFunction operation`

**Causes**:
- node_modules includes development dependencies
- Unneeded files included in zip

**Solution**:
```bash
# 1. Install production dependencies only
cd lamda
rm -rf node_modules package-lock.json
npm install --production

# 2. Check package size
ls -lh ../terraform/lambda.zip

# 3. Optimize dependencies
npm prune --production

# 4. Remove test files from zip
zip -r ../terraform/lambda.zip . -x "*.test.js"
```

### Insufficient IAM Permissions

**Error**: `User: arn:aws:iam::... is not authorized to perform...`

**Causes**:
- IAM user lacks required permissions
- Resource ARN mismatch

**Solution**:
```bash
# 1. Verify current user
aws sts get-caller-identity

# 2. Check attached policies
aws iam list-attached-user-policies --user-name terraform-deployer

# 3. Add AdministratorAccess (or specific policies)
aws iam attach-user-policy \
  --user-name terraform-deployer \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 4. Retry deployment
```

---

## Runtime Issues

### Lambda Function Times Out

**Error**: Task timed out after 30.00 seconds

**Causes**:
- DynamoDB table doesn't exist
- Network connectivity issue
- Downstream API slow
- Infinite loop in code

**Solution**:
```bash
# 1. Check Lambda timeout setting
aws lambda get-function-configuration --function-name prod-url-shortener

# 2. Increase timeout in main.tf
# Change: timeout = 30 → timeout = 60

# 3. Check CloudWatch logs
aws logs tail /aws/lambda/prod-url-shortener --follow

# 4. Verify DynamoDB accessibility
aws dynamodb describe-table --table-name prod-urls

# 5. Test Lambda directly
aws lambda invoke \
  --function-name prod-url-shortener \
  --payload '{"test":"data"}' \
  response.json
cat response.json
```

### Lambda Permission Denied

**Error**: `User: arn:aws:iam::...:assumed-role/... is not authorized to perform: dynamodb:GetItem`

**Causes**:
- Lambda IAM role lacks DynamoDB permissions
- Wrong resource ARN in policy

**Solution**:
```bash
# 1. Check Lambda execution role
aws lambda get-function-configuration \
  --function-name prod-url-shortener \
  --query 'Role'

# 2. Check role policies
aws iam list-role-policies --role-name prod-lambda-role

# 3. Verify DynamoDB resource ARN
terraform output -raw dynamodb_table_arn

# 4. Update IAM policy in main.tf to include correct ARN
# 5. Re-apply Terraform
terraform apply
```

### Lambda Cold Start Issues

**Error**: First request takes 2+ seconds

**Solution**:
```bash
# 1. Increase memory allocation (reduces CPU, improves speed)
# In main.tf: memory_size = 256 → 512

# 2. Use Lambda Provisioned Concurrency
resource "aws_lambda_provisioned_concurrent_executions" "shortener" {
  function_name                     = aws_lambda_function.shortener.function_name
  provisioned_concurrent_executions = 100
}

# 3. Use Lambda layers for dependencies
# 4. Consider using Lambda SnapStart (Java only, not applicable here)
```

---

## API Gateway Issues

### API Returns 403 Forbidden

**Error**: `{"message":"Forbidden"}`

**Causes**:
- JWT token invalid or expired
- Cognito authorizer failing
- WAF blocking request

**Solution**:
```bash
# 1. Verify token validity
jwt decode ${TOKEN}

# 2. Check token expiration
TOKEN_PAYLOAD=$(echo ${TOKEN} | cut -d. -f2 | base64 -d)
echo ${TOKEN_PAYLOAD} | jq .

# 3. Check Cognito user pool
aws cognito-idp describe-user-pool \
  --user-pool-id $(terraform output -raw cognito_user_pool_id)

# 4. Check WAF rules blocking the request
aws wafv2 list-web-acls --scope REGIONAL --region eu-west-2
```

### API Returns 429 Too Many Requests

**Error**: `Too Many Requests`

**Causes**:
- Rate limit exceeded (WAF)
- Lambda concurrency limit reached

**Solution**:
```bash
# 1. Check WAF rate limit setting
terraform show terraform/waf/main.tf | grep limit

# 2. Increase WAF rate limit in waf/main.tf
# Change: limit = 100 → limit = 2000

# 3. Check Lambda concurrent execution limit
aws lambda get-concurrency --function-name prod-url-shortener

# 4. Increase Lambda concurrency in main.tf
# Change: reserved_concurrent_executions = 100 → 1000

# 5. Reapply changes
terraform apply -var-file=env/prod.tfvars
```

### API Gateway CORS Errors

**Error**: `Cross-Origin Request Blocked`

**Causes**:
- CORS not configured
- Wrong origins in allowed list
- Missing headers configuration

**Solution**:
```bash
# CORS is already configured in api_gateway/main.tf
# If issues persist, check:

# 1. Verify CORS in API Gateway
aws apigatewayv2 get-api --api-id $(terraform output -raw api_id)

# 2. Update CORS settings in api_gateway/main.tf
cors_configuration {
  allow_origins = ["https://yourdomain.com"]  # Add your domain
  allow_methods = ["GET", "POST", "OPTIONS"]
  allow_headers = ["Content-Type", "Authorization"]
}

# 3. Reapply Terraform
terraform apply
```

---

## Performance Issues

### High Latency (> 1 second)

**Symptoms**: API responses taking 1+ seconds

**Solution**:
```bash
# 1. Check Lambda duration metric
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=prod-url-shortener \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# 2. Check API Gateway latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Latency \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 3. Optimize Lambda
# - Increase memory (256MB → 512MB)
# - Reduce code complexity
# - Cache connections

# 4. Check DynamoDB performance
aws dynamodb describe-table --table-name prod-urls | jq .Table.BillingModeSummary
```

### High DynamoDB Costs

**Symptoms**: Unexpectedly high AWS bill

**Solution**:
```bash
# 1. Check consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=prod-urls \
  --period 3600 \
  --statistics Sum

# 2. Identify expensive operations
aws logs filter-log-events \
  --log-group-name /aws/dynamodb/prod-urls \
  --filter-pattern "ConsumedCapacity"

# 3. Optimize queries
# - Use consistent read only when necessary
# - Filter items in Lambda, not DynamoDB
# - Use proper key conditions

# 4. Consider provisioned capacity if predictable load
# (currently on-demand, which is good for variable load)
```

---

## Authentication Issues

### JWT Token Expired

**Error**: `UnauthorizedException: The incoming token has expired`

**Solution**:
```bash
# 1. Get new token
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $(terraform output -raw cognito_user_pool_client_id) \
  --auth-parameters USERNAME=testuser,PASSWORD=Password123! \
  --region eu-west-2 \
  --query 'AuthenticationResult.IdToken' \
  --output text)

# 2. Check token expiration
jwt decode ${TOKEN}

# 3. If expired, refresh using refresh token
aws cognito-idp initiate-auth \
  --auth-flow REFRESH_TOKEN_AUTH \
  --client-id ${CLIENT_ID} \
  --auth-parameters REFRESH_TOKEN=${REFRESH_TOKEN}
```

### Invalid JWT Signature

**Error**: `Unauthorized (JWT signature invalid)`

**Causes**:
- Token from wrong Cognito pool
- Token modified in transit
- Clock skew

**Solution**:
```bash
# 1. Verify token issuer
jwt decode ${TOKEN}
# Check: iss should be https://cognito-idp.{region}.amazonaws.com/{pool-id}

# 2. Verify Cognito pool ID
terraform output -raw cognito_user_pool_id

# 3. Check system clock
date
aws sts get-caller-identity

# 4. Verify JWT authorizer configuration
aws apigatewayv2 get-authorizer --api-id ${API_ID} --authorizer-id ${AUTH_ID}
```

### Cognito User Not Found

**Error**: `UserNotFound` (when creating user or authenticating)

**Solution**:
```bash
# 1. List existing users
aws cognito-idp list-users \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --region eu-west-2

# 2. Create test user
aws cognito-idp admin-create-user \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username testuser \
  --temporary-password TempPass123! \
  --region eu-west-2

# 3. Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username testuser \
  --password Password123! \
  --permanent \
  --region eu-west-2

# 4. Try authentication again
```

---

## Database Issues

### DynamoDB Table Not Found

**Error**: `ResourceNotFoundException`

**Causes**:
- Table doesn't exist
- Wrong table name
- Wrong region

**Solution**:
```bash
# 1. List all tables
aws dynamodb list-tables --region eu-west-2

# 2. Verify table exists
aws dynamodb describe-table --table-name prod-urls

# 3. Check Lambda environment variable
aws lambda get-function-configuration \
  --function-name prod-url-shortener \
  --query 'Environment.Variables'

# 4. If missing, redeploy
terraform apply -var-file=env/prod.tfvars

# 5. Verify TABLE_NAME env var matches
# Should be: prod-urls (matches terraform resource name)
```

### DynamoDB Item Not Found (Expected Item Exists)

**Error**: Empty response from GetCommand

**Causes**:
- Wrong partition key value
- Item expired (TTL)
- Item never created

**Solution**:
```bash
# 1. Verify item exists
aws dynamodb get-item \
  --table-name prod-urls \
  --key '{"code":{"S":"abc123"}}'

# 2. Scan all items
aws dynamodb scan --table-name prod-urls --max-items 10

# 3. Check TTL expiration
aws dynamodb scan \
  --table-name prod-urls \
  --filter-expression "expiresAt < :now" \
  --expression-attribute-values '{":now":{"N":"'$(date +%s)'"}}'

# 4. Check item format in DynamoDB vs code
```

### DynamoDB Conditional Check Failure

**Error**: `ConditionalCheckFailedException`

**Causes**:
- Item already exists
- Concurrent write conflict

**Solution**:
```bash
# 1. This is expected when custom code already exists
# The API should return 409 Conflict

# 2. Verify error handling in Lambda
# Check logs:
aws logs tail /aws/lambda/prod-url-shortener --follow

# 3. If seeing in unexpected place, check code logic
# Conditional expressions should only be on specific operations
```

---

## Monitoring & Debugging

### Enable CloudWatch Insights Logging

```bash
# Query Lambda errors
aws logs start-query \
  --log-group-name /aws/lambda/prod-url-shortener \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

### Monitor DynamoDB Metrics

```bash
# Watch consumed capacity in real-time
watch -n 5 'aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=prod-urls \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum | jq .Datapoints'
```

### Enable X-Ray Tracing

Already configured in Lambda (tracing_config enabled in main.tf)

```bash
# View traces
aws xray get-service-graph \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s)
```

---

## Common Errors

### "Invalid JSON in response body"

**Cause**: Lambda returning malformed JSON

**Fix**:
```javascript
// Ensure all responses are valid JSON
return {
  statusCode: 200,
  body: JSON.stringify({ key: "value" })  // Don't return raw object
};
```

### "Missing context object"

**Cause**: requestContext not provided

**Fix**: 
```javascript
// Always check context exists
const method = event.requestContext?.http?.method;
if (!method) {
  return { statusCode: 400, body: 'Invalid request' };
}
```

### "TypeError: Cannot read property 'Item' of undefined"

**Cause**: DynamoDB response not checked

**Fix**:
```javascript
const result = await ddb.send(new GetCommand(...));

// Check if result and item exist
if (!result?.Item) {
  return { statusCode: 404, body: 'Not found' };
}
```

---

## Getting Help

### Debug Command Cheatsheet

```bash
# Check system status
aws health describe-events --region eu-west-2

# View recent errors
aws logs tail /aws/lambda/prod-url-shortener --follow --filter-pattern ERROR

# Check API Gateway logs
aws logs tail /aws/apigateway/prod-url-shortener --follow

# Monitor in real-time
watch -n 1 'aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=prod-url-shortener \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum'
```

### Escalation Path

1. **Check logs**: CloudWatch Logs
2. **Check metrics**: CloudWatch Metrics / Dashboards
3. **Check configuration**: Terraform state / AWS Console
4. **Review code**: Check Lambda function
5. **Contact AWS Support**: If infrastructure issue

---

## Support Resources

- **AWS Lambda Documentation**: https://docs.aws.amazon.com/lambda/
- **Terraform Documentation**: https://registry.terraform.io/providers/hashicorp/aws/
- **AWS CLI Reference**: https://docs.aws.amazon.com/cli/
- **GitHub Issues**: [Link to repo issues]
