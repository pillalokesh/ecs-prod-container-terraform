variable "cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_instance_profile_arn" {
  type = string
}

variable "ecs_tasks_security_group_id" {
  type = string
}

variable "instance_types" {
  type = list(string)
}

variable "asg_min_size" {
  type = number
}

variable "asg_max_size" {
  type = number
}

variable "asg_desired_capacity" {
  type = number
}

variable "on_demand_base_capacity" {
  type = number
}

variable "on_demand_percentage_above_base" {
  type = number
}

variable "ecs_cluster_name" {
  type = string
}
