#!/bin/bash
# ================================================================================
# FILE: destroy.sh
# ================================================================================
#
# Purpose:
#   Orchestrate controlled teardown of Active Directory and dependent
#   RStudio infrastructure.
#
# Teardown Order:
#     1. Destroy RStudio autoscaling cluster.
#     2. Deregister project AMIs and delete associated snapshots.
#     3. Destroy dependent EC2 servers.
#     4. Delete AD-related Secrets Manager entries.
#     5. Destroy Active Directory Domain Controller.
#
# Design Principles:
#   - Reverse dependency order to prevent orphaned resources.
#   - Fail-fast behavior for safe teardown.
#   - Permanent deletion of secrets (no recovery window).
#
# Requirements:
#   - AWS CLI configured and authenticated.
#   - Terraform installed and initialized per module.
#
# Exit Codes:
#   0 = Success
#   1 = Missing directories or Terraform/AWS CLI error
#
# ================================================================================

set -euo pipefail


# ================================================================================
# SECTION: Configuration
# ================================================================================

export AWS_DEFAULT_REGION="us-east-1"


# ================================================================================
# PHASE 1: Destroy RStudio Autoscaling Cluster
# ================================================================================

echo "NOTE: Destroying RStudio Cluster..."

cd 04-cluster || {
  echo "ERROR: Directory 04-cluster not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 2: Deregister AMIs and Delete Snapshots
# ================================================================================

echo "NOTE: Deregistering project AMIs and deleting snapshots..."

for ami_id in $(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=rstudio_ami*" \
  --query "Images[].ImageId" \
  --output text); do

  for snapshot_id in $(aws ec2 describe-images \
    --image-ids "$ami_id" \
    --query "Images[].BlockDeviceMappings[].Ebs.SnapshotId" \
    --output text); do

    echo "NOTE: Deregistering AMI: $ami_id"
    aws ec2 deregister-image --image-id "$ami_id"

    echo "NOTE: Deleting snapshot: $snapshot_id"
    aws ec2 delete-snapshot --snapshot-id "$snapshot_id"
  done
done


# ================================================================================
# PHASE 3: Destroy EC2 Server Instances
# ================================================================================

echo "NOTE: Destroying EC2 server instances..."

cd 02-servers || {
  echo "ERROR: Directory 02-servers not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# PHASE 4: Delete AD Secrets and Destroy Domain Controller
# ================================================================================

echo "NOTE: Deleting AD-related Secrets Manager entries..."

for secret in \
  akumar_ad_credentials_rstudio \
  jsmith_ad_credentials_rstudio \
  edavis_ad_credentials_rstudio \
  rpatel_ad_credentials_rstudio \
  admin_ad_credentials_rstudio; do

  aws secretsmanager delete-secret \
    --secret-id "$secret" \
    --force-delete-without-recovery
done

echo "NOTE: Destroying Active Directory instance..."

cd 01-directory || {
  echo "ERROR: Directory 01-directory not found"
  exit 1
}

terraform init
terraform destroy -auto-approve
cd ..


# ================================================================================
# SECTION: Completion
# ================================================================================

echo "NOTE: Infrastructure teardown complete."
