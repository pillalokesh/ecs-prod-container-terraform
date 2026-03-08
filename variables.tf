variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS instances"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
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
  description = "List of SSM parameter names for secrets"
  type        = list(string)
}

variable "cpu_target_value" {
  description = "Target CPU utilization for service auto-scaling"
  type        = number
}
