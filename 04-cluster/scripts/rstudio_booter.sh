#!/bin/bash

set -euo pipefail

LOG=/root/userdata.log
mkdir -p /root
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR
echo "user-data start: $(date -Is)"

# ---- EFS mounts ----
mkdir -p /efs
echo "${efs_mnt_server}:/ /efs   efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /efs

mkdir -p /efs/home
mkdir -p /efs/data

echo "${efs_mnt_server}:/home /home  efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /home

# ---- AD join ----
secretValue=$(aws secretsmanager get-secret-value --secret-id ${admin_secret} \
  --query SecretString --output text)

admin_password=$(echo $secretValue | jq -r '.password')
admin_username=$(echo $secretValue | jq -r '.username' | sed 's/.*\\//')

echo -e "$admin_password" | sudo /usr/sbin/realm join \
  -U "$admin_username" \
  ${domain_fqdn} \
  --verbose 
  
# ---- SSH + SSSD config ----
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' \
  /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
  /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
  /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
  /etc/sssd/sssd.conf
sudo sed -i 's/^access_provider = ad$/access_provider = simple\nsimple_allow_groups = ${force_group}/' \
  /etc/sssd/sssd.conf

ln -s /efs /etc/skel/efs
touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

sudo pam-auth-update --enable mkhomedir
sudo systemctl restart ssh
sudo systemctl restart sssd
sudo systemctl restart rstudio-server
sudo systemctl enable rstudio-server

# ---- Sudo privileges ----
echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/10-linux-admins

# ---- Home permissions ----
sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs

# ---- R library path ----
cat <<'EOF' | sudo tee /usr/lib/R/etc/Rprofile.site > /dev/null
local({
  userlib <- Sys.getenv("R_LIBS_USER")
  if (!dir.exists(userlib)) {
    dir.create(userlib, recursive = TRUE, showWarnings = FALSE)
  }
  efs <- "/efs/rlibs"
  .libPaths(c(userlib, efs, .libPaths()))
})
EOF

chgrp rstudio-admins /efs/rlibs
