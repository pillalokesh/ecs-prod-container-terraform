aws_region = "us-east-1"
environment = "production"

# VPC and Subnets (Update with your actual IDs)
vpc_id             = "vpc-0911044b43b937f2e"
private_subnet_ids = ["subnet-0f47518c6c7860603", "subnet-0c7d8562f98c12bf7"]
public_subnet_ids  = ["subnet-0a6e328d21a951f62", "subnet-0ef8288539cc6b26a"]

# ECS Configuration
cluster_name   = "prod-ecs-cluster"
service_name   = "nginx-service"
desired_count  = 4
container_port = 80

# Auto Scaling Configuration
asg_min_size                    = 2
asg_max_size                    = 10
asg_desired_capacity            = 4
on_demand_base_capacity         = 2
on_demand_percentage_above_base = 0

# Instance Types
instance_types = ["t3.medium", "t3a.medium", "t2.medium"]

# SSM Parameter Store Secrets (Parameters must exist)
ssm_secret_names = ["/prod/app/db_password", "/prod/app/api_key"]

# Service Auto Scaling
cpu_target_value = 70
