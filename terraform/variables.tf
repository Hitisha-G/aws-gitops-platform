variable "aws_region" {
  type        = string
  description = "AWS region for the platform stack."
  default     = "ap-south-1"
}

variable "project_name" {
  type        = string
  description = "Short name used for tagging and resource prefixes."
  default     = "aws-gitops-platform"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs used by the VPC module."
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create a single NAT gateway for private subnet egress."
  default     = true
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs to CloudWatch Logs."
  default     = false
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Retention days for VPC Flow Logs in CloudWatch."
  default     = 14
}

variable "enable_s3_endpoint" {
  type        = bool
  description = "Create a gateway VPC endpoint for S3 on the private route table."
  default     = true
}

variable "enable_dynamodb_endpoint" {
  type        = bool
  description = "Create a gateway VPC endpoint for DynamoDB on the private route table."
  default     = true
}

variable "enable_ssm_endpoint" {
  type        = bool
  description = "Create interface VPC endpoints for ssm, ssmmessages, and ec2messages in private subnets."
  default     = false
}

variable "enable_ecr_endpoint" {
  type        = bool
  description = "Create interface VPC endpoints for ecr.api and ecr.dkr in private subnets."
  default     = false
}

variable "enable_logs_endpoint" {
  type        = bool
  description = "Create an interface VPC endpoint for CloudWatch Logs in private subnets."
  default     = false
}

variable "enable_secretsmanager_endpoint" {
  type        = bool
  description = "Create an interface VPC endpoint for Secrets Manager in private subnets."
  default     = false
}

variable "enable_kms_endpoint" {
  type        = bool
  description = "Create an interface VPC endpoint for KMS in private subnets."
  default     = false
}
