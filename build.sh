#!/usr/bin/env bash
# =============================================================
# build.sh – Build the NeoPZ Docker image (minimal version)
# Usage: ./build.sh
# All features (MUMPS, METIS, LOG4CXX, LAPACK, VSCode extension defaults)
# are pre-compiled in Debug mode. Users can recompile inside
# the container if they need to remove features.
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="neopz-dev"
OS="$(uname -s)"
ARCH="$(uname -m)"

GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; CYAN="\033[0;36m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✘]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}▶ $*${RESET}"; }

# Returns 0 if the GitHub repo owner/name is publicly accessible, 1 otherwise.
github_repo_exists() {
    local owner="$1" repo="$2" status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://api.github.com/repos/${owner}/${repo}" 2>/dev/null) || true
    [ "$status" = "200" ]
}

# ─────────────────────────────────────────────────────────────
# 1. Check / install Docker
# ─────────────────────────────────────────────────────────────
DOCKER_CMD="docker"

if ! command -v docker &>/dev/null; then
    case "$OS" in
        Linux)
            warn "Docker not found."
            echo "Which Docker version would you like to install?"
            echo "  1) Docker Engine (CLI) - Recommended for Linux (lightweight, standard)"
            echo "  2) Docker Desktop (GUI) - Similar to macOS/Windows experience"
            read -r -p "Select [1/2] (default: 1): " choice
            choice=${choice:-1}

            warn "Installing prerequisites and setting up Docker repository..."
            sudo apt-get update -y -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
                | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
$(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
                | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt-get update -y -qq

            if [ "$choice" = "2" ]; then
                warn "Installing Docker Desktop for Linux..."
                
                # Download the latest package
                DEB_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
                DEB_FILE="/tmp/docker-desktop.deb"
                
                info "Downloading Docker Desktop package..."
                curl -L "$DEB_URL" -o "$DEB_FILE"
                
                info "Installing package (this may take a moment)..."
                sudo apt-get install -y "$DEB_FILE" || true # Ignore apt error about downloaded package
                rm -f "$DEB_FILE"

                echo ""
                info "Docker Desktop installed successfully!"
                warn "IMPORTANT: You must start Docker Desktop from your applications menu to accept the terms and start the engine."
                warn "After starting it, you can return here to run the build."
                exit 0
            else
                warn "Installing Docker Engine..."
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin

                sudo systemctl enable --now docker
                sudo usermod -aG docker "$USER"
                info "Docker installed. Using 'sudo docker' for this session."
                warn "Log out and back in (or run 'newgrp docker') to drop sudo permanently."
                DOCKER_CMD="sudo docker"
            fi
            ;;
        Darwin)
            error "Docker not found on macOS. Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
            ;;
        *)
            error "Unsupported OS '$OS'. Please install Docker manually."
            ;;
    esac
else
    info "Docker found: $(docker --version)"
fi

if ! $DOCKER_CMD info &>/dev/null 2>&1; then
    error "Docker daemon is not running or not accessible. Start Docker and re-run."
fi

# ─────────────────────────────────────────────────────────────
# 2. Resolve GitHub repositories
# ─────────────────────────────────────────────────────────────
section "Resolving GitHub repositories"

# ── NeoPZ: afbrbza → labmec ──────────────────────────────────
NEOPZ_REPO=""
for _owner in afbrbza labmec; do
    if github_repo_exists "$_owner" "neopz"; then
        NEOPZ_REPO="https://github.com/${_owner}/neopz.git"
        info "NeoPZ repository  : ${NEOPZ_REPO}"
        break
    else
        warn "Not found: ${_owner}/neopz"
    fi
done
[ -z "$NEOPZ_REPO" ] && error "NeoPZ repository not found in afbrbza/neopz or labmec/neopz."

####################################################################
# scivision updated their mumps-superbuild repo more recently solving RPATH issues. Now use it as the default MUMPS source.
MUMPS_REPO="https://github.com/scivision/mumps-superbuild.git"
info "MUMPS repository  : ${MUMPS_REPO}"
####################################################################
# ── MUMPS: afbrbza → labmec → giavancini ─────────────────────
# MUMPS_REPO=""
# for _owner in afbrbza labmec giavancini; do
#     if github_repo_exists "$_owner" "mumps"; then
#         MUMPS_REPO="https://github.com/${_owner}/mumps.git"
#         info "MUMPS repository  : ${MUMPS_REPO}"
#         break
#     else
#         warn "Not found: ${_owner}/mumps"
#     fi
# done
# if [ -z "$MUMPS_REPO" ]; then
#     MUMPS_REPO="https://github.com/scivision/mumps-superbuild.git"
#     warn "MUMPS repository (fallback): ${MUMPS_REPO}"
# fi
####################################################################

# ─────────────────────────────────────────────────────────────
# 3. Image tag
# ─────────────────────────────────────────────────────────────
section "Image configuration"

printf "  Image tag (default: latest): "
read -r IMAGE_TAG
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_FULL_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

# if image already exists, ask to overwrite with --no-cache option
nocache=true
if $DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_FULL_NAME}$"; then
    warn "Image '${IMAGE_FULL_NAME}' already exists."
    printf "  Do you want to [o]verwrite or just [r]ebuild? ([o]verride/[R]ebuild): "
    read -r nocache
    case "$nocache" in r|R) nocache=false ;; esac
fi

# ─────────────────────────────────────────────────────────────
# 4. Platform-specific notes
# ─────────────────────────────────────────────────────────────
section "Build configuration"

echo "  All features will be compiled into the image:"
echo "    • NeoPZ (Debug mode)"
echo "    • MUMPS (all variants: d, s, c, z)"
echo "    • METIS (graph partitioner)"
echo "    • LOG4CXX (logging)"
echo "    • OpenBLAS (LAPACK backend)"
echo "    • VSCode extension defaults (C++ Tools, CMake Tools)"
echo ""

_platform_linux_amd_on_build=""
if [ "$OS" = "Darwin" ]; then
    warn "Building on macOS: Using Intel MKL (x86_64 architecture)"
    warn "Apple Silicon users: Container will run in x86_64 emulation mode"
    _platform_linux_amd_on_build="--platform=linux/amd64"
fi

echo ""
printf "  Proceed with build? (Y/n): "
read -r confirm
confirm="${confirm:-y}"
case "$confirm" in y|Y) ;; *) echo "Aborted."; exit 0 ;; esac

# ─────────────────────────────────────────────────────────────
# 5. Build
# ─────────────────────────────────────────────────────────────
echo ""
echo "Building image '${IMAGE_FULL_NAME}'..."
echo ""

$DOCKER_CMD build $([ "$nocache" = true ] && echo "--no-cache") \
    $_platform_linux_amd_on_build \
    --build-arg NEOPZ_REPO="$NEOPZ_REPO" \
    --build-arg MUMPS_REPO="$MUMPS_REPO" \
    -t "$IMAGE_FULL_NAME" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo ""
info "Image '${IMAGE_FULL_NAME}' built successfully."
echo ""
echo "Next steps:"
echo "  • Run './run.sh' to start a container"
echo "  • Or use Docker Desktop on macOS/Windows to manage containers"
echo ""
