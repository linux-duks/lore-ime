#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

if [ -z "$(ls -A "$PI_DATA_DIR")" ]; then
	echo "Data Directory is empty. Initialyzing"
	PI_CONFIG=/etc/public-inbox/config.init bash ./reinit-from-config.sh /etc/public-inbox/config
else
	# public-inbox-index
	echo "Starting"
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
