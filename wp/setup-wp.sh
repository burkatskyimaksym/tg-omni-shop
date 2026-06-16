#!/bin/sh
set -e

echo "========================================"
echo "  TG Omni Shop - WordPress Setup"
echo "========================================"

# Wait for the database to be ready
echo "[INFO] Waiting for database connection..."
until mysqladmin ping -h"db" -P"3306" --silent; do
    echo "[WAIT] MariaDB is not ready yet..."
    sleep 2
done
echo "[OK] Database connection established."

# Only run wp-cli setup if not already installed
if ! wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
    echo "[INFO] WordPress not initialized — running first-time setup..."

    wp core install \
        --allow-root \
        --path=/var/www/html \
        --url="http://localhost:8080" \
        --title="Omni Shop" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@omnishop.local" \
        --skip-email

    echo "[OK] WordPress core installed."

    echo "[INFO] Installing WooCommerce..."
    wp plugin install woocommerce --activate --path=/var/www/html --allow-root
    echo "[OK] WooCommerce installed and activated."

    echo "[INFO] Setting up permalinks (required by WooCommerce REST API)..."
    wp rewrite structure '/%postname%/' --hard --path=/var/www/html --allow-root
    echo "[OK] Permalinks configured."

    # Create a demo product for quick testing
    echo "[INFO] Creating demo product..."
    wp post create \
        --allow-root \
        --post_type=product \
        --post_title='Demo Product' \
        --post_content='This is a sample product for testing.' \
        --post_status=publish \
        --meta_input='{"_price":"199.99","_regular_price":"199.99","_stock_status":"instock"}' \
        --path=/var/www/html \
        --porcelain > /dev/null 2>&1 || true
    echo "[OK] Demo product created."

    echo ""
    echo "========================================"
    echo "  Setup complete!"
    echo "    WordPress:  http://localhost:8080"
    echo "    Admin:      http://localhost:8080/wp-admin"
    echo "    User:       admin"
    echo "    Password:   admin"
    echo "========================================"
else
    echo "[OK] WordPress is already installed — skipping setup."
fi

echo "[INFO] Starting Apache..."
exec apache2-foreground
