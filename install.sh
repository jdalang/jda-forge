#!/bin/bash
# =============================================================================
# JDA Forge — Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jdalang/jda-forge/main/install.sh | sh
# =============================================================================

set -euo pipefail

REPO="https://github.com/jdalang/jda-forge.git"
INSTALL_DIR="${JDA_HOME:-$HOME/.jda}"
FORGE_DIR="$INSTALL_DIR/forge"
BIN_DIR="$INSTALL_DIR/bin"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn()    { echo -e "${YELLOW}warning:${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
err()     { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

command -v git  >/dev/null 2>&1 || err "git is required. Install it and re-run."
command -v jda  >/dev/null 2>&1 || warn "jda compiler not found. Install from https://github.com/jdalang/jda"

# ---------------------------------------------------------------------------
# Clone or update
# ---------------------------------------------------------------------------

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

if [ -d "$FORGE_DIR/.git" ]; then
    info "Updating JDA Forge..."
    git -C "$FORGE_DIR" pull --ff-only --quiet
    success "Updated to latest version"
else
    info "Installing JDA Forge..."
    git clone --depth=1 --quiet "$REPO" "$FORGE_DIR"
    success "Cloned to $FORGE_DIR"
fi

# ---------------------------------------------------------------------------
# Symlink forge CLI
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
        if ! grep -q '.jda/bin' "$rc" 2>/dev/null; then
            echo "" >> "$rc"
            echo "# JDA Forge" >> "$rc"
            echo "$EXPORT_LINE" >> "$rc"
            echo "$FORGE_LINE"  >> "$rc"
            success "Added PATH to $rc"
        else
            success "$rc already configured"
        fi
    fi
}

SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
case "$SHELL_NAME" in
    zsh)  add_to_shell "$HOME/.zshrc"  ;;
    bash) add_to_shell "$HOME/.bashrc" && add_to_shell "$HOME/.bash_profile" ;;
    fish) info "Add to ~/.config/fish/config.fish: set -x PATH \$HOME/.jda/bin \$PATH" ;;
esac

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}JDA Forge installed successfully!${NC}"
echo ""
echo "  forge.jda  →  $FORGE_DIR/forge.jda"
echo "  forge CLI  →  $BIN_DIR/forge"
echo ""
echo "Reload your shell or run:"
echo -e "  ${BOLD}source ~/.zshrc${NC}   (or .bashrc)"
echo ""
echo "Create a new project:"
echo -e "  ${BOLD}forge new myapp${NC}"
echo ""
echo "Use in an existing project:"
echo -e "  ${BOLD}jda build --include \$JDA_FORGE app.jda -o app${NC}"
