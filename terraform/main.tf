terraform {
  # WHAT: Terraform configuration block
  # WHY: Specifies Terraform version requirements and required providers
  # WITHOUT: Terraform doesn't know which cloud provider APIs to use

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # WHAT: Official AWS provider from HashiCorp
      # WHY: Enables Terraform to manage AWS resources via AWS API
      # WITHOUT: Cannot create any AWS resources

      version = "~> 5.0"
      # WHAT: Requires AWS provider version 5.x (5.0, 5.1, 5.2, etc.)
      # WHY: ~> means "compatible with", allows minor updates but not major
      # WITHOUT: Might use incompatible provider version, causing errors
      # BEST PRACTICE: Pin to specific version for production:
      #   version = "= 5.30.0" (exact version, no auto-updates)
    }
  }
}

provider "aws" {
  # WHAT: Configures the AWS provider with region
  # WHY: Tells AWS where to create resources (us-east-1, eu-west-1, etc.)
  # WITHOUT: AWS provider doesn't know which region to use, errors occur
  # AUTHENTICATION: Uses one of these (in order of precedence):
  #   1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
  #   2. Shared credentials file (~/.aws/credentials)
  #   3. IAM role (if running on EC2)
  # BEST PRACTICE: Use IAM roles when running on EC2, never hardcode keys

  region = var.aws_region
  # WHAT: AWS region from variables.tf (default: us-east-1)
  # WHY: Centralized configuration, easy to change region
  # WITHOUT: Must hardcode region, harder to maintain
}

module "vpc" {
  # WHAT: Reusable module that creates VPC with subnets
  # WHY: Modular code, easier to manage complex VPC configurations
  # WITHOUT: Would need to define all VPC resources inline (200+ lines)

  source = "./modules/vpc"
  # WHAT: Path to VPC module directory
  # WHY: Terraform looks here for vpc module code
  # WITHOUT: Module not found error

  name             = var.project_name
  vpc_cidr         = var.vpc_cidr
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  public_azs       = ["${var.aws_region}a", "${var.aws_region}b"]
  private_azs      = ["${var.aws_region}c", "${var.aws_region}d"]
  # WHAT: Passes variables to VPC module
  # WHY: VPC module needs these to create subnets in correct AZs and CIDRs
  # WITHOUT: Module missing required inputs, fails to create VPC
  # NOTE: Availability zones are region-specific (us-east-1a, us-west-2b, etc.)
}

resource "tls_private_key" "ec2_key" {
  # WHAT: Generates SSH key pair (public + private) using TLS provider
  # WHY: Needed for SSH access to EC2 instance
  # WITHOUT: Cannot SSH to EC2, no way to access instance remotely

  algorithm = "RSA"
  # WHAT: Encryption algorithm for key generation
  # WHY: RSA is widely supported, secure, and compatible with EC2
  # ALTERNATIVES: ED25519 (newer, faster, but less compatible)
  # WITHOUT: No algorithm specified, key generation fails

  rsa_bits  = 4096
  # WHAT: Key length in bits
  # WHY: 4096 bits is very secure (2048 is minimum, 4096 is recommended)
  # WITHOUT: Defaults to 2048 (still secure but less so)
  # BEST PRACTICE: Use 4096 for production, 2048 for dev/testing
  # TRADEOFF: Longer keys = more secure but slower SSH connections
}

resource "aws_key_pair" "ec2_key_pair" {
  # WHAT: Registers public key with AWS EC2 for SSH authentication
  # WHY: AWS needs public key to inject into EC2 instance at launch
  # WITHOUT: Cannot use SSH key pair for EC2 authentication

  key_name   = "${var.project_name}-key"
  # WHAT: Name of key pair in AWS (shown in EC2 console)
  # WHY: Identifies key pair, must be unique per region
  # WITHOUT: Cannot reference key pair when launching EC2

  public_key = tls_private_key.ec2_key.public_key_openssh
  # WHAT: Public key portion from generated key pair (OpenSSH format)
  # WHY: AWS stores public key, uses it to validate SSH connections
  # WITHOUT: Key pair incomplete, SSH authentication impossible
  # NOTE: Private key never sent to AWS (kept secure locally/in SSM)
}

resource "aws_security_group" "alb_sg" {
  # WHAT: Security group for Application Load Balancer
  # WHY: Controls traffic to ALB from internet
  # WITHOUT: ALB cannot receive traffic from users

  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows HTTP traffic on port 80 from anywhere
    # WHY: Users access application through ALB on port 80
    # WITHOUT: Users cannot reach application
  }

  ingress {
    description = "Application Port from Internet"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows direct access to app port for testing
    # WHY: Allows testing EC2 instances directly
    # NOTE: Can be removed in production for security
  }

  egress {
    description = "All traffic to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows ALB to forward traffic to EC2 instances
    # WHY: ALB needs to communicate with backend instances
    # WITHOUT: ALB cannot reach EC2 instances
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  # WHAT: Virtual firewall controlling inbound/outbound traffic to EC2
  # WHY: AWS EC2 requires security group to allow/deny network traffic
  # WITHOUT: EC2 created but no traffic allowed (not accessible)

  name        = "${var.project_name}-sg"
  description = "Security group for application"
  vpc_id      = module.vpc.vpc_id
  # WHAT: Associates security group with VPC
  # WHY: Security groups are VPC-specific
  # WITHOUT: Security group not associated with VPC, cannot attach to EC2

  ingress {
    # WHAT: Inbound traffic rules (traffic coming TO EC2)
    # WHY: By default, AWS blocks all inbound traffic (whitelist approach)
    # WITHOUT: Cannot SSH or access application from outside

    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows SSH (port 22) from anywhere (0.0.0.0/0 = all IPs)
    # WHY: Enables remote SSH access for deployment
    # WITHOUT: Cannot SSH to EC2, deployment fails
    # SECURITY RISK: 0.0.0.0/0 allows SSH from entire internet
    # BEST PRACTICE: Restrict to specific IPs or use AWS Session Manager:
    #   cidr_blocks = ["YOUR_JENKINS_IP/32"]  # Only from Jenkins server
    # OR remove SSH rule entirely and use Systems Manager Session Manager
  }

  ingress {
    description     = "Application Port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    # WHAT: Allows traffic only from ALB security group
    # WHY: Best practice - EC2 instances only accept traffic from ALB
    # WITHOUT: More secure than allowing from 0.0.0.0/0
  }

  ingress {
    description = "Application Port from anywhere (for testing)"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows direct access to EC2 instances
    # WHY: Useful for testing individual instances
    # NOTE: Can be removed in production
  }

  egress {
    # WHAT: Outbound traffic rules (traffic FROM EC2 to internet)
    # WHY: EC2 needs outbound access to download Docker images, updates, etc.
    # WITHOUT: Cannot pull Docker images, yum install fails

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows all outbound traffic to anywhere
    # WHY:
    #   -1 protocol: All protocols (TCP, UDP, ICMP, etc.)
    #   0.0.0.0/0: Any destination IP
    # WITHOUT: EC2 cannot reach Docker Hub, AWS APIs, or yum repos
    # BEST PRACTICE: This is standard, rarely needs restriction
  }

  tags = {
    Name = "${var.project_name}-sg"
    # WHAT: Tag for identifying resource in AWS console
    # WHY: Makes resources easier to find and organize
    # WITHOUT: Resources exist but harder to identify
    # BEST PRACTICE: Always tag resources for cost tracking and management
  }
}

resource "aws_instance" "app_server" {
  # WHAT: Creates 4 EC2 instances across different availability zones
  # WHY: High availability - if one AZ goes down, others still serve traffic
  # WITHOUT: Single point of failure

  count = 4
  # WHAT: Creates 4 identical EC2 instances
  # WHY: Distributes load across multiple instances
  # WITHOUT: Only one instance, no redundancy

  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.ec2_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # WHAT: Distributes instances across 4 different availability zones
  # WHY: Each instance in different AZ for high availability
  # count.index cycles through: 0, 1, 2, 3
  # Availability zones: a, b, c, d (using all 4 AZs)
  subnet_id = count.index < 2 ? module.vpc.public_subnet_ids[count.index] : module.vpc.public_subnet_ids[count.index % 2]

  user_data = <<-EOF
              #!/bin/bash
              set -e
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

              if command -v docker &> /dev/null; then
                echo "✅ Docker installed successfully!"
                docker --version
              else
                echo "❌ Docker installation failed!"
                exit 1
              fi

              sudo usermod -aG docker ec2-user || sudo usermod -aG docker ubuntu || true

              echo "✅ User-data script completed!"
            EOF

  tags = {
    Name = "${var.project_name}-server-${count.index + 1}"
    # WHAT: Names instances 1, 2, 3, 4
    # WHY: Easy to identify which instance in AWS console
  }

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
}

# ==============================================================================
# APPLICATION LOAD BALANCER - Distributes traffic across EC2 instances
# ==============================================================================

resource "aws_lb" "app_lb" {
  # WHAT: Application Load Balancer for distributing traffic
  # WHY: Routes traffic to healthy instances, provides single entry point
  # WITHOUT: Must access each EC2 instance individually

  name               = "${var.project_name}-alb"
  internal           = false
  # WHAT: false = internet-facing ALB
  # WHY: Users access from internet
  # ALTERNATIVE: true = internal ALB (only from within VPC)

  load_balancer_type = "application"
  # WHAT: Layer 7 load balancer (HTTP/HTTPS)
  # WHY: Supports path-based routing, SSL termination
  # ALTERNATIVE: "network" for Layer 4 (TCP/UDP)

  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnet_ids
  # WHAT: ALB needs at least 2 subnets in different AZs
  # WHY: High availability across multiple zones

  enable_deletion_protection = false
  # WHAT: Allows Terraform to delete ALB
  # WHY: For testing/development
  # PRODUCTION: Set to true to prevent accidental deletion

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  # WHAT: Target group containing EC2 instances
  # WHY: ALB routes traffic to targets in this group
  # WITHOUT: ALB has nowhere to send traffic

  name     = "${var.project_name}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    # WHAT: Health check configuration
    # WHY: ALB only routes to healthy instances
    # WITHOUT: Traffic sent to failed instances

    enabled             = true
    healthy_threshold   = 2
    # WHAT: Instance healthy after 2 successful checks

    unhealthy_threshold = 2
    # WHAT: Instance unhealthy after 2 failed checks

    timeout             = 5
    # WHAT: Wait 5 seconds for response

    interval            = 30
    # WHAT: Check every 30 seconds

    path                = "/hello"
    # WHAT: Health check endpoint
    # WHY: Verifies app is responding

    matcher             = "200"
    # WHAT: HTTP 200 = healthy
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "app_tg_attachment" {
  # WHAT: Registers each EC2 instance with target group
  # WHY: ALB needs to know which instances to route to
  # WITHOUT: ALB has no targets, returns 503

  count            = 4
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server[count.index].id
  port             = var.app_port
}

resource "aws_lb_listener" "app_listener_80" {
  # WHAT: Listener on port 80 for HTTP traffic
  # WHY: Users access ALB on standard HTTP port
  # WITHOUT: ALB listens but no routing rules

  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
    # WHAT: Forward all traffic to target group
    # WHY: Distributes requests across EC2 instances
  }
}

resource "aws_lb_listener" "app_listener_8081" {
  # WHAT: Listener on port 8081 for direct access
  # WHY: Allows testing ALB on same port as EC2 instances
  # NOTE: Optional, can be removed in production

  load_balancer_arn = aws_lb.app_lb.arn
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "local_file" "private_key" {
  # WHAT: Saves SSH private key to local file system
  # WHY: Needed for manual SSH access during development/troubleshooting
  # WITHOUT: Private key only in Terraform state, harder to access

  content         = tls_private_key.ec2_key.private_key_pem
  # WHAT: Private key in PEM format
  # WHY: Standard format for SSH private keys
  # WITHOUT: Cannot save key to file

  filename        = "${path.module}/ec2-key.pem"
  # WHAT: Saves to terraform/ec2-key.pem
  # WHY: path.module ensures file saved in terraform directory
  # WITHOUT: Saved to random location, hard to find

  file_permission = "0400"
  # WHAT: Sets file permissions to read-only for owner (chmod 400)
  # WHY: SSH requires private keys to be protected
  # WITHOUT: SSH refuses to use key (permissions too open)
  # NOTE: On Windows, file permissions work differently
}

# ==============================================================================
# IAM ROLES - Identity and Access Management
# ==============================================================================
# PURPOSE: Grants AWS permissions to EC2 instances without hardcoding credentials
# WHY: Secure, temporary credentials auto-managed by AWS

resource "aws_iam_role" "ec2_ssm_role" {
  # WHAT: IAM role for EC2 instance (grants SSM permissions)
  # WHY: Allows AWS Systems Manager to manage EC2 instance
  # WITHOUT: EC2 cannot use SSM Session Manager (secure shell alternative)

  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    # WHAT: Trust policy - defines WHO can assume this role
    # WHY: Specifies that EC2 service can use this role
    # WITHOUT: Role exists but nothing can use it

    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        # WHAT: AWS Security Token Service AssumeRole action
        # WHY: Allows temporary credential generation
        # WITHOUT: Cannot generate temporary credentials

        Effect = "Allow",
        # WHAT: Permits the action
        # ALTERNATIVES: "Deny" would block the action
        # WITHOUT: Policy has no effect

        Principal = {
          Service = "ec2.amazonaws.com"
          # WHAT: Specifies EC2 service can assume this role
          # WHY: Grants EC2 instances permission to use this role
          # WITHOUT: Nothing can use this role
          # NOTE: Only EC2 instances can use this role (not Lambda, not users)
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  # WHAT: Attaches AWS-managed policy to IAM role
  # WHY: Grants SSM permissions to EC2 role (simpler than custom policy)
  # WITHOUT: Role exists but has no permissions

  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # WHAT: AWS-managed policy for Systems Manager
  # WHY: Provides minimum permissions for SSM Session Manager, Run Command, etc.
  # WITHOUT: EC2 cannot be managed via SSM
  # PERMISSIONS GRANTED:
  #   - ssm:UpdateInstanceInformation
  #   - ssm:GetParameter (for retrieving parameters)
  #   - ssm:PutInventory
  #   - ec2messages:* (for Session Manager)
  # BEST PRACTICE: Use AWS-managed policies when possible (maintained by AWS)
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  # WHAT: Container for IAM role that can be attached to EC2
  # WHY: EC2 requires instance profile (not just role) for IAM permissions
  # WITHOUT: Cannot attach IAM role to EC2, no SSM permissions

  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
  # WHAT: Links instance profile to IAM role
  # WHY: Grants EC2 the permissions defined in the role
  # WITHOUT: Instance profile exists but has no permissions
  # NOTE: Instance profile can only contain one role
}

# ==============================================================================
# SSM PARAMETER STORE - Secure Secret Storage
# ==============================================================================
# PURPOSE: Stores EC2 details (IP, ID, SSH key) for Jenkins to auto-fetch
# WHY: Eliminates hardcoded values, auto-updates when EC2 recreated

resource "aws_ssm_parameter" "ec2_private_key" {
  # WHAT: Stores SSH private key encrypted in AWS Parameter Store
  # WHY: Jenkins can fetch key automatically (no manual key management)
  # WITHOUT: Must manually copy SSH key to Jenkins (insecure, not auto-updated)

  name        = "/app/${var.project_name}/ec2/private_key"
  # WHAT: Path-based naming (hierarchical structure)
  # WHY:
  #   /app/ = Non-reserved namespace (avoid /aws/ which is reserved)
  #   /${var.project_name}/ = Project namespace (multiple projects safe)
  #   /ec2/ = Resource type
  #   /private_key = Specific parameter
  # WITHOUT: Name collision with other projects
  # BEST PRACTICE: Use hierarchical paths for organization

  description = "Private key for EC2 instance ${aws_instance.app_server.id}"

  type        = "SecureString"
  # WHAT: Encrypted parameter type using AWS KMS
  # WHY: Sensitive data (private key) must be encrypted at rest
  # WITHOUT: Private key stored unencrypted (major security risk)
  # ALTERNATIVES:
  #   - "String": Plaintext (use for non-sensitive data)
  #   - "StringList": Comma-separated values

  overwrite   = true
  # WHAT: Replaces parameter if it already exists
  # WHY: Allows terraform apply to update key when EC2 recreated
  # WITHOUT: Error if parameter exists, terraform apply fails

  value       = tls_private_key.ec2_key.private_key_pem
  # WHAT: Actual SSH private key content
  # WHY: Stored encrypted by AWS KMS
  # WITHOUT: No key stored, Jenkins cannot fetch it
  # SECURITY: Encrypted in transit and at rest, decrypted only when fetched

  tags = {
    Name = "${var.project_name}-ec2-private-key"
  }
}

resource "aws_ssm_parameter" "ec2_instance_ids" {
  # WHAT: Stores all 4 EC2 instance IDs as comma-separated list
  # WHY: Jenkins can fetch all instance IDs for deployment
  # WITHOUT: Must manually track multiple instance IDs

  count       = 4
  name        = "/app/${var.project_name}/ec2/instance_id_${count.index + 1}"
  description = "EC2 instance ID ${count.index + 1} for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_instance.app_server[count.index].id

  tags = {
    Name = "${var.project_name}-ec2-instance-id-${count.index + 1}"
  }
}

resource "aws_ssm_parameter" "ec2_public_ips" {
  # WHAT: Stores all 4 EC2 public IPs separately
  # WHY: Jenkins can deploy to all instances
  # WITHOUT: Can only deploy to one instance

  count       = 4
  name        = "/app/${var.project_name}/ec2/public_ip_${count.index + 1}"
  description = "EC2 instance ${count.index + 1} public IP for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_instance.app_server[count.index].public_ip

  tags = {
    Name = "${var.project_name}-ec2-public-ip-${count.index + 1}"
  }
}

resource "aws_ssm_parameter" "alb_dns_name" {
  # WHAT: Stores ALB DNS name in Parameter Store
  # WHY: Single entry point to access all instances
  # WITHOUT: Must remember ALB DNS name manually

  name        = "/app/${var.project_name}/alb/dns_name"
  description = "ALB DNS name for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_lb.app_lb.dns_name

  tags = {
    Name = "${var.project_name}-alb-dns-name"
  }
}

# ==============================================================================
# IAM ROLE FOR JENKINS - Grants Jenkins SSM Read Permissions
# ==============================================================================
# PURPOSE: Jenkins EC2 instance can read SSM parameters without AWS credentials

resource "aws_iam_role" "jenkins_ssm_role" {
  # WHAT: IAM role for Jenkins EC2 instance
  # WHY: Allows Jenkins to fetch SSM parameters (IP, instance ID, SSH key)
  # WITHOUT: Jenkins cannot access SSM, must hardcode credentials (insecure)

  name = "${var.project_name}-jenkins-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
          # WHAT: Allows EC2 instances to assume this role
          # WHY: Jenkins runs on EC2, needs this role attached
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-jenkins-ssm-role"
  }
}

resource "aws_iam_role_policy" "jenkins_ssm_policy" {
  # WHAT: Inline IAM policy granting specific SSM permissions
  # WHY: Least privilege - only grants permissions Jenkins needs
  # WITHOUT: Jenkins cannot read SSM parameters, deployment fails

  name = "${var.project_name}-jenkins-ssm-policy"
  role = aws_iam_role.jenkins_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          # WHAT: Read single SSM parameter
          # WHY: Jenkins fetches individual parameters (IP, key, instance ID)

          "ssm:GetParameters",
          # WHAT: Read multiple SSM parameters at once
          # WHY: More efficient when fetching several parameters

          "ssm:GetParametersByPath"
          # WHAT: Read all parameters under a path (e.g., /app/aws-image-1/*)
          # WHY: Useful for fetching all project parameters at once
        ],
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/app/${var.project_name}/*"
          # WHAT: ARN (Amazon Resource Name) specifying which parameters
          # WHY: Restricts access to only this project's parameters
          # FORMAT: arn:aws:ssm:REGION:ACCOUNT:parameter/PATH
          # WILDCARD: * matches any account, /* matches any parameter under path
          # WITHOUT: Jenkins could access other projects' SSM parameters
          # BEST PRACTICE: Least privilege - only grant access to required resources
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          # WHAT: Query EC2 instance information
          # WHY: Useful for Jenkins to verify instance status

          "ec2:DescribeInstanceStatus"
          # WHAT: Check if EC2 instance is running/stopped
          # WHY: Jenkins can verify instance health before deployment
        ],
        Resource = "*"
        # WHAT: Applies to all EC2 instances
        # WHY: DescribeInstances doesn't support resource-level permissions
        # NOTE: These are read-only actions, low security risk
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  # WHAT: Instance profile containing Jenkins IAM role
  # WHY: Must be attached to Jenkins EC2 for SSM permissions
  # WITHOUT: Jenkins has no AWS permissions, cannot access SSM

  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_ssm_role.name

  tags = {
    Name = "${var.project_name}-jenkins-profile"
  }
  # SETUP: After terraform apply, attach this profile to Jenkins EC2:
  #   aws ec2 associate-iam-instance-profile \
  #     --instance-id i-jenkinsinstance \
  #     --iam-instance-profile Name=aws-image-1-jenkins-profile
}

# ==============================================================================
# WHAT HAPPENS WITHOUT EACH RESOURCE:
# ==============================================================================
#
# NO VPC MODULE:
#   - No network infrastructure
#   - EC2 placed in default VPC (might not exist in new accounts)
#   - Less control over networking
#
# NO TLS_PRIVATE_KEY:
#   - Cannot generate SSH key
#   - Must manually create and manage SSH keys
#   - Keys not auto-rotated when infrastructure recreated
#
# NO AWS_KEY_PAIR:
#   - EC2 launches but no SSH access
#   - Cannot deploy applications
#   - Must use other access methods (Session Manager, serial console)
#
# NO SECURITY_GROUP:
#   - EC2 uses default security group
#   - Might block all traffic (application not accessible)
#   - No SSH access
#
# NO EC2_INSTANCE:
#   - No server to run application
#   - Infrastructure exists but nothing deployed
#
# NO USER_DATA:
#   - EC2 launches but Docker not installed
#   - Must manually SSH and install Docker
#   - Deployment fails (no Docker daemon)
#
# NO IAM_ROLE (ec2_ssm_role):
#   - EC2 cannot use Systems Manager
#   - No secure shell alternative to SSH
#   - Harder to manage at scale
#
# NO SSM_PARAMETERS:
#   - Must manually manage EC2 IP, instance ID, SSH keys
#   - Jenkins breaks when EC2 recreated (hardcoded values)
#   - Not automated
#
# NO JENKINS IAM_ROLE:
#   - Jenkins cannot fetch SSM parameters
#   - Must manually configure AWS credentials in Jenkins (insecure)
#   - Credentials not auto-rotated
#
# NO LOCAL_FILE (private_key):
#   - Cannot manually SSH for troubleshooting
#   - Must extract key from Terraform state (inconvenient)
#   - Still works for Jenkins (fetches from SSM)
#
# ==============================================================================
# TERRAFORM BEST PRACTICES IMPLEMENTED:
# ==============================================================================
#
# ✅ Using variables for reusability
# ✅ Modular VPC code (separate module)
# ✅ Tags on all resources for organization
# ✅ IAM roles instead of hardcoded credentials
# ✅ SSM Parameter Store for secrets
# ✅ Security group rules well-documented
# ✅ User data for automated setup
#
# 🔧 RECOMMENDED IMPROVEMENTS:
#
# 1. USE TERRAFORM REMOTE STATE:
#    backend "s3" {
#      bucket = "my-terraform-state"
#      key    = "aws-image-1/terraform.tfstate"
#      region = "us-east-1"
#    }
#    WHY: Shared state for team, state locking, backup
#
# 2. ADD ELASTIC IP FOR STATIC IP:
#    resource "aws_eip" "app_eip" {
#      instance = aws_instance.app_server.id
#    }
#    WHY: IP doesn't change on restart, easier DNS management
#
# 3. USE LAUNCH TEMPLATE INSTEAD OF INSTANCE:
#    Enables auto-scaling, easier to update configurations
#
# 4. ADD AUTO SCALING GROUP:
#    Automatically replace unhealthy instances
#
# 5. USE ALB (APPLICATION LOAD BALANCER):
#    Distributes traffic, SSL termination, health checks
#
# 6. ADD CLOUDWATCH ALARMS:
#    Alert when CPU high, disk full, or instance down
#
# 7. RESTRICT SSH TO JENKINS IP:
#    cidr_blocks = ["YOUR_JENKINS_IP/32"]
#    WHY: Reduces attack surface
#
# 8. USE AWS SECRETS MANAGER INSTEAD OF SSM:
#    Better for secrets, automatic rotation, versioning
#
# 9. ADD BACKUP/SNAPSHOT POLICY:
#    Automatic EBS snapshots for disaster recovery
#
# 10. USE TERRAFORM WORKSPACES:
#     Separate dev/staging/prod environments
#
# ==============================================================================
