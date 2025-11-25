output "instance_ids" {
  description = "The IDs of all EC2 instances"
  value       = aws_instance.app_server[*].id
}

output "instance_public_ips" {
  description = "Public IP addresses of all EC2 instances"
  value       = aws_instance.app_server[*].public_ip
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app_lb.dns_name
}

output "alb_url" {
  description = "URL to access your application via ALB"
  value       = "http://${aws_lb.app_lb.dns_name}"
}

output "alb_url_with_port" {
  description = "URL to access your application via ALB on port 8081"
  value       = "http://${aws_lb.app_lb.dns_name}:${var.app_port}/hello"
}

output "ssh_commands" {
  description = "Commands to SSH into each instance"
  value = [
    for i in range(4) : "ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${aws_instance.app_server[i].public_ip}"
  ]
}

output "ec2_direct_urls" {
  description = "URLs to access each EC2 instance directly"
  value = [
    for i in range(4) : "http://${aws_instance.app_server[i].public_ip}:${var.app_port}/hello"
  ]
}

output "jenkins_instance_profile_name" {
  description = "IAM instance profile name to attach to Jenkins EC2 instance"
  value       = aws_iam_instance_profile.jenkins_instance_profile.name
}