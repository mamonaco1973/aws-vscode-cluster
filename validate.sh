#!/bin/bash
# ==============================================================================
# validate.sh - Active Directory + VS Code Validation (DEBUG MODE)
# ==============================================================================
# Purpose:
#   Validates the deployed AWS lab environment by retrieving:
#     - Windows AD Administration host (public DNS for RDP access)
#     - Linux EFS/Samba gateway host (public DNS / public IP)
#     - Standalone debug instance URL and broker health (DEBUG MODE)
#
# Notes:
#   - Requires AWS CLI configured with appropriate permissions.
#   - Instances must be tagged correctly:
#       Name = windows-ad-admin
#       Name = efs-samba-gateway
#       Name = vscode-debug-instance
#   - The ALB lookup is disabled while 04-cluster runs the standalone debug
#     instance instead of the autoscaling cluster.
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

# ##############################################################################
# !! DEBUG MODE - REVERT WITH 04-cluster/debug_instance.tf !!
# ------------------------------------------------------------------------------
# The ALB lookup is skipped while the standalone debug instance replaces the
# autoscaling cluster. Restore the block below when alb.tf is re-enabled:
#
#   alb_dns="$(aws elbv2 describe-load-balancers \
#     --names vscode-alb \
#     --query 'LoadBalancers[0].DNSName' \
#     --output text | xargs)"
# ##############################################################################
alb_dns=""

# ------------------------------------------------------------------------------
# Lookup Standalone Debug Instance (DEBUG MODE)
# ------------------------------------------------------------------------------
debug_dns="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=vscode-debug-instance" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text | xargs)"

debug_id="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=vscode-debug-instance" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
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

# ALB (skipped in DEBUG MODE)
if [ -n "${alb_dns}" ] && [ "${alb_dns}" != "None" ]; then
  print_line "VS Code ALB Endpoint" "http://${alb_dns}"
fi

# Standalone debug instance
if [ -z "${debug_dns}" ] || [ "${debug_dns}" = "None" ]; then
  print_line "Debug Instance" \
    "WARNING: vscode-debug-instance not found or not running"
else
  print_line "Debug Instance ID" "${debug_id}"
  print_line "Debug Broker URL" "http://${debug_dns}:8080"

  # ----------------------------------------------------------------------------
  # Broker Reachability Check
  # ----------------------------------------------------------------------------
  # /healthz answers without a cookie. The instance needs a few minutes after
  # apply to join the domain and start the broker, so a failure here shortly
  # after deployment is expected rather than fatal.
  health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    "http://${debug_dns}:8080/healthz" || true)"

  if [ "${health}" = "200" ]; then
    print_line "Session Broker" "healthy (/healthz returned 200)"
  else
    print_line "Session Broker" \
      "WARNING: /healthz returned '${health}' - may still be booting"
  fi

  echo ""
  echo "NOTE: SSM port forward (bypasses ISP/carrier filtering):"
  echo "      aws ssm start-session --target ${debug_id} \\"
  echo "        --document-name AWS-StartPortForwardingSession \\"
  echo "        --parameters portNumber=8080,localPortNumber=8080"
fi

echo ""
echo "NOTE: Sign in with an AD account (e.g. jsmith or rpatel)."
echo "NOTE: Passwords are stored in Secrets Manager as <user>_ad_credentials_vscode."
echo ""
