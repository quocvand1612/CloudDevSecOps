#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "=== Starting Ephemeral GitHub Runner Initialization at $(date) ==="

# 1. Update OS and Install Base Tools
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    git \
    unzip \
    tar \
    build-essential \
    libssl-dev \
    libffi-dev

# 2. Install AWS CLI v2
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    CLI_ARCH="aarch64"
    RUNNER_ARCH="arm64"
else
    CLI_ARCH="x86_64"
    RUNNER_ARCH="x64"
fi

curl "https://awscli.amazonaws.com/awscli-exe-linux-$${CLI_ARCH}.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update
rm -rf awscliv2.zip aws

# 3. Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# 4. Create Dedicated Runner User
id -u runner &>/dev/null || useradd -m -s /bin/bash -G docker runner
echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

# 5. Fetch Runner Registration Token
# Token can be fetched from AWS Secrets Manager or Parameter Store
TOKEN_SECRET_NAME="${token_secret_name}"
AWS_REGION="${aws_region}"

echo "Fetching runner registration token from AWS Secrets Manager: $TOKEN_SECRET_NAME"
RUNNER_TOKEN=$(aws secretsmanager get-secret-value --secret-id "$TOKEN_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION" 2>/dev/null || true)

if [ -z "$RUNNER_TOKEN" ]; then
    echo "Warning: Secret $TOKEN_SECRET_NAME empty or unavailable. Checking parameter store..."
    RUNNER_TOKEN=$(aws ssm get-parameter --name "/github-runners/${github_org}/token" --with-decryption --query Parameter.Value --output text --region "$AWS_REGION" 2>/dev/null || true)
fi

if [ -z "$RUNNER_TOKEN" ]; then
    echo "ERROR: Failed to retrieve runner token! Cannot proceed."
    exit 1
fi

# 6. Download and Setup GitHub Actions Runner
RUNNER_VERSION="2.321.0"
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
chown -R runner:runner "$RUNNER_DIR"

cd "$RUNNER_DIR"
su runner -c "curl -o actions-runner-linux.tar.gz -L https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-$${RUNNER_ARCH}-$${RUNNER_VERSION}.tar.gz"
su runner -c "tar xzf ./actions-runner-linux.tar.gz"
su runner -c "rm -f actions-runner-linux.tar.gz"

# Install runner dependencies
./bin/installdependencies.sh

# 7. Configure Runner as Ephemeral
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/instance-id)
RUNNER_NAME="aws-spot-$INSTANCE_ID"

echo "Configuring Ephemeral Runner $RUNNER_NAME for org https://github.com/${github_org}..."
su runner -c "./config.sh \
    --url https://github.com/${github_org} \
    --token '$RUNNER_TOKEN' \
    --name '$RUNNER_NAME' \
    --labels '${runner_labels}' \
    --work _work \
    --ephemeral \
    --unattended \
    --replace"

# 8. Run Job Once (Self-Exiting)
echo "Starting GitHub Runner listener (will exit automatically after 1 job)..."
su runner -c "./run.sh" || true

# 9. Self-Termination and Scale Down to 0
echo "=== Job Completed! Self-terminating instance $INSTANCE_ID and scaling down ASG ==="
aws autoscaling terminate-instance-in-auto-scaling-group \
    --instance-id "$INSTANCE_ID" \
    --should-decrement-desired-capacity \
    --region "$AWS_REGION" || true

shutdown -h now
