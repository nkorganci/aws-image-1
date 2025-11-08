
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws" }
    tls = { source = "hashicorp/tls" }
    random = { source = "hashicorp/random" }
    local = { source = "hashicorp/local" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "random_id" "key" {
  byte_length = 4
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "terraform-key-${random_id.key.hex}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/id_rsa_terraform_${random_id.key.hex}"
  file_permission = "0400"
}

resource "aws_security_group" "ssh" {
  name        = "allow-ssh-${random_id.key.hex}"
  description = "Allow SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet_ids.default.ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  key_name                    = aws_key_pair.generated.key_name

  tags = {
    Name = "hello-ec2"
  }

  user_data = <<-EOF
    #!/bin/bash
    # minimal bootstrap (optional)
    yum update -y
  EOF
}

output "instance_public_ip" {
  value = aws_instance.web.public_ip
}

output "ssh_private_key_file" {
  value = local_file.private_key.filename
}
