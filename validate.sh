#!/bin/bash
# ==============================================================================
# validate.sh - Active Directory + VS Code Cluster Validation
# ==============================================================================
# Purpose:
#   Validates the deployed AWS lab environment by retrieving:
#     - Windows AD Administration host (public DNS for RDP access)
#     - Linux EFS/Samba gateway host (public DNS / public IP)
#     - VS Code Application Load Balancer endpoint (HTTPS)
#
# Notes:
#   - Requires AWS CLI configured with appropriate permissions.
#   - Instances must be tagged correctly:
#       Name = windows-ad-admin
#       Name = efs-samba-gateway
#   - ALB must exist with name "vscode-alb"
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"

echo ""
echo "============================================================================"
echo "VS Code AD Lab - Validation Output"
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
# Lookup VS Code ALB
# ------------------------------------------------------------------------------
alb_dns="$(aws elbv2 describe-load-balancers \
  --names vscode-alb \
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
  print_line "VS Code ALB Endpoint" \
    "WARNING: vscode-alb not found"
else
  print_line "VS Code URL" "https://${alb_dns}"

  # ----------------------------------------------------------------------------
  # Broker Reachability Check
  # ----------------------------------------------------------------------------
  # -k is required: the ALB presents a self-signed certificate, so curl would
  # otherwise refuse the connection. Targets can take a few minutes to pass
  # health checks after apply, so a failure here is not necessarily fatal.
  health="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
    "https://${alb_dns}/healthz" || true)"

  if [ "${health}" = "200" ]; then
    print_line "Session Broker" "healthy (/healthz returned 200)"
  else
    print_line "Session Broker" \
      "WARNING: /healthz returned '${health}' - targets may still be booting"
  fi
fi

echo ""
echo "NOTE: Sign in with an AD account (e.g. jsmith or rpatel)."
echo "NOTE: Passwords are stored in Secrets Manager as <user>_ad_credentials_vscode."
echo ""
echo "NOTE: The ALB uses a self-signed certificate. Browsers will warn once —"
echo "      choose Advanced then Proceed. This is expected."
echo ""
