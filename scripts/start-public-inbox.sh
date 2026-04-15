#!/usr/bin/env bash
set -euo pipefail

if [ -z "$(ls -A $PI_DATA_DIR)" ]; then
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
	# Kill all PIDs in our array; ignore errors if they are already dead
	kill "${pids[@]}" 2>/dev/null
	exit 1
}

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
	# Enable extended globbing for the 'not' operator
	shopt -s extglob

	# Run the command
	# The trailing slash on !(all)/ ensures we only match directories
	sleep 2 && public-inbox-extindex "$EXT_DIR" "$BASE_DATA"/!(all)/
fi

echo "Monitoring services (PIDs: ${pids[*]})..."

# 'wait -n' waits for the FIRST process to exit and returns its exit code
wait -n

if [ $? -ne 0 ]; then
	echo "Critial failure detected in one of the services!"
	cleanup
else
	echo "A service finished successfully. Checking remaining..."
fi
