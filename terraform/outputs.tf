output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.app_server.id
}

output "instance_public_ip" {
  description = "Public IP address to access the instance"
  value       = aws_instance.app_server.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${aws_instance.app_server.public_ip}"
}

output "app_url" {
  description = "URL to access your application"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}"
}

output "jenkins_instance_profile_name" {
  description = "IAM instance profile name to attach to Jenkins EC2 instance"
  value       = aws_iam_instance_profile.jenkins_instance_profile.name
}