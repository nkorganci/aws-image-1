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

  # Attach the IAM instance profile that allows SSM to manage the instance
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/ec2-key.pem"
  file_permission = "0400"
}

# Add IAM role for EC2 to allow AWS Systems Manager
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Store the generated private key into SSM Parameter Store (SecureString)
resource "aws_ssm_parameter" "ec2_private_key" {
  # Avoid using a top-level token that starts with the reserved prefix 'aws'.
  # Use a non-reserved top-level namespace (for example: /app/<project>/...)
  name        = "/app/${var.project_name}/ec2/private_key"
  description = "Private key for EC2 instance ${aws_instance.app_server.id}"
  type        = "SecureString"
  overwrite   = true
  value       = tls_private_key.ec2_key.private_key_pem

  tags = {
    Name = "${var.project_name}-ec2-private-key"
  }
}

# Store the EC2 instance ID in SSM Parameter Store for Jenkins
resource "aws_ssm_parameter" "ec2_instance_id" {
  name        = "/app/${var.project_name}/ec2/instance_id"
  description = "EC2 instance ID for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_instance.app_server.id

  tags = {
    Name = "${var.project_name}-ec2-instance-id"
  }
}

# Store the EC2 instance public IP in SSM Parameter Store for Jenkins
resource "aws_ssm_parameter" "ec2_public_ip" {
  name        = "/app/${var.project_name}/ec2/public_ip"
  description = "EC2 instance public IP for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_instance.app_server.public_ip

  tags = {
    Name = "${var.project_name}-ec2-public-ip"
  }
}

# IAM role for Jenkins server to access SSM parameters
resource "aws_iam_role" "jenkins_ssm_role" {
  name = "${var.project_name}-jenkins-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-jenkins-ssm-role"
  }
}

# IAM policy for Jenkins to read SSM parameters
resource "aws_iam_role_policy" "jenkins_ssm_policy" {
  name = "${var.project_name}-jenkins-ssm-policy"
  role = aws_iam_role.jenkins_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/app/${var.project_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile for Jenkins server
resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_ssm_role.name

  tags = {
    Name = "${var.project_name}-jenkins-profile"
  }
}
