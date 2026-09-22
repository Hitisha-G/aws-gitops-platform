locals {
  az_count       = length(var.availability_zones)
  subnet_newbits = 4
  name_prefix    = var.project_name

  # Map AZ name -> index so for_each keys stay stable across plan/apply.
  az_index = {
    for idx, az in var.availability_zones : az => idx
  }

  public_subnet_cidrs = {
    for az, idx in local.az_index :
    az => cidrsubnet(var.vpc_cidr, local.subnet_newbits, idx)
  }

  private_subnet_cidrs = {
    for az, idx in local.az_index :
    az => cidrsubnet(var.vpc_cidr, local.subnet_newbits, idx + local.az_count)
  }

  common_tags = merge(var.tags, {
    Project = var.project_name
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[each.key]
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${each.value + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[each.key]
  availability_zone = each.key

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${each.value + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = local.az_index

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = local.az_index

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}
