#!/bin/bash
set -euo pipefail

# Log all outputs for debugging
exec > >(tee -a /var/log/azure-runner-init.log | logger -t azure-runner -s 2>/dev/console) 2>&1
echo "=== Starting Azure Ephemeral GitHub Runner Initialization at $(date) ==="

# 1. Install Base Packages
export DEBIAN_FRONTEND=noninteractive
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
    libicu-dev

# 2. Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# 3. Create Dedicated Runner User
id -u runner &>/dev/null || useradd -m -s /bin/bash -G docker runner
echo "runner ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner

# 4. Fetch Runner Token from Azure Key Vault via Managed Identity IMDS
KEY_VAULT_NAME="${key_vault_name}"
SECRET_NAME="${secret_name}"

echo "Fetching Key Vault token via IMDS Managed Identity..."
KV_TOKEN=""
for i in {1..15}; do
    echo "Attempt $i: Requesting vault token from IMDS..."
    KV_TOKEN=$(curl -s -f -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | jq -r .access_token 2>/dev/null || true)
    if [ -n "$KV_TOKEN" ] && [ "$KV_TOKEN" != "null" ]; then
        echo "Successfully acquired Key Vault access token."
        break
    fi
    sleep 3
done

if [ -z "$KV_TOKEN" ] || [ "$KV_TOKEN" = "null" ]; then
    echo "ERROR: Failed to acquire Key Vault OAuth token from IMDS!"
    exit 1
fi

echo "Retrieving GitHub runner registration token from Key Vault: $KEY_VAULT_NAME"
RUNNER_TOKEN=""
for j in {1..15}; do
    RUNNER_TOKEN=$(curl -s -f -H "Authorization: Bearer $KV_TOKEN" "https://$KEY_VAULT_NAME.vault.azure.net/secrets/$SECRET_NAME?api-version=7.4" | jq -r .value 2>/dev/null || true)
    if [ -n "$RUNNER_TOKEN" ] && [ "$RUNNER_TOKEN" != "null" ]; then
        echo "Successfully retrieved runner registration token."
        break
    fi
    echo "Attempt $j: Waiting for Key Vault secret response..."
    sleep 3
done

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
    echo "ERROR: Failed to retrieve runner token from Key Vault REST endpoint!"
    exit 1
fi

# 5. Download and Setup Actions Runner
RUNNER_VERSION="2.321.0"
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
chown -R runner:runner "$RUNNER_DIR"

cd "$RUNNER_DIR"
su runner -c "curl -o actions-runner-linux.tar.gz -L https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
su runner -c "tar xzf ./actions-runner-linux.tar.gz"
su runner -c "rm -f actions-runner-linux.tar.gz"

./bin/installdependencies.sh

# 6. Configure Runner as Ephemeral
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

# 7. Run Job Once (Self-Exiting on Ephemeral mode)
echo "Starting GitHub Runner execution..."
su runner -c "./run.sh" || true

# 8. Self-Deallocate / Scale Down VMSS via ARM REST API
echo "=== Job Completed! Self-terminating Azure VMSS instance $HOSTNAME ==="
ARM_TOKEN=$(curl -s -f -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com" | jq -r .access_token 2>/dev/null || true)
INSTANCE_ID=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/instanceId?api-version=2021-02-01&format=text" 2>/dev/null || true)

if [ -n "$ARM_TOKEN" ] && [ "$ARM_TOKEN" != "null" ] && [ -n "$INSTANCE_ID" ]; then
    echo "Deleting VMSS instance $INSTANCE_ID from scale set ${vmss_name}..."
    curl -s -X POST -H "Authorization: Bearer $ARM_TOKEN" -H "Content-Type: application/json" \
        -d "{\"instanceIds\": [\"$INSTANCE_ID\"]}" \
        "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group_name}/providers/Microsoft.Compute/virtualMachineScaleSets/${vmss_name}/delete?api-version=2023-09-01" || true
fi

shutdown -h now
