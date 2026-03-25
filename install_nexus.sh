#!/usr/bin/env bash
# =============================================================================
#  Nexus  ·  Linux Installer
#  Installs Docker, creates a Docker Compose service, and starts Nexus
#  on port 8080 (HTTP).
#
#  Supports: Ubuntu/Debian, RHEL/CentOS/Fedora/Rocky/AlmaLinux
#
#  Usage:
#    sudo bash install_nexus.sh [--port 8080] [--dir /opt/nexus]
#
#  If run on an already-configured node, the script will pull the latest
#  container image from GHCR, recreate the container, and exit — preserving
#  all config data and volumes.
# =============================================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/nexus"
NEXUS_PORT="8080"
IMAGE="ghcr.io/jayarep/nexus:latest"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)  NEXUS_PORT="$2";   shift 2 ;;
        --dir)   INSTALL_DIR="$2";  shift 2 ;;
        --help)
            echo "Usage: sudo bash install_nexus.sh [--port 8080] [--dir /opt/nexus]"
            exit 0 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Try: sudo bash $0"
fi

# =============================================================================
#  Upgrade path — if already installed, pull latest image and recreate
# =============================================================================
if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
    info "Existing installation detected at ${INSTALL_DIR}."
    cd "${INSTALL_DIR}"

    OLD_DIGEST="$(docker inspect --format='{{.Image}}' nexus-app 2>/dev/null || echo "none")"
    OLD_SHORT="none"
    if [[ "$OLD_DIGEST" != "none" ]]; then
        OLD_SHORT="${OLD_DIGEST:7:12}"
        info "Running container image: ${OLD_SHORT}"
    fi

    PRE_PULL_DIGEST="$(docker image inspect --format='{{.Id}}' "${IMAGE}" 2>/dev/null || echo "none")"

    info "Pulling latest image from GHCR..."
    docker compose pull

    POST_PULL_DIGEST="$(docker image inspect --format='{{.Id}}' "${IMAGE}" 2>/dev/null || echo "unknown")"
    POST_PULL_SHORT="${POST_PULL_DIGEST:7:12}"

    if [[ "$PRE_PULL_DIGEST" == "$POST_PULL_DIGEST" && "$OLD_DIGEST" == "$POST_PULL_DIGEST" ]]; then
        echo ""
        echo -e "${YELLOW}============================================================${NC}"
        echo -e "${YELLOW}  No update available — already running the latest image.${NC}"
        echo -e "${YELLOW}============================================================${NC}"
        echo ""
        echo -e "  Image ID:     ${CYAN}${POST_PULL_SHORT}${NC}"
        echo -e "  Install dir:  ${INSTALL_DIR}"
        echo ""
        echo -e "  To force a recreate anyway:  ${CYAN}cd ${INSTALL_DIR} && docker compose up -d --force-recreate${NC}"
        echo ""
        exit 0
    fi

    if [[ "$PRE_PULL_DIGEST" != "$POST_PULL_DIGEST" ]]; then
        PRE_SHORT="${PRE_PULL_DIGEST:7:12}"
        info "New image pulled: ${PRE_SHORT} -> ${POST_PULL_SHORT}"
    else
        info "Container is out of date. Local image: ${POST_PULL_SHORT}, container: ${OLD_SHORT}"
    fi

    info "Recreating container with updated image..."
    docker compose up -d --force-recreate

    RETRIES=12
    until docker inspect -f '{{.State.Running}}' nexus-app 2>/dev/null | grep -q true; do
        RETRIES=$((RETRIES - 1))
        if [[ $RETRIES -le 0 ]]; then
            error "Container did not start within 60 s. Check logs: docker logs nexus-app"
        fi
        sleep 5
    done

    RUNNING_DIGEST="$(docker inspect --format='{{.Image}}' nexus-app 2>/dev/null || echo "unknown")"
    RUNNING_SHORT="${RUNNING_DIGEST:7:12}"
    CREATED="$(docker inspect --format='{{.Created}}' nexus-app 2>/dev/null || echo "unknown")"

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Nexus upgraded successfully!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  Previous:     ${OLD_SHORT}"
    echo -e "  Now running:  ${CYAN}${RUNNING_SHORT}${NC}"
    echo -e "  Created:      ${CREATED}"
    echo -e "  Install dir:  ${INSTALL_DIR}"
    echo -e "  Config data:  Preserved (./conf + Docker volumes)"
    echo ""
    if [[ "$RUNNING_DIGEST" == "$POST_PULL_DIGEST" ]]; then
        success "Confirmed: container is running the new image."
    else
        warn "Container image (${RUNNING_SHORT}) doesn't match pulled image (${POST_PULL_SHORT})."
        warn "Check: docker logs nexus-app"
    fi
    echo ""
    echo -e "  Check logs:   ${CYAN}docker logs -f nexus-app${NC}"
    echo ""
    exit 0
fi

# ── Detect OS ─────────────────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
else
    error "Cannot detect OS. /etc/os-release not found."
fi

is_debian_like() { [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* || "$OS_LIKE" == *"ubuntu"* ]]; }
is_rhel_like()   { [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol)$ || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]; }

# =============================================================================
#  Step 1 – Install Docker Engine
# =============================================================================
install_docker_debian() {
    info "Installing Docker on Debian/Ubuntu..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} \
$(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel() {
    info "Installing Docker on RHEL/CentOS/Fedora..."
    if command -v dnf &>/dev/null; then
        PKG="dnf"
    else
        PKG="yum"
    fi

    $PKG install -y -q yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    $PKG install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

if command -v docker &>/dev/null; then
    DOCKER_VER="$(docker --version)"
    warn "Docker is already installed: $DOCKER_VER — skipping Docker installation."
else
    if is_debian_like; then
        install_docker_debian
    elif is_rhel_like; then
        install_docker_rhel
    else
        error "Unsupported OS: ${OS_ID}. Install Docker manually then re-run this script."
    fi
    success "Docker installed."
fi

if ! docker compose version &>/dev/null; then
    error "Docker Compose plugin not found. Please install 'docker-compose-plugin' and retry."
fi
success "Docker Compose v2 available: $(docker compose version --short)"

systemctl enable --now docker
success "Docker daemon is running."

# =============================================================================
#  Step 2 – Create install directory and .env file
# =============================================================================
info "Creating install directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/conf"

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    info "Creating .env file — you will need to fill in your credentials."
    cat > "${INSTALL_DIR}/.env" <<'ENVFILE'
# Nexus Environment Configuration
# Fill in these values before starting the service.

AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_TENANT_ID=
NEXUS_CREDENTIAL_KEY=
ENVFILE
    chmod 600 "${INSTALL_DIR}/.env"
    warn ".env file created at ${INSTALL_DIR}/.env — edit it with your Azure credentials."
else
    info "Existing .env file found — preserving it."
fi

# =============================================================================
#  Step 3 – Write docker-compose.yml
# =============================================================================
info "Writing docker-compose.yml to ${INSTALL_DIR}..."

cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
# =============================================================================
#  Nexus  ·  Standalone deployment (automation sequencer)
#  Generated by install_nexus.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

name: nexus

services:
  nexus-web:
    image: ${IMAGE}
    container_name: nexus-app
    ports:
      - "${NEXUS_PORT}:8080"
    volumes:
      - ./conf:/app/conf
      - nexus-ps-modules:/usr/local/share/powershell/Modules
      - nexus-py-packages:/usr/local/lib/python3.10/dist-packages
    env_file:
      - .env
    environment:
      - POWERSHELL_TELEMETRY_OPTOUT=1
    restart: unless-stopped
    networks:
      - nexus-network

networks:
  nexus-network:
    driver: bridge

volumes:
  nexus-ps-modules:
  nexus-py-packages:
EOF

success "docker-compose.yml written."

# =============================================================================
#  Step 4 – Create a systemd service unit
# =============================================================================
info "Installing systemd service: nexus.service"

cat > /etc/systemd/system/nexus.service <<'UNIT'
[Unit]
Description=Nexus Automation Sequencer
Documentation=https://github.com/jayarep/nexus
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=INSTALL_DIR_PLACEHOLDER
ExecStart=/usr/bin/docker compose up -d --pull always
ExecStop=/usr/bin/docker compose down
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

sed -i "s|INSTALL_DIR_PLACEHOLDER|${INSTALL_DIR}|g" /etc/systemd/system/nexus.service

systemctl daemon-reload
systemctl enable nexus.service
success "systemd service registered and enabled."

# =============================================================================
#  Step 5 – Pull image and start the service
# =============================================================================
info "Pulling image ${IMAGE} (this may take a moment)..."
cd "${INSTALL_DIR}"
docker compose pull

info "Starting Nexus..."
systemctl start nexus.service

RETRIES=12
until docker inspect -f '{{.State.Running}}' nexus-app 2>/dev/null | grep -q true; do
    RETRIES=$((RETRIES - 1))
    if [[ $RETRIES -le 0 ]]; then
        error "Container did not start within 60 s. Check logs: docker logs nexus-app"
    fi
    sleep 5
done

success "Nexus container is running."

# =============================================================================
#  Done
# =============================================================================
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Nexus installed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  Web UI:       ${CYAN}http://${HOST_IP}:${NEXUS_PORT}${NC}"
echo -e "  Install dir:  ${INSTALL_DIR}"
echo -e "  Config:       ${INSTALL_DIR}/conf/"
echo -e "  Credentials:  ${INSTALL_DIR}/.env"
echo ""
echo -e "  Manage the service:"
echo -e "    systemctl start   nexus"
echo -e "    systemctl stop    nexus"
echo -e "    systemctl restart nexus"
echo -e "    docker logs -f nexus-app"
echo ""
echo -e "${YELLOW}  IMPORTANT: Edit ${INSTALL_DIR}/.env with your Azure credentials${NC}"
echo -e "${YELLOW}  and NEXUS_CREDENTIAL_KEY before using the application.${NC}"
echo ""
