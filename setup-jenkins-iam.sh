#!/bin/bash
# ==============================================================================
# SETUP SCRIPT: Attach IAM Instance Profile to Jenkins EC2
# ==============================================================================
#
# PURPOSE: Attaches the IAM instance profile to Jenkins EC2 so it can access
#          AWS SSM Parameter Store without manual aws configure
#
# USAGE: ./setup-jenkins-iam.sh YOUR_JENKINS_INSTANCE_ID
#
# ==============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "===================================================================="
echo "  Jenkins IAM Instance Profile Setup"
echo "===================================================================="
echo ""

# Check if instance ID provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Jenkins instance ID not provided${NC}"
    echo ""
    echo "Usage: $0 YOUR_JENKINS_INSTANCE_ID"
    echo ""
    echo "To find your Jenkins instance ID:"
    echo "  1. Go to AWS Console → EC2 → Instances"
    echo "  2. Find your Jenkins server"
    echo "  3. Copy the Instance ID (starts with i-)"
    echo ""
    echo "Or use AWS CLI:"
    echo "  aws ec2 describe-instances --filters \"Name=tag:Name,Values=*jenkins*\" --query \"Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0]]\" --output table"
    echo ""
    exit 1
fi

JENKINS_INSTANCE_ID="$1"
AWS_REGION="${2:-us-east-1}"  # Default to us-east-1 if not specified

echo -e "${YELLOW}Jenkins Instance ID:${NC} $JENKINS_INSTANCE_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not installed${NC}"
    echo "Install it: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi
echo -e "${GREEN}✅ AWS credentials OK${NC}"
echo ""

# Check if instance exists
echo "Checking if instance exists..."
if ! aws ec2 describe-instances --instance-ids "$JENKINS_INSTANCE_ID" --region "$AWS_REGION" &> /dev/null; then
    echo -e "${RED}❌ Instance $JENKINS_INSTANCE_ID not found in region $AWS_REGION${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Instance found${NC}"
echo ""

# Get instance profile name from Terraform
echo "Getting IAM instance profile name from Terraform..."
cd terraform || {
    echo -e "${RED}❌ Terraform directory not found${NC}"
    echo "Make sure you run this script from the project root directory"
    exit 1
}

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not installed${NC}"
    exit 1
fi

INSTANCE_PROFILE_NAME=$(terraform output -raw jenkins_instance_profile_name 2>/dev/null)

if [ -z "$INSTANCE_PROFILE_NAME" ]; then
    echo -e "${RED}❌ Could not get instance profile name from Terraform${NC}"
    echo "Make sure you have run 'terraform apply' first"
    exit 1
fi

cd ..

echo -e "${GREEN}✅ Instance Profile:${NC} $INSTANCE_PROFILE_NAME"
echo ""

# Check if instance already has a profile attached
echo "Checking current IAM instance profile..."
CURRENT_PROFILE=$(aws ec2 describe-instances \
    --instance-ids "$JENKINS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text 2>/dev/null)

if [ "$CURRENT_PROFILE" != "None" ] && [ ! -z "$CURRENT_PROFILE" ]; then
    echo -e "${YELLOW}⚠️  Instance already has IAM profile attached:${NC}"
    echo "   $CURRENT_PROFILE"
    echo ""
    read -p "Replace with $INSTANCE_PROFILE_NAME? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo "Removing current profile..."
    aws ec2 disassociate-iam-instance-profile \
        --association-id $(aws ec2 describe-iam-instance-profile-associations \
            --filters "Name=instance-id,Values=$JENKINS_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'IamInstanceProfileAssociations[0].AssociationId' \
            --output text) \
        --region "$AWS_REGION"
    echo -e "${GREEN}✅ Removed old profile${NC}"
fi

# Attach the instance profile
echo ""
echo "Attaching IAM instance profile to Jenkins instance..."
ASSOCIATION_ID=$(aws ec2 associate-iam-instance-profile \
    --instance-id "$JENKINS_INSTANCE_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE_NAME" \
    --region "$AWS_REGION" \
    --query 'IamInstanceProfileAssociation.AssociationId' \
    --output text)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Successfully attached IAM instance profile!${NC}"
    echo "   Association ID: $ASSOCIATION_ID"
else
    echo -e "${RED}❌ Failed to attach instance profile${NC}"
    exit 1
fi

echo ""
echo "===================================================================="
echo "  Verification"
echo "===================================================================="
echo ""

# Wait a moment for the profile to be active
echo "Waiting for profile to become active..."
sleep 5

# Verify the attachment
VERIFY_PROFILE=$(aws ec2 describe-instances \
    --instance-ids "$JENKINS_INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text)

if [ "$VERIFY_PROFILE" != "None" ] && [ ! -z "$VERIFY_PROFILE" ]; then
    echo -e "${GREEN}✅ Verification successful!${NC}"
    echo "   Profile ARN: $VERIFY_PROFILE"
else
    echo -e "${RED}❌ Verification failed - profile not attached${NC}"
    exit 1
fi

echo ""
echo "===================================================================="
echo "  Next Steps"
echo "===================================================================="
echo ""
echo "1. The IAM instance profile is now attached to Jenkins"
echo "2. Jenkins can now access AWS SSM without manual credentials"
echo "3. No need to run 'aws configure' anymore!"
echo ""
echo "To test the setup:"
echo "  1. SSH into Jenkins server:"
echo "     ssh -i your-key.pem ec2-user@YOUR_JENKINS_IP"
echo ""
echo "  2. Test AWS access:"
echo "     aws sts get-caller-identity"
echo "     aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1"
echo ""
echo "  3. Run Jenkins build - it should work automatically!"
echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
