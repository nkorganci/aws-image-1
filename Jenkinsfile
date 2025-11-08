pipeline {
    agent any

    environment {
        DOCKER_HUB_REPO = 'nkorganci/hello-aws'             // Docker Hub repo
        DEPLOY_SERVER   = 'ec2-user@52.34.164.46'           // EC2 public IP
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
                    sh '''
                    echo $DOCKER_HUB_CRED_PSW | docker login -u $DOCKER_HUB_CRED_USR --password-stdin
                    docker push $DOCKER_HUB_REPO:latest
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    sh '''
                    ssh -o StrictHostKeyChecking=no -i $SSH_KEY $DEPLOY_SERVER << 'EOF'
                    echo "🔧 Checking Docker installation..."
                    if ! command -v docker &> /dev/null
                    then
                        echo "🐋 Installing Docker..."
                        sudo yum update -y
                        sudo yum install -y docker
                        sudo systemctl start docker
                        sudo systemctl enable docker
                        sudo usermod -aG docker ec2-user
                        echo "✅ Docker installed!"
                    else
                        echo "✅ Docker already installed."
                    fi

                    echo "🚀 Deploying application..."
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
