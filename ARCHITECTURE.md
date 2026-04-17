# Architecture Decision Records (ADRs)

## ADR-001: Serverless Architecture with Lambda

**Status:** Accepted

### Context
The URL shortener needs to handle potentially high throughput with minimal operational overhead. We must choose between:
- Serverless (Lambda + API Gateway)
- Traditional compute (EC2/ECS)
- Managed Kubernetes (EKS)

### Decision
Implement using AWS Lambda + API Gateway for the URL shortening service.

### Rationale
1. **Cost-efficient**: Pay only for execution time (sub-second operations)
2. **Auto-scaling**: Automatically handles traffic spikes
3. **Minimal operational overhead**: No patching, no capacity planning
4. **Fast iteration**: Quick deployment via GitHub Actions
5. **Built-in monitoring**: CloudWatch integration out-of-box

### Consequences
- **Positive**
  - Lower infrastructure costs for typical usage
  - Automatic scaling without manual intervention
  - Rapid deployment cycles
  
- **Negative**
  - Cold start latency (< 100ms for Node.js)
  - Execution time limits (15 minutes)
  - Vendor lock-in to AWS

### Alternatives Considered
- **EC2 Auto Scaling**: Would require more operational overhead for scaling and patching
- **ECS Fargate**: Container management overhead without significant benefits for this use case
- **EKS**: Over-engineered for this simple service

---

## ADR-002: DynamoDB for Persistence Layer

**Status:** Accepted

### Context
The service needs a fast, scalable key-value store for URL mappings. Options:
- DynamoDB (AWS managed)
- RDS PostgreSQL/Aurora
- ElastiCache (in-memory)
- Document database (MongoDB, Firestore)

### Decision
Use DynamoDB as the primary data store.

### Rationale
1. **Query pattern**: Single key lookup (code → URL) is DynamoDB's strength
2. **Scaling**: On-demand pricing scales automatically with demand
3. **Performance**: Consistent millisecond latency regardless of data size
4. **No operational overhead**: Fully managed service
5. **Point-in-time recovery**: Built-in backup/restore

### Consequences
- **Positive**
  - Scales seamlessly from 0 to millions of requests
  - No database patching or maintenance
  - Built-in encryption and compliance features
  
- **Negative**
  - Higher cost than RDS at massive scale
  - Query language is less flexible than SQL
  - Eventual consistency (mitigated by using strongly consistent reads)

### Alternatives Considered
- **RDS Aurora**: Overkill for simple key-value lookups; higher operational overhead
- **ElastiCache**: Requires separate persistence layer; adds operational complexity
- **S3**: Too slow for individual item lookups

---

## ADR-003: JWT Authentication via Cognito

**Status:** Accepted

### Context
The service needs to authenticate users for the POST /shorten endpoint. Options:
- AWS Cognito (managed)
- Custom JWT implementation
- OAuth2 with third-party provider (Google, GitHub)
- API Keys

### Decision
Use AWS Cognito for user pool management and JWT token issuance.

### Rationale
1. **Fully managed**: No custom authentication code to maintain
2. **Standards-based**: JWT is industry standard
3. **Flexible**: Supports multiple flows (client credentials, authorization code, etc.)
4. **Integration**: Native API Gateway integration for JWT validation
5. **Compliance**: Built-in support for security standards (OIDC, SAML)

### Consequences
- **Positive**
  - No custom auth code means less security risk
  - Easy user management and multi-factor authentication
  - Audit trails for authentication events
  
- **Negative**
  - Additional AWS service to manage
  - Higher cost with many users
  - Learning curve for Cognito-specific features

### Alternatives Considered
- **Custom JWT**: Would require crypto implementations and secret management (security risk)
- **Third-party OAuth**: Adds latency and external dependency
- **API Keys**: Not suitable for user-based authorization

---

## ADR-004: Infrastructure as Code with Terraform

**Status:** Accepted

### Context
Infrastructure must be repeatable, version-controlled, and auditable. Options:
- Terraform (HashiCorp)
- CloudFormation (AWS-native)
- CDK (AWS)
- Pulumi (programmatic IaC)

### Decision
Use Terraform for all infrastructure provisioning.

### Rationale
1. **Provider-agnostic**: Could migrate to other cloud providers if needed
2. **Version control**: Infrastructure tracked in git with full history
3. **Team collaboration**: Code review process for infrastructure changes
4. **Modularity**: Reusable modules for common patterns
5. **Mature ecosystem**: Large community and many examples

### Consequences
- **Positive**
  - Infrastructure changes go through PR review process
  - Rollback capability via git history
  - Consistent environments (dev, prod)
  
- **Negative**
  - State management adds complexity
  - Terraform learning curve
  - Potential for state drift if manually modified

### Alternatives Considered
- **CloudFormation**: AWS-specific; less flexible syntax (YAML)
- **CDK**: Good for complex logic but less readable for configuration
- **Manual provisioning**: No version control, error-prone

---

## ADR-005: GitHub Actions for CI/CD

**Status:** Accepted

### Context
Need automated build, test, and deployment pipeline. Options:
- GitHub Actions (integrated with GitHub)
- AWS CodePipeline
- CircleCI
- Jenkins

### Decision
Use GitHub Actions for CI/CD pipeline.

### Rationale
1. **Integration**: Native GitHub integration (no external tool)
2. **Cost**: Free for public repositories; generous limits for private repos
3. **Ease of use**: YAML-based configuration, easy to understand
4. **Features**: Secrets management, workflows, environments
5. **Community**: Large community with pre-built actions

### Consequences
- **Positive**
  - Single platform for code and CI/CD
  - Easy to set up and maintain
  - Good logging and debugging
  
- **Negative**
  - Lock-in to GitHub
  - Limited customization vs. self-hosted runners

### Alternatives Considered
- **AWS CodePipeline**: More AWS integration but higher cost and complexity
- **Jenkins**: Requires self-hosting and maintenance

---

## ADR-006: WAF for DDoS and Attack Protection

**Status:** Accepted

### Context
The public API is vulnerable to DDoS, rate-based attacks, and injection attacks. Options:
- AWS WAF (managed)
- AWS Shield
- CloudFlare
- Custom rate limiting in Lambda

### Decision
Use AWS WAF with rate limiting and AWS managed rule sets.

### Rationale
1. **Layer 7 protection**: Understands HTTP, can block malicious patterns
2. **Rate limiting**: Prevent both accidental and intentional abuse
3. **Managed rules**: AWS constantly updates OWASP Top 10 protections
4. **Granular control**: Custom rules for business logic
5. **Logging**: Full visibility into blocked requests

### Consequences
- **Positive**
  - Protection against known attack patterns
  - Reduced false positives via AWS managed rules
  - Minimal performance impact
  
- **Negative**
  - Additional cost per rule
  - Configuration required (not fully transparent)

### Alternatives Considered
- **Shield Standard**: Only basic DDoS protection; inadequate for API
- **CloudFlare**: Adds latency; third-party dependency
- **Custom Lambda logic**: Would add latency; difficult to maintain

---

## ADR-007: Environment Separation (Dev/Prod)

**Status:** Accepted

### Context
Different environments need different configurations and isolation. Options:
- Single account with multiple environments
- Separate AWS accounts per environment
- Separate regions

### Decision
Use separate Terraform tfvars files with same AWS account but isolated resources.

### Rationale
1. **Cost-effective**: Single account simplifies billing
2. **Simplicity**: No cross-account role assumptions
3. **Naming conventions**: Resources prefixed with environment (dev-, prod-)
4. **Separate state files**: Different Terraform backends per environment
5. **Easy testing**: Dev environment for QA without production impact

### Consequences
- **Positive**
  - Quick to set up and test changes
  - Shared resources (e.g., WAF) can be optimized
  
- **Negative**
  - Single compromised account affects all environments
  - More conservative: true separation would use separate accounts

### Alternatives Considered
- **Separate AWS accounts**: Better isolation but higher cost and complexity
- **Single production environment**: No safe testing ground

---

## ADR-008: CloudWatch for Monitoring

**Status:** Accepted

### Context
Need comprehensive observability into system behavior. Options:
- CloudWatch (AWS-native)
- Datadog
- New Relic
- Prometheus + Grafana

### Decision
Use AWS CloudWatch for logs, metrics, and alarms.

### Rationale
1. **Integration**: Native AWS service integration
2. **Cost**: Included in AWS usage; no separate licensing
3. **Simplicity**: Easy to configure from Terraform
4. **Features**: Logs, metrics, alarms, dashboards in one service
5. **Compliance**: Audit logs automatically tracked

### Consequences
- **Positive**
  - Single pane of glass for AWS resources
  - Automatic integration with Lambda, DynamoDB, API Gateway
  
- **Negative**
  - Learning curve for CloudWatch insights
  - Less powerful than specialized monitoring tools

---

## Data Model Design

### Primary Key Structure

```
Partition Key: code (string)
  - Unique short code (e.g., "abc1d2e3")
  - Enables efficient retrieval of original URL
  - Auto-generated as 8-char hex or user-specified
```

### Global Secondary Index (GSI)

```
GSI: userId-createdAt-index
  - Partition Key: userId
  - Sort Key: createdAt
  - Allows querying user's URLs in chronological order
  - Useful for: "Show me all my short URLs"
```

### TTL Configuration

```
Attribute: expiresAt (number, unix timestamp in seconds)
- Enabled: true
- DynamoDB automatically deletes expired items
- Default: 1 year from creation
```

### Item Structure

```json
{
  "code": "abc1d2e3",              // PK
  "userId": "user-123",             // GSI PK
  "originalUrl": "https://...",     // The target URL
  "createdAt": 1703001600000,       // GSI SK (milliseconds)
  "expiresAt": 1734595200,          // TTL (seconds)
  "status": "active",               // active | archived | deleted
  "clickCount": 0,                  // Analytics
  "lastAccessedAt": null,           // Analytics
  "tags": []                        // User metadata
}
```

---

## Security Model

### Authentication Flow

```
Client
  ↓
Cognito Authorize Endpoint
  ↓
JWT Token (contains sub, iss, aud, exp)
  ↓
API Gateway JWT Authorizer
  ↓
Lambda Handler (extracts userId from claims)
  ↓
DynamoDB operation
```

### Authorization

- **GET /{code}**: No authentication required (public endpoint)
- **POST /shorten**: JWT required; user ID extracted from token claims

### Network Security

```
Internet
  ↓
AWS WAF (block malicious traffic)
  ↓
API Gateway (HTTPS only, rate limiting)
  ↓
Lambda (VPC optional; currently internet-accessible)
  ↓
DynamoDB (encrypted at rest, access logs)
```

---

## Scaling Considerations

### Horizontal Scaling

- **API Gateway**: Automatically scales across regions
- **Lambda**: Auto-scales with concurrency limits
- **DynamoDB**: On-demand billing scales automatically

### Vertical Scaling

- **Lambda memory**: Can increase from 128MB to 10GB
- **DynamoDB throughput**: Adjustable, on-demand removes limits

### Caching Opportunities

- **CloudFront**: Could cache redirect responses (add later)
- **ElastiCache**: Not needed for simple key-value lookup
- **Lambda@Edge**: Could validate URLs at edge (future optimization)

---

## Disaster Recovery

### Backup Strategy

- **DynamoDB PITR**: Point-in-time recovery enabled
- **Cross-region replication**: Could be added for critical workloads

### Disaster Scenarios

| Scenario | RTO | RPO | Mitigation |
|----------|-----|-----|-----------|
| Accidental data deletion | 1 hour | 15 minutes | DynamoDB PITR |
| Lambda code corruption | 5 minutes | Immediate | Git history, code review |
| Region failure | 1 hour | 0 | Multi-region setup (future) |
| Cognito compromise | 30 minutes | 0 | Password reset, token revocation |

---

## Future Enhancements

1. **Multi-region**: Deploy to multiple regions for global latency reduction
2. **Custom domains**: Allow users to use their own domain
3. **Analytics dashboard**: Show click metrics, popular links
4. **Link expiration**: User-configurable TTL
5. **QR codes**: Generate QR codes for short URLs
6. **Batch operations**: Create/delete multiple URLs at once
7. **Webhook notifications**: Notify when URL accessed
8. **Link preview**: Generate thumbnails of linked pages
