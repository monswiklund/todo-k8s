
data "aws_availability_zones" "azs" {}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.cluster_name}-vpc" }
}

# Public subnets (2 AZ)
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.azs.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                               = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private subnets (2 AZ)
resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.azs.names, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name                               = "${var.cluster_name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"  = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# IGW + NAT (1 NAT för kostnad)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.cluster_name}-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet[0].id
  tags = { Name = "${var.cluster_name}-nat" }
  depends_on = [aws_internet_gateway.igw]
}

# Routes
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  } 
  tags = { Name = "${var.cluster_name}-rt-public" }
}

resource "aws_route_table_association" "pub_assoc" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0" 
    nat_gateway_id = aws_nat_gateway.nat.id 
  }
  tags = { Name = "${var.cluster_name}-rt-private" }
}

resource "aws_route_table_association" "priv_assoc" {
  count          = length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private.id
}

# S3 Gateway Endpoint (spar NAT-kostnad och ökar säkerhet)
resource "aws_vpc_endpoint" "s3" {
  vpc_id         = aws_vpc.main.id
  service_name   = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.public.id, aws_route_table.private.id]
  tags = { Name = "${var.cluster_name}-vpce-s3" }
}
