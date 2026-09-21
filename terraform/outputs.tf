output "vpc_id" {
  description = "ID of the platform VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for workloads."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancers and bastion paths."
  value       = module.vpc.public_subnet_ids
}
