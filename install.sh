#!/bin/sh
# Flaase Installation Script
# Usage: curl -fsSL https://get.flaase.com | sh
#    or: curl -fsSL https://get.flaase.com | sh -s -- --yes
#
# Options:
#   --yes    Automatically run 'fl server init' after installation

set -e

# =============================================================================
# Configuration
# =============================================================================

FLAASE_REPO="MaxenceMahieux/flaase-cli-rust"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="flaase"
SYMLINK_NAME="fl"

# Colors (only if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    GRAY=''
    BOLD=''
    NC=''
fi

# =============================================================================
# Helper Functions
# =============================================================================

print_ascii_art() {
    printf "${CYAN}"
    cat << 'EOF'

   __ _
  / _| | __ _  __ _ ___  ___
 | |_| |/ _` |/ _` / __|/ _ \
 |  _| | (_| | (_| \__ \  __/
 |_| |_|\__,_|\__,_|___/\___|

EOF
    printf "${NC}"
}

info() {
    printf "${CYAN}%s${NC}\n" "$1"
}

success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}!${NC} %s\n" "$1"
}

error() {
    printf "${RED}✗${NC} %s\n" "$1" >&2
}

fatal() {
    error "$1"
    exit 1
}

# Progress indicator (simple version for POSIX sh)
progress() {
    local label="$1"
    local status="$2"
    printf "  %-20s %s\n" "$label" "$status"
}

# =============================================================================
# System Detection
# =============================================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS_ID="$DISTRIB_ID"
        OS_VERSION="$DISTRIB_RELEASE"
        OS_NAME="$DISTRIB_DESCRIPTION"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown OS"
    fi
}

detect_arch() {
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)
            ARCH="x64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            fatal "Unsupported architecture: $ARCH"
            ;;
    esac
}

check_os_supported() {
    case "$OS_ID" in
        ubuntu)
            case "$OS_VERSION" in
                22.04|24.04)
                    return 0
                    ;;
                *)
                    warn "Ubuntu $OS_VERSION is not officially supported. Recommended: 22.04 or 24.04"
                    ;;
            esac
            ;;
        debian)
            case "$OS_VERSION" in
                11|12)
                    return 0
                    ;;
                *)
                    warn "Debian $OS_VERSION is not officially supported. Recommended: 11 or 12"
                    ;;
            esac
            ;;
        *)
            fatal "Unsupported OS: $OS_ID. Flaase requires Ubuntu (22.04/24.04) or Debian (11/12)"
            ;;
    esac
}

# =============================================================================
# Prerequisites
# =============================================================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fatal "This script must be run as root. Try: curl -fsSL https://get.flaase.com | sudo sh"
    fi
}

check_commands() {
    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
        DOWNLOAD_CMD="curl -fsSL"
        DOWNLOAD_OUTPUT="-o"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
        DOWNLOAD_CMD="wget -qO-"
        DOWNLOAD_OUTPUT="-O"
    else
        fatal "curl or wget is required. Install with: apt install curl"
    fi

    # Check for sha256sum
    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "sha256sum not found. Checksum verification will be skipped."
        SKIP_CHECKSUM=1
    fi
}

# =============================================================================
# Installation
# =============================================================================

get_latest_version() {
    info "Fetching latest version..."
    
    if [ "$DOWNLOADER" = "curl" ]; then
        VERSION=$(curl -fsSL "https://api.github.com/repos/${FLAASE_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    else
        VERSION=$(wget -qO- "https://api.github.com/repos/${FLAASE_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    fi
    
    if [ -z "$VERSION" ]; then
        fatal "Could not determine latest version. Check https://github.com/${FLAASE_REPO}/releases"
    fi
}

download_binary() {
    local artifact_name="flaase-linux-${ARCH}"
    local download_url="https://github.com/${FLAASE_REPO}/releases/download/v${VERSION}/${artifact_name}.tar.gz"
    local checksum_url="https://github.com/${FLAASE_REPO}/releases/download/v${VERSION}/${artifact_name}.tar.gz.sha256"
    
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    
    info "Downloading Flaase v${VERSION} for Linux ${ARCH}..."
    
    # Download binary
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL "$download_url" -o "${TMP_DIR}/flaase.tar.gz" || fatal "Download failed. Check your internet connection."
    else
        wget -q "$download_url" -O "${TMP_DIR}/flaase.tar.gz" || fatal "Download failed. Check your internet connection."
    fi
    
    # Verify checksum
    if [ -z "$SKIP_CHECKSUM" ]; then
        info "Verifying checksum..."
        if [ "$DOWNLOADER" = "curl" ]; then
            curl -fsSL "$checksum_url" -o "${TMP_DIR}/flaase.tar.gz.sha256" 2>/dev/null || warn "Checksum file not found, skipping verification"
        else
            wget -q "$checksum_url" -O "${TMP_DIR}/flaase.tar.gz.sha256" 2>/dev/null || warn "Checksum file not found, skipping verification"
        fi
        
        if [ -f "${TMP_DIR}/flaase.tar.gz.sha256" ]; then
            cd "$TMP_DIR"
            # Fix filename in checksum file (release uses artifact name, we use flaase.tar.gz)
            sed -i "s/${artifact_name}.tar.gz/flaase.tar.gz/" flaase.tar.gz.sha256
            if ! sha256sum -c flaase.tar.gz.sha256 >/dev/null 2>&1; then
                fatal "Checksum verification failed! The download may be corrupted."
            fi
            success "Checksum verified"
            cd - >/dev/null
        fi
    fi
    
    # Extract
    info "Extracting..."
    tar -xzf "${TMP_DIR}/flaase.tar.gz" -C "$TMP_DIR" || fatal "Extraction failed"
}

install_binary() {
    info "Installing to ${INSTALL_DIR}..."
    
    # Find the binary in extracted files
    if [ -f "${TMP_DIR}/flaase" ]; then
        BINARY_PATH="${TMP_DIR}/flaase"
    elif [ -f "${TMP_DIR}/${BINARY_NAME}" ]; then
        BINARY_PATH="${TMP_DIR}/${BINARY_NAME}"
    else
        # Search for it
        BINARY_PATH=$(find "$TMP_DIR" -name "flaase" -type f | head -1)
        if [ -z "$BINARY_PATH" ]; then
            fatal "Could not find flaase binary in archive"
        fi
    fi
    
    # Install binary
    install -m 755 "$BINARY_PATH" "${INSTALL_DIR}/${BINARY_NAME}" || fatal "Installation failed. Check permissions."
    
    # Create symlink
    ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${SYMLINK_NAME}" || warn "Could not create symlink 'fl'"
    
    success "Installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

verify_installation() {
    info "Verifying installation..."
    
    if ! command -v flaase >/dev/null 2>&1; then
        fatal "Installation verification failed. 'flaase' command not found."
    fi
    
    INSTALLED_VERSION=$(flaase --version 2>/dev/null | head -1 || echo "unknown")
    success "Flaase installed successfully (${INSTALLED_VERSION})"
}

# =============================================================================
# Post-installation
# =============================================================================

print_next_steps() {
    printf "\n"
    printf "${GREEN}${BOLD}Installation complete!${NC}\n"
    printf "\n"
    printf "Next steps:\n"
    printf "  ${CYAN}fl server init${NC}    Set up this server for deployments\n"
    printf "  ${CYAN}fl --help${NC}         Show all available commands\n"
    printf "\n"
    printf "Documentation: ${CYAN}https://flaase.com/docs${NC}\n"
    printf "\n"
}

run_server_init() {
    printf "\n"
    info "Running 'fl server init'..."
    printf "\n"
    exec fl server init
}

prompt_server_init() {
    printf "\n"
    printf "Would you like to run ${CYAN}fl server init${NC} now? [Y/n] "
    read -r response
    case "$response" in
        [nN][oO]|[nN])
            print_next_steps
            ;;
        *)
            run_server_init
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    AUTO_INIT=0
    for arg in "$@"; do
        case "$arg" in
            --yes|-y)
                AUTO_INIT=1
                ;;
            --help|-h)
                printf "Flaase Installation Script\n\n"
                printf "Usage: curl -fsSL https://get.flaase.com | sh\n"
                printf "   or: curl -fsSL https://get.flaase.com | sh -s -- --yes\n\n"
                printf "Options:\n"
                printf "  --yes, -y    Automatically run 'fl server init' after installation\n"
                printf "  --help, -h   Show this help message\n"
                exit 0
                ;;
        esac
    done
    
    print_ascii_art
    
    printf "${BOLD}Installing Flaase${NC}\n\n"
    
    # Checks
    check_root
    check_commands
    detect_os
    detect_arch
    check_os_supported
    
    info "Detected: ${OS_NAME} (${ARCH})"
    printf "\n"
    
    # Installation
    get_latest_version
    download_binary
    install_binary
    verify_installation
    
    # Post-installation
    if [ "$AUTO_INIT" -eq 1 ]; then
        run_server_init
    else
        prompt_server_init
    fi
}

main "$@"
