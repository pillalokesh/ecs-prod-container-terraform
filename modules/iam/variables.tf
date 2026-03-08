variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ssm_secret_names" {
  type = list(string)
}
