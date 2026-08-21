#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/azure-runner-init.log | logger -t azure-runner -s 2>/dev/console) 2>&1
echo "=== Starting Azure Ephemeral GitHub Runner Initialization at $(date) ==="

# 1. Install Base Packages
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
    build-essential

# 2. Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

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

# 5. Fetch Runner Token from Azure Key Vault (via Managed Identity)
KEY_VAULT_NAME="${key_vault_name}"
SECRET_NAME="${secret_name}"

echo "Authenticating via Azure Managed Identity..."
az login --identity --allow-no-subscriptions || true

echo "Retrieving GitHub runner registration token from Key Vault: $KEY_VAULT_NAME"
RUNNER_TOKEN=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$SECRET_NAME" --query value -o tsv 2>/dev/null || true)

if [ -z "$RUNNER_TOKEN" ]; then
    echo "ERROR: Failed to retrieve runner token from Key Vault!"
    exit 1
fi

# 6. Download and Setup Actions Runner
RUNNER_VERSION="2.321.0"
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
chown -R runner:runner "$RUNNER_DIR"

cd "$RUNNER_DIR"
su runner -c "curl -o actions-runner-linux.tar.gz -L https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
su runner -c "tar xzf ./actions-runner-linux.tar.gz"
su runner -c "rm -f actions-runner-linux.tar.gz"

./bin/installdependencies.sh

# 7. Configure Runner as Ephemeral
HOSTNAME=$(hostname)
RUNNER_NAME="azure-spot-$HOSTNAME"

echo "Configuring Ephemeral Runner $RUNNER_NAME for https://github.com/${github_org}..."
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
echo "Starting GitHub Runner execution loop..."
su runner -c "./run.sh" || true

# 9. Self-Deallocate / Scale Down VMSS
echo "=== Job Completed! Deallocating Azure VMSS instance $HOSTNAME ==="
# Get Instance ID from Azure IMDS
INSTANCE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/instanceId?api-version=2021-02-01&format=text" || true)

if [ -n "$INSTANCE_ID" ]; then
    az vmss delete-instances \
        --resource-group "${resource_group_name}" \
        --name "${vmss_name}" \
        --instance-ids "$INSTANCE_ID" || true
fi

shutdown -h now
