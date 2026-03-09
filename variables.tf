variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# optional: set when you want to reference an existing VPC instead of
# built-in network.
variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = ""
}

# optional: specify if you're using an existing VPC with known subnets.
# otherwise the ASG and other resources pull from module.vpc.private_subnets.
variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS instances"
  type        = list(string)
  default     = []
}

# optional: specify if you're using an existing VPC with known subnets.
# otherwise the ALB uses module.vpc.public_subnets.
variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "service_name" {
  description = "ECS service name"
  type        = string
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "asg_min_size" {
  description = "ASG minimum size"
  type        = number
}

variable "asg_max_size" {
  description = "ASG maximum size"
  type        = number
}

variable "asg_desired_capacity" {
  description = "ASG desired capacity"
  type        = number
}

variable "on_demand_base_capacity" {
  description = "Number of On-Demand instances as baseline"
  type        = number
}

variable "on_demand_percentage_above_base" {
  description = "Percentage of On-Demand instances above base"
  type        = number
}

variable "instance_types" {
  description = "List of instance types for mixed instances policy"
  type        = list(string)
}

variable "ssm_secret_names" {
  description = "List of SSM parameter names for secrets. If left empty, the keys from `ssm_parameters` map will be used instead."
  type    = list(string)
  default = []
}

variable "cpu_target_value" {
  description = "Target CPU utilization for service auto-scaling"
  type        = number
}

# VPC module inputs
variable "vpc_name" {
  description = "Name of the VPC to create"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDRs for private subnets"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDRs for public subnets"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Whether to create a VPN gateway"
  type        = bool
  default     = true
}

variable "vpc_tags" {
  description = "Tags to apply to the VPC"
  type        = map(string)
  default     = {}
}

# ------------------------
# bastion host inputs
# ------------------------
variable "bastion_ami" {
  description = "AMI ID to use for the bastion host (leave empty to skip creating a bastion)"
  type        = string
  default     = ""
}

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_name" {
  description = "Name of the key pair to attach to bastion"
  type        = string
  default     = "bastion-key"
}

variable "my_ip_cidr" {
  description = "CIDR block representing the admin's IP for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

# store secret values (secure string) in SSM Parameter Store; keys are the
# parameter names, values are the plaintext secrets.  Best practice: do **not**
# commit real secrets into version control – use environment-specific files or
# a secrets manager to populate this map at runtime.
variable "ssm_parameters" {
  description = "Map of SSM parameter names to secret values to create"
  type        = map(string)
  default     = {}
}
