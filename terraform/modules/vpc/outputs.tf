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
