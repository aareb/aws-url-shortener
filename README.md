# AWS URL Shortener

A production-ready URL shortener built using:
- AWS Lambda (Node.js)
- API Gateway
- DynamoDB
- Terraform
- GitHub Actions (CI/CD)

## Features
- JWT-protected URL creation
- Public redirection endpoint
- Multi-environment support (dev/prod)
- Auto-scaling & monitoring
- Infrastructure as Code

## Endpoints

POST /shorten  
Authorization: Bearer <JWT>

GET /{code}

## Deploy

```bash
cd terraform
terraform init
terraform apply -var-file=env/dev.tfvars