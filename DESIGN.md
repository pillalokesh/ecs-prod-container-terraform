# Production Design Document

## A) Zero-Downtime Deployments

### Deployment Configuration
- **Minimum Healthy Percent**: 100% - Ensures existing tasks remain running during deployment
- **Maximum Percent**: 200% - Allows new tasks to start before old tasks are terminated
- **Deployment Flow**:
  1. ECS starts new tasks (with updated task definition)
  2. New tasks pass container health checks
  3. New tasks register with ALB target group
  4. ALB health checks pass (2 consecutive successes, 30s interval)
  5. ALB marks new targets as healthy and starts routing traffic
  6. Old tasks are deregistered from ALB
  7. Deregistration delay (30s) allows in-flight requests to complete
  8. Old tasks are stopped after draining

### ALB Health Check Configuration
- **Path**: `/`
- **Healthy Threshold**: 2 consecutive successes
- **Unhealthy Threshold**: 3 consecutive failures
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Deregistration Delay**: 30 seconds

### Circuit Breaker
- Enabled with automatic rollback
- If new tasks fail health checks repeatedly, deployment stops and rolls back to previous version
- Prevents bad deployments from taking down the entire service

---

## B) Secrets Management

### Flow: SSM Parameter Store → Container
1. **Storage**: Secrets stored in AWS Systems Manager Parameter Store (SecureString type)
2. **Reference**: Task definition references secrets by SSM parameter name (not value)
3. **Retrieval**: Task execution role has IAM permission to read specific SSM parameters
4. **Injection**: ECS agent fetches secrets at task startup and injects as environment variables
5. **Runtime**: Container receives secrets as environment variables (never in code/state)

### Why No Secrets in Terraform State
- Task definition uses `secrets` block (not `environment` block)
- `secrets` block stores only the SSM parameter ARN/name, not the actual secret value
- Terraform state contains parameter references, not secret values
- Actual secret values never leave AWS Systems Manager

### IAM Roles
- **Task Execution Role**: Reads SSM parameters during task startup (pulls secrets)
  - Permission: `ssm:GetParameters` on specific parameter ARNs only
- **Task Role**: What the running container can access (application permissions)
  - Least privilege: Only permissions needed by the application
- **Instance Role**: Allows EC2 instances to join ECS cluster
  - Permission: `AmazonEC2ContainerServiceforEC2Role` managed policy

### Secret Leakage Prevention
- Secrets not in: terraform.tfvars, .tf files, state files, logs (CloudWatch logs configured to not log env vars)
- Secrets only accessible to task execution role during startup
- No secrets in container image or user data

---

## C) Spot Instance Strategy

### Configuration
- **On-Demand Base**: 2 instances (always On-Demand)
- **Above Base**: 100% Spot (all instances above base are Spot)
- **Spot Allocation**: `capacity-optimized` strategy (AWS selects least likely to be interrupted pools)

### Interruption Behavior
1. **Spot Interruption Notice**: AWS sends 2-minute warning
2. **ECS Draining**: ECS agent sets instance to DRAINING state
3. **Task Rescheduling**: Tasks on interrupted instance are rescheduled to other instances
4. **Capacity Provider**: Detects capacity shortage and scales ASG
5. **New Instances**: ASG launches new instances (On-Demand if below base, Spot if above)
6. **No Downtime**: On-Demand baseline ensures minimum capacity always available

### Why Users Stay Online
- On-Demand baseline (2 instances) provides guaranteed capacity
- Multi-AZ deployment spreads tasks across availability zones
- Spot interruptions affect only a subset of instances
- Capacity provider auto-scales to replace interrupted capacity
- ALB continues routing to healthy targets
- Minimum healthy percent (100%) ensures sufficient running tasks

---

## D) Scaling Strategy

### Service-Level Scaling (Task Count)
- **Trigger**: ECS Service Average CPU > 70%
- **Action**: Application Auto Scaling increases desired task count
- **Result**: More tasks requested from ECS cluster

### Cluster-Level Scaling (Instance Count)
- **Trigger**: Capacity provider detects insufficient cluster capacity (PENDING tasks)
- **Metric**: Target capacity = 100% (cluster should have capacity for all tasks)
- **Action**: Capacity provider scales ASG to add instances
- **Result**: New EC2 instances join cluster, PENDING tasks become RUNNING

### Pending Tasks Handling
1. Service scales up (e.g., CPU spike) → desired count increases
2. Tasks enter PENDING state (insufficient cluster capacity)
3. Capacity provider detects: `(reserved capacity / total capacity) < target (100%)`
4. Capacity provider triggers ASG scale-out
5. ASG launches new instances (respecting On-Demand base + Spot overflow)
6. New instances join ECS cluster
7. PENDING tasks are placed on new instances → RUNNING state

### No Deadlock Because
- Capacity provider managed scaling is enabled
- Target capacity (100%) ensures cluster always has room for desired tasks
- ASG can scale up to max_size (10 instances)
- Minimum scaling step size (1) ensures gradual scaling
- Maximum scaling step size (10) allows rapid scale-out if needed

---

## E) Operations & Monitoring

### Top 5 Monitors/Alerts

1. **ECS Service CPU Utilization**
   - Metric: `ECSServiceAverageCPUUtilization`
   - Threshold: > 85% for 5 minutes
   - Action: Alert (scaling should handle, but investigate if sustained)

2. **ALB Target Health**
   - Metric: `UnHealthyHostCount`
   - Threshold: > 0 for 2 minutes
   - Action: Page on-call (indicates task failures)

3. **ALB 5xx Errors**
   - Metric: `HTTPCode_Target_5XX_Count`
   - Threshold: > 10 in 5 minutes
   - Action: Page on-call (application errors)

4. **ECS Service Running Task Count**
   - Metric: `RunningTaskCount`
   - Threshold: < desired_count for 5 minutes
   - Action: Page on-call (tasks failing to start/stay running)

5. **Capacity Provider Capacity**
   - Metric: Custom CloudWatch metric from ASG
   - Threshold: ASG at max capacity for 10 minutes
   - Action: Alert (need to increase max_size or optimize)

### What Pages at 3am
- **Service down**: 0 healthy targets in ALB target group
- **Deployment failure**: Circuit breaker triggered rollback
- **Sustained 5xx errors**: > 50 errors in 5 minutes
- **Task start failures**: Tasks repeatedly failing to start (IAM/secrets/image issues)
- **Capacity exhausted**: ASG at max, tasks PENDING for > 10 minutes

### Operational Runbooks
- **Spot Interruption Spike**: Verify On-Demand baseline is healthy, check capacity provider scaling
- **Secret Rotation**: Update SSM parameter, force new deployment to pick up new secret
- **Scale-In Protection**: Capacity provider enables managed termination protection during scale-in
- **Emergency Scale-Down**: Reduce desired_count, capacity provider will scale cluster down gradually
