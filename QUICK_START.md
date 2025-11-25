# 🚀 Quick Start Guide

## One-Time Setup (5 minutes)

### **1. Configure AWS Credentials on Jenkins Host**

SSH into your Jenkins server and run:

```bash
aws configure
```

Enter your AWS credentials when prompted:
```
AWS Access Key ID: YOUR_ACCESS_KEY
AWS Secret Access Key: YOUR_SECRET_KEY
Default region name: us-east-1
Default output format: json
```

**That's it!** You never need to do this again.

---

## Running Your First Build

### **1. Create Jenkins Pipeline Job**

1. Go to Jenkins → New Item
2. Name: `aws-image-1-ec2`
3. Type: Pipeline
4. Click OK

### **2. Configure Pipeline**

**Pipeline section:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/nkorganci/aws-image-1.git`
- Branch: `*/main` (or `*/image-ec2-auto-1` for your branch)
- Script Path: `Jenkinsfile`

**Save**

### **3. Add Docker Hub Credentials**

1. Go to: Jenkins → Manage Jenkins → Credentials
2. Click: (global) → Add Credentials
3. Fill in:
   - Kind: `Username with password`
   - Username: Your Docker Hub username
   - Password: Your Docker Hub token/password
   - ID: `dockerhub` (must be exactly this)
   - Description: Docker Hub credentials
4. Click **Create**

### **4. Run the Build**

1. Go to your pipeline job
2. Click **"Build Now"**
3. Watch the magic happen! ✨

---

## What Happens When You Click "Build Now"

```
┌─────────────────────────────────────────────────┐
│  1. Checkout Code from GitHub                   │
│     ✓ Clones latest code                        │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  2. Build Application (Maven in Docker)         │
│     ✓ Compiles Java code                        │
│     ✓ Creates JAR file                          │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  3. Build Docker Image                          │
│     ✓ Packages JAR with Java runtime           │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  4. Push to Docker Hub                          │
│     ✓ Uploads image to nkorganci/hello-aws     │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  5. Fetch EC2 Details from AWS SSM              │
│     ✓ Gets current EC2 public IP                │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  6. Deploy to EC2                               │
│     ✓ Fetches SSH key from SSM                  │
│     ✓ Connects to EC2 via SSH                   │
│     ✓ Pulls Docker image                        │
│     ✓ Stops old container                       │
│     ✓ Starts new container                      │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  7. Verify Deployment                           │
│     ✓ Tests application endpoint                │
│     ✓ Confirms app is responding                │
└─────────────────────────────────────────────────┘
                    ↓
            ✅ SUCCESS!
   Application running at http://EC2_IP:8081/hello
```

---

## Viewing Your Application

After a successful build, the pipeline will output:

```
✅ Deployment Successful!
Access your application at: http://3.235.152.62:8081
```

Visit:
- **Homepage:** `http://YOUR_EC2_IP:8081`
- **Hello Endpoint:** `http://YOUR_EC2_IP:8081/hello`

---

## Troubleshooting

### ❌ Build fails with "aws: not found"

**Solution:** AWS CLI is not installed on Jenkins host.

```bash
# SSH to Jenkins host
ssh -i your-key.pem ec2-user@YOUR_JENKINS_IP

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version

# Configure
aws configure
```

### ❌ "Unable to locate credentials"

**Solution:** AWS credentials not configured.

```bash
# SSH to Jenkins host as the Jenkins user
sudo su - jenkins
aws configure
```

### ❌ "Cannot connect to Docker daemon"

**Solution:** Jenkins user not in docker group.

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### ❌ Docker Hub push fails

**Solution:** Check Docker Hub credentials in Jenkins.

1. Go to: Jenkins → Manage Jenkins → Credentials
2. Verify credential ID is exactly `dockerhub`
3. Verify username and password are correct

### ❌ SSH connection to EC2 fails

**Solution:** Check security group allows SSH from Jenkins IP.

```bash
# Get Jenkins public IP
curl ifconfig.me

# Update security group to allow SSH from Jenkins IP
aws ec2 authorize-security-group-ingress \
  --group-id sg-YOUR_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_JENKINS_IP/32
```

---

## Making Code Changes

### **Workflow:**

1. Make changes to your code locally
2. Commit and push to GitHub:
   ```bash
   git add .
   git commit -m "Your change description"
   git push origin main
   ```
3. Go to Jenkins → Your job → Click **"Build Now"**
4. Jenkins automatically:
   - Pulls latest code from GitHub
   - Builds and deploys to EC2
   - Your changes are live!

---

## Requirements Checklist

### **Jenkins Host:**
- [x] Docker installed
- [x] AWS CLI installed
- [x] AWS credentials configured (`aws configure`)
- [x] Jenkins user in docker group

### **Jenkins:**
- [x] Docker Hub credentials added (ID: `dockerhub`)
- [x] Pipeline job created
- [x] Pipeline configured to use GitHub repository

### **AWS Infrastructure:**
- [x] Terraform applied (`terraform apply`)
- [x] EC2 instance running with Docker
- [x] Security group allows ports 22 and 8081
- [x] SSM parameters created (Terraform does this)

### **GitHub:**
- [x] Repository accessible (public or Jenkins has access)
- [x] Contains Jenkinsfile
- [x] Contains Dockerfile
- [x] Contains pom.xml

---

## Maintenance

### **Updating Application:**
Just push your code to GitHub and click "Build Now" in Jenkins!

### **Recreating Infrastructure:**
```bash
cd terraform
terraform destroy  # Remove old infrastructure
terraform apply    # Create new infrastructure
```

Jenkins will automatically use the new EC2 instance (IP fetched from SSM).

### **Checking Application Logs:**
```bash
ssh -i terraform/ec2-key.pem ec2-user@YOUR_EC2_IP
sudo docker logs helloaws
```

### **Restarting Application:**
```bash
ssh -i terraform/ec2-key.pem ec2-user@YOUR_EC2_IP
sudo docker restart helloaws
```

---

## What Gets Automated

| Task | Manual | Automated |
|------|--------|-----------|
| Build Java app | ❌ Run Maven locally | ✅ Jenkins builds automatically |
| Create Docker image | ❌ Run docker build | ✅ Jenkins creates automatically |
| Push to Docker Hub | ❌ Manual login and push | ✅ Jenkins pushes automatically |
| Get EC2 IP | ❌ Check AWS Console | ✅ Fetched from SSM automatically |
| Get SSH key | ❌ Copy from Terraform | ✅ Fetched from SSM automatically |
| Deploy to EC2 | ❌ Manual SSH and docker run | ✅ Jenkins deploys automatically |
| Verify deployment | ❌ Manual curl test | ✅ Jenkins verifies automatically |

---

## Summary

**One-Time Setup:**
1. Run `aws configure` on Jenkins host (2 minutes)
2. Add Docker Hub credentials in Jenkins (1 minute)
3. Create Jenkins pipeline job (2 minutes)

**Every Deployment After:**
1. Push code to GitHub
2. Click "Build Now" in Jenkins
3. ✅ Done! Application deployed automatically

**Zero manual intervention after initial setup!** 🎉

---

## Need Help?

- **Documentation:** See `docs/` folder
- **Troubleshooting:** See `docs/JENKINS_REQUIREMENTS.md`
- **Detailed Pipeline Info:** See comments in `Jenkinsfile`
- **Infrastructure:** See `terraform/main.tf`

---

## What's Next?

Consider these improvements:

1. **Add Tests:** Create a test stage before deployment
2. **Notifications:** Add Slack/email notifications
3. **Rollback:** Keep previous Docker image for quick rollback
4. **Multiple Environments:** Create dev/staging/prod pipelines
5. **Blue-Green Deployment:** Zero-downtime deployments
6. **Monitoring:** Add CloudWatch alarms

Happy deploying! 🚀
