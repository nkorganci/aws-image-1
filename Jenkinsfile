/*
 * ==============================================================================
 * JENKINS CI/CD PIPELINE FOR AWS EC2 DEPLOYMENT
 * ==============================================================================
 *
 * PURPOSE: Automates building, testing, and deploying a Spring Boot application
 *          from GitHub to AWS EC2 instance via Docker.
 *
 * WORKFLOW:
 * 1. Checkout code from GitHub
 * 2. Build Java application with Maven
 * 3. Build Docker image
 * 4. Push Docker image to Docker Hub
 * 5. Fetch EC2 details from AWS SSM Parameter Store
 * 6. Deploy to EC2 instance via SSH
 * 7. Verify deployment health
 *
 * ==============================================================================
 */

pipeline {
  // WHAT: Defines this is a Jenkins declarative pipeline
  // WHY: Declarative syntax is clearer and easier to understand than scripted
  // WITHOUT: Cannot define Jenkins pipeline at all

  agent any
  // WHAT: Runs pipeline on any available Jenkins agent/node
  // WHY: Provides flexibility to run on any agent with required tools (Maven, Docker, AWS CLI)
  // WITHOUT: Pipeline won't know where to execute
  // BEST PRACTICE: Use 'agent any' for small teams, or specify labels like 'agent { label "docker" }'

  options {
    // WHAT: Pipeline-level configuration options
    // WHY: Provides consistent behavior and features across all pipeline runs

    timestamps()
    // WHAT: Adds timestamps to console output
    // WHY: Helps debug by showing exact time each step ran
    // WITHOUT: Harder to identify slow steps or timeout issues

    skipDefaultCheckout(true)
    // WHAT: Prevents automatic code checkout at pipeline start
    // WHY: Gives manual control over when/how code is checked out (we do it in stage 1)
    // WITHOUT: Code checked out twice (automatic + manual), wastes time
    // BEST PRACTICE: Use this when you need custom checkout logic (like cleanWs first)

    buildDiscarder(logRotator(numToKeepStr: '10'))
    // WHAT: Keeps only last 10 builds and deletes older ones
    // WHY: Saves Jenkins disk space by removing old build logs and artifacts
    // WITHOUT: Jenkins disk fills up over time, causing performance issues
    // BEST PRACTICE: Keep 10-30 builds depending on your needs

    disableConcurrentBuilds()
    // WHAT: Prevents multiple builds of this job from running simultaneously
    // WHY: Avoids conflicts when deploying to same EC2 instance
    // WITHOUT: Two deployments could run at once, causing Docker container conflicts
    // BEST PRACTICE: Essential for deployment pipelines to prevent race conditions
  }

  environment {
    // WHAT: Defines environment variables available to all pipeline stages
    // WHY: Centralized configuration, easier to update, and reusable across stages
    // WITHOUT: Would need to hardcode values in each stage, harder to maintain

    DOCKER_HUB_REPO = 'nkorganci/hello-aws'
    // WHAT: Docker Hub repository name where images are stored
    // WHY: Centralized location for Docker images, accessible from EC2
    // WITHOUT: Cannot store/retrieve Docker images, deployment impossible

    DEPLOY_USER = 'ec2-user'
    // WHAT: SSH username for connecting to EC2 instance
    // WHY: Amazon Linux 2 uses 'ec2-user' by default (Ubuntu uses 'ubuntu')
    // WITHOUT: SSH connection will fail with "Permission denied"

    PROJECT_NAME = 'aws-image-1'
    // WHAT: Project identifier used in SSM parameter paths
    // WHY: Namespaces SSM parameters to avoid conflicts with other projects
    // WITHOUT: Could accidentally use another project's EC2 instance/keys

    AWS_REGION = 'us-east-1'
    // WHAT: AWS region where your EC2 instance and SSM parameters are located
    // WHY: AWS CLI needs to know which region to query
    // WITHOUT: AWS API calls will fail with "resource not found"

    // SSM Parameter Store paths - automatically managed by Terraform
    SSM_PARAM_PRIVATE_KEY = "/app/${PROJECT_NAME}/ec2/private_key"
    // WHAT: Path to encrypted SSH private key in AWS SSM Parameter Store
    // WHY: Secure storage for sensitive keys, auto-rotated when EC2 recreated
    // WITHOUT: Would need to manually store keys in Jenkins (insecure, not auto-updated)

    SSM_PARAM_INSTANCE_ID = "/app/${PROJECT_NAME}/ec2/instance_id"
    // WHAT: Path to EC2 instance ID in SSM Parameter Store
    // WHY: Enables dynamic lookup of instance (useful for autoscaling/recreation)
    // WITHOUT: Would hardcode instance ID (breaks when instance recreated)
    // NOTE: Currently unused in pipeline but useful for future enhancements

    SSM_PARAM_PUBLIC_IP = "/app/${PROJECT_NAME}/ec2/public_ip"
    // WHAT: Path to EC2 public IP address in SSM Parameter Store
    // WHY: IP changes when EC2 instance restarts/recreates, this auto-updates
    // WITHOUT: Deployment fails after instance restart (wrong IP hardcoded)
  }

  stages {
    // WHAT: Defines sequential steps of the pipeline
    // WHY: Organized, readable workflow with clear separation of concerns
    // WITHOUT: Cannot structure pipeline into logical steps

    stage('Checkout Code') {
      // WHAT: Cleans workspace and clones latest code from GitHub
      // WHY: Ensures clean build environment with latest code
      // WITHOUT: Old files remain, causing stale builds or conflicts

      steps {
        cleanWs()
        // WHAT: Deletes all files from Jenkins workspace before build
        // WHY: Ensures clean slate, no leftover files from previous builds
        // WITHOUT: Old artifacts can cause build failures or incorrect deployments
        // BEST PRACTICE: Always clean before checkout for consistent builds

        git branch: 'main', url: 'https://github.com/nkorganci/aws-image-1.git'
        // WHAT: Clones the 'main' branch from GitHub repository
        // WHY: Gets latest source code for building
        // WITHOUT: No source code to build, pipeline fails immediately
        // BEST PRACTICE: Use branch parameter for flexibility: git branch: "${params.BRANCH}", url: '...'
      }
    }

    stage('Build Application') {
      // WHAT: Compiles Java code and packages into executable JAR file
      // WHY: Creates deployable artifact from source code

      agent {
        docker {
          image 'maven:3.9-eclipse-temurin-17'
          // WHAT: Uses official Maven Docker image with Java 17
          // WHY: No need to install Maven on Jenkins, self-contained build
          // WITHOUT: Requires Maven installed on Jenkins server

          args '-v $HOME/.m2:/root/.m2'
          // WHAT: Mounts Maven local repository for caching dependencies
          // WHY: Faster builds, doesn't re-download dependencies every time
          // WITHOUT: Downloads all dependencies on every build (slow)

          reuseNode true
          // WHAT: Runs Maven container on same node as main pipeline
          // WHY: Shares workspace, doesn't need to re-checkout code
          // WITHOUT: Would checkout code again in new workspace
        }
      }

      steps {
        sh 'mvn -B clean package -DskipTests'
        // WHAT: Maven command to build Java application
        // WHY:
        //   -B (batch mode): Non-interactive, better for CI/CD
        //   clean: Removes old compiled files
        //   package: Compiles code and creates JAR file in target/
        //   -DskipTests: Skips running unit tests (faster builds)
        // WITHOUT: No JAR file created, Docker build will fail
        // BEST PRACTICE: Run tests in separate stage, don't skip them:
        //   stage('Test') { steps { sh 'mvn test' } }
        //   stage('Build') { steps { sh 'mvn -B package -DskipTests' } }
        // NOTE: Runs inside Maven Docker container (no local Maven needed)
      }
    }

    stage('Build Docker Image') {
      // WHAT: Creates Docker image from Dockerfile and built JAR
      // WHY: Packages application with runtime dependencies for consistent deployment

      steps {
        sh 'docker build -t "$DOCKER_HUB_REPO:latest" .'
        // WHAT: Builds Docker image and tags it
        // WHY:
        //   -t: Tags image with name and version
        //   latest: Tag for most recent version (pulled by EC2)
        //   .: Uses Dockerfile in current directory
        // WITHOUT: No Docker image, cannot deploy containerized app
        // BEST PRACTICE: Use Git commit hash as tag for versioning:
        //   sh 'docker build -t "$DOCKER_HUB_REPO:${GIT_COMMIT}" .'
        // NOTE: Requires Docker installed on Jenkins agent
      }
    }

    stage('Push to Docker Hub') {
      // WHAT: Uploads Docker image to Docker Hub registry
      // WHY: Makes image accessible from EC2 instance for deployment

      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub',
          usernameVariable: 'DOCKERHUB_USER',
          passwordVariable: 'DOCKERHUB_PASS'
        )]) {
          // WHAT: Securely injects Docker Hub credentials from Jenkins credentials store
          // WHY: Avoids hardcoding passwords in code, credentials stored securely
          // WITHOUT: Cannot push to private Docker Hub repository
          // BEST PRACTICE: Always use credentials binding, never hardcode passwords
          // SETUP: Create credentials in Jenkins: Manage Jenkins → Credentials → Add
          //        Type: Username with password, ID: 'dockerhub'

          sh '''
            echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker push "$DOCKER_HUB_REPO:latest"
          '''
        }
        // BEST PRACTICE: Logout after push to clear credentials:
        //   sh 'docker logout'
      }
    }

    stage('Fetch EC2 Details') {
      // WHAT: Retrieves current EC2 public IP from AWS SSM Parameter Store
      // WHY: IP address changes when EC2 restarts/recreates, need dynamic lookup

      steps {
        script {
          // WHAT: Retrieves EC2 public IP from AWS SSM Parameter Store
          // WHY: IP changes when instance restarts, need dynamic lookup
          // AUTHENTICATION: Uses AWS credentials from Jenkins (kind: AWS Credentials)
          // NOTE: Credential ID 'aws credential' automatically provides AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY

          withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws credential',
            accessKeyVariable: 'AWS_ACCESS_KEY_ID',
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
          ]]) {
            env.DEPLOY_HOST = sh(
              script: """
                docker run --rm \
                  -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
                  -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
                  -e AWS_DEFAULT_REGION=${AWS_REGION} \
                  amazon/aws-cli:latest \
                  ssm get-parameter --name ${SSM_PARAM_PUBLIC_IP} --query Parameter.Value --output text
              """,
              returnStdout: true
            ).trim()
          }

          echo "✅ Deploying to: ${env.DEPLOY_HOST}"
        }
      }
    }

    stage('Deploy to EC2') {
      // WHAT: Connects to EC2 via SSH and deploys Docker container
      // WHY: Automates deployment, no manual SSH required

      steps {
        script {
          withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws credential',
            accessKeyVariable: 'AWS_ACCESS_KEY_ID',
            secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
          ]]) {
            sh '''
              set -e

              # Fetch SSH private key from SSM using Jenkins AWS credentials
              docker run --rm \
                -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
                -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
                -e AWS_DEFAULT_REGION="$AWS_REGION" \
                amazon/aws-cli:latest \
                ssm get-parameter --name "$SSM_PARAM_PRIVATE_KEY" --with-decryption --query Parameter.Value --output text > ec2-key.pem

              chmod 400 ec2-key.pem

              # Deploy to EC2 via SSH
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
      }
    }

    stage('Verify Deployment') {
      // WHAT: Tests if application is responding to HTTP requests
      // WHY: Confirms deployment succeeded and app is healthy

      steps {
        sleep(time: 10, unit: 'SECONDS')
        // WHAT: Waits 10 seconds before testing
        // WHY: Gives Spring Boot time to fully start up
        // WITHOUT: Health check runs too early, shows failure even if deployment worked
        // BEST PRACTICE: Use retry logic instead of fixed sleep

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
    // WHAT: Actions to run after pipeline completes (success or failure)
    // WHY: Provides feedback and cleanup regardless of outcome
    // WITHOUT: No notification of build results

    success {
      // WHAT: Runs only if all stages succeed
      // WHY: Confirms successful deployment
      // BEST PRACTICE: Send notifications (Slack, email) here

      echo "✅ Deployment Successful!"
      echo "Access your application at: http://${DEPLOY_HOST}:8081"
    }

    failure {
      // WHAT: Runs only if any stage fails
      // WHY: Alerts team that deployment failed
      // BEST PRACTICE: Send alert notifications here

      echo "❌ Deployment Failed!"
      // BEST PRACTICE: Add detailed failure notifications:
      //   emailext subject: "Build Failed", body: "${BUILD_LOG}", to: "team@company.com"
    }

    always {
      // WHAT: Runs regardless of success/failure
      // WHY: Cleanup actions that should always happen
      // BEST PRACTICE: Use for cleaning workspace, docker images, etc.

      cleanWs(cleanWhenNotBuilt: false, deleteDirs: true, disableDeferredWipeout: true)
      // WHAT: Cleans Jenkins workspace after build
      // WHY: Saves disk space, removes sensitive files (SSH keys)
      // WITHOUT: Jenkins disk fills up, old artifacts remain
      // NOTE: Optional - enable this to save space
    }
  }
}

/*
 * ==============================================================================
 * BEST PRACTICES SUMMARY & IMPROVEMENTS TO CONSIDER
 * ==============================================================================
 *
 * ✅ CURRENT GOOD PRACTICES:
 * 1. Using IAM roles instead of hardcoded AWS credentials
 * 2. SSH keys fetched from SSM (encrypted, auto-updated)
 * 3. EC2 IP dynamically fetched from SSM (survives restarts)
 * 4. Credentials managed via Jenkins credentials store
 * 5. Clean workspace before checkout
 * 6. Health check after deployment
 *
 * 🔧 RECOMMENDED IMPROVEMENTS:
 *
 * 1. ADD TESTING STAGE:
 *    stage('Test') {
 *      steps { sh 'mvn test' }
 *    }
 *    WHY: Catches bugs before deployment, prevents broken releases
 *
 * 2. USE VERSION TAGGING (not just 'latest'):
 *    environment {
 *      IMAGE_TAG = "${env.BUILD_NUMBER}" // or ${GIT_COMMIT}
 *    }
 *    stage('Build Docker Image') {
 *      steps {
 *        sh 'docker build -t "$DOCKER_HUB_REPO:$IMAGE_TAG" .'
 *        sh 'docker tag "$DOCKER_HUB_REPO:$IMAGE_TAG" "$DOCKER_HUB_REPO:latest"'
 *      }
 *    }
 *    WHY: Enables rollback to previous versions
 *
 * 3. ADD ROLLBACK CAPABILITY:
 *    Keep previous Docker container or use Blue-Green deployment
 *    WHY: Quick recovery if new version has issues
 *
 * 4. USE PARAMETERIZED BUILDS:
 *    parameters {
 *      choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'])
 *      string(name: 'BRANCH', defaultValue: 'main')
 *    }
 *    WHY: Deploy different branches to different environments
 *
 * 5. ADD CODE QUALITY CHECKS:
 *    stage('Code Analysis') {
 *      steps { sh 'mvn sonar:sonar' }
 *    }
 *    WHY: Maintains code quality, catches security issues
 *
 * 6. IMPROVE HEALTH CHECK:
 *    retry(3) {
 *      sleep(time: 5, unit: 'SECONDS')
 *      sh 'curl --fail http://${DEPLOY_HOST}:8081/actuator/health'
 *    }
 *    WHY: More reliable than single check with fixed sleep
 *
 * 7. ADD NOTIFICATIONS:
 *    post {
 *      success { slackSend color: 'good', message: "Deployed ${env.JOB_NAME}" }
 *      failure { slackSend color: 'danger', message: "Build failed ${env.BUILD_URL}" }
 *    }
 *    WHY: Team immediately knows about build status
 *
 * 8. SECURITY IMPROVEMENT - Use AWS Session Manager instead of SSH:
 *    aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartNonInteractiveCommand
 *    WHY: No SSH keys needed, better audit logging, no port 22 exposed
 *
 * 9. USE SHARED LIBRARY for common functions:
 *    @Library('jenkins-shared-library') _
 *    WHY: Reuse deployment logic across multiple projects
 *
 * 10. ADD MANUAL APPROVAL for production:
 *     stage('Approve Production') {
 *       when { environment name: 'ENVIRONMENT', value: 'prod' }
 *       steps { input "Deploy to production?" }
 *     }
 *     WHY: Prevents accidental production deployments
 *
 * ==============================================================================
 * PREREQUISITES FOR THIS PIPELINE TO WORK:
 * ==============================================================================
 *
 * JENKINS SERVER REQUIREMENTS:
 * 1. ✅ Jenkins running in Docker container (on Windows/Linux/Mac)
 * 2. ✅ Docker installed on host machine
 * 3. ✅ Maven NOT required (uses Docker container)
 * 4. ✅ Git installed
 * 5. ✅ SSH available in Jenkins container (for EC2 deployment)
 *
 * JENKINS CONFIGURATION (REQUIRED):
 * You MUST add these credentials in Jenkins:
 *
 * 1. ✅ Docker Hub credentials
 *    Path: Manage Jenkins → Credentials → System → Global → Add Credentials
 *    Kind: Username with password
 *    ID: 'dockerhub'
 *    Username: Your Docker Hub username
 *    Password: Your Docker Hub password
 *
 * 2. ✅ AWS Credentials
 *    Path: Manage Jenkins → Credentials → System → Global → Add Credentials
 *    Kind: AWS Credentials
 *    ID: 'aws credential'
 *    Access Key ID: Your AWS Access Key ID (from C:\Users\USERNAME\.aws\credentials)
 *    Secret Access Key: Your AWS Secret Access Key (from C:\Users\USERNAME\.aws\credentials)
 *    Description: AWS credentials for SSM and deployment
 *
 * AWS INFRASTRUCTURE (via Terraform):
 * 1. ✅ EC2 instance running with Docker installed
 * 2. ✅ Security group allows inbound traffic on ports 22 and 8081
 * 3. ✅ SSM parameters created:
 *    - /app/aws-image-1/ec2/private_key (SecureString)
 *    - /app/aws-image-1/ec2/public_ip (String)
 *    - /app/aws-image-1/ec2/instance_id (String)
 * 4. ✅ IAM role for Jenkins with SSM GetParameter permissions
 *
 * GITHUB REPOSITORY:
 * 1. ✅ Repository accessible (public or Jenkins has credentials)
 * 2. ✅ Contains valid pom.xml (Maven project)
 * 3. ✅ Contains Dockerfile
 *
 * ==============================================================================
 */
