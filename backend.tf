
terraform {
  backend "s3" {
    bucket  = "lokesh-terraform-state"
    key     = "ecs/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}