
output "vpc_id" {
  description = "VPC del laboratorio Surf School"
  value       = data.aws_vpc.surf_school.id
}

output "app_subnet_ids" {
  description = "Subnets privadas de ECS"
  value = [
    data.aws_subnet.app_1.id,
    data.aws_subnet.app_2.id
  ]
}

output "endpoints_security_group_id" {
  description = "Security Group de los VPC Endpoints"
  value       = data.aws_security_group.endpoints.id
}
