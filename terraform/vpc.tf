resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # required: EKS nodes need DNS resolution
  enable_dns_support   = true # required: for internal AWS service endpoints

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Public Subnets (one per AZ)
resource "aws_subnet" "public" {
  count = 3 # one per AZ for HA

  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  # cidrsubnet("10.0.0.0/16", 8, 1) → "10.0.1.0/24"
  # cidrsubnet("10.0.0.0/16", 8, 2) → "10.0.2.0/24"  etc.
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index + 1}"
    # Required for AWS Load Balancer Controller (internet-facing LBs)
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private Subnets (one per AZ)
resource "aws_subnet" "private" {
  count = 3

  vpc_id     = aws_vpc.main.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  # 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
  availability_zone = data.aws_availability_zones.azs.names[count.index]

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
    # Required for AWS Load Balancer Controller (internal LBs)
    "kubernetes.io/role/internal-elb" = "1"
    # Required for EKS to discover subnets for node placement
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Internet Gateway (provides public internet access for the VPC)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# NAT Gateway (one per AZ for HA, or one to save cost in dev)
# Using one NAT GW for dev - change count to 3 for production
resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }
}

# == Route Tables ==

# Public route table: all traffic → Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table: outbound traffic → NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.main[0].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}