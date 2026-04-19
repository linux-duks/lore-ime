# public-inbox + grokmirror mirroring and hosting setup

Mirror public mailing lists from an upstream source and host them with public-inbox.

## Requirements

`podman + podman-compose v1.1.0
or
docker + docker-compose 1.28.0`

## Quick Start

```bash
# 1. Create your environment configuration
cp .env.example .env

# 2. Edit .env with your values (see Configuration section below)
vim/nano .env

# 3. Generate configuration files
make setup

# 4. Start hosting (public-inbox + nginx)
make run-hosting

# 5. Start mirroring (grokmirror)
make run-mirroring
```

Visit `http://localhost:8088` to see your public inbox instance.

## Configuration

Edit `.env` to configure your instance:

| Variable | Description | Example |
|----------|-------------|---------|
| `MIRROR_UPSTREAM_HOST` | Grokmirror source (where you mirror **FROM**) | `lore.kernel.org` |
| `SERVE_HOST` | Public-inbox serving URL (where you serve **TO**) | `lore.example.com` |
| `ACME_ENABLED` | Enable ACME/SSL with Let's Encrypt | `false` |
| `ACME_EMAIL` | Email for ACME certificate registration | `admin@example.com` |

### Understanding MIRROR_UPSTREAM_HOST vs SERVE_HOST

- **`MIRROR_UPSTREAM_HOST`**: The source you're cloning from. This is the grokmirror manifest host (e.g., `lore.kernel.org`, `lore.rcpassos.me`). Grokmirror uses this to fetch repos and manifests.
  
- **`SERVE_HOST`**: The URL where your instance will be accessible. This is used in nginx server_name, public-inbox URLs, and the extindex configuration.

## Makefile Targets

### Setup

| Target | Description |
|--------|-------------|
| `make setup` | Generate configs from templates |
| `make setup-dry-run` | Preview what would be generated |

### Running Services

| Target | Description |
|--------|-------------|
| `make run-hosting` | Start public-inbox + nginx |
| `make run-mirroring` | Start grokmirror in clone mode |
| `make run-mirroring-indexed` | Start grokmirror with indexing hooks |
| `make run-indexer` | Run manual indexing of cloned repos |
| `make run-all` | Setup, mirror, and host everything |

### Utilities

| Target | Description |
|--------|-------------|
| `make logs` | Show logs for all services |
| `make logs-hosting` | Show hosting logs |
| `make logs-mirroring` | Show mirroring logs |
| `make stop` | Stop all services |
| `make clean` | Remove generated build files |
| `make help` | Show all available targets |

## Container Runtime Configuration

The project supports multiple container runtimes with automatic detection:

**Priority:** podman > docker compose (v2) > docker-compose (v1)

**Override the detected runtime:**

```bash
# Use nerdctl
make run-hosting CONTAINER=nerdctl COMPOSE="nerdctl compose"

# Force docker-compose (v1)
make run-hosting COMPOSE=docker-compose
```

See [`containers.mk`](containers.mk) for the detection logic.

## Profiles

The compose file uses three profiles:

| Profile | Services | Description |
|---------|----------|-------------|
| `hosting` | nginx, public-inbox | Serves the web interface, NNTP, HTTP |
| `mirroring` | grokmirror | Clones repos from upstream |
| `manual` | indexer | One-shot indexing service (run with `run --rm`) |

## ACME/SSL Configuration

To enable automatic SSL with Let's Encrypt:

1. Set `ACME_ENABLED=true` and `ACME_EMAIL=your@email.com` in `.env`
2. Run `make setup` to regenerate configs
3. Restart nginx: `make stop-hosting && make run-hosting`

The nginx config will automatically include ACME challenge endpoints and SSL configuration when enabled.

## Workflow

### Clone Mode (Default)

1. `make run-mirroring` - clones repos from upstream
2. `make run-indexer` - initializes and indexes cloned repos
3. `make run-hosting` - serves the indexed repos

### Indexed Mode (Automatic Indexing)

1. `make run-mirroring-indexed` - clones AND indexes repos automatically
2. `make run-hosting` - serves the indexed repos

### Adding Your Own Mailing List

1. Add inbox configuration to `configs/pi-configs/config.template`
2. Run `make setup` to regenerate
3. Restart hosting: `make stop-hosting && make run-hosting`

## Directory Structure

```
.
├── .env.example          # Template for environment variables
├── compose.yaml          # Docker compose configuration
├── Containerfile         # Container build definition
├── Makefile              # Build/run targets
├── containers.mk         # Container runtime detection
├── configs/              # Template files (tracked in git)
│   ├── grokmirror/       # Grokmirror config templates
│   ├── nginx/            # Nginx config template
│   └── pi-configs/       # Public-inbox config template
├── build/                # Generated configs (git-ignored)
├── data/                 # Shared data directory (git-ignored)
└── scripts/              # Helper scripts
```
