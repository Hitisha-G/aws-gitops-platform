module "vpc" {
  source = "./modules/vpc"

  project_name             = var.project_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  enable_nat_gateway       = var.enable_nat_gateway
  enable_flow_logs         = var.enable_flow_logs
  flow_logs_retention_days = var.flow_logs_retention_days
  enable_s3_endpoint       = var.enable_s3_endpoint

  tags = {
    ManagedBy = "terraform"
    Stack     = "platform"
  }
}
