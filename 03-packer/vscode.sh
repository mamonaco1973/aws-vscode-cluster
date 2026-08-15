#!/bin/bash
# ==============================================================================
# vscode.sh - code-server Installation and PAM Wiring
# ------------------------------------------------------------------------------
# Purpose:
#   - Installs code-server (open-source VS Code server) into the AMI.
#   - Wires a PAM stack so the broker can authenticate AD users via SSSD.
#   - Creates the node-local state root used for per-user editor state.
#
# Design Note:
#   code-server is a SINGLE-user process with a shared-password auth model.
#   It is deliberately NOT enabled as a system service here. The broker
#   (see broker.sh) starts one instance per logged-in user via systemd-run,
#   bound to loopback only. Enabling it globally would give every user the
#   same identity and the same home directory.
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------------------
# Install code-server
# ------------------------------------------------------------------------------
# CODE_SERVER_VERSION may be exported by the Packer build to pin a release.
# Left empty the upstream installer resolves "latest", which is convenient for
# development but means two AMI builds can differ — pin it for real rollouts.
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-}"

cd /tmp
curl -fsSL https://code-server.dev/install.sh -o install-code-server.sh

if [ -n "$CODE_SERVER_VERSION" ]; then
  bash ./install-code-server.sh --version "$CODE_SERVER_VERSION"
else
  bash ./install-code-server.sh
fi

rm -f ./install-code-server.sh

# Record the built version so a running node can report what it shipped with.
/usr/bin/code-server --version | head -1 | tee /etc/vscode-server-version

# The installer registers a user-scoped template unit. Mask nothing, but make
# sure no system-wide instance is enabled — the broker owns process lifecycle.
systemctl disable --now code-server@ubuntu.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# Extension gallery — Open VSX, deliberately
# ------------------------------------------------------------------------------
# This is a licensing boundary, not a preference. code-server is MIT, but
# Microsoft's Marketplace terms permit access only from official Microsoft
# products, so pointing EXTENSIONS_GALLERY there would make a lawful build
# unlawful without changing a line of code.
#
# Open VSX is code-server's default; setting it explicitly means a future
# override has to be a deliberate act rather than an unnoticed default.
# Extensions missing from Open VSX go through /efs/extensions as VSIX files
# obtained from their publishers — never scraped from the Marketplace.
cat <<'EOF' | tee /etc/vscode-gallery.env > /dev/null
EXTENSIONS_GALLERY={"serviceUrl":"https://open-vsx.org/vscode/gallery","itemUrl":"https://open-vsx.org/vscode/item"}
EOF

chmod 0644 /etc/vscode-gallery.env

# ------------------------------------------------------------------------------
# Default editor settings
# ------------------------------------------------------------------------------
# Seeded by the broker into each user's settings.json the first time their
# state directory is created, then left alone — a user who changes one of
# these keeps their change.
#
# Extension auto-update is OFF deliberately. Every workbench load otherwise
# queries the gallery, which leaves the node through the NAT gateway; a slow
# or hanging lookup stalls the extension host and the editor stops responding
# for as long as it takes. Users can still install and update on demand.
cat <<'EOF' | tee /etc/vscode-default-settings.json > /dev/null
{
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false
}
EOF

chmod 0644 /etc/vscode-default-settings.json

# ------------------------------------------------------------------------------
# Node-local per-user state root
# ------------------------------------------------------------------------------
# code-server keeps its state in SQLite. SQLite over NFS is the classic
# corruption scenario, so state lives on instance-local disk while user FILES
# live on EFS-backed /home. Cost: editor layout is lost if a node is replaced.
mkdir -p /var/lib/vscode
chmod 0751 /var/lib/vscode

# ------------------------------------------------------------------------------
# PAM stack for the broker
# ------------------------------------------------------------------------------
# common-auth routes through SSSD, so AD credentials work exactly as they do
# for SSH. The pam_exec line forces home-directory creation on first login,
# mirroring the trick the RStudio build used.
cat <<'EOF' | tee /etc/pam.d/vscode > /dev/null
# PAM configuration for the VS Code session broker

auth     include   common-auth
auth     [success=ok new_authtok_reqd=ok ignore=ignore user_unknown=bad default=die] pam_exec.so /etc/pam.d/vscode-mkhomedir.sh
account  include   common-account
password include   common-password
session  include   common-session
EOF

# ------------------------------------------------------------------------------
# Deploy PAM script to create home directories on first login
# ------------------------------------------------------------------------------
cat <<'EOF' | tee /etc/pam.d/vscode-mkhomedir.sh > /dev/null
#!/bin/bash
su -c "exit" $PAM_USER
EOF

chmod +x /etc/pam.d/vscode-mkhomedir.sh
