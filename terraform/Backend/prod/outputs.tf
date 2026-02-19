output "ecr_repository_url" {
  value = aws_ecr_repository.repo.repository_url
}

output "service_name" {
  value = aws_ecs_service.service.name
}

output "target_group" {
  value = aws_lb_target_group.tg.arn
}