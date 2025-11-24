output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.app_server.id
}

output "instance_public_ip" {
  description = "Public IP address to access the instance"
  value       = aws_instance.app_server.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.app_server.public_dns
}

output "private_key_path" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "ssm_private_key_name" {
  description = "SSM Parameter name that stores the EC2 private key (SecureString)"
  value       = aws_ssm_parameter.ec2_private_key.name
}

output "ssm_private_key_arn" {
  description = "ARN of the SSM Parameter that stores the EC2 private key"
  value       = aws_ssm_parameter.ec2_private_key.arn
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${aws_instance.app_server.public_ip}"
}

output "app_url" {
  description = "URL to access your application"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}"
}