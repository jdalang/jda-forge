#!/bin/bash
# =============================================================================
# JDA Forge — Installer
#
# Via JDA package manager (recommended):
#   jda install forge                     # latest
#   jda install forge@1.0.0              # specific version
#   jda install github.com/jdalang/jda-forge
#   jda install github.com/jdalang/jda-forge@1.0.0
#
# Via curl (bootstrap / CI):
#   curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --version v1.0.0
# =============================================================================

set -euo pipefail

REPO="https://github.com/jdalang/jda-forge.git"
INSTALL_DIR="${JDA_HOME:-$HOME/.jda}"
FORGE_DIR="$INSTALL_DIR/forge"
BIN_DIR="$INSTALL_DIR/bin"
# JDA_PKG_VERSION / JDA_PKG_SOURCE are set by 'jda install'; flags override them.
VERSION="${JDA_PKG_VERSION:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn()    { echo -e "${YELLOW}warning:${NC} $*"; }
success() { echo -e "  ${GREEN}✓${NC} $*"; }
err()     { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --version|-v)
            VERSION="${2:-}"
            [ -z "$VERSION" ] && err "--version requires a value (e.g. --version v1.0.0)"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="${2:-}"
            [ -z "$INSTALL_DIR" ] && err "--dir requires a path"
            FORGE_DIR="$INSTALL_DIR/forge"
            BIN_DIR="$INSTALL_DIR/bin"
            shift 2
            ;;
        --help|-h)
            echo "Usage: install.sh [--version v1.0.0] [--dir /path]"
            echo ""
            echo "Environment variables (set by 'jda install'):"
            echo "  JDA_PKG_VERSION  version to install (e.g. 1.0.0 or v1.0.0)"
            echo "  JDA_PKG_SOURCE   alternate git URL"
            exit 0
            ;;
        *) err "Unknown flag: $1. Use --help for usage." ;;
    esac
done

# Normalise version: accept "1.0.0" or "v1.0.0"
if [ -n "$VERSION" ]; then
    [[ "$VERSION" == v* ]] || VERSION="v${VERSION}"
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

# JDA_PKG_SOURCE lets jda install override the repo URL (e.g. a mirror)
[ -n "${JDA_PKG_SOURCE:-}" ] && REPO="$JDA_PKG_SOURCE"

command -v git >/dev/null 2>&1 || err "git is required. Install it and re-run."
command -v jda >/dev/null 2>&1 || warn "jda compiler not found in PATH. Install from https://github.com/jdalang/jda"

# ---------------------------------------------------------------------------
# Clone or update
# ---------------------------------------------------------------------------

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

if [ -d "$FORGE_DIR/.git" ]; then
    info "Updating JDA Forge repository..."
    git -C "$FORGE_DIR" fetch --tags --quiet
    if [ -n "$VERSION" ]; then
        git -C "$FORGE_DIR" checkout "$VERSION" --quiet \
            || err "Version $VERSION not found. Run: git -C $FORGE_DIR tag | sort -V"
        success "Checked out $VERSION"
    else
        git -C "$FORGE_DIR" pull --ff-only --quiet
        success "Updated to latest ($(git -C "$FORGE_DIR" describe --tags --always 2>/dev/null || echo 'main'))"
    fi
else
    if [ -n "$VERSION" ]; then
        info "Installing JDA Forge $VERSION..."
        git clone --quiet "$REPO" "$FORGE_DIR"
        git -C "$FORGE_DIR" checkout "$VERSION" --quiet \
            || err "Version $VERSION not found."
    else
        info "Installing JDA Forge (latest)..."
        git clone --depth=1 --quiet "$REPO" "$FORGE_DIR"
    fi
    success "Installed to $FORGE_DIR"
fi

INSTALLED_VERSION=$(git -C "$FORGE_DIR" describe --tags --always 2>/dev/null || echo 'main')

# ---------------------------------------------------------------------------
# Symlink CLI
# ---------------------------------------------------------------------------

chmod +x "$FORGE_DIR/bin/forge"
ln -sf "$FORGE_DIR/bin/forge" "$BIN_DIR/forge"
success "Linked forge CLI → $BIN_DIR/forge"

# ---------------------------------------------------------------------------
# Shell config
# ---------------------------------------------------------------------------

EXPORT_LINE="export PATH=\"\$HOME/.jda/bin:\$PATH\""
FORGE_LINE="export JDA_FORGE=\"\$HOME/.jda/forge/forge.jda\""

add_to_shell() {
    local rc="$1"
    if [ -f "$rc" ]; then
        if ! grep -q '\.jda/bin' "$rc" 2>/dev/null; then
            printf '\n# JDA Forge\n%s\n%s\n' "$EXPORT_LINE" "$FORGE_LINE" >> "$rc"
            success "Updated $rc"
        else
            success "$rc already configured"
        fi
    fi
}

SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
case "$SHELL_NAME" in
    zsh)  add_to_shell "$HOME/.zshrc" ;;
    bash) add_to_shell "$HOME/.bashrc"; add_to_shell "$HOME/.bash_profile" ;;
    fish)
        success "Add to ~/.config/fish/config.fish:"
        echo "    set -x PATH \$HOME/.jda/bin \$PATH"
        echo "    set -x JDA_FORGE \$HOME/.jda/forge/forge.jda"
        ;;
esac

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}JDA Forge ${INSTALLED_VERSION} installed successfully!${NC}"
echo ""
echo "  forge.jda  →  $FORGE_DIR/forge.jda"
echo "  forge CLI  →  $BIN_DIR/forge"
echo ""
echo "Reload your shell:"
echo -e "  ${BOLD}source ~/.zshrc${NC}  (or .bashrc)"
echo ""
echo "Create a project:   ${BOLD}forge new myapp${NC}"
echo "Upgrade later:      ${BOLD}forge self-update${NC}"
echo "Install a version:  ${BOLD}forge self-update --version v1.0.0${NC}"
