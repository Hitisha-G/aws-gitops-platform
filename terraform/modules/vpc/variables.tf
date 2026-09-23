variable "project_name" {
  type        = string
  description = "Short name used for resource Name tags."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block allocated to this VPC."

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 4, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR that can be carved with newbits=4 (for example 10.40.0.0/16)."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs that receive one public and one private subnet each."

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones for high availability."
  }

  validation {
    condition     = length(var.availability_zones) == length(toset(var.availability_zones))
    error_message = "availability_zones must not contain duplicate entries."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags merged onto every resource in this module."
  default     = {}
}

variable "enable_nat_gateway" {
  type        = bool
  description = "When true, place one NAT gateway in the first public subnet and route private traffic through it."
  default     = true
}
