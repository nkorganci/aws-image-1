Goal

Provide a secure, automated workflow so that when Terraform creates an EC2 instance and uploads its generated private key to SSM Parameter Store (SecureString), Jenkins can retrieve that private key at runtime without a human manually adding credentials.

Overview (recommended best practice)

- Have Terraform generate the keypair and store the private key in AWS Systems Manager Parameter Store as a SecureString (done in Terraform).
- Give the EC2 instance an IAM instance profile with AmazonSSMManagedInstanceCore so SSM can manage the instance (done in Terraform).
- For Jenkins to retrieve secrets from SSM at build time, grant the Jenkins agent (or Jenkins master) an IAM role or IAM user credentials that allow ssm:GetParameter for the parameter path. Prefer assigning IAM role to the Jenkins EC2 agent (if using EC2 agents) or use an IAM Role for Service Accounts (IRSA) if Jenkins is running in EKS.
- Use the AWS CLI or the AWS SDK in Jenkins pipeline steps to read the SecureString and use it (write it to a file with restrictive permissions) or pass it into the build step via environment variables.

Files changed

- terraform/main.tf: added IAM role/instance profile for SSM and created an SSM SecureString parameter with the generated private key.
- terraform/outputs.tf: added outputs for the SSM parameter name and ARN so automation (like Jenkins) can discover it.

Jenkins options (pick one based on your setup)

1) Jenkins running on an EC2 instance (recommended for minimal changes)
   - Create an IAM instance profile for the Jenkins instance with a policy that allows reading the specific SSM parameter(s): ssm:GetParameter and kms:Decrypt (if using a custom KMS key).
   - Attach that profile to the Jenkins server (or the agent instances) so pipeline steps can call AWS CLI without long-lived keys.

2) Jenkins on AWS ECS / EKS (modern) - use task role or IRSA respectively.

3) Jenkins on-premises / outside AWS
   - Create an IAM user with a least-privilege policy to read the SSM parameter and add the programmatic Access Key ID / Secret to Jenkins Credentials (AWS credentials type) or use pipeline with aws-vault. Prefer rotating those credentials.

Minimum IAM policy for reading a specific SSM parameter (least privilege)

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.project_name}/ec2/private_key"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "*"
    }
  ]
}

(If using the default AWS-managed encryption for SSM SecureString in the same account, you may not need a KMS grant for the Jenkins principal.)

Sample Jenkinsfile (Declarative Pipeline) snippet

pipeline {
  agent any
  environment {
    AWS_DEFAULT_REGION = "${AWS_REGION}"
  }
  stages {
    stage('Fetch EC2 Private Key from SSM') {
      steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'jenkins-aws-creds']]) {
          sh '''
            # Write the SecureString to a private file with restrictive permissions
            aws ssm get-parameter --name "+${SSM_PARAM_NAME}+" --with-decryption --query Parameter.Value --output text > ec2-key.pem
            chmod 400 ec2-key.pem
            # Use it for SSH or other steps
            ssh -i ec2-key.pem ${SSH_USER}@${INSTANCE_IP} hostname
          '''
        }
      }
    }
  }
}

Notes on Jenkins UI configuration

- If Jenkins runs outside AWS, create a new credential of type "AWS Credentials" (requires the AWS Credentials plugin) and paste the programmatic access key/secret; use its ID in the pipeline as `jenkins-aws-creds`.
- If Jenkins runs on EC2 and uses instance profile access, you don't need to add credentials in Jenkins UI; the AWS CLI will pick them up from the instance metadata.
- Ensure the Jenkins node has AWS CLI installed and configured in PATH, or use the official AWS Steps / plugins that can access SSM.

Security considerations and best practices

- Use SecureString and KMS for the private key. Limit the parameter's resource-based access using least privilege.
- Prefer using IAM roles (instance profiles, task roles, IRSA) over long-lived IAM users/keys.
- Rotate keys when possible. Consider using AWS Secrets Manager if you want built-in rotation workflows (Secrets Manager is more expensive but offers rotation).
- Limit parameter TTL and deletion policies; consider lifecycle management.

Next steps (apply and test)

1) terraform init && terraform apply -var '...'
2) Note the output `ssm_private_key_name` and `instance_public_ip` (from outputs).
3) Configure Jenkins credentials or ensure the Jenkins agent has an IAM role with ssm:GetParameter.
4) Run a pipeline that calls `aws ssm get-parameter --with-decryption --name "/${var.project_name}/ec2/private_key" --query Parameter.Value --output text` and writes it to a file with 0400 permissions.

If you'd like, I can:
- Add an example IAM policy file into the repo.
- Generate a sample Jenkinsfile with a fully-populated pipeline that references your Terraform outputs (if you provide the output names or we keep them dynamic).
- Show how to restrict the SSM parameter using a KMS CMK and grant decrypt permissions only to the Jenkins principal.

