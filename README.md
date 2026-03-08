# Production-Grade ECS on EC2 with Terraform

Production-ready AWS ECS (EC2 launch type) infrastructure with zero-downtime deployments, secure secrets management, and cost-optimized capacity.

## Architecture Overview

![Architecture Diagram](./architecture.svg)

- **ECS Cluster**: EC2 launch type with Container Insights
- **Compute**: Auto Scaling Group with On-Demand baseline + Spot overflow
- **Load Balancing**: Application Load Balancer with health checks
- **Secrets**: AWS Systems Manager Parameter Store (no secrets in code/state)
- **Scaling**: Service auto-scaling (CPU) + Capacity provider (cluster)
- **Deployment**: Rolling updates with circuit breaker and automatic rollback

## Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.5.0
- Existing VPC with:
  - Private subnets (for ECS instances)
  - Public subnets (for ALB)
  - NAT Gateway or VPC endpoints (for outbound connectivity)
- SSM Parameter Store secrets (pre-created)

## Quick Start

### 1. Clone Repository

```bash
git clone <repository-url>
cd ecs-prod-container-terraform
```

### 2. Configure Variables

Edit `terraform.tfvars` and update with your actual values:

```hcl
vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"  # Your VPC ID
private_subnet_ids = ["subnet-xxx", "subnet-yyy"]  # Your private subnets
public_subnet_ids  = ["subnet-zzz", "subnet-aaa"]  # Your public subnets
```

### 3. Create SSM Parameters (if not exists)

```bash
aws ssm put-parameter \
  --name "/prod/app/db_password" \
  --value "your-secret-value" \
  --type "SecureString" \
  --region us-east-1

aws ssm put-parameter \
  --name "/prod/app/api_key" \
  --value "your-api-key" \
  --type "SecureString" \
  --region us-east-1
```

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 5. Verify Deployment

```bash
# Get ALB DNS name
terraform output alb_dns_name

# Test endpoint
curl http://<alb-dns-name>
```

## Architecture Decisions

### Zero-Downtime Deployments

- **Min Healthy**: 100% (old tasks stay running)
- **Max Percent**: 200% (new tasks start before old stop)
- **Deregistration Delay**: 30s (drain in-flight requests)
- **Circuit Breaker**: Enabled (auto-rollback on failure)

### Secrets Management

- Secrets stored in SSM Parameter Store (SecureString)
- Task execution role reads secrets at startup
- Secrets injected as environment variables (not in Terraform state)
- Least privilege IAM (only specific parameters accessible)

### Cost-Optimized Capacity

- **On-Demand Base**: 2 instances (guaranteed capacity)
- **Spot Overflow**: All instances above base (cost savings)
- **Spot Strategy**: capacity-optimized (minimize interruptions)
- **Capacity Provider**: Auto-scales cluster based on task demand

### Scaling Strategy

- **Service Scaling**: CPU-based (target 70%)
- **Cluster Scaling**: Capacity provider (target 100% utilization)
- **Multi-AZ**: Tasks spread across availability zones
- **Placement**: Spread by AZ, binpack by memory

## Assumptions

### Existing Infrastructure

- **VPC**: Existing VPC with CIDR block and DNS enabled
- **Subnets**: 
  - Private subnets (2+ AZs) for ECS instances
  - Public subnets (2+ AZs) for ALB
- **NAT Gateway**: Configured in public subnets for private subnet egress
- **Internet Gateway**: Attached to VPC for ALB ingress

### Networking

- Private subnets have route to NAT Gateway (0.0.0.0/0 → nat-xxx)
- Public subnets have route to Internet Gateway (0.0.0.0/0 → igw-xxx)
- Security groups allow:
  - ALB: Inbound 80/443 from internet
  - ECS: Inbound from ALB only
  - ECS: Outbound to internet (for image pulls, SSM, CloudWatch)

### Secrets

- SSM parameters pre-created in Parameter Store
- Parameters use SecureString type (KMS encrypted)
- Parameter names: `/prod/app/db_password`, `/prod/app/api_key`

### Permissions

- AWS credentials configured (AWS CLI, environment variables, or IAM role)
- Permissions to create: IAM roles, EC2 instances, ECS resources, ALB, ASG, CloudWatch

### Configuration

- All infrastructure values defined in `terraform.tfvars`
- Update VPC ID, subnet IDs, and other parameters before deployment
- No default values in `variables.tf` - all values must be provided

## Project Structure

```
.
├── modules/
│   ├── iam/                    # IAM roles and policies
│   ├── security-groups/        # Security groups
│   ├── alb/                    # Application Load Balancer
│   ├── asg/                    # Auto Scaling Group
│   ├── ecs-cluster/            # ECS Cluster and Capacity Provider
│   └── ecs-service/            # ECS Service and Task Definition
├── main.tf                     # Root module calling all modules
├── variables.tf                # Input variable declarations
├── terraform.tfvars            # Variable values (edit this)
├── outputs.tf                  # Output values
├── versions.tf                 # Terraform and provider versions
├── architecture.svg            # Architecture diagram
├── DESIGN.md                   # Architecture design document
├── ADDENDUM.md                 # Production stress test scenarios
└── README.md                   # This file
```

## Key Resources Created

- **ECS Cluster**: `prod-ecs-cluster`
- **ECS Service**: `nginx-service`
- **ALB**: `nginx-service-alb`
- **ASG**: `prod-ecs-cluster-asg`
- **Capacity Provider**: `prod-ecs-cluster-capacity-provider`
- **IAM Roles**: Instance, task execution, task roles
- **Security Groups**: ALB, ECS tasks
- **CloudWatch Log Group**: `/ecs/nginx-service`

## Monitoring & Operations

### Key Metrics

- `ECSServiceAverageCPUUtilization`: Service CPU usage
- `RunningTaskCount`: Number of running tasks
- `UnHealthyHostCount`: Unhealthy ALB targets
- `HTTPCode_Target_5XX_Count`: Application errors
- `TargetResponseTime`: Request latency

### Recommended Alarms

1. Service CPU > 85% for 5 minutes
2. Unhealthy targets > 0 for 2 minutes
3. 5xx errors > 10 in 5 minutes
4. Running tasks < desired for 5 minutes
5. ASG at max capacity for 10 minutes

### Operational Tasks

**Deploy New Version**:
```bash
# Update task definition (new image tag)
# Apply Terraform changes
terraform apply

# Monitor deployment
aws ecs describe-services \
  --cluster prod-ecs-cluster \
  --services nginx-service
```

**Scale Service**:
```bash
# Update desired_count in terraform.tfvars
desired_count = 8

# Apply changes
terraform apply
```

**Rotate Secrets**:
```bash
# Update SSM parameter
aws ssm put-parameter \
  --name "/prod/app/db_password" \
  --value "new-secret-value" \
  --type "SecureString" \
  --overwrite

# Force new deployment (picks up new secret)
aws ecs update-service \
  --cluster prod-ecs-cluster \
  --service nginx-service \
  --force-new-deployment
```

## Time Spent

**Total**: ~3 hours

- Infrastructure code: 90 minutes
- Documentation (DESIGN.md): 45 minutes
- Stress test scenarios (ADDENDUM.md): 45 minutes

## Shortcuts Taken

1. **VPC**: Assumed existing VPC/subnets (would create in production)
2. **TLS**: ALB listener uses HTTP (would use HTTPS with ACM certificate)
3. **Monitoring**: Basic CloudWatch (would add custom dashboards, SNS alerts)
4. **Networking**: Assumed NAT Gateway (would use VPC endpoints for cost savings)
5. **Container**: Used nginx:latest (would use specific version tag)
6. **IAM**: Simplified policies (would add more granular resource restrictions)
7. **Backup**: No automated backups (would add EBS snapshots, config backups)
8. **Configuration**: All values in terraform.tfvars (would use remote backend for team collaboration)

## What I Would Do Next (With More Time)

### Security Enhancements

- [ ] Enable HTTPS on ALB with ACM certificate
- [ ] Add WAF rules (rate limiting, SQL injection protection)
- [ ] Implement VPC Flow Logs for network monitoring
- [ ] Add AWS Config rules for compliance checking
- [ ] Enable GuardDuty for threat detection
- [ ] Implement secrets rotation (Lambda + Secrets Manager)

### Operational Improvements

- [ ] Create CloudWatch dashboards (service health, capacity, costs)
- [ ] Set up SNS topics and email/Slack alerts
- [ ] Implement automated runbooks (Systems Manager Automation)
- [ ] Add X-Ray tracing for distributed tracing
- [ ] Create Terraform modules for reusability
- [ ] Add CI/CD pipeline (GitHub Actions, CodePipeline)

### Cost Optimization

- [ ] Replace NAT Gateway with VPC endpoints (ECR, S3, CloudWatch)
- [ ] Implement Reserved Instances for On-Demand baseline
- [ ] Add cost allocation tags for chargeback
- [ ] Set up AWS Cost Anomaly Detection
- [ ] Implement auto-scaling schedule (scale down off-hours)

### Resilience & DR

- [ ] Multi-region deployment with Route 53 failover
- [ ] Automated backup and restore procedures
- [ ] Chaos engineering tests (Spot interruptions, AZ failures)
- [ ] Implement blue/green deployment strategy
- [ ] Add canary deployments (gradual rollout)

### Testing

- [ ] Integration tests (Terratest)
- [ ] Load testing (Locust, k6)
- [ ] Security scanning (Checkov, tfsec)
- [ ] Compliance validation (AWS Config, Prowler)

## AI/Tools Used

- **GitHub Copilot**: Terraform syntax, IAM policy structure
- **AWS Documentation**: ECS capacity provider configuration, ALB health checks
- **Terraform Registry**: Module examples, best practices

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: Ensure no production traffic before destroying resources.

## Support

For questions or issues:
1. Review DESIGN.md for architecture details
2. Review ADDENDUM.md for failure scenarios
3. Check AWS CloudWatch Logs for task/service errors
4. Verify IAM permissions and security group rules

## License

This is a take-home assessment submission. Not licensed for production use without review.
