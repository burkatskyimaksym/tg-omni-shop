#!/bin/sh
# =============================================================================
# seed-products.sh — Entry point called by setup-wp.sh on first run.
#
# This script is intentionally thin. All product logic lives in:
#   seed-products.py  — reads products.json and calls WP-CLI
#   products.json     — your product catalog (edit this to add products)
#
# To add a new product: edit products.json. That's it.
# =============================================================================

DUMMY_DATA="/var/www/html/wp-content/dummy-data"

if [ ! -f "${DUMMY_DATA}/products.json" ]; then
    echo "[SEED][ERROR] products.json not found at ${DUMMY_DATA}/products.json"
    exit 1
fi

echo "[SEED] Running data-driven product seeder..."
python3 "${DUMMY_DATA}/seed-products.py"