# TG Omni Shop — WordPress & WooCommerce Setup Guide

Welcome! This guide walks you through getting your local development environment running.

---

## Prerequisites

- **Docker** (24.0+)
- **Docker Compose** (v2.x, now part of `docker compose` command)
- A terminal (PowerShell, Terminal, iTerm, or GNOME Terminal)
- Make (optional, but the `Makefile` makes things easier)

---

## Step 1: Start the stack

Navigate to the project root and run:

```bash
docker compose up -d --build
```

Or, if you have `make` installed:

```bash
make up
```

Docker will:
1. Pull the MariaDB 10.11 image.
2. Build the custom WordPress image (with WP-CLI and PHP overrides).
3. Build the custom Nginx image.
4. Run the `setup-wp.sh` script inside the WordPress container.
5. Start phpMyAdmin.

> **Note:** The first build can take **3–5 minutes** depending on your connection.

---

## Step 2: Wait for the setup script

The WordPress container runs a setup script on first boot that:
- Installs WordPress core.
- Installs and activates the **WooCommerce** plugin.
- Configures **permalinks** (required for the WooCommerce REST API).
- Creates a **demo product** for quick testing.

Watch the logs to see when it's done:

```bash
docker compose logs -f wordpress
```

You will see a success message like:

```
========================================
  Setup complete!
    WordPress:  http://localhost:8080
    Admin:      http://localhost:8080/wp-admin
    User:       admin
    Password:   admin
========================================
```

At that point, everything is ready.

---

## Step 3: Access your services

| Service | URL | Credentials |
|--------|-----|---------------|
| **WordPress** | http://localhost:8080 | — |
| **WP Admin** | http://localhost:8080/wp-admin | admin / admin |
| **phpMyAdmin** | http://localhost:8081 | wp_user / (from .env) |
| **Database** | localhost:3306 | From `.env` file |

---

## Step 4: (Recommended) Change the admin password

The default credentials (`admin` / `admin`) are only for local development.

1. Go to **Dashboard → Users→ All Users**.
2. Click on **admin**.
3. Scroll down to **New Password** and generate a strong one.
4. Save changes.

---

## Step 5: Where to put your custom work

| What | Where |
|------|-------|
| Custom themes | [`wp/themes/`](../wp/themes/) |
| Custom plugins | [`wp/plugins/`](../wp/plugins/) |
| PHP overrides | [`wp/php-ini-overrides/`](../wp/php-ini-overrides/) |
| Nginx config | [`nginx/conf.d/`](../nginx/conf.d/) |

These directories are mounted into the containers, so changes take effect immediately.

---

## Useful Commands

Use the `Makefile` shortcuts for easy access:

```bash
make up          # Start everything
make down        # Stop and remove all containers and volumes
make stop        # Stop without removing volumes
make logs        # Tail all logs
make wp-logs     # Tail WordPress logs
make db-logs     # Tail database logs
make wp-shell    # Open a shell inside the WordPress container
make db-shell    # Open MariaDB CLI
make pma         # Open phpMyAdmin in browser
make status      # Show container status
make rebuild     # Clean rebuild (use after Dockerfile changes)
```

Or with raw `docker compose`:

```bash
docker compose up -d          # Start
docker compose down           # Stop
docker compose down -v        # Stop and remove volumes
docker compose logs -f        # Tail logs
docker compose ps             # Container status
```

---

## Troubleshooting

### "Connection refused" when accessing localhost:8080
- Make sure Docker is running.
- Check `docker compose ps` to see if the containers are up.
- Check the WordPress logs for setup errors: `docker compose logs -f wordpress`.

### Port already in use
If you get something like:
```
Bind for 0.0.0.0:8080 failed: port is already allocated
```

Either stop the service using that port, or edit the `ports:` section in `docker-compose.yml` to use a different port (e.g., `8090:80`).

### Import / export a database dump

```bash
# Export
docker compose exec db mysqldump -u wp_user -p omni_shop > backup.sql

# Import
docker compose exec -T db mysql -u wp_user -p omni_shop < backup.sql
```

---

## Next Steps

Once your environment is running, you're ready to:
1. Set up WooCommerce with your store details (currency, taxes, shipping, payments).
2. Generate WooCommerce **REST API keys** (to connect the FastAPI backend).
3. Configure **webhooks** for real-time sync with the Telegram Bot.

These steps are covered in the FastAPI and Telegram Bot setup guides (coming next).