#!/usr/bin/env bash
# =============================================================
# build.sh – Build the NeoPZ Docker image
# Usage: ./build.sh [vscode]
# Compatible with: Linux (apt-based) and macOS (Homebrew)
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="neopz-dev"
OS="$(uname -s)"
ARCH="$(uname -m)"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
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

prompt_yn() {
    # prompt_yn "Question" "default(y|n)" VAR_NAME
    local question="$1" default="$2" varname="$3"
    local hint; [ "$default" = "y" ] && hint="Y/n" || hint="y/N"
    printf "  %s (%s): " "$question" "$hint"
    read -r answer
    answer="${answer:-$default}"
    case "$answer" in
        y|Y) eval "${varname}=1" ;;
        *)   eval "${varname}=0" ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# 1. Check / install Docker
# ─────────────────────────────────────────────────────────────
install_docker_linux() {
    warn "Docker not found. Installing Docker Engine..."
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
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    info "Docker installed. Using 'sudo docker' for this session."
    warn "Log out and back in (or run 'newgrp docker') to drop sudo permanently."
    DOCKER_CMD="sudo docker"
}

install_docker_macos() {
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Install it first: https://brew.sh"
    fi
    warn "Docker Desktop not found. Installing via Homebrew..."
    brew install --cask docker
    open -a Docker
    echo "  Waiting for Docker daemon to start (this may take ~30s)..."
    for i in $(seq 1 30); do
        if docker info &>/dev/null 2>&1; then info "Docker is running."; return; fi
        sleep 2
    done
    error "Docker did not start in time. Please open Docker.app manually and re-run."
}

DOCKER_CMD="docker"

if ! command -v docker &>/dev/null; then
    case "$OS" in
        Linux)  install_docker_linux  ;;
        Darwin) install_docker_macos  ;;
        *)      error "Unsupported OS '$OS'. Please install Docker manually." ;;
    esac
else
    info "Docker found: $(docker --version)"
fi

if ! $DOCKER_CMD info &>/dev/null 2>&1; then
    error "Docker daemon is not running or not accessible. Start Docker and re-run."
fi

# ─────────────────────────────────────────────────────────────
# 2. Check for existing images
# ─────────────────────────────────────────────────────────────
_EXISTING_IMAGES=()
while IFS= read -r _img; do
    [ -n "$_img" ] && _EXISTING_IMAGES+=("$_img")
done < <($DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null \
    | grep "^neopz-dev:" || true)

if [ ${#_EXISTING_IMAGES[@]} -gt 0 ]; then
    section "Existing neopz-dev images"
    for _img in "${_EXISTING_IMAGES[@]}"; do
        _sz=$($DOCKER_CMD images --format "{{.Size}}" "$_img" 2>/dev/null)
        _cr=$($DOCKER_CMD images --format "{{.CreatedSince}}" "$_img" 2>/dev/null)
        echo "  • ${_img}  (${_sz}, ${_cr})"
    done
    echo ""
    printf "  (b)uild a new image  /  (s)kip and use existing  [default: b]: "
    read -r _build_ans
    case "${_build_ans:-b}" in
        s|S) info "Skipping build. Run ./run.sh to start a container."; exit 0 ;;
        *) ;;
    esac
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# 3. Interactive configuration
# ─────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo "     NeoPZ Docker Image Configuration        "
echo "============================================="

# ── Build type ────────────────────────────────────────────────
section "Build type"
echo "  [d] Debug   – symbols, no optimization, ideal for development (default)"
echo "  [r] Release – optimized, smaller binary"
printf "  Choice (D/r): "
read -r bt_answer
case "${bt_answer:-d}" in
    r|R) BUILD_TYPE="Release" ;;
    *)   BUILD_TYPE="Debug"   ;;
esac
info "Build type: ${BUILD_TYPE}"

# ── NeoPZ optional features ───────────────────────────────────
section "NeoPZ optional features"
prompt_yn "Enable unit tests – BUILD_UNITTESTING (Catch2)" "n" BUILD_UNITTESTING
prompt_yn "Enable LOG4CXX logging library" "y" USING_LOG4CXX

# ── MUMPS ─────────────────────────────────────────────────────
section "MUMPS sparse direct solver"
prompt_yn "Enable MUMPS" "n" USING_MUMPS

MUMPS_BUILD_SINGLE=0
MUMPS_BUILD_COMPLEX=0
MUMPS_BUILD_COMPLEX16=0

if [ "$USING_MUMPS" = "1" ]; then
    echo ""
    echo "  MUMPS numeric variants  (double [d] is always included):"
    echo ""
    echo "    [s]  single          – real single precision (smumps)"
    echo "    [c]  complex float   – complex single precision (cmumps)"
    echo "    [z]  complex double  – complex double precision (zmumps)"
    echo "    [all] – all four variants"
    echo ""
    printf "  Enter variants to add, e.g. 'sz', 'scz', 'all', or Enter for [d] only: "
    read -r MUMPS_VARIANTS

    case "$MUMPS_VARIANTS" in
        all|ALL) MUMPS_BUILD_SINGLE=1; MUMPS_BUILD_COMPLEX=1; MUMPS_BUILD_COMPLEX16=1 ;;
        *)
            case "$MUMPS_VARIANTS" in *s*) MUMPS_BUILD_SINGLE=1    ;; esac
            case "$MUMPS_VARIANTS" in *c*) MUMPS_BUILD_COMPLEX=1   ;; esac
            case "$MUMPS_VARIANTS" in *z*) MUMPS_BUILD_COMPLEX16=1 ;; esac
            ;;
    esac

    # Print selected variants
    VARIANTS_LABEL="d (double)"
    [ "$MUMPS_BUILD_SINGLE"    = "1" ] && VARIANTS_LABEL="$VARIANTS_LABEL, s (single)"
    [ "$MUMPS_BUILD_COMPLEX"   = "1" ] && VARIANTS_LABEL="$VARIANTS_LABEL, c (complex float)"
    [ "$MUMPS_BUILD_COMPLEX16" = "1" ] && VARIANTS_LABEL="$VARIANTS_LABEL, z (complex double)"
    info "MUMPS variants: ${VARIANTS_LABEL}"
fi

# ── METIS ─────────────────────────────────────────────────────
section "METIS graph partitioner"
prompt_yn "Enable METIS (mesh partitioning; used by NeoPZ and MUMPS when both are enabled)" "n" USING_METIS

# ── Intel MKL ─────────────────────────────────────────────────
section "Intel MKL / oneAPI"
USING_MKL=0

if [ "$OS" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
    warn "Apple Silicon (ARM) detected – Intel MKL is x86_64-only and is NOT supported."
    warn "MKL is disabled."
else
    prompt_yn "Enable Intel MKL / oneAPI (x86_64 only)" "n" USING_MKL
fi

# ── Image tag ─────────────────────────────────────────────────
section "Image tag"
echo "  The image will be tagged as  neopz-dev:<tag>"
if [ ${#_EXISTING_IMAGES[@]} -gt 0 ]; then
    echo "  Existing tags: ${_EXISTING_IMAGES[*]}"
fi
printf "  Tag (default: latest): "
read -r IMAGE_TAG
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_FULL_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
info "Image will be tagged: ${IMAGE_FULL_NAME}"

# ─────────────────────────────────────────────────────────────
# 4. Resolve GitHub repositories
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

# ── MUMPS: afbrbza → labmec → giavancini → scivision fallback ─
MUMPS_REPO=""
for _owner in afbrbza labmec giavancini; do
    if github_repo_exists "$_owner" "mumps"; then
        MUMPS_REPO="https://github.com/${_owner}/mumps.git"
        info "MUMPS repository  : ${MUMPS_REPO}"
        break
    else
        warn "Not found: ${_owner}/mumps"
    fi
done
if [ -z "$MUMPS_REPO" ]; then
    MUMPS_REPO="https://github.com/scivision/mumps-superbuild.git"
    warn "MUMPS repository (fallback): ${MUMPS_REPO}"
fi

# ─────────────────────────────────────────────────────────────
# 4. Summary + confirmation
# ─────────────────────────────────────────────────────────────
flag_label() { [ "$1" = "1" ] && echo -e "${GREEN}ON${RESET}" || echo -e "${YELLOW}OFF${RESET}"; }
echo ""
echo "─────────────────────────────────────────────"
echo "  IMAGE               : ${IMAGE_FULL_NAME}"
echo "  BUILD_TYPE          : ${BUILD_TYPE}"
echo "  BUILD_UNITTESTING   : $(flag_label $BUILD_UNITTESTING)"
echo "  USING_LOG4CXX       : $(flag_label $USING_LOG4CXX)"
echo "  USING_MUMPS         : $(flag_label $USING_MUMPS)"
if [ "$USING_MUMPS" = "1" ]; then
echo "    MUMPS_BUILD_SINGLE    : $(flag_label $MUMPS_BUILD_SINGLE)"
echo "    MUMPS_BUILD_COMPLEX   : $(flag_label $MUMPS_BUILD_COMPLEX)"
echo "    MUMPS_BUILD_COMPLEX16 : $(flag_label $MUMPS_BUILD_COMPLEX16)"
fi
echo "  USING_MKL           : $(flag_label $USING_MKL)"
echo "  USING_METIS         : $(flag_label $USING_METIS)"
echo "  NEOPZ_REPO          : ${NEOPZ_REPO}"
echo "  MUMPS_REPO          : ${MUMPS_REPO}"
echo "─────────────────────────────────────────────"
echo ""
printf "  Proceed with build? (Y/n): "
read -r confirm
confirm="${confirm:-y}"
case "$confirm" in y|Y) ;; *) echo "Aborted."; exit 0 ;; esac

# ─────────────────────────────────────────────────────────────
# 5. Build
# ─────────────────────────────────────────────────────────────
echo ""
echo "Building image '${IMAGE_NAME}'..."
echo ""

$DOCKER_CMD build --no-cache \
    --build-arg BUILD_TYPE="$BUILD_TYPE" \
    --build-arg BUILD_UNITTESTING="$BUILD_UNITTESTING" \
    --build-arg USING_LOG4CXX="$USING_LOG4CXX" \
    --build-arg USING_MKL="$USING_MKL" \
    --build-arg USING_METIS="$USING_METIS" \
    --build-arg USING_MUMPS="$USING_MUMPS" \
    --build-arg MUMPS_BUILD_SINGLE="$MUMPS_BUILD_SINGLE" \
    --build-arg MUMPS_BUILD_COMPLEX="$MUMPS_BUILD_COMPLEX" \
    --build-arg MUMPS_BUILD_COMPLEX16="$MUMPS_BUILD_COMPLEX16" \
    --build-arg NEOPZ_REPO="$NEOPZ_REPO" \
    --build-arg MUMPS_REPO="$MUMPS_REPO" \
    -t "$IMAGE_FULL_NAME" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo ""
info "Image '${IMAGE_FULL_NAME}' built successfully."

# ─────────────────────────────────────────────────────────────
# 5. Optional: install VSCode extensions on the host
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "vscode" ]; then
    "${SCRIPT_DIR}/install_vscode_extensions.sh"
fi
