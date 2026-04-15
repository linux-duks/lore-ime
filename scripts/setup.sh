#!/usr/bin/env bash
#
# Generate configuration files from templates
# Reads .env file and produces configs in build/ directory
#
# Usage: ./setup.sh [--env PATH] [--force]
#
# Options:
#   --env PATH    Path to .env file (default: .env)
#   --force       Overwrite existing .env if missing
#   --dry-run     Show what would be generated without writing

set -euo pipefail

ENV_FILE=".env"
FORCE=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
	echo "Usage: $0 [--env PATH] [--force] [--dry-run]"
	echo ""
	echo "Generate configuration files from templates"
	echo ""
	echo "Options:"
	echo "  --env PATH    Path to .env file (default: .env)"
	echo "  --force       Overwrite existing .env if missing"
	echo "  --dry-run     Show what would be generated without writing"
	exit 0
}

while [[ $# -gt 0 ]]; do
	case $1 in
	--env)
		ENV_FILE="$2"
		shift 2
		;;
	--force)
		FORCE=true
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		log_error "Unknown option: $1"
		usage
		;;
	esac
done

# Copy .env.example to .env if not exists
if [[ ! -f "$ENV_FILE" ]]; then
	if [[ "$FORCE" = true ]]; then
		cp .env.example "$ENV_FILE"
		log_info "Created $ENV_FILE from .env.example"
	else
		log_error "$ENV_FILE not found"
		log_info "Run: cp .env.example $ENV_FILE"
		log_info "Then edit $ENV_FILE with your values"
		log_info "Or run: $0 --force"
		exit 1
	fi
fi

# Source the .env file
set -a
source "$ENV_FILE"
set +a

# Validate required variables
required_vars=("MIRROR_UPSTREAM_HOST" "SERVE_HOST" "ACME_ENABLED" "ACME_EMAIL")
missing=()

for var in "${required_vars[@]}"; do
	if [[ -z "${!var:-}" ]]; then
		missing+=("$var")
	fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
	log_error "Missing required variables: ${missing[*]}"
	log_info "Please set them in $ENV_FILE"
	exit 1
fi

# Create build directory structure
if [[ "$DRY_RUN" = false ]]; then
	mkdir -p build/grokmirror build/nginx build/pi-configs
fi

# Process template function
process_template() {
	local template="$1"
	local output="$2"

	if [[ ! -f "$template" ]]; then
		log_error "Template not found: $template"
		return 1
	fi

	if [[ "$DRY_RUN" = true ]]; then
		log_info "Would generate: $output from $template"
		return 0
	fi

	# Handle conditional blocks
	local content
	content=$(cat "$template")

	# Process {{#ACME_ENABLED}}...{{/ACME_ENABLED}} blocks
	if [[ "$ACME_ENABLED" == "true" ]]; then
		content=$(echo "$content" | sed \
			-e 's/^{{#ACME_ENABLED}}$//' \
			-e 's/^{{\/ACME_ENABLED}}$//')
	else
		content=$(echo "$content" | sed \
			-e '/^{{#ACME_ENABLED}}$/,/^{{\/ACME_ENABLED}}$/d')
	fi

	# Process {{#PI_IMAP_ENABLED}}...{{/PI_IMAP_ENABLED}} blocks
	if [[ "$PI_IMAP_ENABLED" == "true" ]]; then
		content=$(echo "$content" | sed \
			-e 's/^{{#PI_IMAP_ENABLED}}$//' \
			-e 's/^{{\/PI_IMAP_ENABLED}}$//')
	else
		content=$(echo "$content" | sed \
			-e '/^{{#PI_IMAP_ENABLED}}$/,/^{{\/PI_IMAP_ENABLED}}$/d')
	fi



	# Process {{#SPAMCHECK_ENABLED}}...{{/SPAMCHECK_ENABLED}} blocks
	if [[ "${PI_IMAP_ENABLED:-false}" == "true" ]]; then
		content=$(echo "$content" | sed \
			-e 's/^{{#SPAMCHECK_ENABLED}}$//' \
			-e 's/^{{\/SPAMCHECK_ENABLED}}$//')
	else
		content=$(echo "$content" | sed \
			-e '/^{{#SPAMCHECK_ENABLED}}$/,/^{{\/SPAMCHECK_ENABLED}}$/d')
	fi

	# Replace {{VAR}} placeholders with values
	sed_args=(
		-e "s|{{MIRROR_UPSTREAM_HOST}}|${MIRROR_UPSTREAM_HOST}|g"
		-e "s|{{SERVE_HOST}}|${SERVE_HOST}|g"
		-e "s|{{ACME_EMAIL}}|${ACME_EMAIL}|g"
	)

	# Conditionally append the IMAP replacements
	if [[ "$PI_IMAP_ENABLED" == "true" ]]; then
		sed_args+=(
			-e "s|{{PI_IMAP_LIST_NAME}}|${PI_IMAP_LIST_NAME}|g"
			-e "s|{{PI_IMAP_LIST_ADDRESS}}|${PI_IMAP_LIST_ADDRESS}|g"
			-e "s|{{PI_IMAP_AUTH_URL}}|${PI_IMAP_AUTH_URL}|g"
		)
	fi

	# Execute sed using the array expansion
	# Note: I used <<< "$content" instead of echo, which is generally safer in Bash
	content=$(sed "${sed_args[@]}" <<<"$content")

	# Remove any remaining empty lines from conditional blocks
	content=$(sed '/^$/N;/^\n$/d' <<<"$content")

	echo "$content" >"$output"
	log_info "Generated: $output"
}

# Process all templates
log_info "Generating configurations..."

process_template "configs/grokmirror/clone.conf.template" "build/grokmirror/clone.conf"
process_template "configs/grokmirror/indexed.conf.template" "build/grokmirror/indexed.conf"
process_template "configs/nginx/angie.conf.template" "build/nginx/angie.conf"
process_template "configs/pi-configs/config.template" "build/pi-configs/config"

if [[ "$DRY_RUN" = false ]]; then
	log_info "Configuration generation complete!"
	log_info "Generated files:"
	find build/ -type f | sed 's/^/  /'
	echo ""
	log_info "Ensuring data directories exist..."
	mkdir -p data/all 2>/dev/null || true
	echo ""
	log_info "Next steps:"
	echo "  make run-hosting && make logs-hosting"
	echo "  make run-indexer"
	echo "  make run-mirroring && make logs-mirroring"
	echo " or"
	echo "  $(grep -q podman <<<"${COMPOSE:-podman-compose}" && echo "podman" || echo "docker") compose --profile hosting up -d"
	echo "  $(grep -q podman <<<"${COMPOSE:-podman-compose}" && echo "podman" || echo "docker") compose --profile mirroring up -d"
else
	log_info "Dry run complete. Run without --dry-run to generate files."
fi
