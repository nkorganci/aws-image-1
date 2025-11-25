# AWS Credentials Setup for Jenkins

## 🎯 The Problem

Your AWS credentials are on your **local Windows machine** at:
```
C:\Users\nkorg\.aws\credentials
```

But Jenkins is running on an **AWS EC2 server**, which doesn't have access to your local machine's credentials.

## ✅ The Solution

You need to configure AWS credentials **ON THE JENKINS SERVER** (not on your local machine).

---

## Option 1: Automated Setup (Recommended - 2 minutes)

Run this script from your local machine:

```bash
./setup-aws-credentials.sh
```

The script will:
1. Connect to your Jenkins server via SSH
2. Install AWS CLI (if not installed)
3. Configure your AWS credentials
4. Test the setup

**That's it!** Your Jenkins pipeline will work after this.

---

## Option 2: Manual Setup (5 minutes)

### Step 1: Get Your Jenkins Server IP

```bash
cd terraform
terraform output instance_public_ip
```

Or check in AWS Console → EC2 → Instances

### Step 2: SSH to Jenkins Server

```bash
ssh -i terraform/ec2-key.pem ec2-user@YOUR_JENKINS_IP
```

### Step 3: Install AWS CLI (if not installed)

```bash
# Check if AWS CLI is installed
aws --version

# If not installed, install it:
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Verify installation
aws --version
```

### Step 4: Configure AWS Credentials

```bash
aws configure
```

When prompted, enter:
```
AWS Access Key ID: YOUR_ACCESS_KEY
AWS Secret Access Key: YOUR_SECRET_KEY
Default region name: us-east-1
Default output format: json
```

### Step 5: Test AWS Access

```bash
# Test general AWS access
aws sts get-caller-identity

# Test SSM access (what the pipeline uses)
aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1
```

If both commands work, you're all set! ✅

---

## Where to Get AWS Credentials

### Method 1: From AWS Console (Recommended)

1. Go to: **AWS Console** → **IAM** → **Users**
2. Click on your username
3. Go to **"Security credentials"** tab
4. Under **"Access keys"**, click **"Create access key"**
5. Choose **"Command Line Interface (CLI)"**
6. Click **"Create access key"**
7. **SAVE THESE CREDENTIALS** (shown only once!)
   - Access key ID: `AKIA...`
   - Secret access key: `wJalr...`

### Method 2: From Your Local Machine (If Already Configured)

**Windows:**
```powershell
# View your credentials
type C:\Users\nkorg\.aws\credentials
```

**Linux/Mac:**
```bash
# View your credentials
cat ~/.aws/credentials
```

Look for:
```ini
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = wJalr...
```

**Copy these values** and use them in Step 4 above.

---

## Verification Checklist

After setup, verify everything is working:

### On Jenkins Server (via SSH):

```bash
# 1. Check AWS CLI is installed
aws --version
# Expected: aws-cli/2.x.x ...

# 2. Check credentials are configured
cat ~/.aws/credentials
# Expected: Should show your access key (not secret)

# 3. Test AWS access
aws sts get-caller-identity
# Expected: Should show your AWS account details

# 4. Test SSM access
aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1
# Expected: Should return EC2 public IP
```

If all checks pass, you're ready! ✅

---

## Common Issues

### ❌ "Command not found: aws"

**Solution:** AWS CLI not installed on Jenkins server.

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### ❌ "Unable to locate credentials"

**Solution:** AWS credentials not configured on Jenkins server.

```bash
aws configure
# Enter your AWS Access Key ID and Secret Access Key
```

### ❌ "Access Denied" when accessing SSM

**Solution:** Your AWS user/role doesn't have SSM permissions.

Add this policy to your IAM user:
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
    }
  ]
}
```

### ❌ "Invalid security token" error

**Solution:** Credentials expired or invalid.

Re-run `aws configure` with fresh credentials from AWS Console.

---

## Security Best Practices

### ✅ DO:
- Use IAM user with **least privilege** (only SSM and EC2 read permissions)
- Store credentials in `~/.aws/credentials` on Jenkins server
- Keep credentials file permissions at `600` (readable only by owner)
- Rotate credentials regularly (every 90 days)
- Use separate AWS user for Jenkins (not your personal user)

### ❌ DON'T:
- Don't hardcode credentials in Jenkinsfile
- Don't commit credentials to Git
- Don't share credentials via email/chat
- Don't use root account credentials
- Don't give Jenkins user full admin access

---

## Alternative: Use IAM Instance Profile (Advanced)

Instead of configuring credentials manually, you can attach an IAM role to Jenkins EC2:

```bash
# Get instance profile name from Terraform
cd terraform
terraform output jenkins_instance_profile_name

# Attach to Jenkins instance
aws ec2 associate-iam-instance-profile \
  --instance-id YOUR_JENKINS_INSTANCE_ID \
  --iam-instance-profile Name=aws-image-1-jenkins-profile \
  --region us-east-1
```

**Benefits:**
- No manual credentials needed
- Credentials automatically rotated by AWS
- More secure

**Drawback:**
- Only works if Jenkins is running on EC2 (not Docker)
- Requires Jenkins restart after attaching role

---

## After Setup

Once AWS credentials are configured on Jenkins server:

1. **Go to Jenkins:** `http://YOUR_JENKINS_IP:9090`
2. **Run your pipeline:** Click "Build Now"
3. **It will work!** ✅

The pipeline will:
- Read credentials from `~/.aws/credentials` on Jenkins server
- Pass them to AWS CLI Docker containers
- Successfully fetch EC2 details from SSM
- Deploy your application

---

## Need Help?

**Check these:**
1. ✅ AWS CLI installed on Jenkins server? (`aws --version`)
2. ✅ Credentials configured? (`aws configure list`)
3. ✅ Credentials valid? (`aws sts get-caller-identity`)
4. ✅ SSM access working? (`aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1`)

If all 4 checks pass, your pipeline will work! 🚀

---

## Summary

**Your credentials location:**
- ❌ **Local machine:** `C:\Users\nkorg\.aws\credentials` (Jenkins can't access this)
- ✅ **Jenkins server:** `/home/ec2-user/.aws/credentials` (Jenkins reads from here)

**What you need to do:**
1. SSH to Jenkins server
2. Run `aws configure`
3. Enter your AWS credentials
4. Done! Pipeline works forever

**One-time setup, works forever!** 🎉
