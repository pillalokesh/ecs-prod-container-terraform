module "iam" {
  source = "./modules/iam"

  cluster_name     = var.cluster_name
  service_name     = var.service_name
  aws_region       = var.aws_region
  ssm_secret_names = var.ssm_secret_names
}

module "security_groups" {
  source = "./modules/security-groups"

  vpc_id         = var.vpc_id
  service_name   = var.service_name
  container_port = var.container_port
}

module "alb" {
  source = "./modules/alb"

  service_name           = var.service_name
  vpc_id                 = var.vpc_id
  public_subnet_ids      = var.public_subnet_ids
  alb_security_group_id  = module.security_groups.alb_security_group_id
  container_port         = var.container_port
}

module "asg" {
  source = "./modules/asg"

  cluster_name                    = var.cluster_name
  private_subnet_ids              = var.private_subnet_ids
  ecs_instance_profile_arn        = module.iam.ecs_instance_profile_arn
  ecs_tasks_security_group_id     = module.security_groups.ecs_tasks_security_group_id
  instance_types                  = var.instance_types
  asg_min_size                    = var.asg_min_size
  asg_max_size                    = var.asg_max_size
  asg_desired_capacity            = var.asg_desired_capacity
  on_demand_base_capacity         = var.on_demand_base_capacity
  on_demand_percentage_above_base = var.on_demand_percentage_above_base
  ecs_cluster_name                = var.cluster_name
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  cluster_name = var.cluster_name
  asg_arn      = module.asg.asg_arn
}

module "ecs_service" {
  source = "./modules/ecs-service"

  service_name                   = var.service_name
  cluster_id                     = module.ecs_cluster.cluster_id
  cluster_name                   = module.ecs_cluster.cluster_name
  desired_count                  = var.desired_count
  container_port                 = var.container_port
  capacity_provider_name         = module.ecs_cluster.capacity_provider_name
  target_group_arn               = module.alb.target_group_arn
  task_execution_role_arn        = module.iam.ecs_task_execution_role_arn
  task_role_arn                  = module.iam.ecs_task_role_arn
  aws_region                     = var.aws_region
  ssm_secret_names               = var.ssm_secret_names
  listener_arn                   = module.alb.listener_arn
  task_execution_ssm_policy_id   = module.iam.ecs_task_execution_ssm_policy_id
  cpu_target_value               = var.cpu_target_value
}
