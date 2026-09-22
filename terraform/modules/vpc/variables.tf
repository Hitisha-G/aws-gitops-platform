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

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones for high availability."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags merged onto every resource in this module."
  default     = {}
}
