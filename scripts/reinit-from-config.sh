#!/bin/bash
#
# Reinitialize a public-inbox from an existing config file
# Usage: reinit-from-config.sh [CONFIG_FILE] [INBOX_NAME]
#
# If CONFIG_FILE is not specified, uses ~/.public-inbox/config
# If INBOX_NAME is not specified, processes ALL inboxes and creates extindex

set -e

CONFIG_FILE="${1:-$HOME/.public-inbox/config}"
INBOX_NAME="$2"

# Check if running interactively
is_interactive() {
	[[ -t 0 ]]
}

# Prompt for confirmation (only in interactive mode)
# Usage: confirm_prompt "message" [default]
# Returns: 0 for yes, 1 for no
confirm_prompt() {
	local msg="$1"
	local default="${2:-n}"

	if is_interactive; then
		read -p "$msg" response
		case "$response" in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		*) [[ "$default" == "y" ]] && return 0 || return 1 ;;
		esac
	else
		# Non-interactive: assume yes
		return 0
	fi
}

if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Config file not found: $CONFIG_FILE" >&2
	exit 1
fi

# Get list of all inbox names from config
get_inbox_names() {
	git config -f "$CONFIG_FILE" --get-regexp '^publicinbox\..*\.address$' |
		sed 's/publicinbox\.\(.*\)\.address.*/\1/' | sort -u
}

# Get a config value for a specific inbox
get_config() {
	local name="$1"
	local key="$2"
	git config -f "$CONFIG_FILE" "publicinbox.${name}.${key}" 2>/dev/null || true
}

# Get all values for a key (e.g., multiple addresses)
get_config_all() {
	local name="$1"
	local key="$2"
	git config -f "$CONFIG_FILE" --get-all "publicinbox.${name}.${key}" 2>/dev/null || true
}

# Get extindex config
get_extindex_config() {
	local key="$1"
	git config -f "$CONFIG_FILE" "extindex.all.${key}" 2>/dev/null || true
}

# Process a single inbox
process_inbox() {
	local name="$1"
	local base_dir="$2"

	# Read config values
	local inbox_dir=$(get_config "$name" "inboxdir")
	local url=$(get_config "$name" "url")
	local description=$(get_config "$name" "description")
	local newsgroup=$(get_config "$name" "newsgroup")
	local listid=$(get_config "$name" "listid")
	local nntpmirror=$(get_config "$name" "nntpmirror")
	local imapmirror=$(get_config "$name" "imapmirror")
	local indexlevel=$(get_config "$name" "indexlevel")

	# Validate required fields
	if [[ -z "$inbox_dir" ]]; then
		echo "Error: inboxdir is required for '$name'" >&2
		return 1
	fi

	if [[ -z "$url" ]]; then
		echo "Error: url is required for '$name'" >&2
		return 1
	fi

	# If base_dir is specified, create inbox in subdirectory
	if [[ -n "$base_dir" ]]; then
		inbox_dir="$base_dir/$name"
		echo "Processing '$name' -> $inbox_dir"
	else
		echo "Processing '$name' -> $inbox_dir"
	fi

	# Build the public-inbox-init command
	local cmd="public-inbox-init -V2"
	cmd="$cmd '$name'"
	cmd="$cmd '$inbox_dir'"

	# Ensure URL has protocol
	if [[ "$url" != http://* && "$url" != https://* ]]; then
		url="https://$url"
	fi
	cmd="$cmd '$url'"

	# Add address(es)
	for addr in $(get_config_all "$name" "address"); do
		cmd="$cmd '$addr'"
	done

	# Add optional parameters
	if [[ -n "$newsgroup" ]]; then
		cmd="$cmd --ng '$newsgroup'"
	fi

	if [[ -n "$indexlevel" ]]; then
		cmd="$cmd -L '$indexlevel'"
	fi

	# Add extra config options via -c
	if [[ -n "$listid" ]]; then
		cmd="$cmd -c listid='$listid'"
	fi

	if [[ -n "$nntpmirror" ]]; then
		cmd="$cmd -c nntpmirror='$nntpmirror'"
	fi

	if [[ -n "$imapmirror" ]]; then
		cmd="$cmd -c imapmirror='$imapmirror'"
	fi

	# Run the command
	echo "  Running: $cmd"
	eval "$cmd"

	# Set git description if provided
	if [[ -n "$description" ]]; then
		if [[ -d "$inbox_dir/all.git" ]]; then
			echo "$description" >"$inbox_dir/all.git/description"
			echo "  Set git description in all.git"
		elif [[ -d "$inbox_dir" ]]; then
			# v1 format
			echo "$description" >"$inbox_dir/description"
			echo "  Set git description"
		fi
	fi

	echo "  Done!"
	echo
}

# Create or update extindex configuration
setup_extindex() {
	local extindex_dir="$1"

	echo "Setting up extindex at $extindex_dir"

	# Check if extindex section already exists
	local existing_topdir=$(get_extindex_config "topdir")

	if [[ -n "$existing_topdir" ]]; then
		echo "  extindex already configured at: $existing_topdir"
		extindex_dir="$existing_topdir"
	else
		# Check if section header exists (even without topdir)
		local has_section=$(git config -f "$CONFIG_FILE" --get-regexp '^extindex\.all\.' 2>/dev/null | head -1 || true)

		if [[ -n "$has_section" ]]; then
			echo "  extindex section exists but has no topdir, adding: $extindex_dir"
			# Add topdir to existing section
			echo "    topdir = $extindex_dir" >>"$CONFIG_FILE"
		else
			# Add new extindex section to config
			echo "" >>"$CONFIG_FILE"
			echo "[extindex \"all\"]" >>"$CONFIG_FILE"
			echo "    topdir = $extindex_dir" >>"$CONFIG_FILE"
			echo "    url = /" >>"$CONFIG_FILE"
			echo "  Added extindex section to config"
		fi
	fi

	# Create extindex directory if it doesn't exist
	mkdir -p "$extindex_dir"

	# Create ALL.git inside extindex directory (per extindex format spec)
	local all_git_dir="$extindex_dir/ALL.git"

	if [[ ! -d "$all_git_dir" ]]; then
		git init --bare "$all_git_dir"
		echo "  Created ALL.git repository at $all_git_dir"
	fi

	# Set description for ALL.git
	if [[ ! -f "$all_git_dir/description" ]]; then
		echo "Public Inbox Archive" >"$all_git_dir/description"
		echo "  Set ALL.git description"
	fi

	# Create description file in extindex directory (for WWW display)
	if [[ ! -f "$extindex_dir/description" ]]; then
		echo "Public Inbox Archive" >"$extindex_dir/description"
		echo "  Set extindex description"
	fi

	# Create ei.lock file (required for extindex format)
	# if [[ ! -f "$extindex_dir/ei.lock" ]]; then
	#     touch "$extindex_dir/ei.lock"
	#     echo "  Created ei.lock"
	# fi

	# Run public-inbox-extindex with explicit directory
	echo "  Running: public-inbox-extindex --all '$extindex_dir'"
	public-inbox-extindex --all "$extindex_dir"

	echo "  extindex created/updated successfully!"
	echo
}

# Setup wwwListing for root path
setup_www_listing() {
	echo "Enabling wwwListing for root path (/)"

	# Check if wwwListing is already set
	local existing=$(git config -f "$CONFIG_FILE" "publicinbox.wwwListing" 2>/dev/null || true)

	if [[ -n "$existing" ]]; then
		echo "  wwwListing already set to: $existing"
	else
		# Check if [publicinbox] section exists without wwwListing
		local has_section=$(git config -f "$CONFIG_FILE" --get-regexp '^publicinbox\.[^.]' 2>/dev/null | head -1 || true)

		if [[ -n "$has_section" ]]; then
			# Section exists, just add wwwListing
			echo "    wwwListing = all" >>"$CONFIG_FILE"
			echo "  Added wwwListing = all to existing [publicinbox] section"
		else
			# No [publicinbox] section exists, create new one
			echo "" >>"$CONFIG_FILE"
			echo "[publicinbox]" >>"$CONFIG_FILE"
			echo "    wwwListing = all" >>"$CONFIG_FILE"
			echo "  Added [publicinbox] section with wwwListing = all"
		fi
	fi
	echo
}

# If no inbox name specified, process ALL inboxes
if [[ -z "$INBOX_NAME" ]]; then
	echo "Processing ALL inboxes from $CONFIG_FILE"
	echo
	# List inboxes first
	echo "Inboxes to process:"
	for name in $(get_inbox_names); do
		inbox_dir=$(get_config "$name" "inboxdir")
		echo "  - $name -> $inbox_dir"
	done
	echo

	if ! confirm_prompt "Continue? [y/N] " "n"; then
		echo "Aborted."
		exit 0
	fi
	echo

	for name in $(get_inbox_names); do
		process_inbox "$name" ""
	done

	# Setup extindex
	echo
	echo "=== Setting up extindex ==="
	extindex_dir=$(get_extindex_config "topdir")
	if [[ -z "$extindex_dir" ]]; then
		# Default extindex location
		extindex_dir="/data/extindex/all"
	fi

	if confirm_prompt "Create extindex at $extindex_dir? [Y/n] " "y"; then
		setup_extindex "$extindex_dir"
		setup_www_listing
	else
		echo "Skipping extindex creation."
	fi

	echo "All inboxes processed!"
	exit 0
fi

# Validate inbox exists
if ! get_config "$INBOX_NAME" "address" >/dev/null 2>&1; then
	echo "Error: Inbox '$INBOX_NAME' not found in $CONFIG_FILE" >&2
	exit 1
fi

# Process single inbox (no base dir = use inboxdir from config)
process_inbox "$INBOX_NAME" ""
