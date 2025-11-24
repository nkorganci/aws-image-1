pipeline {
  agent any

  options {
    timestamps()
    skipDefaultCheckout(true)
  }

  environment {
    DOCKER_HUB_REPO = 'nkorganci/hello-aws'
    DEPLOY_USER     = 'ec2-user'
    PROJECT_NAME    = 'aws-image-1'
    AWS_REGION      = 'us-east-1'

    SSM_PARAM_PRIVATE_KEY = "/app/${PROJECT_NAME}/ec2/private_key"
    SSM_PARAM_INSTANCE_ID = "/app/${PROJECT_NAME}/ec2/instance_id"
    SSM_PARAM_PUBLIC_IP   = "/app/${PROJECT_NAME}/ec2/public_ip"
  }

  stages {
    stage('Checkout Code') {
      steps {
        cleanWs()
        git branch: 'main', url: 'https://github.com/nkorganci/aws-image-1.git'
      }
    }

    stage('Build Application') {
      steps {
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

    stage('Fetch EC2 Details') {
      steps {
        script {
          env.DEPLOY_HOST = sh(
            script: "aws --region ${AWS_REGION} ssm get-parameter --name ${SSM_PARAM_PUBLIC_IP} --query Parameter.Value --output text",
            returnStdout: true
          ).trim()

          echo "✅ Deploying to: ${env.DEPLOY_HOST}"
        }
      }
    }

    stage('Deploy to EC2') {
      steps {
        sh '''
          aws --region "$AWS_REGION" ssm get-parameter --name "$SSM_PARAM_PRIVATE_KEY" --with-decryption --query Parameter.Value --output text > ec2-key.pem
          chmod 400 ec2-key.pem

          ssh -o StrictHostKeyChecking=no -i ec2-key.pem ${DEPLOY_USER}@${DEPLOY_HOST} << 'ENDSSH'
            set -e
            sudo docker pull nkorganci/hello-aws:latest
            sudo docker stop helloaws 2>/dev/null || true
            sudo docker rm helloaws 2>/dev/null || true
            sudo docker run -d -p 8081:8081 --name helloaws --restart=always nkorganci/hello-aws:latest
            echo "✅ Deployment complete!"
ENDSSH

          rm -f ec2-key.pem
        '''
      }
    }

    stage('Verify Deployment') {
      steps {
        sleep(time: 10, unit: 'SECONDS')
        sh '''
          RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://${DEPLOY_HOST}:8081/hello || echo "000")
          if [ "$RESPONSE" = "200" ]; then
            echo "✅ Application is responding!"
          else
            echo "⚠️ Application returned HTTP $RESPONSE"
          fi
        '''
      }
    }
  }

  post {
    success {
      echo "✅ Deployment Successful!"
      echo "Access your application at: http://${DEPLOY_HOST}:8081"
    }
    failure {
      echo "❌ Deployment Failed!"
    }
  }
}
