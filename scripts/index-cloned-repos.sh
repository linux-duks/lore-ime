#!/usr/bin/env bash
#
# Index cloned grokmirror repos for public-inbox hosting
# Scans /data/ for v2 inboxes, adds them to config, indexes them,
# and updates the extindex.
#
# Usage: ./index-cloned-repos.sh [OPTIONS]
#
# Options:
#   -c CONFIG     Path to public-inbox config (default: /etc/public-inbox/config)
#   -d TOPDIR     Path to grokmirror data directory (default: /data)
#   -o ORIGIN     Origin URL to fetch inbox configs from (default: https://lore.kernel.org)
#   -j JOBS       Number of parallel indexing jobs (default: 4)
#   -n            Dry-run: show what would be done without executing
#   -v            Verbose output
#   -h            Show this help

set -euo pipefail

PI_CONFIG="${PI_CONFIG:-/etc/public-inbox/config}"
TOPDIR="/data"
ORIGIN="https://lore.kernel.org"
JOBS=4
DRY_RUN=false
VERBOSE=false
INTERRUPTED=false

export PI_CONFIG TOPDIR JOBS

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
    exit 0
}

while getopts "c:d:o:j:nvh" opt; do
    case $opt in
        c) PI_CONFIG="$OPTARG" ;;
        d) TOPDIR="$OPTARG" ;;
        o) ORIGIN="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        n) DRY_RUN=true ;;
        v) VERBOSE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ "$VERBOSE" = true ]; then
    set -x
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_dry()   { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }

trap 'INTERRUPTED=true; log_warn "Interrupt received, exiting after current operation completes"' INT TERM

# Check if inbox is already in config
inbox_in_config() {
    local name="$1"
    git config -f "$PI_CONFIG" --get "publicinbox.${name}.inboxdir" >/dev/null 2>&1
}

# Check if an inbox directory needs v2 initialization
# Returns 0 if needs init, 1 if complete
needs_init() {
    local inbox_dir="$1"

    # Has git epoch repos
    local has_epoch=false
    for epoch_dir in "${inbox_dir}"/git/*.git; do
        if [ -d "$epoch_dir" ]; then
            has_epoch=true
            break
        fi
    done

    if [ "$has_epoch" = false ]; then
        return 1  # No git repos at all, not a grokmirror inbox
    fi

    # Lacks v2 wrapper structure
    if [ ! -d "${inbox_dir}/all.git" ] || [ ! -f "${inbox_dir}/msgmap.sqlite3" ]; then
        return 0  # Needs init
    fi

    return 1  # Already complete
}

# Get config value for an inbox from the PI_CONFIG file
get_config() {
    local name="$1"
    local key="$2"
    git config -f "$PI_CONFIG" "publicinbox.${name}.${key}" 2>/dev/null || true
}

# Fetch remote config for an inbox
fetch_remote_config() {
    local inbox_name="$1"
    local inbox_dir="$2"
    local config_url="${ORIGIN}/${inbox_name}/_/text/config/raw"

    if curl --compressed -sf -o "${inbox_dir}/remote.config.$$" "$config_url" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Extract addresses from remote config
extract_addresses() {
    git config -f "${1}/remote.config.$$" -l 2>/dev/null | \
        sed -ne 's/^publicinbox\..*\.address=//p' | tr '\n' ' '
}

# Extract description from remote config
extract_description() {
    git config -f "${1}/remote.config.$$" -l 2>/dev/null | \
        sed -ne 's/^publicinbox\..*\.description=//p' | head -1
}

# Find all v2 inboxes in TOPDIR
find_v2_inboxes() {
    local inboxes=()

    # v2 inboxes have this structure: inboxdir/git/N.git
    # We look for the top-level inbox directories
    for dir in "${TOPDIR}"/*/; do
        [ -d "${dir}git" ] || continue

        # Check if this is a v2 inbox (has git/0.git or similar)
        local has_epoch=false
        for epoch_dir in "${dir}"git/*.git; do
            if [ -d "$epoch_dir" ]; then
                has_epoch=true
                break
            fi
        done

        if [ "$has_epoch" = true ]; then
            local inbox_name
            inbox_name=$(basename "$dir")
            inboxes+=("$inbox_name")
        fi
    done

    echo "${inboxes[@]}"
}

# Initialize a single inbox
# Returns: 0 = initialized, 1 = failed, 2 = skipped (already complete)
init_inbox() {
    local inbox_name="$1"
    local inbox_dir="${TOPDIR}/${inbox_name}"
    local url="${ORIGIN}/${inbox_name}"

    # If inbox is in config AND complete, skip
    if inbox_in_config "$inbox_name" && ! needs_init "$inbox_dir"; then
        log_info "Skipping '${inbox_name}' - already initialized"
        return 2
    fi

    # If inbox is in config but needs init (grokmirror clone), use config values
    if inbox_in_config "$inbox_name"; then
        log_info "Reinitializing '${inbox_name}' - in config but lacks v2 structure"

        local config_url config_address
        config_url=$(get_config "$inbox_name" "url")
        config_address=$(get_config "$inbox_name" "address")

        if [ -z "$config_url" ]; then
            config_url="${url}"
        fi
        if [ -z "$config_address" ]; then
            config_address="${inbox_name}@localhost"
            log_warn "Using fallback address: ${config_address}"
        fi

        if [ "$DRY_RUN" = true ]; then
            log_dry "public-inbox-init -V2 '${inbox_name}' '${inbox_dir}' '${config_url}' ${config_address}"
            log_dry "public-inbox-index --jobs=${JOBS} '${inbox_dir}'"
            return 0
        fi

        if public-inbox-init -V2 \
            "${inbox_name}" \
            "${inbox_dir}" \
            "${config_url}" \
            "${config_address}"; then

            log_info "Reinitialized '${inbox_name}'"
        else
            log_error "Failed to reinitialize '${inbox_name}'"
            return 1
        fi

        log_info "Indexing '${inbox_name}'"
        if public-inbox-index --jobs="${JOBS}" "${inbox_dir}"; then
            log_info "Indexed '${inbox_name}'"
        else
            log_error "Failed to index '${inbox_name}'"
            return 1
        fi

        return 0
    fi

    # Inbox not in config - full init with remote config fetch
    log_info "Initializing inbox '${inbox_name}'"

    # Try to get remote config
    local addresses=""
    local description=""

    if fetch_remote_config "$inbox_name" "$inbox_dir"; then
        addresses=$(extract_addresses "$inbox_dir")
        description=$(extract_description "$inbox_dir")
    fi

    # Fallback addresses
    if [ -z "$addresses" ]; then
        addresses="${inbox_name}@localhost"
        log_warn "Using fallback address: ${addresses}"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry "public-inbox-init -V2 '${inbox_name}' '${inbox_dir}' '${url}' ${addresses}"
        if [ -n "$description" ]; then
            log_dry "Set description: ${description}"
        fi
        log_dry "public-inbox-index --jobs=${JOBS} '${inbox_dir}'"
        rm -f "${inbox_dir}/remote.config.$$"
        return 0
    fi

    # Run public-inbox-init
    if public-inbox-init -V2 \
        "${inbox_name}" \
        "${inbox_dir}" \
        "${url}" \
        ${addresses}; then

        # Set description if available
        if [ -n "$description" ]; then
            echo "${description}" > "${inbox_dir}/description"
        fi

        log_info "Initialized '${inbox_name}'"
    else
        log_error "Failed to initialize '${inbox_name}'"
        rm -f "${inbox_dir}/remote.config.$$"
        return 1
    fi

    rm -f "${inbox_dir}/remote.config.$$"

    # Run public-inbox-index
    log_info "Indexing '${inbox_name}'"
    if public-inbox-index --jobs="${JOBS}" "${inbox_dir}"; then
        log_info "Indexed '${inbox_name}'"
    else
        log_error "Failed to index '${inbox_name}'"
        return 1
    fi
}

# Run extindex on all inboxes
run_extindex() {
    if [ "$DRY_RUN" = true ]; then
        log_dry "public-inbox-extindex --all --jobs=${JOBS} /data/all"
        return 0
    fi

    log_info "Running extindex on all inboxes"
    if public-inbox-extindex --all --jobs="${JOBS}" /data/all; then
        log_info "Extindex complete"
    else
        log_error "Extindex failed"
        return 1
    fi
}

# Main
main() {
    log_info "Scanning for v2 inboxes in ${TOPDIR}"

    local inboxes
    inboxes=$(find_v2_inboxes)

    if [ -z "$inboxes" ]; then
        log_warn "No v2 inboxes found in ${TOPDIR}"
        exit 0
    fi

    local total=0
    local initialized=0
    local skipped=0
    local failed=0

    for inbox_name in $inboxes; do
        if [ "$INTERRUPTED" = true ]; then
            log_info "Interrupted, exiting..."
            break
        fi
        
        total=$((total + 1))

        local rc=0
        init_inbox "$inbox_name" || rc=$?

        case $rc in
            0) initialized=$((initialized + 1)) ;;
            1) failed=$((failed + 1)) ;;
            2) skipped=$((skipped + 1)) ;;
        esac
    done

    log_info "Summary: ${total} inboxes found, ${initialized} initialized, ${skipped} skipped, ${failed} failed"

    if [ "$INTERRUPTED" = true ]; then
        log_info "Skipping extindex due to interrupt"
        exit 0
    fi

    if [ "$initialized" -gt 0 ] || [ "$DRY_RUN" = true ]; then
        run_extindex
    fi
}

main "$@"
