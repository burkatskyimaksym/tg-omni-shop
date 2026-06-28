#!/bin/sh
set -e

echo "========================================"
echo "  TG Omni Shop - WordPress Setup"
echo "========================================"

# Verify PHP mysqli is actually functional
if ! php -r 'mysqli_init();' > /dev/null 2>&1; then
    echo "[ERROR] PHP mysqli extension is missing or non-functional — verify the Docker image."
    exit 1
fi

# Wait for the database to be ready
echo "[INFO] Waiting for database connection..."
until mysqladmin ping -h"db" -P"3306" --silent; do
    echo "[WAIT] MariaDB is not ready yet..."
    sleep 2
done
echo "[OK] Database connection established."

# Ensure WordPress core is present
if [ ! -e /var/www/html/wp-includes/version.php ]; then
    echo "[INFO] Downloading WordPress core..."
    wp core download --allow-root --path=/var/www/html
    echo "[OK] WordPress core downloaded."
fi

# Fix ownership of writable wp-content subdirs only.
# branding/ and dummy-data/ are mounted :ro so chown must skip them.
# themes/ and plugins/ are mounted from host and edited in VS Code —
# DO NOT chown them or the host loses write access.
for dir in uploads mu-plugins upgrade; do
    mkdir -p /var/www/html/wp-content/${dir}
    chown -R www-data:www-data /var/www/html/wp-content/${dir}
done

# ---------------------------------------------------------------------------
# REVERSE-PROXY FIX (runs every boot, not just first run)
# ---------------------------------------------------------------------------
mkdir -p /var/www/html/wp-content/mu-plugins
cat > /var/www/html/wp-content/mu-plugins/reverse-proxy-fix.php << 'PHP'
<?php
/**
 * Must-Use Plugin: Reverse Proxy HTTP Fix
 */
$_SERVER['HTTPS']       = 'off';
$_SERVER['SERVER_PORT'] = '80';

if ( ! defined( 'FORCE_SSL_ADMIN' ) ) {
    define( 'FORCE_SSL_ADMIN', false );
}
PHP
chown www-data:www-data /var/www/html/wp-content/mu-plugins/reverse-proxy-fix.php
echo "[OK] Reverse-proxy fix installed as must-use plugin."

# ---------------------------------------------------------------------------
# BRANDING — runs every boot, re-imports only if file changed
# ---------------------------------------------------------------------------
LOGO_PATH="/var/www/html/wp-content/branding/logo.png"
BANNER_PATH="/var/www/html/wp-content/branding/banner.jpg"

if wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
    if [ -f "${LOGO_PATH}" ]; then
        LOGO_MD5=$(md5sum "${LOGO_PATH}" | cut -d' ' -f1)
        STORED_MD5=$(wp option get logo_md5 --path=/var/www/html --allow-root 2>/dev/null || echo "")

        if [ "${LOGO_MD5}" != "${STORED_MD5}" ]; then
            echo "[INFO] Logo changed, re-importing..."
            LOGO_ID=$(wp media import "${LOGO_PATH}" \
                --title="Site Logo" \
                --porcelain \
                --path=/var/www/html \
                --allow-root)
            wp option update site_logo "${LOGO_ID}" --path=/var/www/html --allow-root
            wp option update custom_logo "${LOGO_ID}" --path=/var/www/html --allow-root
            wp option update logo_md5 "${LOGO_MD5}" --path=/var/www/html --allow-root
            echo "[OK] Logo updated (ID: ${LOGO_ID})"
        else
            echo "[OK] Logo unchanged, skipping."
        fi
    fi

    if [ -f "${BANNER_PATH}" ]; then
        BANNER_MD5=$(md5sum "${BANNER_PATH}" | cut -d' ' -f1)
        STORED_BANNER_MD5=$(wp option get banner_md5 --path=/var/www/html --allow-root 2>/dev/null || echo "")

        if [ "${BANNER_MD5}" != "${STORED_BANNER_MD5}" ]; then
            echo "[INFO] Banner changed, re-importing..."
            BANNER_ID=$(wp media import "${BANNER_PATH}" \
                --title="Store Banner" \
                --porcelain \
                --path=/var/www/html \
                --allow-root)
            wp option update store_banner_id "${BANNER_ID}" --path=/var/www/html --allow-root
            wp option update banner_md5 "${BANNER_MD5}" --path=/var/www/html --allow-root
            echo "[OK] Banner updated (ID: ${BANNER_ID})"
        else
            echo "[OK] Banner unchanged, skipping."
        fi
    fi
fi

# Create wp-config.php from environment variables if not present
if [ ! -e /var/www/html/wp-config.php ]; then
    echo "[INFO] Creating wp-config.php..."
    SITE_URL="${WP_SITE_URL:-http://localhost:8080}"

    wp config create \
        --allow-root \
        --path=/var/www/html \
        --dbhost="${WORDPRESS_DB_HOST}" \
        --dbname="${WORDPRESS_DB_NAME}" \
        --dbuser="${WORDPRESS_DB_USER}" \
        --dbpass="${WORDPRESS_DB_PASSWORD}" \
        --dbprefix="${WORDPRESS_TABLE_PREFIX:-wp_}"

    wp config set WP_HOME    "${SITE_URL}" --allow-root --path=/var/www/html
    wp config set WP_SITEURL "${SITE_URL}" --allow-root --path=/var/www/html
    wp config set FORCE_SSL_ADMIN false --raw --allow-root --path=/var/www/html

    echo "[OK] wp-config.php created."
fi

# ---------------------------------------------------------------------------
# FIRST-RUN SETUP — only runs once when WordPress is not yet installed
# ---------------------------------------------------------------------------
if ! wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
    echo "[INFO] WordPress not initialized — running first-time setup..."

    SITE_URL="${WP_SITE_URL:-http://localhost:8080}"

    wp core install \
        --allow-root \
        --path=/var/www/html \
        --url="${SITE_URL}" \
        --title="${STORE_NAME:-Omni Shop}" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@omnishop.local" \
        --skip-email

    echo "[OK] WordPress core installed."

    # Store name and description
    wp option update blogname "${STORE_NAME:-Omni Shop}" --path=/var/www/html --allow-root
    wp option update blogdescription "${STORE_DESCRIPTION:-Your one-stop store}" --path=/var/www/html --allow-root
    echo "[OK] Store name and description set."

    # Clean up default WordPress content — delete by slug, never by ID
    wp post delete \
        $(wp post list --post_type=post --name=hello-world --field=ID --allow-root --path=/var/www/html 2>/dev/null) \
        --force --allow-root --path=/var/www/html 2>/dev/null || true

    wp post delete \
        $(wp post list --post_type=page --name=sample-page --field=ID --allow-root --path=/var/www/html 2>/dev/null) \
        --force --allow-root --path=/var/www/html 2>/dev/null || true

    wp comment delete 1 --force --allow-root --path=/var/www/html 2>/dev/null || true
    echo "[OK] Default content removed."

    echo "[INFO] Installing WooCommerce..."
    if [ -d /var/www/html/wp-content/plugins/woocommerce ]; then
        echo "[INFO] WooCommerce directory already exists, activating..."
        wp plugin activate woocommerce --path=/var/www/html --allow-root || true
    else
        wp plugin install woocommerce --activate --path=/var/www/html --allow-root
    fi
    echo "[OK] WooCommerce installed and activated."

    echo "[INFO] Installing Kadence theme..."
    if [ -d /var/www/html/wp-content/themes/kadence ]; then
        echo "[INFO] Kadence theme directory already exists, skipping install..."
    else
        wp theme install kadence --path=/var/www/html --allow-root
    fi

    # Activate child theme if present, otherwise activate Kadence directly
    if [ -d /var/www/html/wp-content/themes/kadence-child ]; then
        wp theme activate kadence-child --path=/var/www/html --allow-root
        echo "[OK] Kadence child theme activated."
    else
        wp theme activate kadence --path=/var/www/html --allow-root
        echo "[OK] Kadence theme activated."
    fi

    echo "[INFO] Setting up permalinks (required by WooCommerce REST API)..."
    wp rewrite structure '/%postname%/' --hard --path=/var/www/html --allow-root

    # Write .htaccess manually — WP-CLI cannot regenerate it without AllowOverride All
    cat > /var/www/html/.htaccess << 'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS
    echo "[OK] Permalinks and .htaccess configured."

    # Import branding on first run (md5 check handles subsequent runs)
    if [ -f "${LOGO_PATH}" ]; then
        echo "[INFO] Importing logo..."
        LOGO_MD5=$(md5sum "${LOGO_PATH}" | cut -d' ' -f1)
        LOGO_ID=$(wp media import "${LOGO_PATH}" \
            --title="Site Logo" \
            --porcelain \
            --path=/var/www/html \
            --allow-root)
        wp option update site_logo "${LOGO_ID}" --path=/var/www/html --allow-root
        wp option update custom_logo "${LOGO_ID}" --path=/var/www/html --allow-root
        wp option update logo_md5 "${LOGO_MD5}" --path=/var/www/html --allow-root
        echo "[OK] Logo imported (ID: ${LOGO_ID})"
    fi

    if [ -f "${BANNER_PATH}" ]; then
        echo "[INFO] Importing banner..."
        BANNER_MD5=$(md5sum "${BANNER_PATH}" | cut -d' ' -f1)
        BANNER_ID=$(wp media import "${BANNER_PATH}" \
            --title="Store Banner" \
            --porcelain \
            --path=/var/www/html \
            --allow-root)
        wp option update store_banner_id "${BANNER_ID}" --path=/var/www/html --allow-root
        wp option update banner_md5 "${BANNER_MD5}" --path=/var/www/html --allow-root
        echo "[OK] Banner imported (ID: ${BANNER_ID})"
    fi

# ---------------------------------------------------------------------------
    # WOOCOMMERCE STORE CONFIGURATION
    # ---------------------------------------------------------------------------
    echo "[INFO] Configuring WooCommerce store settings..."

    wp option update woocommerce_default_country "UA:UA-30" --path=/var/www/html --allow-root
    wp option update woocommerce_currency         "UAH"          --path=/var/www/html --allow-root
    wp option update woocommerce_currency_pos     "right_space"  --path=/var/www/html --allow-root
    wp option update woocommerce_price_thousand_sep " "          --path=/var/www/html --allow-root
    wp option update woocommerce_price_decimal_sep  ","          --path=/var/www/html --allow-root
    wp option update woocommerce_onboarding_profile '{"skipped":true,"completed":true}' --format=json --path=/var/www/html --allow-root
    wp option update woocommerce_admin_notices '[]' --format=json --path=/var/www/html --allow-root
    echo "[OK] WooCommerce configured (UA/Kyiv, UAH, wizard skipped)."

    # ---------------------------------------------------------------------------
    # HOMEPAGE — point the front page to the WooCommerce Shop page
    # ---------------------------------------------------------------------------
    echo "[INFO] Configuring homepage..."

    SHOP_PAGE_ID=$(wp post list \
        --post_type=page \
        --pagename=shop \
        --field=ID \
        --allow-root \
        --path=/var/www/html 2>/dev/null | head -1)

    if [ -n "${SHOP_PAGE_ID}" ]; then
        wp option update show_on_front   "page"             --path=/var/www/html --allow-root
        wp option update page_on_front   "${SHOP_PAGE_ID}"  --path=/var/www/html --allow-root
        wp option update woocommerce_shop_page_id "${SHOP_PAGE_ID}" --path=/var/www/html --allow-root
        echo "[OK] Homepage set to Shop page (ID: ${SHOP_PAGE_ID})."
    else
        echo "[WARN] Shop page not found — WooCommerce may not be fully activated yet."
    fi

    # ---------------------------------------------------------------------------
    # SEED PRODUCTS
    # ---------------------------------------------------------------------------
    echo "[INFO] Seeding products..."
    if [ -f /var/www/html/wp-content/dummy-data/seed-products.sh ]; then
        sh /var/www/html/wp-content/dummy-data/seed-products.sh
    else
        echo "[WARN] seed-products.sh not found — no products created."
        echo "[WARN] Add wp/dummy-data/seed-products.sh to seed your catalog."
    fi

    echo ""
    echo "========================================"
    echo "  Setup complete!"
    echo "    WordPress:  http://localhost:8080"
    echo "    Admin:      http://localhost:8080/wp-admin"
    echo "    User:       admin"
    echo "    Password:   admin"
    echo "========================================"
else
    echo "[OK] WordPress is already installed — skipping first-run setup."
fi

chown -R www-data:www-data /var/www/html/wp-content/uploads

echo "[INFO] Starting Apache..."
exec apache2-foreground