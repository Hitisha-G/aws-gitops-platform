variable "project_name" {
  type        = string
  description = "Short name used for resource Name tags."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block allocated to this VPC."
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs that receive one public and one private subnet each."
}

variable "tags" {
  type        = map(string)
  description = "Common tags merged onto every resource in this module."
  default     = {}
}
