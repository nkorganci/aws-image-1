terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"

  name             = var.project_name
  vpc_cidr         = var.vpc_cidr
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  public_azs       = ["${var.aws_region}a", "${var.aws_region}b"]
  private_azs      = ["${var.aws_region}c", "${var.aws_region}d"]
}

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for application"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Application Port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_instance" "app_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.ec2_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  subnet_id = module.vpc.public_subnet_ids[0]

  user_data = <<-EOF
              #!/bin/bash
              set -e  # Exit on error

              # Log everything
              exec > >(tee /var/log/user-data.log)
              exec 2>&1

              echo "Starting Docker installation..."

              if command -v yum &> /dev/null; then
                sudo yum update -y || echo "Yum update failed, continuing..."
                sudo yum install -y docker || { echo "Docker install failed!"; exit 1; }
              elif command -v apt-get &> /dev/null; then
                sudo apt-get update -y || echo "Apt update failed, continuing..."
                sudo apt-get install -y docker.io || { echo "Docker install failed!"; exit 1; }
              fi

              sudo systemctl enable docker
              sudo systemctl start docker

              # Verify installation
              if command -v docker &> /dev/null; then
                echo "✅ Docker installed successfully!"
                docker --version
              else
                echo "❌ Docker installation failed!"
                exit 1
              fi

              # Add user to docker group
              sudo usermod -aG docker ec2-user || sudo usermod -aG docker ubuntu || true

              echo "✅ User-data script completed!"
            EOF

  tags = {
    Name = "${var.project_name}-server"
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/ec2-key.pem"
  file_permission = "0400"
}
