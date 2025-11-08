pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
  }

  environment {
    DOCKER_HUB_REPO = 'nkorganci/hello-aws'
    DEPLOY_SERVER   = 'ec2-user@52.34.164.46'
  }

  stages {
    stage('Checkout Code') {
      steps {
        git branch: 'main', url: 'https://github.com/nkorganci/aws-image-1.git'
      }
    }

    stage('Build Application (Maven in Docker)') {
      agent {
        docker {
          image 'maven:3.9-eclipse-temurin-17'
          args '-v $HOME/.m2:/root/.m2'
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
        sh 'docker build -t "$DOCKER_HUB_REPO:latest" .'
      }
    }

    stage('Push to Docker Hub') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub',
          usernameVariable: 'DOCKERHUB_USER',
          passwordVariable: 'DOCKERHUB_PASS'
        )]) {
          sh '''
            echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker push "$DOCKER_HUB_REPO:latest"
          '''
        }
      }
    }

    stage('Deploy to EC2') {
      steps {
        sshagent(credentials: ['ec2-ssh']) {
          sh '''
            ssh -o StrictHostKeyChecking=no ${DEPLOY_SERVER} << 'ENDSSH'
              set -e

              # Install Docker if not present
              if ! command -v docker >/dev/null 2>&1; then
                echo "Docker not found. Installing Docker..."
                if command -v yum >/dev/null 2>&1; then
                  sudo yum -y update
                  sudo yum -y install docker
                elif command -v dnf >/dev/null 2>&1; then
                  sudo dnf -y install docker
                elif command -v apt-get >/dev/null 2>&1; then
                  sudo apt-get update -y
                  sudo apt-get install -y docker.io
                fi
                sudo systemctl enable docker
                sudo systemctl start docker
                sudo usermod -aG docker ec2-user || true
                echo "✅ Docker installed successfully!"
              else
                echo "✅ Docker already installed!"
              fi

              # Pull latest image and deploy
              echo "Pulling latest Docker image..."
              sudo docker pull nkorganci/hello-aws:latest

              echo "Stopping and removing old container..."
              sudo docker stop helloaws 2>/dev/null || true
              sudo docker rm helloaws 2>/dev/null || true

              echo "Starting new container..."
              sudo docker run -d -p 8080:8080 --name helloaws --restart=always nkorganci/hello-aws:latest

              echo "✅ Deployment complete!"
              echo "Application is running at http://52.34.164.46:8080"
ENDSSH
          '''
        }
      }
    }
  }

  post {
    success {
      echo "✅ Deployment Successful!"
      echo "Access your application at: http://52.34.164.46:8080"
    }
    failure {
      echo "❌ Deployment Failed!"
    }
  }
}