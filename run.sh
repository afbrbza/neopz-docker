#!/usr/bin/env bash
# =============================================================
# run.sh – Start NeoPZ development container (Linux-focused)
# macOS/Windows: Use Docker Desktop GUI for easier management
# Usage: ./run.sh
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="neopz-dev"
OS="$(uname -s)"

GREEN="\033[0;32m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
section() { echo -e "\n${CYAN}▶ $*${RESET}"; }

# ─────────────────────────────────────────────────────────────
# 1. Platform check
# ─────────────────────────────────────────────────────────────
if [ "$OS" != "Linux" ]; then
    warn "This script is optimized for Linux."
    warn "On macOS/Windows, use Docker Desktop to manage containers."
    echo ""
    printf "  Continue anyway? (y/N): "
    read -r _continue
    case "$_continue" in y|Y) ;; *) exit 0 ;; esac
fi

# ─────────────────────────────────────────────────────────────
# 2. Check Docker
# ─────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Please install Docker or run ./build.sh" >&2
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Docker daemon is not running. Start it and try again." >&2
    exit 1
fi

info "Docker found: $(docker --version)"

# ─────────────────────────────────────────────────────────────
# 3. Find or create container
# ─────────────────────────────────────────────────────────────
section "Container management"

# Discover existing neopz containers
_NEOPZ_CTRS=()
while IFS= read -r _cname; do
    [ -z "$_cname" ] && continue
    _cst=$(docker inspect "$_cname" --format '{{.State.Status}}' 2>/dev/null)
    _cimg=$(docker inspect "$_cname" --format '{{.Config.Image}}' 2>/dev/null)
    _NEOPZ_CTRS+=("${_cname}|${_cst}|${_cimg}")
done < <(docker ps -a --format "{{.Names}}" 2>/dev/null | grep "^neopz-dev" || true)

# Discover available images
_NEOPZ_IMGS=()
while IFS= read -r _img; do
    [ -n "$_img" ] && _NEOPZ_IMGS+=("$_img")
done < <(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep "^neopz-dev:" || true)

_ACTION="create"
CONTAINER_NAME=""
PROJECTS_DIR="$HOME/neopz_workspace"
PROJECT_MOUNT_NAME=""
PROJECT_MOUNT_PATH=""

# If containers exist, offer to reuse one
if [ ${#_NEOPZ_CTRS[@]} -gt 0 ]; then
    echo "  Existing containers:"
    _i=1
    for _c in "${_NEOPZ_CTRS[@]}"; do
        IFS='|' read -r _cn _cst _cimg <<< "$_c"
        printf "    [%d] %-30s %-16s %s\n" "$_i" "$_cn" "(${_cst})" "$_cimg"
        _i=$((_i + 1))
    done
    echo "    [n] Create a new container"
    echo ""
    printf "  Choice (default: n): "
    read -r _choice
    _choice="${_choice:-n}"
    if [[ "$_choice" =~ ^[0-9]+$ ]] && [ "$_choice" -ge 1 ] && [ "$_choice" -le "${#_NEOPZ_CTRS[@]}" ]; then
        IFS='|' read -r CONTAINER_NAME _cst _cimg <<< "${_NEOPZ_CTRS[$((_choice - 1))]}"
        _ACTION="use_existing"
        info "Reusing: ${CONTAINER_NAME}"
    fi
fi

# Create new container
if [ "$_ACTION" = "create" ]; then
    # Ensure image exists
    if [ ${#_NEOPZ_IMGS[@]} -eq 0 ]; then
        warn "No neopz-dev image found. Running build.sh..."
        echo ""
        "${SCRIPT_DIR}/build.sh"
        echo ""
        while IFS= read -r _img; do
            [ -n "$_img" ] && _NEOPZ_IMGS+=("$_img")
        done < <(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep "^neopz-dev:" || true)
    fi

    # Select image (if multiple exist)
    if [ ${#_NEOPZ_IMGS[@]} -eq 1 ]; then
        IMAGE_NAME="${_NEOPZ_IMGS[0]}"
        info "Using image: ${IMAGE_NAME}"
    elif [ ${#_NEOPZ_IMGS[@]} -gt 1 ]; then
        echo ""
        echo "  Available images:"
        _i=1
        for _img in "${_NEOPZ_IMGS[@]}"; do
            _sz=$(docker images --format "{{.Size}}" "$_img" 2>/dev/null)
            _cr=$(docker images --format "{{.CreatedSince}}" "$_img" 2>/dev/null)
            printf "    [%d] %-32s %-12s %s\n" "$_i" "$_img" "$_sz" "$_cr"
            _i=$((_i + 1))
        done
        printf "\n  Choice (default: 1): "
        read -r _ic
        _ic="${_ic:-1}"
        if [[ "$_ic" =~ ^[0-9]+$ ]] && [ "$_ic" -ge 1 ] && [ "$_ic" -le "${#_NEOPZ_IMGS[@]}" ]; then
            IMAGE_NAME="${_NEOPZ_IMGS[$((_ic - 1))]}"
        else
            IMAGE_NAME="${_NEOPZ_IMGS[0]}"
        fi
        info "Selected: ${IMAGE_NAME}"
    fi

    # Container name
    _default_cname="neopz-dev"
    if docker inspect "$_default_cname" &>/dev/null 2>&1; then
        _n=2
        while docker inspect "neopz-dev-${_n}" &>/dev/null 2>&1; do
            _n=$((_n + 1))
        done
        _default_cname="neopz-dev-${_n}"
    fi

    printf "\n  Container name (default: %s): " "$_default_cname"
    read -r CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME:-$_default_cname}"

    # Project directory and mount point
    printf "  Host project directory (default: %s): " "$PROJECTS_DIR"
    read -r _pd
    PROJECTS_DIR="${_pd:-$PROJECTS_DIR}"

    mkdir -p "$PROJECTS_DIR"

    PROJECT_MOUNT_NAME="$(basename "$PROJECTS_DIR")"
    PROJECT_MOUNT_PATH="/home/labmec/${PROJECT_MOUNT_NAME}"
fi

# ─────────────────────────────────────────────────────────────
# 4. Start container
# ─────────────────────────────────────────────────────────────
section "Starting container"

if [ "$_ACTION" = "use_existing" ]; then
    _cst=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null)
    if [ "$_cst" = "running" ]; then
        warn "Container '${CONTAINER_NAME}' is already running."
    else
        docker start "$CONTAINER_NAME" &>/dev/null
        info "Container '${CONTAINER_NAME}' restarted."
    fi
else
    docker run -d \
        --name "$CONTAINER_NAME" \
        -v "${PROJECTS_DIR}:${PROJECT_MOUNT_PATH}" \
        "$IMAGE_NAME" \
        sleep infinity
    info "Container '${CONTAINER_NAME}' created and started"
    info "Volume mounted: ${PROJECTS_DIR} → ${PROJECT_MOUNT_PATH}"
fi

# ─────────────────────────────────────────────────────────────
# 5. Usage hints
# ─────────────────────────────────────────────────────────────
section "How to use the container"
echo ""
echo "  Shell into the container:"
echo -e "    ${CYAN}docker exec -it ${CONTAINER_NAME} /bin/bash${RESET}"
echo ""
echo "  Root access (install packages):"
echo -e "    ${CYAN}docker exec -it -u root ${CONTAINER_NAME} /bin/bash${RESET}"
echo ""
echo "  Stop the container:"
echo -e "    ${CYAN}docker stop ${CONTAINER_NAME}${RESET}"
echo ""
echo "  Remove the container:"
echo -e "    ${CYAN}docker rm ${CONTAINER_NAME}${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────
# 6. Open VScode if available and container is running
# ─────────────────────────────────────────────────────────────
if command -v code &>/dev/null; then
    if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        warn "Container '${CONTAINER_NAME}' is not running. Start it to open in VSCode."
        exit 0
    else
        WORKDIR_IN_CONTAINER=$(docker inspect --format '{{(index .Mounts 0).Destination}}' "$CONTAINER_NAME")

        section "VSCode"
        CONTAINER_HEX=$(printf '%s' "{\"containerName\":\"/${CONTAINER_NAME}\"}" \
            | od -v -A n -t x1 | tr -d ' \n')
        FULL_URI="vscode-remote://attached-container+${CONTAINER_HEX}${WORKDIR_IN_CONTAINER}/${VSCODE_OPEN_PROJECT}"
        echo "  Opening project folder in VSCode (attached to container)..."
        echo -e "    ${CYAN}${WORKDIR_IN_CONTAINER}/${VSCODE_OPEN_PROJECT}${RESET}"
        code --folder-uri "$FULL_URI"
        info "VSCode launched. Install the 'Dev Containers' extension if prompted."
    fi
else
    warn "VSCode not found. Open the project folder in VSCode and use Remote Containers extension to attach to '${CONTAINER_NAME}'."
fi

echo ""