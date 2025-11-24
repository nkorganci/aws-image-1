# Jenkins Automated Deployment Setup

This guide explains how to set up Jenkins for fully automated deployments without manual credential or instance ID management.

## Overview

The automation works by:
1. **Terraform** stores EC2 instance details (ID, IP, SSH key) in AWS Systems Manager (SSM) Parameter Store
2. **Jenkins** automatically fetches these values from SSM using an IAM role
3. **No manual updates** needed for instance IDs, IPs, or SSH keys

## Prerequisites

- Jenkins server running on an EC2 instance in AWS
- AWS CLI installed on Jenkins server
- Docker installed on Jenkins server
- Terraform applied to create infrastructure

## Setup Steps

### 1. Apply Terraform Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will create:
- EC2 instance for your application
- SSM parameters for instance ID, public IP, and SSH private key
- IAM role and instance profile for Jenkins

### 2. Attach IAM Role to Jenkins EC2 Instance

After Terraform completes, attach the IAM instance profile to your Jenkins EC2 instance:

**Option A: Using AWS Console**
1. Go to EC2 Console → Instances
2. Select your Jenkins instance
3. Actions → Security → Modify IAM role
4. Select the instance profile: `aws-image-1-jenkins-profile`
5. Click "Update IAM role"

**Option B: Using AWS CLI**
```bash
# Get the instance profile name from Terraform output
INSTANCE_PROFILE=$(terraform output -raw jenkins_instance_profile_name)

# Get your Jenkins instance ID
JENKINS_INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"  # Replace with your Jenkins instance ID

# Attach the instance profile
aws ec2 associate-iam-instance-profile \
  --instance-id $JENKINS_INSTANCE_ID \
  --iam-instance-profile Name=$INSTANCE_PROFILE
```

### 3. Verify AWS CLI Access on Jenkins

SSH into your Jenkins server and verify it can access SSM:

```bash
# Test SSM access
aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1

# If successful, you should see the public IP
```

If you get "Unable to locate credentials", the IAM role is not properly attached.

### 4. Configure Jenkins (One-Time Setup)

1. **Install Required Plugins** (if not already installed):
   - Docker Pipeline
   - Pipeline
   - Git

2. **Add Docker Hub Credentials**:
   - Go to Jenkins → Manage Jenkins → Credentials
   - Add credentials with ID: `dockerhub`
   - Type: Username with password
   - Username: your Docker Hub username
   - Password: your Docker Hub password/token

3. **Create Pipeline Job**:
   - New Item → Pipeline
   - Pipeline script from SCM
   - SCM: Git
   - Repository URL: https://github.com/nkorganci/aws-image-1.git
   - Branch: main
   - Script Path: Jenkinsfile

### 5. Remove Old AWS Credentials (Optional)

Since Jenkins now uses IAM roles, you can remove any manually configured AWS credentials:

1. Go to Jenkins → Manage Jenkins → Credentials
2. Delete the credential with ID `aws credential` (if it exists)
3. The Jenkinsfile no longer requires this

## How It Works

### Automatic Instance Discovery

The Jenkinsfile automatically:

1. **Fetches EC2 Public IP** from SSM:
   ```groovy
   env.DEPLOY_HOST = sh(
     script: "aws --region ${AWS_REGION} ssm get-parameter --name ${SSM_PARAM_PUBLIC_IP} --query Parameter.Value --output text",
     returnStdout: true
   ).trim()
   ```

2. **Fetches EC2 Instance ID** from SSM:
   ```groovy
   env.INSTANCE_ID = sh(
     script: "aws --region ${AWS_REGION} ssm get-parameter --name ${SSM_PARAM_INSTANCE_ID} --query Parameter.Value --output text",
     returnStdout: true
   ).trim()
   ```

3. **Fetches SSH Private Key** from SSM (encrypted):
   ```bash
   aws --region "$AWS_REGION" ssm get-parameter \
     --name "$SSM_PARAM_PRIVATE_KEY" \
     --with-decryption \
     --query Parameter.Value \
     --output text > ec2-key.pem
   ```

### Security Benefits

- ✅ **No hardcoded credentials** in Jenkins or code
- ✅ **SSH keys** stored encrypted in SSM (SecureString)
- ✅ **IAM role-based** authentication (temporary credentials)
- ✅ **Automatic rotation** when infrastructure is recreated
- ✅ **Least privilege** access (only SSM read permissions)

## Running Deployments

Simply trigger a Jenkins build:

1. Go to your Jenkins job
2. Click "Build Now"
3. Jenkins will automatically:
   - Checkout code
   - Build Maven application
   - Build Docker image
   - Push to Docker Hub
   - Fetch current EC2 IP and instance ID from SSM
   - Fetch SSH key from SSM
   - Deploy to the correct EC2 instance
   - Verify deployment

## Updating Infrastructure

If you recreate your EC2 instance:

```bash
cd terraform
terraform apply
```

**That's it!** The next Jenkins build will automatically:
- Pick up the new instance ID
- Use the new public IP
- Use the new SSH key

**No manual updates needed in Jenkins!**

## Troubleshooting

### Issue: Jenkins can't access SSM

**Symptom**: Error "Unable to locate credentials"

**Solution**:
- Verify IAM instance profile is attached to Jenkins EC2 instance
- Check IAM role has SSM permissions
- Restart Jenkins service after attaching role

### Issue: SSH connection fails

**Symptom**: "Permission denied (publickey)"

**Solution**:
- Verify SSH key is correctly stored in SSM
- Check security group allows SSH (port 22) from Jenkins IP
- Verify ec2-user exists on target instance

### Issue: Wrong IP address used

**Symptom**: Deployment tries to connect to old IP

**Solution**:
- Run `terraform apply` to update SSM parameters
- Check SSM Parameter Store has correct IP
- Verify Jenkins fetches IP dynamically in the pipeline

## SSM Parameter Paths

The following SSM parameters are automatically managed by Terraform:

- `/app/aws-image-1/ec2/private_key` - SSH private key (SecureString)
- `/app/aws-image-1/ec2/instance_id` - EC2 instance ID
- `/app/aws-image-1/ec2/public_ip` - EC2 public IP address

## IAM Permissions Required

The Jenkins IAM role has these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:us-east-1:*:parameter/app/aws-image-1/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    }
  ]
}
```

## Summary

✅ **No manual instance ID updates** - Fetched from SSM automatically
✅ **No manual IP updates** - Fetched from SSM automatically
✅ **No manual SSH key management** - Retrieved from SSM automatically
✅ **No AWS credentials in Jenkins** - Uses IAM role attached to EC2
✅ **Fully automated** - Just click "Build Now" in Jenkins

Your Jenkins pipeline is now fully automated! 🚀
