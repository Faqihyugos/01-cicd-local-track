#!/usr/bin/env bash
# =============================================================================
# install-mac-as.sh — One-liner Installer untuk Mac (Apple Silicon & Intel)
# Be A DevOps Employee: Local Machine Track
#
# Apple Silicon → Homebrew
# Intel         → MacPorts (Homebrew sudah tidak mendukung Mac Intel)
#
# Usage: curl -fsSL <url> | bash
#        atau: ./scripts/install-mac-as.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_step() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }
log_ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
log_skip() { echo -e "  ${YELLOW}⏭  $1 (sudah ada — skip)${NC}"; }
log_fail() { echo -e "  ${RED}❌ ERROR: $1${NC}"; exit 1; }

# ─── Cek OS & Arsitektur ─────────────────────────────────────────────────────
if [[ "$OSTYPE" != "darwin"* ]]; then
  log_fail "Script ini hanya untuk macOS. Gunakan install-linux.sh untuk Linux."
fi

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  ARCH_NAME="Apple Silicon (arm64 - M1/M2/M3/M4)"
  PKG_MGR="brew"
  PKG_MGR_NAME="Homebrew"
  BREW_PREFIX="/opt/homebrew"
elif [ "$ARCH" = "x86_64" ]; then
  ARCH_NAME="Intel (x86_64)"
  PKG_MGR="port"
  PKG_MGR_NAME="MacPorts"
  PORT_PREFIX="/opt/local"
else
  log_fail "Arsitektur tidak didukung: $ARCH (hanya mendukung arm64 dan x86_64)"
fi

# Profile shell untuk menyimpan PATH
shell_profile() {
  if [[ "${SHELL:-}" == */bash ]]; then
    echo "$HOME/.bash_profile"
  else
    echo "$HOME/.zprofile"
  fi
}

# Install paket via package manager yang sesuai
pkg_install() {
  local name="$1"
  if [ "$PKG_MGR" = "brew" ]; then
    brew install "$name"
  else
    sudo port -N install "$name"
  fi
}

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Be A DevOps Employee — macOS Installer       ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Target: Mac $ARCH_NAME"
echo -e "  Tool yang akan diinstall: $PKG_MGR_NAME, Docker Desktop, KinD, kubectl, Helm, Terraform"
echo ""
read -r -p "  Lanjutkan? (y/N): " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Dibatalkan."; exit 0; }

# ─── Package Manager ─────────────────────────────────────────────────────────
log_step "1/6 — $PKG_MGR_NAME"

if [ "$PKG_MGR" = "brew" ]; then
  if command -v brew &>/dev/null; then
    log_skip "Homebrew $(brew --version | head -1)"
  else
    echo "  Menginstall Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -f "$BREW_PREFIX/bin/brew" ]; then
      echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >> "$(shell_profile)"
      eval "$($BREW_PREFIX/bin/brew shellenv)"
    fi

    log_ok "Homebrew terinstall"
  fi
else
  # MacPorts butuh Xcode Command Line Tools
  if ! xcode-select -p &>/dev/null; then
    echo "  Menginstall Xcode Command Line Tools..."
    xcode-select --install || true
    read -r -p "  Selesaikan instalasi Command Line Tools di dialog, lalu tekan Enter..."
    xcode-select -p &>/dev/null || log_fail "Xcode Command Line Tools belum terinstall"
  fi

  if [ -x "$PORT_PREFIX/bin/port" ]; then
    export PATH="$PORT_PREFIX/bin:$PORT_PREFIX/sbin:$PATH"
    log_skip "MacPorts $(port version | awk '{print $2}')"
  else
    echo "  Menginstall MacPorts..."
    MACOS_VER=$(sw_vers -productVersion)
    MACOS_MAJOR=${MACOS_VER%%.*}
    if [ "$MACOS_MAJOR" = "10" ]; then
      MACOS_TAG=$(echo "$MACOS_VER" | cut -d. -f1-2)   # contoh: 10.15
    else
      MACOS_TAG="$MACOS_MAJOR"                         # contoh: 15
    fi

    PKG_URL=$(curl -fsSL https://api.github.com/repos/macports/macports-base/releases/latest \
      | grep -o '"browser_download_url": *"[^"]*"' \
      | sed -E 's/.*"(https[^"]*)"/\1/' \
      | grep -E "MacPorts-[0-9.]+-${MACOS_TAG}-[A-Za-z]+\.pkg$" \
      | head -1 || true)
    [ -n "$PKG_URL" ] || log_fail "Installer MacPorts untuk macOS $MACOS_VER tidak ditemukan"

    PKG_FILE="$(mktemp -d)/MacPorts.pkg"
    echo "  Download: $PKG_URL"
    curl -fL --progress-bar -o "$PKG_FILE" "$PKG_URL"
    sudo installer -pkg "$PKG_FILE" -target /
    rm -f "$PKG_FILE"

    echo "export PATH=\"$PORT_PREFIX/bin:$PORT_PREFIX/sbin:\$PATH\"" >> "$(shell_profile)"
    export PATH="$PORT_PREFIX/bin:$PORT_PREFIX/sbin:$PATH"

    log_ok "MacPorts $(port version | awk '{print $2}') terinstall"
  fi

  echo "  Update port definitions (port selfupdate)..."
  sudo port -N selfupdate
fi

# ─── Docker Desktop ───────────────────────────────────────────────────────────
log_step "2/6 — Docker Desktop"

if command -v docker &>/dev/null && docker info &>/dev/null; then
  log_skip "Docker $(docker version --format '{{.Client.Version}}' 2>/dev/null)"
else
  if [ -d "/Applications/Docker.app" ]; then
    log_skip "Docker Desktop sudah ada di Applications (belum running)"
    echo -e "  ${YELLOW}  → Buka Docker Desktop dari Launchpad dan tunggu sampai running${NC}"
  else
    if [ "$PKG_MGR" = "brew" ]; then
      echo "  Menginstall Docker Desktop via Homebrew Cask..."
      brew install --cask docker
    else
      # MacPorts tidak menyediakan Docker Desktop → pakai DMG resmi
      echo "  Menginstall Docker Desktop (DMG resmi, amd64)..."
      DMG_FILE="$(mktemp -d)/Docker.dmg"
      curl -fL --progress-bar -o "$DMG_FILE" "https://desktop.docker.com/mac/main/amd64/Docker.dmg"
      sudo hdiutil attach "$DMG_FILE" -nobrowse -quiet -mountpoint /Volumes/Docker
      sudo /Volumes/Docker/Docker.app/Contents/MacOS/install --accept-license --user="$USER" \
        || sudo cp -R /Volumes/Docker/Docker.app /Applications/
      sudo hdiutil detach /Volumes/Docker -quiet
      rm -f "$DMG_FILE"
    fi
    echo ""
    echo -e "  ${YELLOW}  ⚠️  Buka Docker Desktop dari Launchpad, tunggu sampai running, lalu tekan Enter...${NC}"
    read -r -p "  Docker Desktop sudah running? (tekan Enter untuk lanjut)"
  fi
fi

# ─── KinD ────────────────────────────────────────────────────────────────────
log_step "3/6 — KinD (Kubernetes in Docker)"

if command -v kind &>/dev/null; then
  log_skip "KinD $(kind version)"
else
  pkg_install kind
  log_ok "KinD $(kind version)"
fi

# ─── kubectl ─────────────────────────────────────────────────────────────────
log_step "4/6 — kubectl"

if command -v kubectl &>/dev/null; then
  log_skip "kubectl $(kubectl version --client 2>/dev/null | head -1)"
else
  pkg_install kubectl
  log_ok "kubectl $(kubectl version --client 2>/dev/null | head -1)"
fi

# ─── Helm ────────────────────────────────────────────────────────────────────
log_step "5/6 — Helm"

if command -v helm &>/dev/null; then
  log_skip "Helm $(helm version --short)"
else
  pkg_install helm
  log_ok "Helm $(helm version --short)"
fi

# ─── Terraform ───────────────────────────────────────────────────────────────
log_step "6/6 — Terraform"

if command -v terraform &>/dev/null; then
  log_skip "Terraform $(terraform version | head -1)"
else
  if [ "$PKG_MGR" = "brew" ]; then
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
  else
    pkg_install terraform
  fi
  log_ok "Terraform $(terraform version | head -1)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  ✅  Instalasi selesai!                ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Langkah selanjutnya:"
echo -e "  ${BLUE}1.${NC} Pastikan Docker Desktop sudah running (ikon di menu bar)"
echo -e "  ${BLUE}2.${NC} Buka terminal baru (agar PATH $PKG_MGR_NAME aktif)"
echo -e "  ${BLUE}3.${NC} Jalankan: ${BOLD}./00-preflight/check-env.sh${NC}"
echo ""
