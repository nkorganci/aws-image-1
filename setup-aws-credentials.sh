#!/bin/bash
# ==============================================================================
# SETUP AWS CREDENTIALS ON JENKINS SERVER
# ==============================================================================
#
# PURPOSE: Configure AWS credentials on Jenkins EC2 server so the pipeline
#          can access AWS services (SSM, EC2, etc.)
#
# USAGE: Run this script on your LOCAL machine, it will SSH to Jenkins and
#        configure AWS credentials there
#
# ==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

echo "===================================================================="
echo "  AWS Credentials Setup for Jenkins Server"
echo "===================================================================="
echo ""

# Check if SSH key exists
if [ ! -f "terraform/ec2-key.pem" ]; then
    echo -e "${RED}❌ SSH key not found at terraform/ec2-key.pem${NC}"
    echo ""
    echo "Please run 'terraform apply' first to generate the SSH key."
    exit 1
fi

# Get Jenkins instance details
echo "Getting Jenkins instance details from Terraform..."
cd terraform

JENKINS_IP=$(terraform output -raw instance_public_ip 2>/dev/null)
if [ -z "$JENKINS_IP" ]; then
    echo -e "${RED}❌ Could not get Jenkins IP from Terraform${NC}"
    echo "Make sure you have run 'terraform apply'"
    exit 1
fi

cd ..

echo -e "${GREEN}✅ Jenkins IP:${NC} $JENKINS_IP"
echo ""

# Test SSH connection
echo "Testing SSH connection to Jenkins..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i terraform/ec2-key.pem ec2-user@$JENKINS_IP "echo 'SSH connection successful'" &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Jenkins server${NC}"
    echo "Make sure:"
    echo "  1. Jenkins EC2 instance is running"
    echo "  2. Security group allows SSH from your IP"
    echo "  3. SSH key permissions are correct (chmod 400 terraform/ec2-key.pem)"
    exit 1
fi
echo -e "${GREEN}✅ SSH connection successful${NC}"
echo ""

# Get AWS credentials from user
echo "===================================================================="
echo "  Enter Your AWS Credentials"
echo "===================================================================="
echo ""
echo "You can find your AWS credentials at:"
echo "  • AWS Console → IAM → Users → Your User → Security Credentials"
echo "  • Click 'Create access key' if you don't have one"
echo ""

read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -sp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
echo ""

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ Credentials cannot be empty${NC}"
    exit 1
fi

echo -e "${YELLOW}📡 Configuring AWS credentials on Jenkins server...${NC}"
echo ""

# Configure AWS on Jenkins server
ssh -o StrictHostKeyChecking=no -i terraform/ec2-key.pem ec2-user@$JENKINS_IP << EOF
    set -e

    echo "Checking if AWS CLI is installed..."
    if ! command -v aws &> /dev/null; then
        echo "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
        echo "✅ AWS CLI installed"
    else
        echo "✅ AWS CLI already installed: \$(aws --version)"
    fi

    echo ""
    echo "Configuring AWS credentials..."
    mkdir -p ~/.aws

    # Create credentials file
    cat > ~/.aws/credentials << CREDS
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
CREDS

    # Create config file
    cat > ~/.aws/config << CONFIG
[default]
region = us-east-1
output = json
CONFIG

    chmod 600 ~/.aws/credentials
    chmod 600 ~/.aws/config

    echo "✅ AWS credentials configured"
    echo ""
    echo "Testing AWS access..."
    if aws sts get-caller-identity &> /dev/null; then
        echo "✅ AWS credentials are valid!"
        aws sts get-caller-identity
    else
        echo "❌ AWS credentials test failed"
        exit 1
    fi

    echo ""
    echo "Testing SSM access..."
    if aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1 &> /dev/null; then
        echo "✅ SSM access working!"
    else
        echo "⚠️  SSM parameter not found (this is OK if you haven't run terraform apply yet)"
    fi
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "===================================================================="
    echo -e "  ${GREEN}✅ SUCCESS! AWS Credentials Configured${NC}"
    echo "===================================================================="
    echo ""
    echo "Jenkins server now has AWS access!"
    echo ""
    echo "Next steps:"
    echo "  1. Go to Jenkins: http://$JENKINS_IP:9090"
    echo "  2. Run your pipeline build"
    echo "  3. It should work now! 🚀"
    echo ""
    echo -e "${YELLOW}Note:${NC} Your credentials are stored securely on the Jenkins server at:"
    echo "  ~/.aws/credentials (only accessible by ec2-user)"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Setup failed${NC}"
    exit 1
fi
