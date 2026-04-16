# AWS URL Shortener

A production-ready URL shortener built using:
- AWS Lambda (Node.js)
- API Gateway
- DynamoDB
- Terraform
- GitHub Actions (CI/CD)

 ┌──────────────┐
                        │   End Users  │
                        └──────┬───────┘
                               │
                               ▼
                     ┌──────────────────┐
                     │   API Gateway    │
                     │  (Public REST)   │
                     └──────┬─────┬─────┘
                            │     │
           GET /{code} (public)    │   POST /shorten (JWT)
                            │     │
                            ▼     ▼
                   ┌────────────┐  ┌────────────┐
                   │ Redirect   │  │  Shorten   │
                   │  Lambda    │  │  Lambda    │
                   │ (Node.js)  │  │ (Node.js)  │
                   └─────┬──────┘  └─────┬──────┘
                         │               │
                         └───────┬───────┘
                                 ▼
                         ┌────────────────┐
                         │   DynamoDB     │
                         │ URL Mappings  │
                         └────────────────┘

        ┌───────────────────────────────────────────┐
        │ AWS WAF (Rate Limiting, Abuse Protection) │
        └───────────────────────────────────────────┘

        ┌───────────────────────────────────────────┐
        │ CloudWatch (Logs, Metrics, Alarms)         │
        └───────────────────────────────────────────┘

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
