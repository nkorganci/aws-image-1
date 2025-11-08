pipeline {
    agent any

    environment {
        DOCKER_HUB_REPO = 'nkorganci/hello-aws'             // your Docker Hub repo
        DEPLOY_SERVER   = 'ec2-user@52.34.164.46'           // your EC2 public IP
        SSH_KEY         = credentials('ec2-ssh')            // Jenkins SSH key ID
        DOCKER_HUB_CRED = credentials('dockerhub')          // Docker Hub credentials
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/nkorganci/aws-image-1.git'
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh 'docker build -t $DOCKER_HUB_REPO:latest .'
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                script {
                    sh 'echo $DOCKER_HUB_CRED_PSW | docker login -u $DOCKER_HUB_CRED_USR --password-stdin'
                    sh 'docker push $DOCKER_HUB_REPO:latest'
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    sh '''
                    ssh -o StrictHostKeyChecking=no -i $SSH_KEY $DEPLOY_SERVER << 'EOF'
                    # 1️⃣ Update and install Docker if not present
                    if ! command -v docker &> /dev/null
                    then
                        echo "Docker not found. Installing Docker..."
                        sudo yum update -y
                        sudo yum install -y docker
                        sudo systemctl start docker
                        sudo systemctl enable docker
                        sudo usermod -aG docker ec2-user
                        echo "✅ Docker installed successfully!"
                    else
                        echo "✅ Docker already installed!"
                    fi

                    # 2️⃣ Deploy the container
                    docker pull $DOCKER_HUB_REPO:latest
                    docker stop helloaws || true
                    docker rm helloaws || true
                    docker run -d -p 8080:8080 --name helloaws --restart always $DOCKER_HUB_REPO:latest
                    EOF
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ Deployment Successful!"
        }
        failure {
            echo "❌ Deployment Failed!"
        }
    }
}
