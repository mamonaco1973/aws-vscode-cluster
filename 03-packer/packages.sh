#!/bin/bash
set -euo pipefail
# ---------------------------------------------------------------------------------
# Update OS and Install Required Packages
# ---------------------------------------------------------------------------------
# Refresh package metadata
apt-get update -y

# Prevent interactive prompts during package installs
export DEBIAN_FRONTEND=noninteractive

# Install packages needed for:
#   - Active Directory integration: realmd, sssd-ad, sssd-tools, adcli, krb5-user
#   - NSS/PAM integration: libnss-sss, libpam-sss
#   - Samba client tools: samba-common-bin, samba-libs
#   - Home directory automation: oddjob, oddjob-mkhomedir
#   - EFS mounts: nfs-common, stunnel4 (TLS)
#   - In-session development: build-essential, cmake, python3-pip
#   - Utilities: less, unzip, nano, vim

echo "=== Phase 1: Base utilities and AD join tools ==="

apt-get install -y less unzip realmd sssd-ad sssd-tools libnss-sss \
    libpam-sss adcli samba-common-bin samba-libs oddjob \
    oddjob-mkhomedir packagekit krb5-user nano vim stunnel4 \
    nfs-common

echo "=== Phase 2: Build tools for in-session development ==="
apt-get install -y build-essential cmake python3-pip

echo "=== Phase 3: Clean up ==="
apt-get autoremove -y
apt-get clean

# Install Amazon EFS utilities (for mounting EFS with TLS support)
cd /tmp
git clone https://github.com/mamonaco1973/amazon-efs-utils.git
cd amazon-efs-utils
sudo dpkg -i amazon-efs-utils*.deb  
which mount.efs
