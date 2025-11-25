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
    description = "Application Port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # WHAT: Allows HTTP traffic on port 8081 from anywhere
    # WHY: Users need to access Spring Boot application
    # WITHOUT: Application running but not accessible from internet
    # NOTE: 0.0.0.0/0 is appropriate for public web apps
    # FOR PRIVATE APPS: Restrict to VPN or specific IPs
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
  # WHAT: Creates EC2 virtual machine to run Docker containers
  # WHY: Hosts the Spring Boot application
  # WITHOUT: No server to deploy application to

  ami                    = var.ami_id
  # WHAT: Amazon Machine Image ID (operating system template)
  # WHY: EC2 needs base OS image to boot from
  # WITHOUT: Cannot launch EC2, no OS installed
  # NOTE: AMI IDs are region-specific
  # EXAMPLES:
  #   us-east-1: ami-0c55b159cbfafe1f0 (Amazon Linux 2)
  #   eu-west-1: ami-0d71ea30463e0ff8d (Amazon Linux 2)
  # FIND AMI: aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*"

  instance_type          = var.instance_type
  # WHAT: EC2 size/capacity (CPU, RAM, network)
  # WHY: Determines performance and cost
  # WITHOUT: Must specify, no default
  # EXAMPLES:
  #   t3.micro:  2 vCPU, 1 GB RAM, $0.0104/hour (Free Tier eligible)
  #   t3.small:  2 vCPU, 2 GB RAM, $0.0208/hour
  #   t3.medium: 2 vCPU, 4 GB RAM, $0.0416/hour
  # BEST PRACTICE: Start small (t3.micro), scale up if needed

  key_name               = aws_key_pair.ec2_key_pair.key_name
  # WHAT: Associates SSH key pair with EC2 instance
  # WHY: Enables SSH authentication using private key
  # WITHOUT: Cannot SSH to instance, deployment impossible
  # NOTE: Key pair must exist in same region as EC2

  vpc_security_group_ids = [aws_security_group.app_sg.id]
  # WHAT: Attaches security group firewall to EC2
  # WHY: Controls which traffic can reach EC2
  # WITHOUT: EC2 has no firewall rules, might use default (too restrictive)

  subnet_id = module.vpc.public_subnet_ids[0]
  # WHAT: Places EC2 in first public subnet from VPC module
  # WHY: Public subnet has internet access (needed for SSH, app access)
  # WITHOUT: EC2 placed in default subnet (might be private, no internet)
  # PRIVATE SUBNET: No direct internet access, requires NAT gateway
  # PUBLIC SUBNET: Direct internet access via Internet Gateway

  user_data = <<-EOF
              #!/bin/bash
              # WHAT: Script runs ONCE when EC2 first launches
              # WHY: Automates initial setup (install Docker, configure system)
              # WITHOUT: Must manually SSH and install Docker every time
              # NOTE: Runs as root user automatically

              set -e  # Exit on error
              # WHAT: Stops script if any command fails
              # WHY: Prevents continuing with broken state
              # WITHOUT: Script continues even if Docker install fails

              # Log everything
              exec > >(tee /var/log/user-data.log)
              exec 2>&1
              # WHAT: Saves script output to /var/log/user-data.log
              # WHY: Debugging - can review what happened during setup
              # WITHOUT: No logs, hard to troubleshoot setup failures

              echo "Starting Docker installation..."

              if command -v yum &> /dev/null; then
                # WHAT: Installs Docker on Amazon Linux / RHEL / CentOS
                # WHY: yum is package manager for these distros
                sudo yum update -y || echo "Yum update failed, continuing..."
                sudo yum install -y docker || { echo "Docker install failed!"; exit 1; }
              elif command -v apt-get &> /dev/null; then
                # WHAT: Installs Docker on Ubuntu / Debian
                # WHY: apt-get is package manager for these distros
                sudo apt-get update -y || echo "Apt update failed, continuing..."
                sudo apt-get install -y docker.io || { echo "Docker install failed!"; exit 1; }
              fi
              # WHAT: Detects OS and uses appropriate package manager
              # WHY: Makes script work on multiple Linux distributions
              # WITHOUT: Script only works on specific OS

              sudo systemctl enable docker
              # WHAT: Configures Docker to start automatically on boot
              # WHY: Ensures Docker runs after EC2 restarts
              # WITHOUT: Docker doesn't start after reboot, containers stop

              sudo systemctl start docker
              # WHAT: Starts Docker daemon immediately
              # WHY: Makes Docker available for use right away
              # WITHOUT: Docker installed but not running, cannot deploy

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
              # WHAT: Adds ec2-user to docker group
              # WHY: Allows running docker commands without sudo
              # WITHOUT: Must use sudo for every docker command
              # NOTE: Requires logout/login to take effect

              echo "✅ User-data script completed!"
            EOF
  # WHAT: End of user_data heredoc
  # WHY: Marks end of bash script
  # BEST PRACTICE: Keep user_data simple, complex setup better done via:
  #   - Ansible/Chef/Puppet
  #   - Pre-baked AMI with Docker installed
  #   - AWS Systems Manager Run Command

  tags = {
    Name = "${var.project_name}-server"
  }

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
  # WHAT: Attaches IAM role to EC2 instance
  # WHY: Grants EC2 permissions to use AWS services (SSM in this case)
  # WITHOUT: EC2 cannot be managed by Systems Manager
  # USE CASE: Allows AWS SSM Session Manager for secure shell access
  # BEST PRACTICE: Always use IAM roles, never hardcode AWS credentials on EC2
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

resource "aws_ssm_parameter" "ec2_instance_id" {
  # WHAT: Stores EC2 instance ID in Parameter Store
  # WHY: Jenkins can fetch current instance ID dynamically
  # WITHOUT: Must manually update instance ID in Jenkins after recreation

  name        = "/app/${var.project_name}/ec2/instance_id"
  description = "EC2 instance ID for ${var.project_name}"
  type        = "String"
  # WHAT: Plaintext parameter (not sensitive)
  # WHY: Instance ID is not secret, no encryption needed
  # WITHOUT: Still works, but wastes KMS decryption calls

  overwrite   = true
  value       = aws_instance.app_server.id
  # WHAT: EC2 instance ID (e.g., i-0123456789abcdef0)
  # WHY: Changes when EC2 recreated, this auto-updates
  # WITHOUT: Jenkins uses old instance ID, deployment fails

  tags = {
    Name = "${var.project_name}-ec2-instance-id"
  }
}

resource "aws_ssm_parameter" "ec2_public_ip" {
  # WHAT: Stores EC2 public IP address in Parameter Store
  # WHY: IP changes when EC2 stops/starts, Jenkins needs current IP
  # WITHOUT: Must manually update IP in Jenkins after every restart

  name        = "/app/${var.project_name}/ec2/public_ip"
  description = "EC2 instance public IP for ${var.project_name}"
  type        = "String"
  overwrite   = true
  value       = aws_instance.app_server.public_ip
  # WHAT: Public IP address (e.g., 54.123.45.67)
  # WHY: Required for SSH and HTTP access
  # WITHOUT: Jenkins cannot find EC2, deployment fails
  # NOTE: Public IP changes every time EC2 stops/starts
  # ALTERNATIVE: Use Elastic IP for static IP (costs $0.005/hour when not attached)

  tags = {
    Name = "${var.project_name}-ec2-public-ip"
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
