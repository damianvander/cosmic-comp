#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# install-kinetic-cosmic-comp.sh
#
# Downloads and installs a kinetic-scrolling-patched cosmic-comp binary from
# GitHub releases. Automatically picks the release matching your installed
# epoch, or lets you choose a specific version.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/damianvander/cosmic-comp/kinetic-overrides-rebased/install-kinetic-cosmic-comp.sh | bash
#
#   # Or with a specific epoch:
#   ./install-kinetic-cosmic-comp.sh epoch-1.2.0
#
#   # Or always grab the latest patched release:
#   ./install-kinetic-cosmic-comp.sh --latest
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="damianvander/cosmic-comp"
API="https://api.github.com/repos/${REPO}/releases"
BINARY_NAME="cosmic-comp"
INSTALL_DIR="/usr/bin"

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

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl jq gzip sha256sum; do
    command -v "$cmd" > /dev/null 2>&1 || die "Required tool '${cmd}' not found. Install it and retry."
done

# ── Detect current install ────────────────────────────────────────────────────
detect_installed_epoch() {
    if ! command -v "$BINARY_NAME" > /dev/null 2>&1; then
        warn "cosmic-comp not found in PATH"
        return 1
    fi

    local version_output
    version_output=$("$BINARY_NAME" --version 2>/dev/null) || return 1
    local git_hash
    git_hash=$(echo "$version_output" | grep -oP 'git commit \K[0-9a-f]+' || true)

    if [ -z "$git_hash" ]; then
        warn "Could not parse git hash from: $version_output"
        return 1
    fi

    info "Installed: ${version_output}"
    info "Git hash:  ${git_hash:0:12}"

    # Try to find which epoch tag contains this commit by checking the
    # upstream repo's tags via the GitHub API.
    local tags_json
    tags_json=$(curl -fsSL "https://api.github.com/repos/pop-os/cosmic-comp/tags?per_page=100") || return 1

    local tag commit
    while IFS=$'\t' read -r tag commit; do
        # Check if the installed hash is an ancestor of this tag's commit.
        # Since we don't have the repo locally, we compare directly — if the
        # installed hash matches a tag commit exactly, that's our epoch.
        if [[ "$commit" == "${git_hash}"* ]] || [[ "${git_hash}" == "${commit}"* ]]; then
            echo "$tag"
            return 0
        fi
    done < <(echo "$tags_json" | jq -r '.[] | select(.name | startswith("epoch-")) | [.name, .commit.sha] | @tsv')

    # If no exact match, we can't determine the epoch from hash alone
    return 1
}

# ── List available patched releases ───────────────────────────────────────────
list_releases() {
    curl -fsSL "${API}" | jq -r '
        .[] | select(.tag_name | startswith("patched-epoch-"))
        | [.tag_name, .name, .published_at] | @tsv
    ' 2>/dev/null
}

get_latest_release() {
    curl -fsSL "${API}/latest" 2>/dev/null
}

get_release_by_tag() {
    curl -fsSL "${API}/tags/$1" 2>/dev/null
}

# ── Resolve which release to install ──────────────────────────────────────────
REQUESTED="${1:-}"
RELEASE_TAG=""

if [ "$REQUESTED" = "--latest" ] || [ "$REQUESTED" = "-l" ]; then
    info "Fetching latest patched release..."
    RELEASE_JSON=$(get_latest_release)
    RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
    if [ -z "$RELEASE_TAG" ]; then
        die "No releases found at ${REPO}"
    fi

elif [ -n "$REQUESTED" ]; then
    # User specified an epoch tag directly
    TAG="$REQUESTED"
    [[ "$TAG" != epoch-* ]] && TAG="epoch-${TAG}"
    RELEASE_TAG="patched-${TAG}"
    info "Looking for release: ${RELEASE_TAG}"
    RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
    if echo "$RELEASE_JSON" | jq -e '.message' > /dev/null 2>&1; then
        die "Release '${RELEASE_TAG}' not found. Run with --latest or check available releases at:\n  https://github.com/${REPO}/releases"
    fi

else
    # Auto-detect from installed version
    info "Detecting installed cosmic-comp version..."
    if EPOCH=$(detect_installed_epoch); then
        info "Detected epoch: ${BOLD}${EPOCH}${RESET}"
        RELEASE_TAG="patched-${EPOCH}"
        info "Looking for release: ${RELEASE_TAG}"
        RELEASE_JSON=$(get_release_by_tag "$RELEASE_TAG")
        if echo "$RELEASE_JSON" | jq -e '.message' > /dev/null 2>&1; then
            warn "No patched release found for ${EPOCH}"
            info "Falling back to latest patched release..."
            RELEASE_JSON=$(get_latest_release)
            RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
        fi
    else
        warn "Could not auto-detect epoch — using latest patched release"
        RELEASE_JSON=$(get_latest_release)
        RELEASE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')
    fi

    if [ -z "$RELEASE_TAG" ]; then
        die "No patched releases found at ${REPO}"
    fi
fi

RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name // .tag_name')
info "Release:   ${BOLD}${RELEASE_NAME}${RESET}"
info "Tag:       ${RELEASE_TAG}"

# ── Find download URLs ───────────────────────────────────────────────────────
BINARY_URL=$(echo "$RELEASE_JSON" | jq -r '
    .assets[] | select(.name == "cosmic-comp.gz") | .browser_download_url
')
CHECKSUM_URL=$(echo "$RELEASE_JSON" | jq -r '
    .assets[] | select(.name == "checksums-sha256.txt") | .browser_download_url
')

# Fall back to uncompressed binary if .gz isn't available
if [ -z "$BINARY_URL" ]; then
    BINARY_URL=$(echo "$RELEASE_JSON" | jq -r '
        .assets[] | select(.name == "cosmic-comp") | .browser_download_url
    ')
    COMPRESSED=false
else
    COMPRESSED=true
fi

[ -z "$BINARY_URL" ] && die "No binary asset found in release ${RELEASE_TAG}"

# ── Download to temp directory ────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading binary..."
if [ "$COMPRESSED" = true ]; then
    curl -fSL --progress-bar -o "${TMPDIR}/cosmic-comp.gz" "$BINARY_URL"
    info "Decompressing..."
    gzip -d "${TMPDIR}/cosmic-comp.gz"
else
    curl -fSL --progress-bar -o "${TMPDIR}/cosmic-comp" "$BINARY_URL"
fi

chmod +x "${TMPDIR}/cosmic-comp"

# ── Verify checksum ──────────────────────────────────────────────────────────
if [ -n "$CHECKSUM_URL" ]; then
    info "Verifying checksum..."
    curl -fsSL -o "${TMPDIR}/checksums-sha256.txt" "$CHECKSUM_URL"
    EXPECTED=$(grep ' cosmic-comp$' "${TMPDIR}/checksums-sha256.txt" | awk '{print $1}')
    if [ -n "$EXPECTED" ]; then
        ACTUAL=$(sha256sum "${TMPDIR}/cosmic-comp" | awk '{print $1}')
        if [ "$EXPECTED" = "$ACTUAL" ]; then
            ok "Checksum verified"
        else
            die "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Got:      ${ACTUAL}"
        fi
    else
        warn "Could not find uncompressed binary checksum — skipping verification"
    fi
else
    warn "No checksum file in release — skipping verification"
fi

# ── Confirm version ──────────────────────────────────────────────────────────
NEW_VERSION=$("${TMPDIR}/cosmic-comp" --version 2>/dev/null || echo "unknown")
info "New binary: ${NEW_VERSION}"

# ── Back up existing binary ──────────────────────────────────────────────────
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

if [ -f "$INSTALL_PATH" ]; then
    CURRENT_VERSION=$("$INSTALL_PATH" --version 2>/dev/null || echo "unknown")
    info "Current:   ${CURRENT_VERSION}"

    BACKUP_PATH="${INSTALL_PATH}.bak"
    info "Backing up current binary to ${BACKUP_PATH}"
    sudo cp "$INSTALL_PATH" "$BACKUP_PATH"
    ok "Backup saved"
fi

# ── Install ──────────────────────────────────────────────────────────────────
info "Installing to ${INSTALL_PATH} (requires sudo)..."
sudo install -Dm0755 "${TMPDIR}/cosmic-comp" "$INSTALL_PATH"
ok "Installed successfully!"

echo ""
echo -e "${BOLD}${GREEN}Done!${RESET} Patched cosmic-comp is now at ${INSTALL_PATH}"
echo ""
echo -e "  ${CYAN}To activate:${RESET} Log out and back in, or run:"
echo -e "    ${BOLD}sudo systemctl restart cosmic-comp.service${RESET}"
echo ""
echo -e "  ${CYAN}To revert:${RESET}"
echo -e "    ${BOLD}sudo mv ${INSTALL_PATH}.bak ${INSTALL_PATH}${RESET}"
