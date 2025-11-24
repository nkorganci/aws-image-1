// filepath: d:\workspace\aws-image-1\terraform\modules\vpc\main.tf
// Reusable VPC module: creates VPC, public/private subnets across AZs, IGW, NAT Gateway(s), route tables

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${var.name}-igw" }
}

// Create public subnets (count ensures numeric indexing)
resource "aws_subnet" "public" {
  count                  = length(var.public_subnets)
  vpc_id                 = aws_vpc.this.id
  cidr_block             = var.public_subnets[count.index]
  availability_zone      = var.public_azs[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.name}-public-${count.index}" }
}

// Create private subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.private_azs[count.index]
  tags = { Name = "${var.name}-private-${count.index}" }
}

// Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

// Associate public subnets to public route table
resource "aws_route_table_association" "public_assoc" {
  count = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

// Allocate one Elastic IP for NAT Gateway (single NAT for simplicity)
resource "aws_eip" "nat" {
  vpc = true
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "${var.name}-nat" }
  depends_on = [aws_internet_gateway.this]
}

// Private route table - route 0.0.0.0/0 to NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  count = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
