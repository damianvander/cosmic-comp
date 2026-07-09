#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# install-kinetic.sh
#
# Downloads and installs a kinetic-scrolling-patched COSMIC binary from this
# repo's GitHub releases. Handles both patched components:
#
#     cosmic-comp      the compositor (kinetic scroll engine + per-app factors)
#     cosmic-settings  the settings app (UI toggle for smooth scrolling)
#
# It picks the release matching your installed epoch, or lets you choose one.
#
# Usage:
#   ./install-kinetic.sh                        # cosmic-comp, auto-detect epoch
#   ./install-kinetic.sh cosmic-settings        # settings app, auto-detect
#   ./install-kinetic.sh cosmic-comp epoch-1.2.0
#   ./install-kinetic.sh cosmic-settings --latest
#
#   curl -fsSL https://raw.githubusercontent.com/damianvander/cosmic-comp/master/install-kinetic.sh | bash
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="damianvander/cosmic-comp"          # patch repo hosting the releases
API="https://api.github.com/repos/${REPO}/releases"
INSTALL_DIR="/usr/bin"

# ── Parse arguments (component + optional version selector, any order) ────────
COMPONENT="cosmic-comp"
SELECTOR=""
for arg in "$@"; do
    case "$arg" in
        cosmic-comp|comp)          COMPONENT="cosmic-comp" ;;
        cosmic-settings|settings)  COMPONENT="cosmic-settings" ;;
        *)                         SELECTOR="$arg" ;;
    esac
done

case "$COMPONENT" in
    cosmic-comp)     UPSTREAM="pop-os/cosmic-comp";     BINARY="cosmic-comp" ;;
    cosmic-settings) UPSTREAM="pop-os/cosmic-settings"; BINARY="cosmic-settings" ;;
esac

# ── Colours ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD='\033[1m'  GREEN='\033[32m'  YELLOW='\033[33m'
    RED='\033[31m'  CYAN='\033[36m'   RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

info()  { echo -e "${BOLD}${CYAN}::${RESET} $*"; }
ok()    { echo -e "${BOLD}${GREEN}✓${RESET} $*"; }
warn()  { echo -e "${BOLD}${YELLOW}⚠${RESET} $*"; }
die()   { echo -e "${BOLD}${RED}✗${RESET} $*" >&2; exit 1; }

info "Component: ${BOLD}${COMPONENT}${RESET}"

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq gzip sha256sum; do
    command -v "$cmd" > /dev/null 2>&1 || die "Required tool '${cmd}' not found. Install it and retry."
done

# ── Detect which upstream epoch the installed binary belongs to ───────────────
detect_installed_epoch() {
    command -v "$BINARY" > /dev/null 2>&1 || { warn "$BINARY not found in PATH"; return 1; }

    local version_output git_hash
    version_output=$("$BINARY" --version 2>/dev/null) || return 1
    git_hash=$(echo "$version_output" | grep -oP 'git commit \K[0-9a-f]+' || true)
    [ -z "$git_hash" ] && { warn "Could not parse git hash from: $version_output"; return 1; }

    info "Installed: ${version_output}"

    local tags_json tag commit
    tags_json=$(curl -fsSL "https://api.github.com/repos/${UPSTREAM}/tags?per_page=100") || return 1
    while IFS=$'\t' read -r tag commit; do
        if [[ "$commit" == "${git_hash}"* ]] || [[ "${git_hash}" == "${commit}"* ]]; then
            echo "$tag"; return 0
        fi
    done < <(echo "$tags_json" | jq -r '.[] | select(.name | startswith("epoch-")) | [.name, .commit.sha] | @tsv')
    return 1
}

get_release_by_tag() { curl -fsSL "${API}/tags/$1" 2>/dev/null; }

# Newest release whose tag starts with patched-<component>-
latest_component_release() {
    curl -fsSL "${API}" | jq -c --arg p "patched-${COMPONENT}-" \
        'map(select(.tag_name | startswith($p))) | .[0] // empty'
}

# ── Resolve which release to install ──────────────────────────────────────────
RELEASE_TAG=""

if [ "$SELECTOR" = "--latest" ] || [ "$SELECTOR" = "-l" ]; then
    info "Fetching latest patched release for ${COMPONENT}..."
    RELEASE_JSON=$(latest_component_release)
    [ -z "$RELEASE_JSON" ] && die "No patched-${COMPONENT}-* releases found at ${REPO}"
    RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

elif [ -n "$SELECTOR" ]; then
    TAG="$SELECTOR"
    [[ "$TAG" != epoch-* ]] && TAG="epoch-${TAG}"
    RELEASE_TAG="patched-${COMPONENT}-${TAG}"
    info "Looking for release: ${RELEASE_TAG}"
    RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
    echo "$RELEASE_JSON" | jq -e '.message' > /dev/null 2>&1 && \
        die "Release '${RELEASE_TAG}' not found.\n  See https://github.com/${REPO}/releases"

else
    info "Detecting installed ${COMPONENT} version..."
    if EPOCH=$(detect_installed_epoch); then
        info "Detected epoch: ${BOLD}${EPOCH}${RESET}"
        RELEASE_TAG="patched-${COMPONENT}-${EPOCH}"
        RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
        if echo "$RELEASE_JSON" | jq -e '.message' > /dev/null 2>&1; then
            warn "No patched release for ${EPOCH} — falling back to latest"
            RELEASE_JSON=$(latest_component_release)
            RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
        fi
    else
        warn "Could not auto-detect epoch — using latest patched release"
        RELEASE_JSON=$(latest_component_release)
        RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
    fi
    [ -z "$RELEASE_TAG" ] && die "No patched releases found for ${COMPONENT} at ${REPO}"
fi

RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // .tag_name')
info "Release:   ${BOLD}${RELEASE_NAME}${RESET}"
info "Tag:       ${RELEASE_TAG}"

# ── Find download URLs (assets are named after the binary) ────────────────────
BINARY_URL=$(echo "$RELEASE_JSON" | jq -r --arg n "${BINARY}.gz" \
    '.assets[] | select(.name == $n) | .browser_download_url')
CHECKSUM_URL=$(echo "$RELEASE_JSON" | jq -r \
    '.assets[] | select(.name == "checksums-sha256.txt") | .browser_download_url')

if [ -z "$BINARY_URL" ]; then
    BINARY_URL=$(echo "$RELEASE_JSON" | jq -r --arg n "${BINARY}" \
        '.assets[] | select(.name == $n) | .browser_download_url')
    COMPRESSED=false
else
    COMPRESSED=true
fi
[ -z "$BINARY_URL" ] && die "No ${BINARY} asset found in release ${RELEASE_TAG}"

# ── Download ──────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading ${BINARY}..."
if [ "$COMPRESSED" = true ]; then
    curl -fSL --progress-bar -o "${TMPDIR}/${BINARY}.gz" "$BINARY_URL"
    gzip -d "${TMPDIR}/${BINARY}.gz"
else
    curl -fSL --progress-bar -o "${TMPDIR}/${BINARY}" "$BINARY_URL"
fi
chmod +x "${TMPDIR}/${BINARY}"

# ── Verify checksum ──────────────────────────────────────────────────────────
if [ -n "$CHECKSUM_URL" ]; then
    info "Verifying checksum..."
    curl -fsSL -o "${TMPDIR}/checksums-sha256.txt" "$CHECKSUM_URL"
    EXPECTED=$(grep " ${BINARY}\$" "${TMPDIR}/checksums-sha256.txt" | awk '{print $1}')
    if [ -n "$EXPECTED" ]; then
        ACTUAL=$(sha256sum "${TMPDIR}/${BINARY}" | awk '{print $1}')
        [ "$EXPECTED" = "$ACTUAL" ] && ok "Checksum verified" \
            || die "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Got:      ${ACTUAL}"
    else
        warn "No matching checksum entry — skipping verification"
    fi
else
    warn "No checksum file in release — skipping verification"
fi

NEW_VERSION=$("${TMPDIR}/${BINARY}" --version 2>/dev/null || echo "unknown")
info "New binary: ${NEW_VERSION}"

# ── Back up existing binary & install ─────────────────────────────────────────
INSTALL_PATH="${INSTALL_DIR}/${BINARY}"
if [ -f "$INSTALL_PATH" ]; then
    info "Current:   $("$INSTALL_PATH" --version 2>/dev/null || echo "unknown")"
    info "Backing up to ${INSTALL_PATH}.bak"
    sudo cp "$INSTALL_PATH" "${INSTALL_PATH}.bak"
    ok "Backup saved"
fi

info "Installing to ${INSTALL_PATH} (requires sudo)..."
sudo install -Dm0755 "${TMPDIR}/${BINARY}" "$INSTALL_PATH"
ok "Installed successfully!"

echo ""
echo -e "${BOLD}${GREEN}Done!${RESET} Patched ${BINARY} is now at ${INSTALL_PATH}"
echo ""
if [ "$COMPONENT" = "cosmic-comp" ]; then
    echo -e "  ${CYAN}To activate:${RESET} log out and back in, or run:"
    echo -e "    ${BOLD}sudo systemctl restart cosmic-comp.service${RESET}"
else
    echo -e "  ${CYAN}To activate:${RESET} relaunch Settings (close and reopen it)."
fi
echo -e "  ${CYAN}To revert:${RESET}  ${BOLD}sudo mv ${INSTALL_PATH}.bak ${INSTALL_PATH}${RESET}"
