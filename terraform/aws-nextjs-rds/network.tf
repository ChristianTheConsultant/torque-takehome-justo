# A dedicated, minimal VPC: no NAT gateway (the single biggest hidden cost
# in demo VPCs). EC2 sits in a public subnet with a public IP; RDS sits in
# private subnets that have no route to the internet at all.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # RDS subnet groups require at least two AZs even for single-AZ instances.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  tags = { Name = "${var.name_prefix}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets fall back to the VPC main route table (local routes only).

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web"
  description = "Next.js app on EC2"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-web" }
}

resource "aws_vpc_security_group_ingress_rule" "web_app" {
  security_group_id = aws_security_group.web.id
  description       = "Next.js HTTP"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
}

# Outbound is needed at boot for dnf, nodejs.org, the npm registry, git and
# the SSM API.
resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db"
  description = "PostgreSQL, reachable only from the web tier"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from web tier"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
