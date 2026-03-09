aws_region = "us-east-1"
environment = "production"

# VPC creation variables - will create new VPC
vpc_name           = "prod-ecs-vpc"
vpc_cidr           = "10.0.0.0/16"
azs                = ["us-east-1a", "us-east-1b"]
private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
enable_nat_gateway = true
enable_vpn_gateway = false
vpc_tags = {
  Terraform   = "true"
  Environment = "production"
}


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


# Service Auto Scaling
cpu_target_value = 70

# bastion host settings
bastion_ami            = ""  
bastion_key_name       = "dev-bastion"
my_ip_cidr             = "0.0.0.0/0"          # your IP for SSH access

# create sample secrets (empty map by default)
# SSM Parameter Store Secrets (Parameters must exist)
ssm_secret_names = ["/prod/app/db_password", "/prod/app/api_key"]
