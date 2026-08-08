#!/bin/bash
# ==============================================================================
# broker.sh - VS Code Session Broker Installation
# ------------------------------------------------------------------------------
# Purpose:
#   - Installs the broker application into /opt/vscode-broker.
#   - Creates an isolated virtualenv for its Python dependencies.
#   - Registers the systemd unit that fronts the cluster on port 8080.
#
# The unit is installed but NOT enabled here. The booter enables it after the
# node has joined the domain, so the broker never accepts a login before SSSD
# can resolve AD users.
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

INSTALL_DIR=/opt/vscode-broker

# ------------------------------------------------------------------------------
# Python runtime
# ------------------------------------------------------------------------------
# Ubuntu 24.04 marks the system interpreter externally-managed (PEP 668), so a
# virtualenv is required — pip cannot install into it directly.
apt-get update
apt-get install -y python3-venv python3-pip

mkdir -p "${INSTALL_DIR}"
cp /tmp/broker/broker.py "${INSTALL_DIR}/broker.py"
cp /tmp/broker/requirements.txt "${INSTALL_DIR}/requirements.txt"

# Login page assets (CSS, logo, favicon). Without these the sign-in page
# renders unstyled — broker.py serves them from this directory.
cp -r /tmp/broker/static "${INSTALL_DIR}/static"

python3 -m venv "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install --upgrade pip
"${INSTALL_DIR}/venv/bin/pip" install -r "${INSTALL_DIR}/requirements.txt"

chmod 0755 "${INSTALL_DIR}"
chmod 0644 "${INSTALL_DIR}/broker.py"
chmod 0755 "${INSTALL_DIR}/static"
chmod 0644 "${INSTALL_DIR}"/static/*

# ------------------------------------------------------------------------------
# Default configuration
# ------------------------------------------------------------------------------
# The booter overwrites this file with values templated from Terraform. The
# defaults here keep the unit startable if that step is ever skipped.
cat <<'EOF' | tee /etc/vscode-broker.env > /dev/null
BROKER_PORT=8080
REQUIRED_GROUP=vscode-users
SESSION_IDLE_MINUTES=120
PORT_RANGE_START=9000
PORT_RANGE_END=9500
VSCODE_STATE_ROOT=/var/lib/vscode
EOF

chmod 0644 /etc/vscode-broker.env

# ------------------------------------------------------------------------------
# systemd unit
# ------------------------------------------------------------------------------
# Runs as root by necessity: it authenticates against PAM and launches
# per-user processes with systemd-run --uid.
#
# Exactly ONE worker. The session registry lives in process memory, so a
# second worker would spawn duplicate code-server instances for one user.
cat <<'EOF' | tee /etc/systemd/system/vscode-broker.service > /dev/null
[Unit]
Description=VS Code session broker
Documentation=https://github.com/mamonaco1973/aws-vscode-cluster
After=network-online.target sssd.service
Wants=network-online.target

[Service]
Type=exec
WorkingDirectory=/opt/vscode-broker
EnvironmentFile=-/etc/vscode-broker.env
ExecStart=/opt/vscode-broker/venv/bin/uvicorn broker:app \
          --host 0.0.0.0 --port ${BROKER_PORT} --workers 1 \
          --proxy-headers --forwarded-allow-ips='*'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Deliberately not enabled — the booter starts it post domain join.
