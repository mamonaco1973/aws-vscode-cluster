#!/bin/bash
# ================================================================================
# FILE: apply.sh
# ================================================================================
#
# Purpose:
#   Orchestrate a four-phase infrastructure deployment for Active Directory
#   and dependent RStudio infrastructure.
#
# Deployment Flow:
#     1. Deploy AD Domain Controller (Terraform).
#     2. Deploy domain-joined EC2 servers (Terraform).
#     3. Build custom RStudio AMI (Packer).
#     4. Deploy RStudio autoscaling cluster (Terraform).
#
# Design Principles:
#   - Strict sequencing to ensure AD is available before dependencies.
#   - Fail-fast behavior using set -euo pipefail.
#   - Environment validation before execution.
#   - Post-build validation after provisioning completes.
#
# Requirements:
#   - AWS CLI configured with sufficient IAM permissions.
#   - Terraform and Packer installed and in PATH.
#   - check_env.sh and validate.sh present in working directory.
#
# Exit Codes:
#   0 = Success
#   1 = Validation failure or provisioning error
#
# ================================================================================


# ================================================================================
# SECTION: Configuration
# ================================================================================

# Target AWS region.
export AWS_DEFAULT_REGION="us-east-1"

# Active Directory DNS zone.
DNS_ZONE="mcloud.mikecloud.com"

# Fail on errors, unset variables, and pipe failures.
set -euo pipefail


# ================================================================================
# SECTION: Environment Validation
# ================================================================================

echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi


# ================================================================================
# PHASE 1: Active Directory Deployment
# ================================================================================

echo "NOTE: Building Active Directory instance..."

cd 01-directory || {
  echo "ERROR: Directory 01-directory not found"
  exit 1
}

terraform init
terraform apply -auto-approve

cd ..


# ================================================================================
# PHASE 2: Dependent EC2 Servers
# ================================================================================

echo "NOTE: Building EC2 server instances..."

cd 02-servers || {
  echo "ERROR: Directory 02-servers not found"
  exit 1
}

terraform init
terraform apply -auto-approve

cd ..


# ================================================================================
# PHASE 3: RStudio AMI Build (Packer)
# ================================================================================

# Resolve networking identifiers for Packer build.
vpc_id=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=rstudio-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text)

subnet_id=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=pub-subnet-1" \
            "Name=vpc-id,Values=$vpc_id" \
  --query "Subnets[0].SubnetId" \
  --output text)
  
cd 03-packer

echo "NOTE: Building RStudio AMI with Packer..."

packer init ./rstudio_ami.pkr.hcl
packer build \
  -var "vpc_id=$vpc_id" \
  -var "subnet_id=$subnet_id" \
  ./rstudio_ami.pkr.hcl || {
    echo "ERROR: Packer build failed. Aborting."
    cd ..
    exit 1
  }

cd ..


# ================================================================================
# PHASE 4: RStudio Autoscaling Cluster
# ================================================================================

echo "NOTE: Building RStudio Autoscaling Cluster..."

cd 04-cluster || {
  echo "ERROR: Directory 04-cluster not found"
  exit 1
}

terraform init
terraform apply -auto-approve

cd ..


# ================================================================================
# SECTION: Post-Deployment Validation
# ================================================================================

./validate.sh
