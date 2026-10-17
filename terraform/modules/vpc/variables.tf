variable "project_name" {
  type        = string
  description = "Short name used for resource Name tags."

  # Used verbatim in IAM role names ("<name>-vpc-flow-logs", 64-char limit)
  # and CloudWatch log group paths, so keep it short and DNS-style.
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.project_name))
    error_message = "project_name must use lowercase letters, digits, and hyphens, and must not start or end with a hyphen."
  }

  validation {
    condition     = length(var.project_name) <= 50
    error_message = "project_name must be 50 characters or fewer so the derived \"<name>-vpc-flow-logs\" IAM role name stays within the 64-character limit."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block allocated to this VPC."

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 4, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR that can be carved with newbits=4 (for example 10.40.0.0/16)."
  }

  # AWS accepts IPv4 VPC and subnet blocks between /16 and /28. With newbits=4
  # the carved subnets are 4 bits longer than the VPC, so only /16-/24 VPCs work.
  validation {
    condition = (
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", var.vpc_cidr))
      ? tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
      : false
    )
    error_message = "vpc_cidr must be an IPv4 block between /16 and /24 so the VPC and its newbits=4 subnets (/20-/28) fit AWS size limits."
  }

  # cidrsubnet() silently masks host bits, so "10.40.1.0/16" would plan with
  # subnets from 10.40.0.0 while AWS rejects the VPC block itself.
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) ? cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0] : false
    error_message = "vpc_cidr must be a network address with no host bits set (for example 10.40.0.0/16, not 10.40.1.0/16)."
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

variable "enable_flow_logs" {
  type        = bool
  description = "When true, send VPC Flow Logs to a dedicated CloudWatch Logs group."
  default     = false
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Retention period in days for the VPC Flow Logs CloudWatch group."
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a CloudWatch Logs retention value supported by AWS."
  }
}

variable "flow_logs_traffic_type" {
  type        = string
  description = "Which traffic VPC Flow Logs capture: ACCEPT, REJECT, or ALL."
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of ACCEPT, REJECT, or ALL."
  }
}

variable "enable_s3_endpoint" {
  type        = bool
  description = "When true, create a gateway VPC endpoint for S3 and associate it with the private route table."
  default     = true
}

variable "enable_dynamodb_endpoint" {
  type        = bool
  description = "When true, create a gateway VPC endpoint for DynamoDB and associate it with the private route table."
  default     = true
}

variable "enable_ssm_endpoint" {
  type        = bool
  description = "When true, create interface VPC endpoints for ssm, ssmmessages, and ec2messages in private subnets (Session Manager without a bastion)."
  default     = false
}

variable "enable_ecr_endpoint" {
  type        = bool
  description = "When true, create interface VPC endpoints for ecr.api and ecr.dkr in private subnets (private image pulls without NAT)."
  default     = false
}

variable "enable_logs_endpoint" {
  type        = bool
  description = "When true, create an interface VPC endpoint for CloudWatch Logs in private subnets (private log shipping without NAT)."
  default     = false
}

variable "enable_secretsmanager_endpoint" {
  type        = bool
  description = "When true, create an interface VPC endpoint for Secrets Manager in private subnets (private secret fetches without NAT)."
  default     = false
}

variable "enable_kms_endpoint" {
  type        = bool
  description = "When true, create an interface VPC endpoint for KMS in private subnets (private key ops without NAT)."
  default     = false
}

variable "enable_eks_subnet_tags" {
  type        = bool
  description = "When true, tag public subnets for internet-facing ELBs and private subnets for internal ELBs (kubernetes.io/role/*)."
  default     = false
}

variable "eks_cluster_tag" {
  type        = string
  description = "Optional EKS cluster name. When non-empty and enable_eks_subnet_tags is true, also set kubernetes.io/cluster/<name> = shared on public and private subnets."
  default     = ""

  # EKS cluster names are 1-100 chars, start with a letter or digit, and use
  # only letters, digits, hyphens, and underscores. Anything else would put an
  # invalid kubernetes.io/cluster/<name> tag key on every subnet.
  validation {
    condition     = var.eks_cluster_tag == "" || can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.eks_cluster_tag))
    error_message = "eks_cluster_tag must be empty or a valid EKS cluster name: 1-100 letters, digits, hyphens, or underscores, starting with a letter or digit."
  }
}
