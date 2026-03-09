variable "service_name" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "desired_count" {
  type = number
}

variable "container_port" {
  type = number
}

variable "capacity_provider_name" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ssm_secret_names" {
  type = list(string)
}

variable "listener_arn" {
  type = string
}

variable "task_execution_ssm_policy_id" {
  type = string
}

variable "cpu_target_value" {
  type = number
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_tasks_security_group_id" {
  type = string
}
