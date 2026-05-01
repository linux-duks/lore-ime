#!/usr/bin/env bash
#
# Purge public-inbox indexing data from cloned repos
# Removes msgmap.sqlite3, over.sqlite3, xapian dirs, all.git, description
# but preserves git/*.git/ directories (grokmirror clones)
#
# Usage: ./purge-indexing.sh [OPTIONS]
#
# Options:
#   -d TOPDIR     Path to data directory (default: /data)
#   -n            Dry-run: show what would be done without executing
#   -v            Verbose output
#   -h            Show this help

set -euo pipefail

TOPDIR="/data"
DRY_RUN=false
VERBOSE=false

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
    exit 0
}

while getopts "d:nvh" opt; do
    case $opt in
        d) TOPDIR="$OPTARG" ;;
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

# Find v2 inboxes in TOPDIR
find_inboxes() {
    local inboxes=()
    shopt -s nullglob

    for dir in "${TOPDIR}"/*/; do
        [ -d "${dir}git" ] || continue

        # Check if this is a v2 inbox (has git/*.git)
        local has_epoch=false
        for epoch_dir in "${dir}"git/*.git; do
            if [ -d "$epoch_dir" ]; then
                has_epoch=true
                break
            fi
        done

        if [ "$has_epoch" = true ]; then
            inboxes+=("$(basename "$dir")")
        fi
    done

    shopt -u nullglob
    echo "${inboxes[@]}"
}

# Purge indexing data for a single inbox
purge_inbox() {
    local inbox_name="$1"
    local inbox_dir="${TOPDIR}/${inbox_name}"

    if [ ! -d "$inbox_dir" ]; then
        log_error "Inbox directory not found: ${inbox_dir}"
        return 1
    fi

    log_info "Purging indexing data from '${inbox_name}'"

    # Files/dirs to remove (public-inbox indexing artifacts)
    local purge_patterns=(
        "msgmap.sqlite3"
        "msgmap.sqlite3-journal"
        "over.sqlite3"
        "over.sqlite3-journal"
        "description"
        "all.git"
        "xap*/"
    )

    for pattern in "${purge_patterns[@]}"; do
        for target in "${inbox_dir}"/${pattern}; do
            if [ -e "$target" ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_dry "rm -rf '${target}'"
                else
                    rm -rf "$target"
                    log_info "Removed: ${target}"
                fi
            fi
        done
    done

    # Check if git/ directory still exists (grokmirror clones)
    if [ -d "${inbox_dir}/git" ]; then
        local git_count
        git_count=$(find "${inbox_dir}/git" -maxdepth 1 -name "*.git" -type d 2>/dev/null | wc -l)
        log_info "Preserved ${git_count} git repos in ${inbox_dir}/git/"
    else
        log_warn "No git/ directory found in ${inbox_dir} - was this cloned by grokmirror?"
    fi
}

# Purge external index (extindex)
purge_extindex() {
    local extindex_dir="${TOPDIR}/all"

    if [ -d "$extindex_dir" ]; then
        log_info "Purging external index at '${extindex_dir}'"
        if [ "$DRY_RUN" = true ]; then
            log_dry "rm -rf '${extindex_dir}'"
        else
            rm -rf "$extindex_dir"
            log_info "Removed external index: ${extindex_dir}"
        fi
    else
        log_info "No external index found at '${extindex_dir}'"
    fi

    # Recreate empty directory so $cfg->ALL resolves (public-inbox requires dir to exist)
    if [ "$DRY_RUN" = true ]; then
        log_dry "mkdir -p '${extindex_dir}'"
    else
        mkdir -p "$extindex_dir"
        log_info "Recreated empty extindex directory: ${extindex_dir}"
    fi
}

# Main
main() {
    log_info "Scanning for v2 inboxes in ${TOPDIR}"

    local inboxes
    inboxes=$(find_inboxes)

    if [ -z "$inboxes" ]; then
        log_warn "No v2 inboxes found in ${TOPDIR}"
    else
        local count=0
        for inbox_name in $inboxes; do
            count=$((count + 1))
            purge_inbox "$inbox_name"
        done
        log_info "Purged indexing data from ${count} inboxes"
    fi

    # Always purge external index (extindex)
    purge_extindex
}

main "$@"
