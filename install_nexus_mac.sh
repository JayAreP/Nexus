#!/usr/bin/env bash
# =============================================================================
#  Nexus  ·  macOS Installer
#  Installs Docker Desktop (if needed), creates a Docker Compose service,
#  and starts Nexus on port 8080.
#
#  Supports: macOS (Intel and Apple Silicon / arm64)
#
#  Usage:
#    bash install_nexus_mac.sh [--port 8080] [--dir ~/nexus]
#
#  If run on an already-configured node, the script will pull the latest
#  container image from GHCR, recreate the container, and exit — preserving
#  all config data and volumes.
#
#  Note: The Nexus container image is built for linux/amd64. On Apple Silicon
#  Macs it runs under Rosetta 2 emulation via Docker Desktop. This works but
#  may be slower than native arm64.
# =============================================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_DIR="${HOME}/nexus"
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
            echo "Usage: bash install_nexus_mac.sh [--port 8080] [--dir ~/nexus]"
            exit 0 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

# ── macOS check ───────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
    error "This script is for macOS only. Use install_nexus.sh for Linux."
fi

# ── Detect architecture ──────────────────────────────────────────────────────
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    info "Apple Silicon (arm64) detected — container will run under Rosetta 2 emulation."
    PLATFORM_LINE="    platform: linux/amd64"
else
    info "Intel Mac (x86_64) detected — container will run natively."
    PLATFORM_LINE=""
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

# =============================================================================
#  Step 1 – Check / Install Docker Desktop
# =============================================================================
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_VER="$(docker --version)"
    success "Docker is available: $DOCKER_VER"
else
    if [[ -d "/Applications/Docker.app" ]]; then
        warn "Docker Desktop is installed but not running."
        info "Starting Docker Desktop..."
        open -a Docker
        info "Waiting for Docker daemon to start (this may take a minute)..."
        RETRIES=30
        until docker info &>/dev/null 2>&1; do
            RETRIES=$((RETRIES - 1))
            if [[ $RETRIES -le 0 ]]; then
                error "Docker daemon did not start within 150 s. Open Docker Desktop manually and re-run this script."
            fi
            sleep 5
        done
        success "Docker Desktop is now running."
    else
        echo ""
        echo -e "${YELLOW}============================================================${NC}"
        echo -e "${YELLOW}  Docker Desktop is not installed.${NC}"
        echo -e "${YELLOW}============================================================${NC}"
        echo ""
        echo -e "  Install Docker Desktop for Mac from:"
        echo -e "  ${CYAN}https://www.docker.com/products/docker-desktop/${NC}"
        echo ""
        if command -v brew &>/dev/null; then
            echo -e "  Or install via Homebrew:"
            echo -e "  ${CYAN}brew install --cask docker${NC}"
            echo ""
            read -rp "  Install Docker Desktop via Homebrew now? [y/N] " REPLY
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                info "Installing Docker Desktop via Homebrew..."
                brew install --cask docker
                info "Starting Docker Desktop..."
                open -a Docker
                info "Waiting for Docker daemon to start (this may take a minute)..."
                RETRIES=30
                until docker info &>/dev/null 2>&1; do
                    RETRIES=$((RETRIES - 1))
                    if [[ $RETRIES -le 0 ]]; then
                        error "Docker daemon did not start within 150 s. Open Docker Desktop manually and re-run this script."
                    fi
                    sleep 5
                done
                success "Docker Desktop installed and running."
            else
                error "Docker is required. Install Docker Desktop and re-run this script."
            fi
        else
            error "Docker is required. Install Docker Desktop and re-run this script."
        fi
    fi
fi

if ! docker compose version &>/dev/null; then
    error "Docker Compose not available. Please update Docker Desktop and retry."
fi
success "Docker Compose available: $(docker compose version --short)"

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
#  Nexus  ·  macOS deployment (automation sequencer)
#  Generated by install_nexus_mac.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

name: nexus

services:
  nexus-web:
    image: ${IMAGE}
    container_name: nexus-app
${PLATFORM_LINE}
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
#  Step 4 – Configure auto-start via launchd
# =============================================================================
PLIST_PATH="${HOME}/Library/LaunchAgents/com.nexus.docker-compose.plist"
DOCKER_PATH="$(command -v docker)"

info "Installing launchd agent for auto-start on login..."
mkdir -p "${HOME}/Library/LaunchAgents"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nexus.docker-compose</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DOCKER_PATH}</string>
        <string>compose</string>
        <string>-f</string>
        <string>${INSTALL_DIR}/docker-compose.yml</string>
        <string>up</string>
        <string>-d</string>
        <string>--pull</string>
        <string>always</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/nexus-launch.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/nexus-launch.log</string>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST

success "launchd agent installed at ${PLIST_PATH}"

# =============================================================================
#  Step 5 – Pull image and start
# =============================================================================
info "Pulling image ${IMAGE} (this may take a moment)..."
cd "${INSTALL_DIR}"
docker compose pull

info "Starting Nexus..."
docker compose up -d

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
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Nexus installed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  Web UI:       ${CYAN}http://localhost:${NEXUS_PORT}${NC}"
echo -e "  Install dir:  ${INSTALL_DIR}"
echo -e "  Config:       ${INSTALL_DIR}/conf/"
echo -e "  Credentials:  ${INSTALL_DIR}/.env"
echo ""
echo -e "  Manage the service:"
echo -e "    cd ${INSTALL_DIR}"
echo -e "    docker compose up -d        # start"
echo -e "    docker compose down          # stop"
echo -e "    docker compose restart       # restart"
echo -e "    docker logs -f nexus-app     # view logs"
echo ""
echo -e "  Auto-start on login is enabled via launchd."
echo -e "  To disable:  ${CYAN}launchctl unload ${PLIST_PATH}${NC}"
echo ""
if [[ "$ARCH" == "arm64" ]]; then
    echo -e "${YELLOW}  Note: Running under Rosetta 2 emulation on Apple Silicon.${NC}"
    echo -e "${YELLOW}  Performance may be slower than on native amd64 hardware.${NC}"
    echo ""
fi
echo -e "${YELLOW}  IMPORTANT: Edit ${INSTALL_DIR}/.env with your Azure credentials${NC}"
echo -e "${YELLOW}  and NEXUS_CREDENTIAL_KEY before using the application.${NC}"
echo ""
