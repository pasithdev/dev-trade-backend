#!/usr/bin/env bash
# =============================================================
#  Crypto-Bot — Ubuntu Install & Config Script
#  Tested on Ubuntu 22.04 / 24.04 LTS
#
#  Usage:
#    chmod +x setup.sh
#    sudo ./setup.sh
# =============================================================

set -euo pipefail

# ---------- colours ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------- config ----------
APP_NAME="crypto-bot"
APP_DIR="/opt/${APP_NAME}"
VENV_DIR="${APP_DIR}/venv"
SERVICE_NAME="${APP_NAME}.service"
SERVICE_USER="cryptobot"
PYTHON_VERSION="3.11"    # minimum required

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Crypto-Bot — Ubuntu Setup Script${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ---------- root check ----------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root (use sudo).${NC}"
    exit 1
fi

# =============================================================
# 1. System Packages
# =============================================================
echo -e "${GREEN}[1/7] Updating system and installing dependencies...${NC}"
apt-get update -y
apt-get install -y \
    software-properties-common \
    curl \
    wget \
    git \
    build-essential \
    libssl-dev \
    libffi-dev

# ---------- Python 3.11+ ----------
echo -e "${GREEN}[2/7] Installing Python ${PYTHON_VERSION}...${NC}"
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -y
apt-get install -y \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-distutils

# Make sure pip is available
curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION}

echo -e "${GREEN}  → Python version:${NC}"
python${PYTHON_VERSION} --version

# =============================================================
# 2. Create system user (no-login)
# =============================================================
echo -e "${GREEN}[3/7] Creating system user '${SERVICE_USER}'...${NC}"
if id "${SERVICE_USER}" &>/dev/null; then
    echo -e "${YELLOW}  → User '${SERVICE_USER}' already exists, skipping.${NC}"
else
    useradd --system --no-create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
    echo -e "${GREEN}  → Created user '${SERVICE_USER}'.${NC}"
fi

# =============================================================
# 3. Deploy application code
# =============================================================
echo -e "${GREEN}[4/7] Deploying application to ${APP_DIR}...${NC}"
mkdir -p "${APP_DIR}"

# Copy project files (run from the directory containing setup.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "${SCRIPT_DIR}/bot.py"            "${APP_DIR}/"
cp "${SCRIPT_DIR}/backend_client.py" "${APP_DIR}/"
cp "${SCRIPT_DIR}/binance_client.py" "${APP_DIR}/"
cp "${SCRIPT_DIR}/requirements.txt"  "${APP_DIR}/"

# ---------- .env file ----------
if [[ -f "${APP_DIR}/.env" ]]; then
    echo -e "${YELLOW}  → .env already exists at ${APP_DIR}/.env — keeping existing file.${NC}"
else
    cp "${SCRIPT_DIR}/.env.example" "${APP_DIR}/.env"
    echo -e "${YELLOW}  → Created .env from template. EDIT IT NOW:${NC}"
    echo -e "${YELLOW}    sudo nano ${APP_DIR}/.env${NC}"
fi

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${APP_DIR}"

# =============================================================
# 4. Python venv & pip install
# =============================================================
echo -e "${GREEN}[5/7] Creating virtual environment & installing pip packages...${NC}"
python${PYTHON_VERSION} -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel
"${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${VENV_DIR}"

echo -e "${GREEN}  → Installed packages:${NC}"
"${VENV_DIR}/bin/pip" list --format=columns

# =============================================================
# 5. Create systemd service
# =============================================================
echo -e "${GREEN}[6/7] Creating systemd service '${SERVICE_NAME}'...${NC}"

cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=Crypto Trading Bot (Binance Futures)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${VENV_DIR}/bin/python ${APP_DIR}/bot.py
Restart=always
RestartSec=10

# Environment
EnvironmentFile=${APP_DIR}/.env

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${APP_NAME}

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

echo -e "${GREEN}  → Service created and enabled on boot.${NC}"

# =============================================================
# 6. Firewall (optional — outbound only bot)
# =============================================================
echo -e "${GREEN}[7/7] Checking firewall...${NC}"
if command -v ufw &>/dev/null; then
    echo -e "${YELLOW}  → UFW detected. The bot only makes outbound HTTPS requests.${NC}"
    echo -e "${YELLOW}    No inbound rules are needed for the bot itself.${NC}"
else
    echo -e "${YELLOW}  → No UFW detected, skipping firewall config.${NC}"
fi

# =============================================================
# Done!
# =============================================================
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  ✅  Setup Complete!${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo ""
echo -e "  1. ${YELLOW}Edit your .env config:${NC}"
echo -e "     sudo nano ${APP_DIR}/.env"
echo ""
echo -e "  2. ${YELLOW}Start the bot:${NC}"
echo -e "     sudo systemctl start ${APP_NAME}"
echo ""
echo -e "  3. ${YELLOW}Check status:${NC}"
echo -e "     sudo systemctl status ${APP_NAME}"
echo ""
echo -e "  4. ${YELLOW}View live logs:${NC}"
echo -e "     sudo journalctl -u ${APP_NAME} -f"
echo ""
echo -e "  5. ${YELLOW}Stop the bot:${NC}"
echo -e "     sudo systemctl stop ${APP_NAME}"
echo ""
echo -e "  6. ${YELLOW}Restart after .env changes:${NC}"
echo -e "     sudo systemctl restart ${APP_NAME}"
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  Quick Reference${NC}"
echo -e "${CYAN}======================================${NC}"
echo -e "  App directory : ${APP_DIR}"
echo -e "  Virtual env   : ${VENV_DIR}"
echo -e "  Config file   : ${APP_DIR}/.env"
echo -e "  Service       : ${SERVICE_NAME}"
echo -e "  Logs          : journalctl -u ${APP_NAME} -f"
echo ""
