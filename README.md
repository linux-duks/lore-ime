# Public-Inbox-Stack

Scripts and containers for mirroring and hosting [public-inbox](https://public-inbox.org/) mailing list archivers. Batteries included, all in containers.

Supports **mirroring only**, **hosting only**, or **both**.

## Complete Architecture

```
Upstream (public-inbox.example.org, etc.)
        │
        │  grok-pull (git clone/fetch)
        ▼
   ┌───────────┐
   │grokmirror │  profiles: mirroring
   └────┬──────┘
        │  /data/ (git repos)
        ▼
   ┌─────────┐     ┌───────────┐
   │ indexer │ or  │ grok-pi-  │  profiles: manual / indexed hooks
   └────┬────┘     └─────┬─────┘
        │                │
        ▼                ▼
   ┌─────────────────────────┐
   │  public-inbox (httpd,   │  profiles: hosting
   │  nntpd, watch, extindex)│
   └────────────┬────────────┘
                │  port 8080
                ▼
        ┌────────────────┐
        │  Angie/nginx   │  profiles: hosting
        │  (proxy+SSL)   │
        └────────────────┘
                │
                ▼  http://your-host:8088
```

## Requirements

- **podman** + **podman-compose** >= 1.1.0
  _or_
- **docker** + **docker-compose** >= 1.28.0 (v2 plugin preferred)

Runtime is auto-detected. See [Container Runtime](#container-runtime) for details.

## Quick Start

```bash
# 1. Create your environment configuration
cp example.env .env

# 2. Edit .env with your values (see Configuration section)
vim .env

# 3. Generate configuration files from templates
make setup

# 4. Start mirroring (clones repos from upstream)
make run-mirroring

# 5. Index the cloned repos
make run-indexer

# 6. Start hosting (public-inbox + nginx)
make run-hosting
```

Visit `http://localhost:8088` (or your configured port) to see your instance.

Or run everything in one command:

```bash
make run-all
```

## Configuration

### How Configuration Works

All configuration flows from a single `.env` file:

1. **Copy** `example.env` to `.env` and edit your values
2. **Run** `make setup` — this executes `scripts/setup.sh` which:
   - Reads `.env` and validates required variables
   - Processes templates in `config_template/` using two mechanisms:
     - **Conditional blocks**: `{{#VAR}}...{{/VAR}}` — kept if `VAR=true`, removed entirely if `VAR=false`
     - **Variable substitution**: `{{VAR}}` — replaced with the value from `.env`
   - Writes rendered configs to `configs/` (git-ignored, regenerated each time)
3. **Mount** — `compose.yaml` mounts `configs/` into the containers at runtime

```
.env  ──setup.sh──►  config_template/  ──►  configs/
(user edit)        (source templates)     (rendered output, mounted into containers)
```

### Environment Variables

Edit `.env` to configure your instance. All variables are documented below:

#### Mirroring

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `MIRROR_UPSTREAM_HOST` | Grokmirror source URL (where you mirror **from**) | _(required)_ | `https://public-inbox.example.org` |
| `GROKMIRROR_MODE` | Mirroring mode: `clone` (just git) or `indexed` (git + auto-indexing via hooks) | `clone` | `clone` |

#### Hosting

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `SERVE_HOST` | Domain where your instance will be accessible | `localhost` | `lists.example.com` |
| `SERVE_HTTP_PORT` | HTTP port exposed on the host | `80` | `8088` |
| `SERVE_HTTPS_PORT` | HTTPS port exposed on the host | `443` | `8443` |
| `SERVE_NNTP_PORT` | NNTP port exposed on the host | `119` | `1119` |
| `PI_HTTP_ENABLE` | Enable the public-inbox HTTP daemon | `true` | `true` |
| `PI_NNTP_ENABLE` | Enable the public-inbox NNTP daemon | `false` | `true` |
| `PI_INDEXING_ENABLE` | Run extindex on container startup | `false` | `true` |

#### IMAP Watch (for hosting your own lists)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `PI_IMAP_ENABLED` | Enable IMAP watcher to ingest mail from an IMAP mailbox | `false` | `true` |
| `PI_IMAP_LIST_NAME` | Inbox name/identifier | `list.name` | `my-list` |
| `PI_IMAP_LIST_ADDRESS` | Email address for the list | `name@lists.domain.tld` | `discuss@lists.example.com` |
| `PI_IMAP_AUTH_URL` | IMAP connection string with credentials | _(none)_ | `imaps://user:pass@imap.server.tld:993/INBOX` |

#### Spam Checking

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `SPAMCHECK_ENABLED` | Enable SpamAssassin spam checking via `spamc` | `false` | `true` |

#### SSL/TLS

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ACME_ENABLED` | Enable automatic SSL via Let's Encrypt (ACME) | `false` | `true` |
| `ACME_EMAIL` | Email for ACME certificate registration | `admin@example.com` | `admin@example.com` |

### Understanding MIRROR_UPSTREAM_HOST vs SERVE_HOST

- **`MIRROR_UPSTREAM_HOST`**: The source you're cloning **from**. This is the grokmirror manifest host (e.g., `https://public-inbox.example.org`). Grokmirror uses this to fetch the manifest and git repos.
- **`SERVE_HOST`**: The domain where **your** instance will be accessible. Used in nginx `server_name`, public-inbox URLs, and the extindex configuration.

### Grokmirror Modes

#### Clone Mode (`GROKMIRROR_MODE=clone`)

Pure git cloning/fetching. No indexing happens during mirroring. You must run indexing separately with `make run-indexer`.

**Use when:** You want full control over when indexing happens, or you're only interested in the git repos.

#### Indexed Mode (`GROKMIRROR_MODE=indexed`)

Clones repos AND automatically indexes them via `grok-pi-indexer` hooks:

- **`post_update_hook`** — runs after each pull to update the index
- **`post_clone_complete_hook`** — runs after cloning a new repo to initialize it
- **`post_work_complete_hook`** — runs after all work is done to update the extindex

**Use when:** You want a set-and-forget mirror that stays indexed automatically.

### Conditional Configuration

The template system supports conditional blocks. Setting a variable to `true` in `.env` enables the corresponding feature:

| Variable | What it enables |
|----------|-----------------|
| `ACME_ENABLED=true` | HTTPS server block with Let's Encrypt certificates in nginx |
| `PI_IMAP_ENABLED=true` | IMAP inbox definition in public-inbox config |
| `SPAMCHECK_ENABLED=true` | SpamAssassin integration via `spamc` in public-inbox-watch |

## Makefile Targets

### Setup

| Target | Description |
|--------|-------------|
| `make setup` | Generate configs from templates (reads `.env`, writes to `configs/`) |
| `make setup-dry-run` | Preview what would be generated without writing files |

### Running Services

| Target | Description |
|--------|-------------|
| `make run-hosting` | Start public-inbox + nginx (hosting profile) |
| `make watch-hosting` | Same as `run-hosting` but in foreground (see logs in terminal) |
| `make run-mirroring` | Start grokmirror daemon (mirroring profile, detached, pulls every hour) |
| `make pull-mirror` | Run grokmirror once, pull and exit (mirroring profile) |
| `make run-mirroring-indexed` | Start grokmirror in indexed mode (auto-indexing enabled) |
| `make run-indexer` | One-shot manual indexing of cloned repos (manual profile) |
| `make purge-indexing` | Purge public-inbox indexing data (preserves grokmirror git clones) |
| `make run-all` | Full pipeline: `setup` → `run-mirroring` → `run-hosting` |

### Utilities

| Target | Description |
|--------|-------------|
| `make logs` | Follow logs for all services |
| `make logs-hosting` | Follow logs for hosting services only |
| `make logs-mirroring` | Follow logs for mirroring services only |
| `make stop` | Stop all services |
| `make stop-hosting` | Stop hosting services only |
| `make stop-mirroring` | Stop mirroring services only |
| `make clean` | Remove generated `configs/` directory |
| `make help` | Show all available targets |

## Container Runtime

The project auto-detects your container runtime with this priority:

1. **podman** + **podman-compose**
2. **docker compose** (v2 plugin)
3. **docker-compose** (v1 standalone)

Override the detected runtime:

```bash
# Use nerdctl
make run-hosting CONTAINER=nerdctl COMPOSE="nerdctl compose"

# Force docker-compose v1
make run-hosting COMPOSE=docker-compose
```

When running with `sudo`, the real user/group ID is preserved so files in `data/` are owned by your user, not root.

## Compose Profiles

| Profile | Services | Description |
|---------|----------|-------------|
| `hosting` | `public-inbox`, `nginx` | Serves the web interface, NNTP, and HTTP |
| `mirroring` | `grokmirror` | Clones and fetches repos from upstream |
| `manual` | `indexer` | One-shot indexing service (run with `run --rm`) |

## Workflows

### Clone Mode (Manual Indexing)

```bash
make setup
make run-mirroring        # starts daemon, clones/fetches repos every hour in background
# or
make pull-mirror          # one-shot: clones/fetches repos once and exits
make run-indexer          # initializes and indexes all cloned repos
make run-hosting          # serves the indexed repos
```

Re-run `make pull-mirror` followed by `make run-indexer` periodically to fetch new messages and update the index.

### Indexed Mode (Automatic Indexing)

```bash
make setup
make run-mirroring-indexed  # clones AND indexes automatically
make run-hosting            # serves the indexed repos
```

No manual indexing needed — hooks handle it after every pull.

### Hosting Only (No Mirroring)

If you have your own mailing lists (not mirrored):

1. Add inbox definitions to `config_template/pi-configs/config.template`
2. Place your git repos in `data/<inbox-name>/git/`
3. `make setup && make run-hosting`

### Adding Your Own Mailing List via IMAP

1. Set `PI_IMAP_ENABLED=true` in `.env`
2. Configure `PI_IMAP_LIST_NAME`, `PI_IMAP_LIST_ADDRESS`, and `PI_IMAP_AUTH_URL`
3. `make setup && make run-hosting`

The `public-inbox-watch` daemon will poll the IMAP mailbox and ingest new messages.

## Services Detail

### grokmirror

Runs `grok-pull` to clone/fetch git repos from an upstream grokmirror manifest. Configuration is generated from `config_template/grokmirror/clone.conf.template` or `indexed.conf.template` depending on `GROKMIRROR_MODE`.

### indexer

Runs `scripts/index-cloned-repos.sh` to scan `/data/` for cloned v2 inboxes, initialize them with `public-inbox-init -V2`, index with `public-inbox-index`, and update the external index with `public-inbox-extindex --all`.

Features:

- Extracts mailing list addresses from git `refs/meta/origins:i` (no HTTP needed)
- Falls back to HTTP config fetch from upstream if git origins are unavailable
- HTTP rate limiting (15s minimum between requests) to avoid bot detection
- Graceful interrupt handling (SIGINT/SIGTERM)
- Dry-run mode (`-n`) for previewing operations

### public-inbox

Runs `scripts/start-public-inbox.sh` which starts the appropriate daemons based on `.env` flags:

- `public-inbox-httpd` — HTTP/PSGI web interface
- `public-inbox-nntpd` — NNTP server
- `public-inbox-watch` — IMAP watcher (when `PI_IMAP_ENABLED=true`)
- `spamd` — SpamAssassin daemon (when `SPAMCHECK_ENABLED=true`)
- `public-inbox-extindex` — External indexing (when `PI_INDEXING_ENABLE=true`)

If the data directory is empty on startup, `reinit-from-config.sh` runs automatically to initialize inboxes from the public-inbox config file.

### nginx (Angie)

[Angie](https://angie.software/) — an nginx fork with built-in ACME support. Proxies HTTP/HTTPS to `public-inbox:8080` and streams NNTP (TCP) to `public-inbox:119`. Also serves `theme.css` as a static file.

## SSL/TLS Configuration

To enable automatic SSL with Let's Encrypt:

1. Set `ACME_ENABLED=true` and `ACME_EMAIL=your@email.com` in `.env`
2. Ensure `SERVE_HOST` is a real domain that resolves to your server
3. Run `make setup` to regenerate nginx config with ACME blocks
4. Start hosting: `make run-hosting`

Angie will automatically obtain and renew certificates. The `acme/` directory on the host stores certificate state.

## Directory Structure

```
.
├── example.env                     # Template for .env (copy and edit)
├── .env                            # Your environment config (git-ignored, created by you)
├── compose.yaml                    # Docker/podman compose definition
├── Containerfile                   # Shared container image build
├── Makefile                        # Build/run targets
├── containers.mk                   # Container runtime auto-detection
├── config_template/                # Source templates (tracked in git)
│   ├── grokmirror/
│   │   ├── clone.conf.template     # Grokmirror config for clone mode
│   │   └── indexed.conf.template   # Grokmirror config with indexing hooks
│   ├── nginx/
│   │   └── angie.conf.template     # Angie/nginx web server config
│   └── pi-configs/
│       ├── config.template         # Public-inbox config template
│       ├── config.example          # Example with IMAP + spamcheck
│       └── 216dark.css             # Dark theme for web UI
├── configs/                        # Generated configs (git-ignored, created by setup.sh)
│   ├── grokmirror/clone.conf
│   ├── grokmirror/indexed.conf
│   ├── nginx/angie.conf
│   └── pi-configs/config
├── data/                           # Shared data directory (git-ignored)
│   ├── <inbox-name>/               # Per-inbox data (git repos, sqlite, xapian)
│   └── all/                        # External index (extindex)
├── logs/                           # Public-inbox logs (git-ignored)
├── acme/                           # Let's Encrypt certificates (git-ignored)
├── scripts/
│   ├── setup.sh                    # Config generation from templates
│   ├── index-cloned-repos.sh       # Manual indexer for cloned repos
│   ├── start-public-inbox.sh       # Container entrypoint for public-inbox
│   ├── reinit-from-config.sh       # Reinitialize inboxes from config file
│   └── copy_config_files.py        # Legacy: fetch remote configs via curl
├── grokmirror/                     # Grokmirror source (git submodule)
└── public-inbox/                   # Public-inbox source (git submodule)
```

## Troubleshooting

### Config generation fails

```
[ERROR] .env not found
```

Run `cp example.env .env` first, then edit `.env` with your values.

### No v2 inboxes found

The indexer scans `/data/` for directories with `git/N.git` structure. If grokmirror hasn't finished cloning yet, run `make run-mirroring` first and wait for it to complete.

### Indexing is slow or hangs

Large inboxes (10,000+ messages) may trigger a hint about `--split-shards`. This flag is **not recommended** in containerized environments — it requires 2-3x temporary disk space and is prone to Xapian database corruption on interruption. The script does not use it by default.

### Container permission errors

When using `sudo make`, the real user ID should be preserved. If you see permission errors in `data/`, check ownership:

```bash
ls -la data/
```

Fix with: `sudo chown -R $(id -u):$(id -g) data/`

### Reinitializing from scratch

If your data directory is corrupted or you want to start fresh:

```bash
make stop
rm -rf data/*
make setup          # regenerates configs
make run-hosting    # auto-runs reinit-from-config.sh on empty data dir
make run-indexer    # re-indexes all repos
```

### Purging Indexing Data

To remove public-inbox indexing artifacts (Xapian, msgmap, over.sqlite3, all.git) while preserving grokmirror git clones:

```bash
make purge-indexing
# or with dry-run to preview:
./scripts/purge-indexing.sh -d /data -n
```

Use this when you want to re-index from scratch without re-cloning all repos from upstream. After purging, run `make run-indexer` to rebuild the indexes.

### Viewing generated configs

Before applying, preview what `make setup` will generate:

```bash
make setup-dry-run
```

Or inspect the templates directly in `config_template/` to understand what each variable controls.
