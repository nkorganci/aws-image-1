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
              # Install Docker if not present (omitted for brevity)...

              echo "Pulling latest Docker image..."
              sudo docker pull nkorganci/hello-aws:latest

              echo "Stopping and removing old container..."
              sudo docker stop helloaws 2>/dev/null || true
              sudo docker rm helloaws 2>/dev/null || true

              echo "Starting new container with correct port mapping (8081)..."
              sudo docker run -d -p 8081:8081 --name helloaws --restart=always nkorganci/hello-aws:latest

              echo "✅ Deployment complete!"
              echo "Application is running at http://52.34.164.46:8081"
ENDSSH
        '''
      }
    }
  }

  post {
    success {
      echo "✅ Deployment Successful!"
      echo "Access your application at: http://52.34.164.46:8081"
    }
    failure {
      echo "❌ Deployment Failed!"
    }
  }
}
