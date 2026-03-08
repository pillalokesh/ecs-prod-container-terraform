# Production Stress Test Scenarios

## 1) Spot Failure During Deployment

### Scenario
During a deployment, 60% of Spot instances are reclaimed by AWS.

### Step-by-Step Breakdown

**Initial State**:
- 4 instances running (2 On-Demand base + 2 Spot)
- 8 tasks running (2 per instance)
- Deployment starts: new task definition being rolled out

**Spot Interruption Occurs**:
1. **T+0s**: AWS sends 2-minute interruption notice to 2 Spot instances (60% of capacity)
2. **T+0s**: ECS agent on interrupted instances sets state to DRAINING
3. **T+0s**: No new tasks are placed on DRAINING instances
4. **T+5s**: Running tasks on interrupted instances continue serving traffic via ALB

**Capacity Provider Response**:
5. **T+10s**: Capacity provider detects capacity shortage (reserved capacity increasing)
6. **T+15s**: Capacity provider triggers ASG scale-out
7. **T+20s**: ASG launches 2 new instances (On-Demand, since we're now below base capacity)

**Task Rescheduling**:
8. **T+30s**: New instances join ECS cluster
9. **T+35s**: ECS schedules replacement tasks on new instances + existing healthy instances
10. **T+60s**: New tasks start, pass health checks, register with ALB
11. **T+90s**: ALB marks new tasks as healthy, starts routing traffic

**Graceful Shutdown**:
12. **T+120s**: Spot instances terminate
13. **T+120s**: Tasks on terminated instances are stopped
14. **T+125s**: ALB removes terminated tasks from target group (already drained)

### Where Does New Capacity Come From?
- **Immediate**: 2 On-Demand instances (baseline) continue running
- **Short-term**: Existing healthy instances absorb rescheduled tasks
- **Long-term**: Capacity provider scales ASG, launches new On-Demand instances (to restore base capacity)

### Why Is There No Downtime?
1. **On-Demand Baseline**: 2 On-Demand instances never interrupted, continue serving traffic
2. **Minimum Healthy Percent**: 100% ensures sufficient tasks remain running during transition
3. **Multi-AZ Spread**: Tasks distributed across AZs, Spot interruption affects subset
4. **ALB Health Checks**: Only routes to healthy targets
5. **Capacity Provider**: Auto-scales cluster before capacity exhausted
6. **Deployment Configuration**: Max 200% allows new tasks to start before old tasks stop

---

## 2) Secrets Break at Runtime

### Scenario
SSM permission is removed from the task execution role during operation.

### What Breaks?

**Immediate Impact**:
- **Existing Tasks**: Continue running normally (secrets already injected at startup)
- **New Tasks**: Fail to start with error: `CannotPullSecrets` or `ResourceInitializationError`

**ECS Behavior**:
1. Service attempts to start new tasks (deployment, scaling, or replacement)
2. Task execution role tries to fetch secrets from SSM
3. IAM denies `ssm:GetParameters` request (permission removed)
4. Task fails to start, enters STOPPED state
5. ECS retries task placement (exponential backoff)
6. Service cannot reach desired count

**CloudWatch Logs**:
```
Task stopped at: <timestamp>
Reason: ResourceInitializationError: unable to pull secrets or registry auth
```

### Detection

**Automated**:
- CloudWatch alarm: `RunningTaskCount < DesiredCount` for > 5 minutes
- ECS event stream: Task state change events with failure reason
- CloudWatch Logs Insights: Query for "ResourceInitializationError"

**Manual**:
- ECS console shows tasks in STOPPED state with failure reason
- Service events tab shows repeated task start failures

### Recovery Steps

1. **Immediate**: Verify existing tasks are healthy (they are, secrets already loaded)
2. **Identify**: Check IAM policy on task execution role
3. **Fix**: Restore `ssm:GetParameters` permission to task execution role
4. **Validate**: Manually trigger task start to verify secret retrieval works
5. **Redeploy**: Force new deployment or wait for next scheduled deployment

### Avoiding Secret Leakage

**What NOT to Do**:
- ❌ Don't hardcode secrets in task definition
- ❌ Don't pass secrets via environment variables in Terraform
- ❌ Don't log secrets to CloudWatch
- ❌ Don't store secrets in container image

**Correct Approach**:
- ✅ Use `secrets` block in task definition (not `environment`)
- ✅ Reference SSM parameter by name/ARN only
- ✅ Least privilege IAM: task execution role can only read specific parameters
- ✅ Secrets never appear in Terraform state (only parameter references)
- ✅ Use SecureString type in SSM Parameter Store (encrypted at rest)

---

## 3) Pending Task Deadlock

### Scenario
Service wants 10 tasks; cluster can run 6; 4 tasks are PENDING.

### Step-by-Step Resolution

**Initial State**:
- Desired count: 10 tasks
- Running tasks: 6
- Pending tasks: 4 (insufficient cluster capacity)

**Capacity Provider Detection** (T+0 to T+60s):
1. **T+0s**: 4 tasks in PENDING state (cannot be placed)
2. **T+10s**: Capacity provider calculates: `(reserved capacity / total capacity) = (10 / 6) = 167%`
3. **T+15s**: Target capacity is 100%, current is 167% → cluster under-provisioned
4. **T+20s**: Capacity provider triggers ASG scale-out

**ASG Scaling** (T+60s to T+180s):
5. **T+60s**: ASG receives scale-out signal from capacity provider
6. **T+65s**: ASG calculates: need 4 more instances to accommodate 10 tasks
7. **T+70s**: ASG launches 2 new instances (respecting On-Demand base + Spot strategy)
8. **T+180s**: New instances boot, join ECS cluster

**Task Placement** (T+180s to T+240s):
9. **T+180s**: ECS detects new cluster capacity
10. **T+185s**: ECS places 4 PENDING tasks on new instances
11. **T+200s**: Tasks start, pull image, inject secrets
12. **T+220s**: Tasks pass health checks
13. **T+240s**: ALB marks tasks as healthy, routes traffic

### What Triggers Capacity Increase?

**Capacity Provider Managed Scaling**:
- **Metric**: `CapacityProviderReservation` (percentage of cluster capacity reserved by tasks)
- **Target**: 100% (cluster should have exactly enough capacity for desired tasks)
- **Calculation**: `(M * 100) / N` where M = tasks needing capacity, N = cluster capacity
- **Trigger**: When reservation > target, scale out; when reservation < target, scale in

**In This Scenario**:
- M = 10 tasks (desired)
- N = 6 tasks (current cluster capacity)
- Reservation = (10 * 100) / 6 = 167%
- Target = 100%
- Action: Scale out to increase N until reservation ≈ 100%

### Why Doesn't It Deadlock?

1. **Automatic Scaling**: Capacity provider detects PENDING tasks and scales ASG automatically
2. **No Manual Intervention**: No human action required to break deadlock
3. **Managed Scaling Enabled**: `managed_scaling.status = "ENABLED"` in capacity provider
4. **Target Capacity**: Set to 100%, ensures cluster always has room for desired tasks
5. **ASG Max Size**: 10 instances (sufficient headroom for scale-out)
6. **Minimum Scaling Step**: 1 instance (gradual scaling)
7. **Maximum Scaling Step**: 10 instances (rapid scale-out if needed)

**Deadlock Would Occur If**:
- ❌ Capacity provider managed scaling disabled
- ❌ ASG at max size (no room to scale)
- ❌ Target capacity set too low (e.g., 50%)
- ❌ IAM permissions missing for capacity provider to scale ASG

---

## 4) Deployment Safety

### Scenario
Rolling deployment with new task definition version.

### Timeline: When Do Things Happen?

**T+0s: Deployment Starts**
- User updates task definition (new image tag, config change, etc.)
- ECS service receives new desired state
- Deployment configuration: min 100%, max 200%

**T+5s: New Tasks Start**
- ECS calculates: can start up to 200% of desired count (e.g., 4 desired → 8 max)
- ECS starts 4 new tasks (with new task definition)
- Old tasks (4) continue running and serving traffic

**T+30s: New Tasks Pull Image & Start**
- New tasks pull container image from ECR
- Task execution role injects secrets from SSM
- Containers start, nginx begins listening on port 80

**T+60s: Container Health Checks Pass**
- ECS waits for `health_check_grace_period_seconds = 60`
- Containers respond to health checks
- ECS marks tasks as HEALTHY

**T+90s: ALB Registration**
- New tasks register with ALB target group
- ALB begins health checks (HTTP GET `/`)
- Health check interval: 30s, healthy threshold: 2 successes

**T+150s: ALB Marks New Tasks Healthy**
- New tasks pass 2 consecutive ALB health checks (30s * 2 = 60s)
- ALB marks new targets as healthy
- ALB starts routing traffic to new tasks

**T+150s: Old Tasks Deregistration Begins**
- ECS deregisters old tasks from ALB target group
- ALB stops sending new connections to old tasks
- Existing connections continue (deregistration delay = 30s)

**T+180s: Old Tasks Drain**
- Deregistration delay (30s) completes
- In-flight requests finish
- ALB removes old tasks from target group

**T+185s: Old Tasks Stop**
- ECS sends SIGTERM to old task containers
- Containers gracefully shut down (30s timeout)
- Old tasks enter STOPPED state

**T+190s: Deployment Complete**
- All old tasks stopped
- All new tasks running and healthy
- Service at desired count (4 tasks, all new version)

### When Do Old Tasks Stop Receiving Traffic?

**T+150s**: ALB deregisters old tasks
- **New connections**: Immediately routed to new tasks only
- **Existing connections**: Continue to old tasks (connection draining)

### When Are Old Tasks Killed?

**T+185s**: After deregistration delay (30s) + drain time
- ECS sends SIGTERM to container
- Container has 30s to gracefully shut down (configurable via `stopTimeout`)
- If container doesn't stop, ECS sends SIGKILL after timeout

### What If New Tasks Fail Health Checks?

**Circuit Breaker Behavior**:
1. **T+60s**: New tasks fail container health checks repeatedly
2. **T+120s**: ECS detects: new tasks not reaching HEALTHY state
3. **T+180s**: Circuit breaker threshold reached (e.g., 3 consecutive failures)
4. **T+185s**: ECS stops deployment, marks as FAILED
5. **T+190s**: ECS triggers automatic rollback (circuit breaker enabled)
6. **T+200s**: ECS stops new (unhealthy) tasks
7. **T+210s**: Old tasks continue running (never deregistered)
8. **T+220s**: Service returns to previous stable state

**Result**: Zero downtime, old version continues serving traffic

---

## 5) TLS, Trust Boundary, Identity

### Where Is TLS Terminated?

**TLS Termination Point**: Application Load Balancer (ALB)

**Traffic Flow**:
1. **Client → ALB**: HTTPS (TLS 1.2/1.3 encrypted)
2. **ALB → ECS Tasks**: HTTP (unencrypted, within VPC)

**Rationale**:
- ALB handles TLS termination (certificate management via ACM)
- Backend traffic within VPC (private subnets, security groups)
- Simplifies container configuration (no TLS cert management in containers)
- ALB can inspect HTTP traffic for health checks, routing, WAF

**Production Enhancement**:
- For end-to-end encryption: Enable TLS between ALB and targets (requires cert in container)
- Use AWS Certificate Manager (ACM) for ALB certificate
- Enforce HTTPS-only via ALB listener rules (redirect HTTP → HTTPS)

### What AWS Identity Does the Container Run As?

**Task Role**: `ecs-task-role` (IAM role for running container)

**Identity Flow**:
1. Container makes AWS API call (e.g., S3, DynamoDB)
2. AWS SDK uses ECS task metadata endpoint to retrieve temporary credentials
3. Credentials are for the task role (not task execution role)
4. AWS service validates credentials and checks IAM policy

**Task Execution Role vs Task Role**:
- **Task Execution Role**: Used by ECS agent (pulls image, fetches secrets, writes logs)
- **Task Role**: Used by application code inside container (S3, DynamoDB, etc.)

### What AWS Resources Can It Access?

**Current Configuration**: None (task role has no policies attached)

**Least Privilege Example**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject"
    ],
    "Resource": "arn:aws:s3:::my-app-bucket/*"
  }]
}
```

**Production Best Practice**:
- Grant only permissions required by application
- Use resource-level restrictions (specific S3 buckets, DynamoDB tables)
- Use condition keys (e.g., `aws:SourceVpc` to restrict to VPC)
- Regularly audit IAM policies (AWS Access Analyzer)

---

## 6) Cost Floor

### Scenario
Traffic drops to zero for 12 hours.

### What Are You Still Paying For?

**Compute**:
- **On-Demand Instances**: 2 instances (baseline) running 24/7
  - Cost: ~$0.0416/hour * 2 * 12 hours = ~$1.00 (t3.medium)
- **Spot Instances**: 0 (capacity provider scales down to baseline)

**Networking**:
- **Application Load Balancer**: $0.0225/hour * 12 hours = $0.27
- **ALB LCU**: Minimal (no traffic, but still charged for active connections)
- **NAT Gateway**: $0.045/hour * 12 hours = $0.54 (per AZ)
  - If 2 AZs: $1.08 total

**Storage & Logs**:
- **CloudWatch Logs**: Minimal (no traffic, but still ingesting system logs)
- **EBS Volumes**: Attached to EC2 instances (included in instance cost)

**Total Cost Floor**: ~$2.35 for 12 hours (~$4.70/day, ~$141/month)

### What Would You Change to Reduce Cost Without Reducing Safety?

**Option 1: VPC Endpoints (Eliminate NAT Gateway)**
- Replace NAT Gateway with VPC endpoints for ECR, S3, CloudWatch
- Savings: ~$32/month per AZ (NAT Gateway hourly charge)
- Tradeoff: Slightly more complex networking setup

**Option 2: Smaller Instance Types**
- Use t3.small or t3.micro for baseline (if workload allows)
- Savings: ~50% compute cost
- Tradeoff: Less burst capacity, may need more instances

**Option 3: Scale to Zero (Advanced)**
- Use AWS Lambda or Fargate Spot for zero-traffic periods
- Scale ECS service to 0 tasks, terminate all instances
- Use ALB + Lambda for health checks, trigger scale-up on first request
- Savings: ~90% cost reduction during zero-traffic
- Tradeoff: Cold start latency (30-60s to scale from zero)

**Option 4: Reserved Instances / Savings Plans**
- Commit to 1-year or 3-year Reserved Instances for baseline capacity
- Savings: ~40-60% on On-Demand baseline
- Tradeoff: Upfront commitment, less flexibility

**Recommended**: Option 1 (VPC Endpoints) + Option 4 (Reserved Instances)
- Eliminates NAT Gateway cost (~$32/month per AZ)
- Reduces baseline compute cost (~40-60%)
- Maintains safety (On-Demand baseline, no cold starts)

---

## 7) Failure Modes

### Failure 1: Availability Zone Outage

**Scenario**: Entire AZ becomes unavailable (AWS infrastructure failure)

**Detection**:
- CloudWatch alarm: `UnHealthyHostCount` increases
- ECS service: Running task count drops below desired
- ALB: Targets in affected AZ marked unhealthy

**Blast Radius**:
- ~33% of tasks offline (assuming 3 AZs, even distribution)
- ~33% of instances offline
- ALB stops routing to affected AZ automatically

**Mitigation**:
1. **Immediate**: ALB routes traffic to healthy AZs only (automatic)
2. **T+30s**: ECS detects task failures, attempts to reschedule
3. **T+60s**: Capacity provider detects capacity shortage
4. **T+120s**: ASG launches new instances in healthy AZs
5. **T+300s**: New tasks running in healthy AZs, service restored to desired count

**Design Handles It**:
- Multi-AZ deployment (tasks spread across 3 AZs)
- ALB health checks (automatic failover to healthy AZs)
- Capacity provider (auto-scales to replace lost capacity)
- Minimum healthy percent (100%) ensures sufficient capacity during recovery

---

### Failure 2: Container Image Registry Unavailable (ECR Outage)

**Scenario**: AWS ECR service outage, cannot pull container images

**Detection**:
- ECS tasks fail to start with error: `CannotPullContainerError`
- CloudWatch Logs: "Error pulling image: connection timeout"
- ECS service events: Repeated task start failures

**Blast Radius**:
- **Existing tasks**: Continue running (image already pulled)
- **New tasks**: Cannot start (deployments, scaling, replacements blocked)
- **Service availability**: Maintained by existing tasks

**Mitigation**:
1. **Immediate**: Existing tasks continue serving traffic (no impact)
2. **T+0**: Pause any in-progress deployments (circuit breaker stops rollout)
3. **T+0**: Disable auto-scaling scale-out (prevent new task attempts)
4. **Wait**: Monitor AWS Service Health Dashboard for ECR recovery
5. **T+recovery**: ECR restored, resume deployments and scaling

**Design Handles It**:
- Existing tasks unaffected (image already on instance)
- Circuit breaker prevents bad deployments from taking down service
- Minimum healthy percent ensures existing tasks remain running
- No automatic scale-down (tasks continue running during outage)

**Production Enhancement**:
- Use ECR image replication to multiple regions
- Cache images on ECS instances (image pull policy: IfNotPresent)
- Implement image pre-warming (pull images to instances before needed)

---

### Failure 3: Task Memory Leak / OOM Kill

**Scenario**: Application has memory leak, tasks consume increasing memory until OOM killed

**Detection**:
- CloudWatch alarm: `MemoryUtilization` > 90% for task
- ECS task stopped with exit code 137 (SIGKILL, OOM)
- CloudWatch Logs: "Out of memory" or kernel OOM killer messages

**Blast Radius**:
- **Single task**: Killed by OOM, service reschedules replacement
- **Multiple tasks**: If leak affects all tasks, rolling OOM kills
- **Service availability**: Maintained if OOM kills are gradual (not all at once)

**Mitigation**:
1. **T+0**: ECS detects task stopped (exit code 137)
2. **T+5s**: ECS schedules replacement task on another instance
3. **T+60s**: New task starts, passes health checks
4. **T+90s**: ALB routes traffic to new task
5. **Repeat**: Cycle continues (leak persists in new tasks)

**Design Handles It**:
- Task-level isolation (one task OOM doesn't affect others)
- ECS auto-restart (replacement tasks scheduled automatically)
- ALB health checks (unhealthy tasks removed from rotation)
- Multiple tasks (service continues with remaining healthy tasks)

**Production Enhancement**:
- Set memory hard limit in task definition (prevents runaway consumption)
- Monitor memory utilization per task (CloudWatch Container Insights)
- Implement application-level memory monitoring (heap dumps, profiling)
- Use circuit breaker to detect repeated task failures (stop deployment if leak introduced)
- Implement graceful degradation (reduce task memory limit, scale out more tasks)

**Long-Term Fix**:
- Identify and fix memory leak in application code
- Deploy patched version via rolling deployment
- Monitor memory utilization post-deployment
