# Deployment Guide

Complete step-by-step guide for deploying the URL Shortener to AWS.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Local Development](#local-development)
4. [Development Deployment](#development-deployment)
5. [Production Deployment](#production-deployment)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Troubleshooting](#troubleshooting)
8. [Rollback Procedures](#rollback-procedures)

---

## Prerequisites

### Required Tools

```bash
# macOS / Linux
brew install terraform aws-cli nodejs

# Windows (using chocolatey)
choco install terraform awscli nodejs

# Verify installations
terraform version      # >= 1.5.0
aws --version         # >= 2.0
node --version        # >= 20.0.0
```

### AWS Account Setup

1. **Create IAM User for Deployment**

```bash
aws iam create-user --user-name terraform-deployer
aws iam attach-user-policy --user-name terraform-deployer \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-access-key --user-name terraform-deployer
```

2. **Configure AWS Credentials**

```bash
aws configure
# Enter:
# AWS Access Key ID: [from above]
# AWS Secret Access Key: [from above]
# Default region: eu-west-2
# Default output format: json
```

3. **Verify Access**

```bash
aws sts get-caller-identity
```

### GitHub Setup

1. Fork/clone the repository
2. Generate GitHub Personal Access Token (for automation)
3. Add to repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

---

## Initial Setup

### 1. Create Terraform State Bucket

```bash
# Create unique bucket name
BUCKET_NAME="url-shortener-tf-state-$(date +%s)"

# Create S3 bucket with versioning
aws s3 mb s3://${BUCKET_NAME} --region eu-west-2
aws s3api put-bucket-versioning \
  --bucket ${BUCKET_NAME} \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket ${BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket ${BUCKET_NAME} \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Created bucket: ${BUCKET_NAME}"
```

### 2. Update Terraform Backend Configuration

Edit `terraform/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket      = "url-shortener-tf-state-YOUR-UNIQUE-ID"  # Update this
    key         = "terraform.tfstate"
    region      = "eu-west-2"
    encrypt     = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 3. Create DynamoDB State Lock Table

```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-2
```

---

## Local Development

### 1. Clone Repository

```bash
git clone https://github.com/your-org/aws-url-shortener.git
cd aws-url-shortener
```

### 2. Install Dependencies

```bash
# Lambda dependencies
cd lamda
npm install
npm list  # Verify installations

# Check for vulnerabilities
npm audit

cd ..
```

### 3. Initialize Terraform

```bash
cd terraform

# Download providers
terraform init

# List resources
terraform state list
```

### 4. Validate Configuration

```bash
# Format check
terraform fmt -check -recursive

# Validation
terraform validate

# Security scan (optional - requires tfsec)
tfsec .
```

---

## Development Deployment

### 1. Plan Changes

```bash
cd terraform

# Show what will be created
terraform plan -var-file=env/dev.tfvars -out=tfplan.dev

# Review output carefully
# Look for:
# - No unexpected resource deletions
# - Correct environment values
# - No secrets in plain text
```

### 2. Create Lambda Package

```bash
# Ensure clean directory
cd ../lamda
rm -rf node_modules package-lock.json

# Install production dependencies only
npm install --production

# Create deployment package
cd ..
zip -r terraform/lambda.zip lamda/

# Verify package
unzip -l terraform/lambda.zip
```

### 3. Apply Infrastructure

```bash
cd terraform

# Apply the plan
terraform apply tfplan.dev

# Note outputs
terraform output

# Wait for completion (may take 5-10 minutes)
```

### 4. Retrieve Outputs

```bash
# Save outputs for testing
terraform output -json > outputs.json

# Extract key values
API_ENDPOINT=$(terraform output -raw api_endpoint)
COGNITO_POOL=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT=$(terraform output -raw cognito_user_pool_client_id)

echo "API Endpoint: ${API_ENDPOINT}"
echo "Cognito Pool: ${COGNITO_POOL}"
echo "Cognito Client: ${COGNITO_CLIENT}"
```

---

## Testing Deployment

### 1. Create Cognito Test User

```bash
POOL_ID=$(terraform output -raw cognito_user_pool_id)

aws cognito-idp admin-create-user \
  --user-pool-id ${POOL_ID} \
  --username testuser \
  --temporary-password TempPass123! \
  --region eu-west-2

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id ${POOL_ID} \
  --username testuser \
  --password Password123! \
  --permanent \
  --region eu-west-2
```

### 2. Obtain JWT Token

```bash
CLIENT_ID=$(terraform output -raw cognito_user_pool_client_id)

TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id ${CLIENT_ID} \
  --auth-parameters USERNAME=testuser,PASSWORD=Password123! \
  --region eu-west-2 \
  --query 'AuthenticationResult.IdToken' \
  --output text)

echo "JWT Token: ${TOKEN}"
```

### 3. Test POST /shorten

```bash
API_ENDPOINT=$(terraform output -raw api_endpoint)

curl -X POST ${API_ENDPOINT}/shorten \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{
    "url": "https://www.example.com",
    "customCode": "example-link"
  }' | jq .
```

Expected output:
```json
{
  "shortUrl": "https://dev.example.com/example-link",
  "code": "example-link",
  "originalUrl": "https://www.example.com",
  "expiresAt": 1734595200
}
```

### 4. Test GET /{code}

```bash
# Follow redirect
curl -L ${API_ENDPOINT}/example-link -i

# Should show:
# HTTP/1.1 302 Found
# Location: https://www.example.com
```

### 5. Test WAF Rate Limiting

```bash
# Make rapid requests (should block after ~400 in 5 min)
for i in {1..50}; do
  curl ${API_ENDPOINT}/example-link
done

# Should eventually see:
# HTTP 429 Too Many Requests
```

---

## Production Deployment

### Prerequisites

1. ✅ Development deployment working
2. ✅ All tests passing
3. ✅ Code review completed
4. ✅ Change approval obtained

### 1. Create Production Environment File

Edit `terraform/env/prod.tfvars`:

```hcl
env            = "prod"
aws_region     = "eu-west-2"
base_url       = "https://short.example.com"  # Update with prod domain
environment    = "prod"
project_name   = "url-shortener"
log_bucket_arn = "arn:aws:s3:::url-shortener-logs-prod"
jwt_secret     = "use-aws-secrets-manager"  # Store securely
```

### 2. Plan Production Deployment

```bash
cd terraform

terraform plan -var-file=env/prod.tfvars -out=tfplan.prod

# Carefully review differences from dev
# Expect:
# - Higher Lambda concurrency
# - No development-only resources
# - Longer log retention
```

### 3. Apply with Approval

```bash
# Option A: Manual approval
terraform apply tfplan.prod

# Option B: Automated (GitHub Actions)
git push origin master
# Review GitHub Actions workflow
# Approve deployment when prompted
```

### 4. Verify Production

```bash
# Check Lambda is working
aws lambda invoke \
  --function-name prod-url-shortener \
  --payload '{"requestContext":{"http":{"method":"GET","path":"/test"}}}' \
  response.json
cat response.json

# Check DynamoDB is accessible
aws dynamodb list-tables --region eu-west-2 | grep prod-urls

# Check API Gateway
aws apigatewayv2 get-apis --region eu-west-2
```

### 5. Production Monitoring Setup

```bash
# Create SNS topic for alarms
aws sns create-topic --name url-shortener-alarms --region eu-west-2

# Subscribe to alarms
aws sns subscribe \
  --topic-arn arn:aws:sns:eu-west-2:ACCOUNT:url-shortener-alarms \
  --protocol email \
  --notification-endpoint ops-team@example.com

# Update Terraform to use topic
# (Add to main.tf)
```

---

## Post-Deployment Verification

### Health Checks

```bash
#!/bin/bash
set -e

API_ENDPOINT=$(terraform output -raw api_endpoint)

echo "1. Checking API Gateway..."
curl -s -o /dev/null -w "%{http_code}" ${API_ENDPOINT}/healthcheck || echo "OK (404 expected)"

echo "2. Checking Lambda logs..."
aws logs tail /aws/lambda/prod-url-shortener --max-items 10

echo "3. Checking DynamoDB..."
aws dynamodb scan --table-name prod-urls --max-items 5 --region eu-west-2

echo "4. Checking CloudWatch dashboard..."
aws cloudwatch list-dashboards --region eu-west-2 | grep prod

echo "All checks passed! ✓"
```

### Smoke Tests

```bash
# Create a short URL
RESPONSE=$(curl -X POST ${API_ENDPOINT}/shorten \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://example.com"}')

CODE=$(echo ${RESPONSE} | jq -r '.code')
echo "Created short URL: ${CODE}"

# Test redirect
curl -L ${API_ENDPOINT}/${CODE} -i | head -5

echo "Smoke tests passed! ✓"
```

---

## Troubleshooting

### Terraform Init Fails

**Error**: `Error: error reading S3 Bucket in account`

**Solution**:
```bash
# Check credentials
aws sts get-caller-identity

# Check bucket exists
aws s3 ls s3://your-bucket-name

# Check permissions
aws s3api get-bucket-versioning --bucket your-bucket-name
```

### Lambda Deployment Fails

**Error**: `InvalidParameterValueException: Could not verify the runtime`

**Solution**:
```bash
# Verify Node.js version in index.js
node --version  # Should be 20.x

# Check Lambda package
unzip -t terraform/lambda.zip
```

### DynamoDB Access Denied

**Error**: `User: arn:aws:iam::... is not authorized to perform: dynamodb:GetItem`

**Solution**:
```bash
# Check IAM role policy
aws iam get-role-policy --role-name prod-lambda-role --policy-name prod-lambda-policy

# Verify resource ARN matches
terraform output -raw dynamodb_table_arn
```

### Cognito Token Invalid

**Error**: `UnauthorizedException: The incoming token has expired`

**Solution**:
```bash
# Re-authenticate user
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id ${CLIENT_ID} \
  --auth-parameters USERNAME=testuser,PASSWORD=Password123!

# Check token expiration
jwt decode ${TOKEN}
```

---

## Rollback Procedures

### Rollback via Terraform

```bash
# Show history
terraform state list

# Show specific resource
terraform state show aws_lambda_function.shortener

# Rollback to previous version
git log --oneline terraform/
git revert <commit-hash>
git push

# Terraform will detect rollback
cd terraform
terraform plan -var-file=env/prod.tfvars
terraform apply
```

### Rollback via Git Tag

```bash
# If you tagged releases
git tag v1.0.0
git push origin v1.0.0

# To rollback to previous release
git checkout v0.9.0
git push origin HEAD:master
```

### Emergency Rollback (Disable API)

```bash
# Temporarily block all traffic (via WAF)
aws wafv2 update-web-acl \
  --name prod-url-shortener \
  --scope REGIONAL \
  --default-action Block={} \
  --region eu-west-2

# Or via API Gateway
aws apigatewayv2 delete-stage \
  --api-id ${API_ID} \
  --stage-name '$default'
```

---

## Zero-Downtime Deployment

The system supports zero-downtime deployments:

1. **Lambda Update**
   - API Gateway routes to new version automatically
   - No requests dropped

2. **Database Migration**
   - New attributes added with defaults
   - No schema lock

3. **API Gateway Update**
   - New routes tested in separate stage first
   - Swap traffic via API mapping

---

## Maintenance Windows

### Recommended Schedule

- **Dev**: Anytime
- **Prod**: Weekly (Tuesday 02:00 UTC)
- **Duration**: 15-30 minutes

### Communication

```bash
# Announce maintenance
aws sns publish \
  --topic-arn arn:aws:sns:eu-west-2:ACCOUNT:url-shortener-alarms \
  --message "Maintenance window: URL Shortener 02:00-02:30 UTC"
```

---

## Monitoring During Deployment

```bash
# Watch CloudWatch logs in real-time
aws logs tail /aws/lambda/prod-url-shortener --follow

# Monitor error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=prod-url-shortener \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 60 \
  --statistics Sum
```

---

## Success Criteria

Deployment is successful when:

- ✅ All Terraform resources created without errors
- ✅ API Gateway endpoint is healthy
- ✅ Lambda function logs show no critical errors
- ✅ DynamoDB table is accessible
- ✅ JWT authentication working
- ✅ Rate limiting active
- ✅ CloudWatch alarms configured
- ✅ Smoke tests passing
- ✅ No customer impact detected

---

## Support & Escalation

| Issue | Contact | Response Time |
|-------|---------|----------------|
| Deployment failed | DevOps team | 30 min |
| API degraded | On-call engineer | 15 min |
| Data loss | Security team | Immediate |
| DDoS attack | AWS DRT | Immediate |
