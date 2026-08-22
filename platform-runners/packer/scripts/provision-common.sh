#!/bin/bash
# ==============================================================================
# Golden Image Provisioning - Common DevOps/DevSecOps toolchain
# Shared between AWS AMI and Azure Managed Image builds.
# Cloud-specific CLI (aws-cli / az-cli) is installed by the calling template
# via CLOUD env var passed through Packer's shell provisioner `environment_vars`.
# ==============================================================================
set -euo pipefail

echo "=== Golden image provisioning started at $(date) (CLOUD=${CLOUD:-unknown}) ==="
export DEBIAN_FRONTEND=noninteractive

# 1. Base packages (same set previously installed at every boot)
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
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
    libffi-dev \
    libicu-dev \
    software-properties-common

# 2. Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  RUNNER_ARCH="arm64"; BIN_ARCH="arm64"; TF_ARCH="arm64"
else
  RUNNER_ARCH="x64"; BIN_ARCH="amd64"; TF_ARCH="amd64"
fi

# 3. Cloud CLI
if [ "${CLOUD:-}" = "aws" ]; then
  if [ "$ARCH" = "aarch64" ]; then CLI_ARCH="aarch64"; else CLI_ARCH="x86_64"; fi
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-${CLI_ARCH}.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws)
elif [ "${CLOUD:-}" = "azure" ]; then
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

# 4. Terraform CLI
TF_VERSION="1.9.8"
curl -sL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip" -o /tmp/terraform.zip
sudo unzip -q -o /tmp/terraform.zip -d /usr/local/bin && rm -f /tmp/terraform.zip

# 5. tflint
curl -sL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | sudo bash

# 6. kubectl + Helm
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${BIN_ARCH}/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl
curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash

# 7. Trivy (container/IaC vulnerability scanner)
curl -sL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

# 8. Checkov (IaC security scanner) - needs pip
sudo apt-get install -y --no-install-recommends python3-pip pipx
sudo pipx install --global checkov

# 9. Semgrep (SAST)
sudo pipx install --global semgrep

# 10. cosign + syft/grype (image signing & SBOM)
curl -sL "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-${BIN_ARCH}" -o /tmp/cosign
sudo install -m 0755 /tmp/cosign /usr/local/bin/cosign && rm -f /tmp/cosign
curl -sL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin
curl -sL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin

# 11. Dedicated runner user (matching the existing boot-script convention)
sudo id -u runner &>/dev/null || sudo useradd -m -s /bin/bash -G docker runner
echo "runner ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/runner > /dev/null

# 12. Pre-download and extract GitHub Actions runner binary (version pinned;
#     must be bumped here AND in the boot script's RUNNER_VERSION together)
RUNNER_VERSION="2.336.0"
RUNNER_DIR="/home/runner/actions-runner"
sudo mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
sudo curl -o actions-runner-linux.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
sudo tar xzf actions-runner-linux.tar.gz
sudo rm -f actions-runner-linux.tar.gz
sudo ./bin/installdependencies.sh
sudo chown -R runner:runner "$RUNNER_DIR"

# 13. Clean up apt caches to keep image size down
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Marker consumed by the VM bootstrap scripts. Keeping the runner version in
# the marker prevents an older image from silently skipping a required update.
printf 'runner_version=%s\ncloud=%s\n' "$RUNNER_VERSION" "${CLOUD:-unknown}" | sudo tee /etc/devsecops-runner-golden > /dev/null

echo "=== Golden image provisioning completed at $(date) ==="
echo "--- Versions baked in ---"
docker --version || true
terraform --version || true
tflint --version || true
kubectl version --client || true
helm version || true
trivy --version || true
checkov --version || true
semgrep --version || true
cosign version || true
syft version || true
grype version || true
