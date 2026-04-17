# AWS URL Shortener

A production-ready, serverless URL shortener built on AWS with Terraform infrastructure-as-code, GitHub Actions CI/CD, and comprehensive monitoring.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        End Users                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
            ┌──────────────────────────────────┐
            │  AWS WAF (Rate Limiting & DDoS)  │
            └──────────────────────┬───────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
          ┌─────────▼─────────┐      ┌───────────▼────────┐
          │  GET /{code}      │      │  POST /shorten     │
          │  (Public)         │      │  (JWT Protected)   │
          └─────────┬─────────┘      └───────────┬────────┘
                    │                             │
                    │ API Gateway                 │ Lambda
                    │                             │ Authorizer
                    │                             │ (Cognito JWT)
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
          ┌─────────▼──────────┐     ┌──────────▼──────────┐
          │      DynamoDB      │     │ CloudWatch Logs     │
          │  URL Mappings      │     │ & Monitoring        │
          │  (TTL Enabled)     │     │                     │
          └────────────────────┘     └─────────────────────┘

```

## Key Features

**Production-Grade Security**
- JWT-based authentication via AWS Cognito
- AWS WAF with rate limiting, SQL injection, XSS protection
- SSRF prevention with internal IP blocking
- HTTPS only communication

**Scalability**
- Serverless architecture (AWS Lambda + DynamoDB)
- Auto-scaling Lambda concurrency
- DynamoDB on-demand billing
- Horizontal scaling with no operational overhead

**High Availability**
- Multi-AZ DynamoDB
- Point-in-time recovery enabled
- CloudWatch alarms and dashboards
- Structured logging for debugging

**Infrastructure as Code**
- 100% Terraform-managed infrastructure
- Multi-environment support (dev/prod)
- Modular architecture (API Gateway, WAF, Cognito)
- Version-controlled configuration

**CI/CD Pipeline**
- GitHub Actions automated deployment
- Terraform plan review before apply
- Lambda package validation and audit
- Environment-based deployment

**Monitoring & Observability**
- CloudWatch dashboards
- Custom metric alarms
- Structured JSON logging
- X-Ray tracing support

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| **Compute** | AWS Lambda (Node.js 20) |
| **API** | API Gateway v2 (HTTP) |
| **Database** | DynamoDB (on-demand) |
| **Authentication** | AWS Cognito |
| **Security** | AWS WAF |
| **IaC** | Terraform |
| **CI/CD** | GitHub Actions |
| **Monitoring** | CloudWatch |

---

## Project Structure

```
aws-url-shortener/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD pipeline
├── lamda/                      # Lambda function code
│   ├── index.js               # Main handler
│   └── package.json           # Dependencies
├── terraform/
│   ├── main.tf                # Core resources (Lambda, DynamoDB, IAM)
│   ├── cognito.tf             # Cognito user pool & client
│   ├── monitoring.tf          # CloudWatch alarms & dashboards
│   ├── secrets.tf             # SSM Parameter Store configs
│   ├── backend.tf             # S3 state backend config
│   ├── variables.tf           # Variable definitions
│   ├── outputs.tf             # Output values
│   ├── api_gateway/           # API Gateway module
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── waf/                   # WAF module
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── env/
│       ├── dev.tfvars         # Dev environment vars
│       └── prod.tfvars        # Prod environment vars
├── API.md                     # API documentation
└── README.md                  # This file
```

---

## Getting Started

### Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.5.0
- Node.js >= 20.0.0
- AWS CLI configured
- GitHub account with repository access

### Local Development

#### 1. Clone Repository
```bash
git clone https://github.com/your-org/aws-url-shortener.git
cd aws-url-shortener
```

#### 2. Install Dependencies
```bash
cd lamda
npm install
cd ..
```

#### 3. Create S3 Backend (One-time setup)
```bash
aws s3 mb s3://url-shortener-tf-state-$(date +%s) \
  --region eu-west-2
# Update backend.tf with your bucket name
```

#### 4. Initialize Terraform
```bash
cd terraform
terraform init
```

#### 5. Plan Infrastructure
```bash
terraform plan -var-file=env/dev.tfvars
```

#### 6. Deploy
```bash
terraform apply -var-file=env/dev.tfvars
```

---

## Deployment

### Automated (GitHub Actions)

The repository includes a GitHub Actions workflow that:

1. **Lint & Validate** - Format checks and Terraform validation
2. **Build** - Package Lambda function and dependencies
3. **Plan** - Generate Terraform execution plan
4. **Deploy** - Apply infrastructure changes (on master push)

#### Setup GitHub Secrets

Add these secrets to your GitHub repository settings:

```
AWS_ACCESS_KEY_ID        - AWS IAM user access key
AWS_SECRET_ACCESS_KEY    - AWS IAM user secret key
```

#### Deploy Process

```bash
git push origin master
# GitHub Actions automatically:
# 1. Validates code
# 2. Builds Lambda package
# 3. Plans Terraform changes
# 4. Applies changes to dev environment
```

### Manual Deployment

```bash
cd terraform

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Initialize (if first time)
terraform init

# Plan changes
terraform plan -var-file=env/dev.tfvars -out=tfplan

# Review plan, then apply
terraform apply tfplan
```

---

## Configuration

### Environment Variables

Edit `terraform/env/{dev,prod}.tfvars`:

```hcl
env            = "dev"                                    # Environment name
aws_region     = "eu-west-2"                            # AWS region
base_url       = "https://dev.example.com"              # Short URL base
environment    = "dev"                                   # Environment tag
project_name   = "url-shortener"                         # Project name
log_bucket_arn = "arn:aws:s3:::url-shortener-logs-dev"  # S3 for WAF logs
jwt_secret     = "your-jwt-secret-here"                 # JWT secret
```

### Cognito Configuration

Edit `terraform/cognito.tf` to customize:

- Password policy
- User pool settings
- OAuth flows
- Callback URLs

### WAF Rules

Edit `terraform/waf/main.tf` to adjust:

- Rate limit threshold (default: 2000 req/5min per IP)
- Geo-blocking countries
- Custom rule sets

---

## API Usage

See [API.md](./API.md) for comprehensive API documentation.

### Create Short URL
```bash
curl -X POST https://api.example.com/shorten \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {jwt_token}" \
  -d '{
    "url": "https://example.com/very/long/url",
    "customCode": "my-link"
  }'
```

### Redirect
```bash
curl -L https://short.example.com/my-link
# Returns: 302 redirect to original URL
```

---

## Monitoring

### CloudWatch Dashboard

Access the automatically created dashboard:
```bash
aws cloudwatch list-dashboards --region eu-west-2
```

Monitor:
- Lambda invocations, errors, duration
- API Gateway latency and errors
- DynamoDB consumed capacity
- WAF blocked requests

### Alarms

The following alarms are automatically created:

| Alarm | Threshold | Action |
|-------|-----------|--------|
| Lambda Errors | > 5 errors/5min | Alert |
| API 5xx Errors | > 5 errors/5min | Alert |
| API Latency High | > 1s average | Alert |
| DynamoDB Errors | > 10 errors/5min | Alert |
| Lambda Throttles | > 0 | Alert |

### Logs

View Lambda execution logs:
```bash
aws logs tail /aws/lambda/dev-url-shortener --follow
```

---

## Security Best Practices

### 1. Secrets Management
- JWT secret stored in AWS Secrets Manager
- Never commit secrets to version control
- Rotate secrets regularly

### 2. Network Security
- WAF blocks malicious traffic
- Rate limiting prevents abuse
- SSRF protection with IP validation

### 3. Authentication
- JWT tokens from Cognito
- Bearer token validation on protected endpoints
- User context extracted and audited

### 4. Data Protection
- HTTPS only (TLS 1.2+)
- DynamoDB encryption at rest
- Point-in-time recovery enabled
- Access logs stored in S3

### 5. Principle of Least Privilege
- Lambda IAM role limited to required actions
- Cognito scopes restricted
- WAF rules block suspicious patterns

---

## Troubleshooting

### Lambda Execution Error

Check logs:
```bash
aws logs tail /aws/lambda/dev-url-shortener --follow
```

Common issues:
- **DynamoDB table not found** - Check TABLE_NAME env var
- **Permission denied** - Verify IAM role policy
- **Timeout** - Increase Lambda timeout in main.tf

### Terraform Apply Fails

```bash
# Check state
terraform state list
terraform state show aws_dynamodb_table.urls

# Refresh state
terraform refresh

# Check for resource locks
aws dynamodb scan --table-name {state-table}
```

### Cognito JWT Invalid

- Verify token issuer matches Cognito pool
- Check audience claim matches client ID
- Ensure token not expired

---

## Performance Tuning

### Lambda
- Memory: 256MB (adjust in main.tf if needed)
- Timeout: 30 seconds (for slow downstream APIs)
- Concurrent executions: 1000 (prod), 100 (dev)

### DynamoDB
- Billing mode: On-demand (auto-scales)
- TTL: Enabled for automatic cleanup
- GSI: For querying by userId

### API Gateway
- HTTP/2 protocol
- Throttling: 2000 req/s, 5000 burst
- Caching: None (to show latest data)

---

## Cost Estimation (Monthly, US-East-1)

| Service | Estimate | Notes |
|---------|----------|-------|
| **Lambda** | $0.20 | 1M requests @ 256MB |
| **DynamoDB** | $1.25 | 1M on-demand units |
| **API Gateway** | $0.35 | 1M requests |
| **Cognito** | $0.50 | 50K active users |
| **WAF** | $5.00 | Fixed cost + rules |
| **CloudWatch** | $0.50 | Logs + alarms |
| **Total** | **~$7.80** | Highly scalable |

---

## Contributing

1. Create a feature branch
2. Make changes (following code style)
3. Run tests and validation
4. Submit pull request
5. GitHub Actions will validate before merge

---

## Deployment Runbook

### Production Deployment

1. **Tag Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **Review Plan**
   ```bash
   # GitHub Actions will create a plan
   # Review in PR before merging
   ```

3. **Merge to Master**
   ```bash
   # GitHub Actions automatically applies changes
   ```

4. **Verify Deployment**
   ```bash
   aws apigatewayv2 get-apis --region eu-west-2
   curl https://short.example.com/test
   ```

### Rollback

```bash
# Revert to previous commit
git revert <commit-hash>
git push origin master

# GitHub Actions will deploy previous version
```

---

## SLOs & Monitoring

### Service Level Objectives

| Metric | Target | Alert |
|--------|--------|-------|
| Availability | 99.9% | < 99% |
| P99 Latency | < 500ms | > 1000ms |
| Error Rate | < 0.1% | > 1% |
| Throughput | 10k req/s | Throttled |

---

## License (for demo purpose)

MIT License - See LICENSE file

## Support (assumption support for demo)

- Email: support@example.com 
- Issues: GitHub Issues
- Slack: #url-shortener channel


**Reasoning:**
- Predictable single‑key access pattern
- Horizontal scalability without operational work
- Sub‑millisecond latency at global scale

**Tradeoff:**
- No relational querying
- Schema evolution requires forethought

---

### Why No Caching (Yet)

Caching (CloudFront / ElastiCache) was intentionally omitted:

- Short URLs often have skewed access patterns
- DynamoDB handles read scale efficiently
- Simplicity preferred for initial version

**Future upgrade path:**
- CloudFront with origin = API Gateway
- TTL‑based caching for hot links


## Security Considerations

- JWT authentication protects URL creation endpoints
- Public redirection endpoint is rate-limited
- AWS WAF mitigates abusive and malicious traffic
- Least-privilege IAM policies applied to Lambda

## Security & Traffic Protection

- URL creation endpoint is protected using JWT authentication.
- Public redirection endpoint is rate-limited using AWS WAF to prevent abuse.
- CloudWatch alarms monitor Lambda errors and API Gateway 5XX responses.
- IAM roles follow least-privilege principles.

## Endpoints

POST /shorten  
Authorization: Bearer <JWT>

GET /{code}

## Observability

- Lambda logs captured in CloudWatch with retention policies
- CloudWatch Alarms configured for:
  - Lambda execution errors
  - API Gateway 5XX errors
- WAF metrics enabled for traffic analysis
``


## Secrets Management

Sensitive values are **not stored in the repository** and are injected securely using **GitHub Secrets**.

### GitHub Secrets Used

The following secrets are configured at the repository level:

- `AWS_ACCESS_KEY_ID` – AWS access key for Terraform deployments
- `AWS_SECRET_ACCESS_KEY` – AWS secret key
- `AWS_REGION` – Target AWS region

These secrets are referenced directly in the GitHub Actions workflow and made available as environment variables during CI/CD execution.
``


## Deploy

``` bash
cd terraform
terraform init
terraform validate
terraform plan -var-file=env/dev.tfvars
terraform apply -var-file=env/dev.tfvars
