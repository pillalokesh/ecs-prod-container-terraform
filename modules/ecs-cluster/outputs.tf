output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "capacity_provider_name" {
  value = aws_ecs_capacity_provider.main.name
}
