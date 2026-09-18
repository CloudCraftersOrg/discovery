data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "condor" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "condor-vpc"
  }
}

resource "aws_internet_gateway" "condor" {
  vpc_id = aws_vpc.condor.id

  tags = {
    Name = "condor-igw"
  }
}

# Public — NAT only, no workload (CLAUDE.md #4: nothing in the estate is
# reachable from the internet).
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.condor.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "condor-public-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.condor.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.condor.id
  }

  tags = {
    Name = "condor-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "condor-nat"
  }
}

# One NAT gateway, to save cost — same as the pre-consolidation design.
resource "aws_nat_gateway" "condor" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "condor-nat"
  }

  depends_on = [aws_internet_gateway.condor]
}

# app — the estate applications (Tienda, Pagos, Inventario, Facturación,
# Reportes, Jenkins).
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.condor.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "condor-app-${count.index}"
  }
}

# data — RDS/Aurora for the estate apps.
resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.condor.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20 + count.index)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "condor-data-${count.index}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.condor.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.condor.id
  }

  tags = {
    Name = "condor-private"
  }
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.private.id
}

# promo — ADR-044: stands in for the old second-region condor-promo VPC.
# Single AZ, isolated, no 0.0.0.0/0 route. Holds P1-12's planted findings
# (AK-COV-04, AK-INF-07, AK-PIP-08).
resource "aws_subnet" "promo" {
  vpc_id            = aws_vpc.condor.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 30)
  availability_zone = local.azs[0]

  tags = {
    Name = "condor-promo"
  }
}

resource "aws_route_table" "promo" {
  vpc_id = aws_vpc.condor.id

  tags = {
    Name = "condor-promo"
  }
}

resource "aws_route_table_association" "promo" {
  subnet_id      = aws_subnet.promo.id
  route_table_id = aws_route_table.promo.id
}

# 10.20.128.0/18: reserved for P2-01's platform subnets, deliberately absent below (ADR-044).
