pipeline {
    agent any

    environment {
        // Docker Hub credentials (you'll add these in Jenkins)
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        DOCKER_IMAGE = 'nkorganci/spring-hello-app'

        // EC2 details
        EC2_HOST = '34.214.199.163'
        EC2_USER = 'ec2-user'  // or 'ubuntu' for Ubuntu instances

        // Container settings
        CONTAINER_NAME = 'spring-app'
        APP_PORT = '8081'
    }

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code from Git...'
                checkout scm
            }
        }

        stage('Build JAR') {
            steps {
                echo 'Building Spring Boot application...'
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('Build Docker Image') {
            steps {
                echo 'Building Docker image...'
                script {
                    docker.build("${DOCKER_IMAGE}:${BUILD_NUMBER}")
                    docker.build("${DOCKER_IMAGE}:latest")
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo 'Pushing Docker image to Docker Hub...'
                script {
                    docker.withRegistry('https://index.docker.io/v1/', 'dockerhub-credentials') {
                        docker.image("${DOCKER_IMAGE}:${BUILD_NUMBER}").push()
                        docker.image("${DOCKER_IMAGE}:latest").push()
                    }
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                echo 'Deploying to EC2...'
                sshagent(['ec2-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_HOST} '
                            # Stop and remove existing container
                            docker stop ${CONTAINER_NAME} || true
                            docker rm ${CONTAINER_NAME} || true

                            # Pull latest image
                            docker pull ${DOCKER_IMAGE}:latest

                            # Run new container
                            docker run -d \
                                -p ${APP_PORT}:${APP_PORT} \
                                --name ${CONTAINER_NAME} \
                                --restart unless-stopped \
                                ${DOCKER_IMAGE}:latest

                            # Clean up old images
                            docker image prune -f
                        '
                    """
                }
            }
        }

        stage('Health Check') {
            steps {
                echo 'Checking if application is running...'
                script {
                    sleep(time: 10, unit: 'SECONDS')
                    sh """
                        curl -f http://${EC2_HOST}:${APP_PORT}/hello || exit 1
                    """
                }
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline completed successfully!'
            echo "Application is running at: http://${EC2_HOST}:${APP_PORT}/hello"
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        always {
            echo 'Cleaning up workspace...'
            cleanWs()
        }
    }
}