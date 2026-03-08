output "asg_name" {
  value = aws_autoscaling_group.ecs.name
}

output "asg_arn" {
  value = aws_autoscaling_group.ecs.arn
}
