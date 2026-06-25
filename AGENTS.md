# AGENTS.md — TG Omni Shop

> Compact, high-signal guidance for OpenCode agents. If a fact is obvious from `docker-compose.yml` or can be inferred from standard tooling, it is omitted.

---

## Architecture & Entrypoints

This is a **Docker Compose** project producing an e-commerce website (WordPress + WooCommerce). The containers are the only supported runtime environment.

| Service | Image / Build | Purpose | Exposed at |
|--------|----------------|---------|------------|
| `db` | `mariadb:10.11` | WordPress database | `localhost:3306` |
| `wordpress` | Build from `./wp/Dockerfile` | PHP 8.3 + Apache + WP-CLI | Via `nginx`Nx Only |
| `nginx` | `nginx:alpine` | Reverse proxy + static file cache | `localhost:8080` (HTTP), `localhost:8443` (HTTPS) |
| `phpmyadmin` | `phpmyadmin/phpmyadmin` | DB admin UI | `localhost:8081` |

### Simplified runtime flow
```
Browser → nginx:8080 → wordpress:80 → db:3306
```

- The WordPress container runs a **custom setup script** (`setup-wp.sh`) which handles first-run setup (installs core, WooCommerce, sets up permalinks, imports branding from `./wp/branding/`) and re-applies config on every boot.
- **Do not run `wp core install` or similar setup commands manually** inside the container; `setup-wp.sh` is idempotent for config but creates clean first-run state only when WordPress is not yet installed.

---

## Developer Commands (via `Makefile`)

All local development is managed through `make` commands. Do not guess `docker compose` arguments; use the shortcuts.

```bash
# Start the entire stack (builds images if needed)
make up

# Graceful stop (keeps volumes and state)
make stop

# DESTRUCTIVE stop (removes volumes, resets database + files)
make down

# View real-time logs
make logs

# Shell access to containers
make wp-shell   # WordPress container (root, but shell drops to www-data when running apache)
make db-shell   # MariaDB container

# Open phpMyAdmin in browser
make pma

# Check container status
make status

# Rebuild from scratch (kills containers, purges Docker cache, rebuilds, restarts)
make rebuild
```

### Database: Admin Access
- **URL:** `http://localhost:8081` (phpMyAdmin, auto-login via `.env` credentials)
- **DB Host:** `db` (from the `wordpress` container)
- **DB Name/User/Pass:** Defined in `.env` (`MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`)
- **CLI:** `make db-cli` (prompts for password, uses `wp_user`)

### WordPress: Admin Access
- **URL:** `http://localhost:8080/wp-admin`
- **User:** `admin`
- **Password:** `admin`

---

## Environment & Secrets

All configurable values live in the `.env` file (copied from `.env.example`).

**Critical `.env` variables:**
```ini
STORE_NAME="Omni Shop"
STORE_DESCRIPTION="Your one-stop store"
WORDPRESS_DEBUG=true              # Set to 'false' in production
MARIADB_ROOT_PASSWORD=<strong_secret>
MARIADB_DATABASE=omni_shop
MARIADB_USER=wp_user
MARIADB_PASSWORD=<strong_secret>
```

- **Never commit `.env`.** It is listed in `.gitignore`.
- The `.env.example` file is committed as a template. If you add new required env vars, update `.env.example` as well.

---

## Important Code Boundaries

### What is version-controlled

| Path | Status | Git Rule |
|------|--------|----------|
| `./wp/themes/kadence-child/` | **Version controlled** | `!wp/themes/kadence-child` in `.gitignore` |
| `./wp/plugins/` | **Ignored** (except `.gitkeep`) | `wp/plugins/*` ignored; auto-installed by WP-CLI on first run |
| `./wp/themes/` | **Ignored** (except `kadence-child` and `.gitkeep`) | Core themes auto-downloaded; only custom child theme is tracked |
| `./wp/branding/` | **Version controlled** | Logo (`logo.png`) and banner (`banner.jpg`) are auto-imported into WordPress media library by `setup-wp.sh` every boot via MD5 checksum comparison. If MD5 changes, `wp media import` is re-run. |

### WordPress setup script behavior (`wp/setup-wp.sh`)

The `setup-wp.sh` script is the single source of truth for bootstrapping WordPress. Key behaviors an agent must not fight:

1. **First-run (when WP is not installed):**
   - Downloads WordPress core.
   - Runs `wp core install` with hardcoded admin `admin`/`admin`.
   - Installs & activates `woocommerce` plugin automatically.
   - Installs `kadence` theme; if `kadence-child` directory exists, activates the child theme instead.
   - Runs `wp rewrite structure '/%postname%/' --hard` and manually writes `.htaccess` (required for WooCommerce REST API URLs to work correctly).
   - Removes default posts/pages/comments.
   - Imports `logo.png` and `banner.jpg` from `./wp/branding/` into the WP media library.
   - Runs `./wp/dummy-data/seed-products.sh` if it exists; otherwise creates one demo product.

2. **Every boot (idempotent):**
   - Re-creates the reverse-proxy must-use plugin (`mu-plugins/reverse-proxy-fix.php`) which prevents infinite redirect loops between Nginx and Apache.
   - Compares MD5 hashes of `logo.png` and `banner.jpg` in `./wp/branding/` against stored values. If changed, re-imports them into the media library.

**Agent tip:** If WordPress appears "reset" or missing data, ensure:
- The `wp_data` Docker volume was not accidentally removed (`make down` does this).
- You are not trying to mount a new `wp_data` volume without migrating the old one.
- You wait for the `db` healthcheck to pass before `wordpress` starts; `depends_on` with `condition: service_healthy` handles this.

---

## Nginx & Reverse Proxy

`./nginx/conf.d/default.conf` handles all incoming traffic and proxies to the `wordpress` container.

**Known gotchas:**
- `X-Forwarded-Port` is explicitly set to `$server_port` in Nginx. Without this, WordPress compares `siteurl` (port `8080`) to the `Host` header (port `80`) and causes an **infinite redirect loop**.
- `setup-wp.sh` permanently sets `$_SERVER['HTTPS'] = 'off'` and `$_SERVER['SERVER_PORT'] = '80'` via a Must-Use Plugin. Do not attempt to force SSL/HTTPS inside the WordPress container; offloading to Nginx is the intended design.
- Max upload size is `64M` (set in `nginx/conf.d/default.conf` and synced in `wp/php-ini-overrides/php.ini`).

---

## Theme Development

The active theme is **`kadence-child`**.

- **Location:** `./wp/themes/kadence-child/`
- **Parent Theme:** `kadence` (auto-downloaded by `setup-wp.sh` on first run)
- **Key files:**
  - `style.css` — Theme metadata and custom CSS
  - `functions.php` — Enqueues parent and child styles, uses `filemtime()` for cache-busting

**Do not edit the parent theme** (it lives inside the Docker volume and is untracked). All customizations go into `kadence-child`.

---

## Testing / Verification

There is no automated test suite. Verify changes manually via:

1. `make up` → wait for all containers healthy (`make status`)
2. Visit `http://localhost:8080/wp-admin` (admin/admin)
3. Verify WooCommerce products, theme appearance, and any plugin functionality.

---

## AI / Telegram Bot (Planned)

The project roadmap includes a Python-based AI Telegram bot layer (FastAPI + aiogram) with pgvector and OpenRouter integrations. **As of the current codebase, none of these backend services or Python code exist in the repository.** Do not create them unless explicitly asked.

---

## Summary of "Do Not"

| Do Not... | Because... |
|-----------|-----------|
| Run `wp core install` or `wp db reset` manually | `setup-wp.sh` handles this idempotently |
| Modify parent `kadence` theme files | They are auto-downloaded and live in an untracked volume |
| Try to enable SSL/HTTPS inside the WordPress container | Nginx offloads this; the `reverse-proxy-fix` plugin prevents loops |
| `chown -R www-data` on `./wp/themes/` or `./wp/plugins/` | They are bind-mounted from the host; this would break host write access |
| Use `docker compose up` directly without `--build` | `make up` includes `--build`, ensuring `Dockerfile` changes are picked up |
