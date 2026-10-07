data "aws_region" "current" {}

locals {
  # Regional service-name prefix shared by gateway and interface endpoints.
  endpoint_service_prefix = "com.amazonaws.${data.aws_region.current.name}"

  # Shared private-subnet placement for every interface endpoint.
  private_subnet_ids = [
    for az in var.availability_zones : aws_subnet.private[az].id
  ]

  # Interface services keyed by stable name; toggled by feature flags.
  interface_endpoint_services = merge(
    var.enable_ssm_endpoint ? {
      ssm         = "ssm"
      ssmmessages = "ssmmessages"
      ec2messages = "ec2messages"
    } : {},
    var.enable_ecr_endpoint ? {
      ecr_api = "ecr.api"
      ecr_dkr = "ecr.dkr"
    } : {},
    var.enable_logs_endpoint ? {
      logs = "logs"
    } : {},
    var.enable_secretsmanager_endpoint ? {
      secretsmanager = "secretsmanager"
    } : {},
    var.enable_kms_endpoint ? {
      kms = "kms"
    } : {}
  )
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "${local.endpoint_service_prefix}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_dynamodb_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "${local.endpoint_service_prefix}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dynamodb-endpoint"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  count = length(local.interface_endpoint_services) > 0 ? 1 : 0

  name_prefix = "${local.name_prefix}-vpce-"
  description = "HTTPS from the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS return traffic to clients in the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpce-sg"
  })

  lifecycle {
    create_before_destroy = true

    # ECR image layers live in S3; interface ecr.api/ecr.dkr alone cannot pull layers.
    precondition {
      condition     = !var.enable_ecr_endpoint || var.enable_s3_endpoint
      error_message = "enable_ecr_endpoint requires enable_s3_endpoint so private image layer pulls can use the S3 gateway endpoint."
    }
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "${local.endpoint_service_prefix}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${replace(each.key, "_", "-")}-endpoint"
  })
}
