output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered by AZ index."
  value = [
    for az in var.availability_zones : aws_subnet.private[az].id
  ]
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, ordered by AZ index."
  value = [
    for az in var.availability_zones : aws_subnet.public[az].id
  ]
}

output "private_route_table_id" {
  description = "ID of the private route table (default route via NAT when enabled)."
  value       = aws_route_table.private.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway when enable_nat_gateway is true; otherwise null."
  value       = var.enable_nat_gateway ? aws_nat_gateway.this[0].id : null
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log when enable_flow_logs is true; otherwise null."
  value       = var.enable_flow_logs ? aws_flow_log.this[0].id : null
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group name for VPC Flow Logs when enabled; otherwise null."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint when enable_s3_endpoint is true; otherwise null."
  value       = var.enable_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
}

output "dynamodb_endpoint_id" {
  description = "ID of the DynamoDB gateway VPC endpoint when enable_dynamodb_endpoint is true; otherwise null."
  value       = var.enable_dynamodb_endpoint ? aws_vpc_endpoint.dynamodb[0].id : null
}

output "ssm_endpoint_id" {
  description = "ID of the SSM interface VPC endpoint when enable_ssm_endpoint is true; otherwise null."
  value       = var.enable_ssm_endpoint ? aws_vpc_endpoint.interface["ssm"].id : null
}

output "ssmmessages_endpoint_id" {
  description = "ID of the ssmmessages interface VPC endpoint when enable_ssm_endpoint is true; otherwise null."
  value       = var.enable_ssm_endpoint ? aws_vpc_endpoint.interface["ssmmessages"].id : null
}

output "ec2messages_endpoint_id" {
  description = "ID of the ec2messages interface VPC endpoint when enable_ssm_endpoint is true; otherwise null."
  value       = var.enable_ssm_endpoint ? aws_vpc_endpoint.interface["ec2messages"].id : null
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID used by interface VPC endpoints when SSM, ECR, or Logs endpoints are enabled; otherwise null."
  value       = length(local.interface_endpoint_services) > 0 ? aws_security_group.vpc_endpoints[0].id : null
}

output "ecr_api_endpoint_id" {
  description = "ID of the ECR API interface VPC endpoint when enable_ecr_endpoint is true; otherwise null."
  value       = var.enable_ecr_endpoint ? aws_vpc_endpoint.interface["ecr_api"].id : null
}

output "ecr_dkr_endpoint_id" {
  description = "ID of the ECR DKR interface VPC endpoint when enable_ecr_endpoint is true; otherwise null."
  value       = var.enable_ecr_endpoint ? aws_vpc_endpoint.interface["ecr_dkr"].id : null
}

output "logs_endpoint_id" {
  description = "ID of the CloudWatch Logs interface VPC endpoint when enable_logs_endpoint is true; otherwise null."
  value       = var.enable_logs_endpoint ? aws_vpc_endpoint.interface["logs"].id : null
}
