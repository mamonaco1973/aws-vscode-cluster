#!/bin/bash
# ==============================================================================
# validate.sh - Active Directory + RStudio Cluster Validation
# ==============================================================================
# Purpose:
#   Validates the deployed AWS lab environment by retrieving:
#     - Windows AD Administration host (public DNS for RDP access)
#     - Linux EFS/Samba gateway host (public DNS / public IP)
#     - RStudio Application Load Balancer endpoint
#
# Notes:
#   - Requires AWS CLI configured with appropriate permissions.
#   - Instances must be tagged correctly:
#       Name = windows-ad-admin
#       Name = efs-samba-gateway
#   - ALB must exist with name "rstudio-alb"
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"

echo ""
echo "============================================================================"
echo "RStudio AD Lab - Validation Output"
echo "============================================================================"
echo ""

# ------------------------------------------------------------------------------
# Lookup Windows AD Admin Instance (Public DNS)
# ------------------------------------------------------------------------------
windows_dns="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=windows-ad-admin" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text | xargs)"

# ------------------------------------------------------------------------------
# Lookup Linux EFS Gateway Instance (Public DNS / Public IP)
# ------------------------------------------------------------------------------
linux_dns="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=efs-samba-gateway" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text | xargs)"

linux_ip="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=efs-samba-gateway" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text | xargs)"

# ------------------------------------------------------------------------------
# Lookup RStudio ALB
# ------------------------------------------------------------------------------
alb_dns="$(aws elbv2 describe-load-balancers \
  --names rstudio-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text | xargs)"

# ------------------------------------------------------------------------------
# Pretty Aligned Output (Only formatting improvement)
# ------------------------------------------------------------------------------
label_width=28

print_line() {
  local label="$1"
  local value="$2"
  printf "NOTE: %-*s %s\n" "${label_width}" "${label}:" "${value}"
}

# Windows
if [ -z "${windows_dns}" ] || [ "${windows_dns}" = "None" ]; then
  print_line "Windows RDP Host FQDN" \
    "WARNING: windows-ad-admin not found or no public DNS"
else
  print_line "Windows RDP Host FQDN" "${windows_dns}"
fi

# Linux (prefer public DNS, fallback to public IP)
linux_value=""
if [ -n "${linux_dns}" ] && [ "${linux_dns}" != "None" ]; then
  linux_value="${linux_dns}"
elif [ -n "${linux_ip}" ] && [ "${linux_ip}" != "None" ]; then
  linux_value="${linux_ip}"
fi

if [ -z "${linux_value}" ]; then
  print_line "Linux Gateway Public" \
    "WARNING: efs-samba-gateway not found or no public IP/DNS"
else
  print_line "Linux Gateway Public" "${linux_value}"
fi

# ALB
if [ -z "${alb_dns}" ] || [ "${alb_dns}" = "None" ]; then
  print_line "RStudio ALB Endpoint" \
    "WARNING: rstudio-alb not found"
else
  print_line "RStudio ALB Endpoint" "http://${alb_dns}"
fi

echo ""
