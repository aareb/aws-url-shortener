# AWS URL Shortener

A production-ready URL shortener built using:
- AWS Lambda (Node.js)
- API Gateway
- DynamoDB
- Terraform
- GitHub Actions (CI/CD)

```
End Users
    │
    ▼
API Gateway (Public REST)
    │
    ├─→ GET /{code}  →  Redirect Lambda
    │
    └─→ POST /shorten (JWT)  →  Shorten Lambda
            │
            └────────────────┬─────────────────┐
                             ▼                 ▼
                         DynamoDB          CloudWatch
                      URL Mappings      (Logs, Metrics)
                             ▲
                             │
                          AWS WAF
                    (Rate Limiting & Abuse
                         Protection)
```

## Architecture Overview

## Architecture Overview

This service implements a serverless URL shortener using:

- **Amazon API Gateway** – public HTTP interface
- **Amazon DynamoDB** – low‑latency key‑value storage
- **AWS WAF** – edge security and abuse prevention

### High‑level Flow

1. Client sends `GET /{shortCode}`
2. API Gateway routes the request
3. DynamoDB is queried for the original URL
4. API Gateway returns a `301` redirect

This design intentionally avoids compute (Lambda/EC2) to minimize
latency, operational overhead, and cost for a read‑heavy workload.

## Requirement Mapping

| Requirement | Implementation |
|------------|---------------|
| Public Endpoint | API Gateway |
| Authentication | JWT-based authorization |
| CI/CD | GitHub Actions + Terraform |
| Multiple Environments | dev/prod tfvars |
| Scaling | Lambda + DynamoDB |
| Monitoring | CloudWatch Logs (Alarms planned) |
| Malicious Traffic | WAF + rate limiting (to be added) |

## Features
- JWT-protected URL creation
- Public redirection endpoint
- Multi-environment support (dev/prod)
- Auto-scaling & monitoring
- Infrastructure as Code

## Design Decisions & Tradeoffs

### Why API Gateway → DynamoDB (No Lambda)

**Chosen:**
- API Gateway direct integration with DynamoDB

**Alternatives considered:**
- Lambda + DynamoDB
- ECS / EC2 based API

**Reasoning:**
- URL resolution is a simple key‑value lookup
- No transformation or business logic required
- Avoids cold starts and Lambda operational overhead
- Lower cost and lower latency for high‑volume reads

**Tradeoff:**
- Harder to introduce complex logic later
- Reduced flexibility vs compute‑based architecture

---

### Why DynamoDB

**Chosen:**
- DynamoDB (on‑demand capacity)

**Alternatives considered:**
- RDS / Aurora
- ElastiCache

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
terraform apply -var-file=env/dev.tfvars
