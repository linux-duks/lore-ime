#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

PARENT_PATH=$(
	cd "$(dirname "${BASH_SOURCE[0]}")"
	pwd -P
)

# Check each inbox defined in the config file.
# If an inbox's directory is missing or empty (no git repo), initialize it.
init_needed=()
if [[ -f "$PI_CONFIG" ]]; then
	inbox_names=$(git config -f "$PI_CONFIG" --get-regexp '^publicinbox\..*\.inboxdir$' |
		sed 's/publicinbox\.\(.*\)\.inboxdir.*/\1/' | sort -u)
	for name in $inbox_names; do
		inbox_dir=$(git config -f "$PI_CONFIG" "publicinbox.${name}.inboxdir" 2>/dev/null || true)
		if [[ -z "$inbox_dir" ]]; then
			echo "WARN: inboxdir not set for '$name', skipping"
			continue
		fi
		if [[ ! -d "$inbox_dir" ]] || [[ -z "$(ls -A "$inbox_dir" 2>/dev/null)" ]]; then
			echo "Inbox '$name' missing or empty at $inbox_dir — needs init"
			init_needed+=("$name")
		fi
	done
fi

if [[ ${#init_needed[@]} -gt 0 ]]; then
	for name in "${init_needed[@]}"; do
		echo "Initializing inbox '$name'..."
		PI_CONFIG=/etc/public-inbox/config.init bash "$PARENT_PATH/reinit-from-config.sh" /etc/public-inbox/config "$name"
	done
else
	echo "All inboxes present, skipping init"
fi

# Array to keep track of process IDs
pids=()

# Cleanup function to kill all background processes
cleanup() {
	echo "Shutting down all services..."
	# Only try to kill if there are PIDs to kill
	if [ ${#pids[@]} -gt 0 ]; then
		kill "${pids[@]}" 2>/dev/null
	fi
	exit 0 # Use 0 for a graceful shutdown unless you want Podman to see an error
}

# TRAP signals: This is crucial for Podman.
# When you run 'podman stop', it sends SIGTERM.
# Without this trap, the script dies and leaves "zombie" child processes.
trap cleanup SIGTERM SIGINT

if [ "$SPAMCHECK_ENABLED" = "true" ]; then
	spamd --username debian-spamd -l \
		--nouser-config \
		--syslog stderr \
		--pidfile /var/run/spamd.pid \
		--helper-home-dir /var/lib/spamassassin \
		&
	# -s stderr 2>/dev/null &
	pids+=($!)
fi

# startup interval
sleep 2

EXT_DIR="/data/all/"
BASE_DATA="/data"

mkdir -p $EXT_DIR

if [ "$PI_HTTP_ENABLE" = "true" ]; then
	public-inbox-httpd &
	pids+=($!)
fi

if [ "$PI_NNTP_ENABLE" = "true" ]; then
	public-inbox-nntpd &
	pids+=($!)
fi

if [ "$PI_IMAP_ENABLED" = "true" ]; then
	sleep 2
	public-inbox-watch &
	pids+=($!)
fi

if [ "$PI_INDEXING_ENABLE" = "true" ]; then
	echo "Running Indexing job"
	# The trailing slash on !(all)/ ensures we only match directories
	sleep 2 && public-inbox-extindex "$EXT_DIR" "$BASE_DATA"/!(all)/
	echo "Running Indexing job for the all folder"
	public-inbox-extindex --all
fi

if [ ${#pids[@]} -eq 0 ]; then
	echo "No services enabled. Exiting."
	exit 0
fi

echo "Monitoring services (PIDs: ${pids[*]})..."

# 'wait -n' waits for the FIRST process to exit
# The '!' negates the exit code, so the block runs if the command fails (non-zero)
if ! wait -n; then
	cleanup
else
	echo "A service finished successfully. Checking remaining..."
fi
