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
