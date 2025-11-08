pipeline {
  agent any

  environment {
    DOCKER_HUB_REPO = 'nkorganci/hello-aws'
    DEPLOY_SERVER   = 'ec2-user@52.34.164.46'
    SSH_KEY         = credentials('ec2-ssh')
    DOCKER_HUB_CRED = credentials('dockerhub')
  }

  stages {
    stage('Checkout Code') {
      steps {
        git branch: 'main', url: 'https://github.com/nkorganci/aws-image-1.git'
      }
    }

    stage('Build Application (Maven in Docker)') {
      /* Run just this stage inside a Maven+JDK17 container,
         mounting the current workspace into the container */
      agent {
        docker {
          image 'maven:3.9-eclipse-temurin-17'
          reuseNode true
        }
      }
      steps {
        sh 'mvn -v'
        sh 'mvn -B clean package -DskipTests'
      }
    }

    stage('Build Docker Image') {
      steps {
        sh 'docker build -t $DOCKER_HUB_REPO:latest .'
      }
    }

    stage('Push to Docker Hub') {
      steps {
        sh '''
          echo $DOCKER_HUB_CRED_PSW | docker login -u $DOCKER_HUB_CRED_USR --password-stdin
          docker push $DOCKER_HUB_REPO:latest
        '''
      }
    }

    stage('Deploy to EC2') {
      steps {
        sh '''
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY $DEPLOY_SERVER << 'EOF'
        # Install Docker on Amazon Linux if missing, then deploy latest image
        if ! command -v docker >/dev/null 2>&1; then
          sudo yum update -y
          sudo yum install -y docker
          sudo service docker start
          sudo systemctl enable docker
          sudo usermod -aG docker ec2-user
        fi

        docker pull $DOCKER_HUB_REPO:latest
        docker stop helloaws || true
        docker rm helloaws || true
        docker run -d -p 8080:8080 --name helloaws --restart always $DOCKER_HUB_REPO:latest
        EOF
        '''
      }
    }
  }

  post {
    success { echo "✅ Deployment Successful!" }
    failure { echo "❌ Deployment Failed!" }
  }
}
