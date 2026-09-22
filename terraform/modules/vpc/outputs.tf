output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered by AZ index."
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, ordered by AZ index."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_route_table_id" {
  description = "ID of the private route table (no internet route)."
  value       = aws_route_table.private.id
}
