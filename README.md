# AWS URL Shortener

A production-ready URL shortener built using:
- AWS Lambda (Node.js)
- API Gateway
- DynamoDB
- Terraform
- GitHub Actions (CI/CD)

## Architecture Overview

The URL shortener is implemented using a serverless architecture on AWS:

- **API Gateway** – Public REST endpoints
- **AWS Lambda (Node.js)** – Business logic
- **DynamoDB** – Persistent storage for URL mappings
- **AWS WAF** – Protection against abusive and malicious traffic
- **CloudWatch** – Logging, monitoring, and alarms
- **Terraform** – Infrastructure as Code
- **GitHub Actions** – CI/CD pipeline
``
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

## Security Considerations

- JWT authentication protects URL creation endpoints
- Public redirection endpoint is rate-limited
- AWS WAF mitigates abusive and malicious traffic
- Least-privilege IAM policies applied to Lambda

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

## Set Environment Variables (Quick testing)

$env:AWS_ACCESS_KEY_ID = "your-access-key-id"
$env:AWS_SECRET_ACCESS_KEY = "your-secret-access-key"  
$env:AWS_DEFAULT_REGION = "us-east-1"  # or your preferred region

## Deploy

``` bash
cd terraform
terraform init
terraform apply -var-file=env/dev.tfvars