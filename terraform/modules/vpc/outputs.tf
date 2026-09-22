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
