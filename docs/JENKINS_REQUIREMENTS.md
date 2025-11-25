# Jenkins Server Requirements

## ✅ What Your Jenkins Server Needs

### **Minimal Installation (Recommended)**

Your Jenkins server only needs **2 things installed**:

1. **Jenkins** (obviously!)
2. **Docker** (to run build containers)

That's it! Everything else runs in Docker containers.

---

## 🐳 What Runs in Docker Containers

The following tools are **NOT** installed on Jenkins - they run in Docker:

| Tool | Docker Image | Used For |
|------|-------------|----------|
| **Maven** | `maven:3.9-eclipse-temurin-17` | Building Java application |
| **AWS CLI** | `amazon/aws-cli:latest` | Fetching EC2 details from SSM |
| **SSH Client** | `amazon/aws-cli:latest` (with openssh) | Deploying to EC2 |

---

## 📋 Complete Setup Checklist

### **Jenkins Server (localhost:9090)**

- [ ] **Docker installed and running**
  ```bash
  docker --version
  sudo systemctl status docker
  ```

- [ ] **Jenkins running**
  ```bash
  # Check Jenkins is accessible
  curl http://localhost:9090
  ```

- [ ] **Docker Hub credentials configured**
  - Go to: Jenkins → Manage Jenkins → Credentials
  - Add Username/Password credential
  - ID: `dockerhub`
  - Username: Your Docker Hub username
  - Password: Your Docker Hub token

- [ ] **IAM instance profile attached to Jenkins EC2**
  ```bash
  # Get instance profile name from Terraform
  cd terraform
  terraform output jenkins_instance_profile_name

  # Attach to Jenkins instance (replace YOUR_JENKINS_INSTANCE_ID)
  aws ec2 associate-iam-instance-profile \
    --instance-id YOUR_JENKINS_INSTANCE_ID \
    --iam-instance-profile Name=aws-image-1-jenkins-profile \
    --region us-east-1
  ```

- [ ] **AWS credentials available** (one of these methods):
  - **Option A (Recommended):** IAM instance profile attached to Jenkins EC2
  - **Option B:** AWS credentials in `~/.aws/credentials`
  - **Option C:** Environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

---

## 🚫 What You DON'T Need to Install

You do **NOT** need to install these on Jenkins:

- ❌ Maven
- ❌ AWS CLI
- ❌ Java JDK
- ❌ SSH client
- ❌ Git (actually you do need git, but usually pre-installed)

All of these run inside Docker containers automatically!

---

## 🔧 Jenkins Plugins Required

These plugins should be installed in Jenkins:

1. **Docker Pipeline** (for `agent { docker { } }` syntax)
2. **Pipeline** (core pipeline functionality)
3. **Git** (for checking out code)
4. **Credentials Binding** (for Docker Hub credentials)
5. **Workspace Cleanup** (for `cleanWs()` function)

### Check if plugins are installed:
1. Go to: Jenkins → Manage Jenkins → Plugins
2. Go to "Installed plugins" tab
3. Search for each plugin above

### Install missing plugins:
1. Go to: Jenkins → Manage Jenkins → Plugins
2. Go to "Available plugins" tab
3. Search and install missing plugins
4. Restart Jenkins after installation

---

## ✅ Verify Your Setup

Run this verification script on your Jenkins server:

```bash
#!/bin/bash

echo "=== Jenkins Setup Verification ==="

# Check Docker
if command -v docker &> /dev/null; then
    echo "✅ Docker installed: $(docker --version)"
else
    echo "❌ Docker NOT installed"
fi

# Check Docker daemon
if systemctl is-active --quiet docker; then
    echo "✅ Docker daemon running"
else
    echo "❌ Docker daemon NOT running"
fi

# Check Jenkins user can run Docker
if docker ps &> /dev/null; then
    echo "✅ Jenkins user can run Docker"
else
    echo "❌ Jenkins user CANNOT run Docker (add to docker group)"
fi

# Check AWS credentials
if aws sts get-caller-identity &> /dev/null 2>&1; then
    echo "✅ AWS credentials configured"
elif [ -f ~/.aws/credentials ]; then
    echo "✅ AWS credentials file exists"
else
    echo "⚠️  AWS credentials not found (IAM role should work)"
fi

# Check IAM instance profile
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d' ' -f2)
if [ ! -z "$INSTANCE_ID" ]; then
    PROFILE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null)
    if [ ! -z "$PROFILE" ]; then
        echo "✅ IAM instance profile attached: $PROFILE"
    else
        echo "⚠️  No IAM instance profile attached"
    fi
fi

echo ""
echo "=== Summary ==="
echo "Required: Docker ✓"
echo "Not Required: Maven, AWS CLI, SSH (all run in Docker)"
```

---

## 🎯 Why This Approach?

### **Traditional Approach (Bad):**
```
Jenkins Server needs:
- Jenkins
- Docker
- Maven
- AWS CLI
- Java JDK
- SSH client
- Python
- npm
- ... (list grows over time)
```
**Problems:**
- ❌ Version conflicts
- ❌ Dependency hell
- ❌ Hard to maintain
- ❌ Different behavior on different Jenkins servers

### **Docker-Based Approach (Good):**
```
Jenkins Server needs:
- Jenkins
- Docker

Everything else runs in containers:
- Maven (specific version)
- AWS CLI (latest)
- Any other tool
```
**Benefits:**
- ✅ Consistent builds
- ✅ Easy to upgrade tools (just change Docker image tag)
- ✅ No version conflicts
- ✅ Works on any Jenkins with Docker

---

## 🔐 Security Notes

1. **IAM Instance Profile (Recommended)**
   - Attach `aws-image-1-jenkins-profile` to Jenkins EC2
   - No need to store AWS credentials
   - Credentials automatically rotated by AWS

2. **Docker Hub Credentials**
   - Store in Jenkins credential store (encrypted)
   - Never hardcode in Jenkinsfile
   - Use credential ID: `dockerhub`

3. **SSH Private Keys**
   - Stored encrypted in AWS SSM Parameter Store
   - Fetched on-demand during deployment
   - Automatically deleted after use
   - Never stored permanently on Jenkins

---

## 📞 Troubleshooting

### **Issue: Docker permission denied**
```bash
# Add Jenkins user to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### **Issue: AWS credentials not working**
```bash
# Test AWS credentials
aws sts get-caller-identity

# If using IAM role, check instance profile
aws ec2 describe-instances --instance-ids $(ec2-metadata --instance-id | cut -d' ' -f2) \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

### **Issue: Docker Hub push fails**
- Check Docker Hub credentials in Jenkins
- Verify credential ID is exactly `dockerhub`
- Test Docker login manually:
  ```bash
  docker login -u YOUR_USERNAME
  ```

### **Issue: Cannot fetch from SSM**
- Check IAM instance profile is attached
- Verify IAM role has SSM GetParameter permission
- Test SSM access:
  ```bash
  aws ssm get-parameter --name /app/aws-image-1/ec2/public_ip --region us-east-1
  ```

---

## 🚀 Ready to Build!

Once you have:
- ✅ Docker installed on Jenkins
- ✅ Docker Hub credentials configured
- ✅ IAM instance profile attached

You're ready to run the Jenkins pipeline! Just click "Build Now" and everything will work automatically.
