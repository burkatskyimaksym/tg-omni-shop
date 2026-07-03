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

# ---------------------------------------------------------------------------
# WAYFORPAY GATEWAY (block-checkout compatible) — runs every boot
# ---------------------------------------------------------------------------
# Deliberately placed AFTER the first-run setup block above, not gated on
# `wp core is-installed` on its own. On a fresh container, WordPress and
# WooCommerce don't exist until the first-run block above creates them
# *during this same script execution* — so checking is-installed earlier
# in the script would see "false" and skip this whole section on exactly
# the run where it's needed most. By this point WordPress is guaranteed
# to exist whether this was a first run or a subsequent boot.
#
# The official wayforpay/Word-Press-Woocommerce repo has no block-checkout
# support on master (see open PR #40 — "Added support block design from
# Woocoomers v6.9.0", unmerged as of writing). We pull that PR branch
# directly so the gateway actually shows up under WooCommerce Blocks
# checkout. If PR #40 gets merged upstream, switch WFP_PR_REF below to
# "master" and drop the pull/40/head fetch.
echo "[INFO] Installing WayForPay payment gateway..."

WFP_PLUGIN_DIR="/var/www/html/wp-content/plugins/wc-wayforpay"
WFP_PR_REF="pull/40/head"

if [ -d "${WFP_PLUGIN_DIR}" ]; then
    echo "[INFO] WayForPay plugin directory already exists, skipping clone..."
else
    git clone --quiet https://github.com/wayforpay/Word-Press-Woocommerce.git "${WFP_PLUGIN_DIR}"
    git -C "${WFP_PLUGIN_DIR}" fetch --quiet origin "${WFP_PR_REF}:block-support"
    git -C "${WFP_PLUGIN_DIR}" checkout --quiet block-support

    # ./wp/plugins is a host bind mount (see docker-compose.yml). The
    # clone above runs as root, which would leave root-owned files on
    # the host and break VS Code write access — same failure mode the
    # "DO NOT chown them" comment above is warning about, except here
    # we WANT a chown because we (root) just created these files and
    # nothing else owns them yet. www-data (UID 33) matches how the
    # rest of wp-content is owned in this image; adjust if your host
    # user has a different UID mapped via docker-compose `user:`.
    chown -R www-data:www-data "${WFP_PLUGIN_DIR}"

    echo "[OK] WayForPay gateway cloned (block-support branch from PR #40)."
fi

wp plugin is-active wc-wayforpay --path=/var/www/html --allow-root 2>/dev/null || \
    wp plugin activate wc-wayforpay --path=/var/www/html --allow-root

# Verified against the actual installed gateway via wp eval var_dump():
# id="wayforpay", form_fields are merchant_account / secret_key.
# Test credentials — see https://wiki.wayforpay.com/en/view/852472
# Replace with real merchant credentials before going to production.
wp eval '
    $gateways = WC()->payment_gateways()->payment_gateways();
    $found = false;
    foreach ( $gateways as $gateway ) {
        if ( $gateway->id === "wayforpay" ) {
            $found = true;
            $settings = $gateway->settings;
            $settings["enabled"]          = "yes";
            $settings["merchant_account"] = "'"${WAY_FOR_PAY_MERCHANT_ACCOUNT}"'";
            $settings["secret_key"]       = "'"${WAY_FOR_PAY_MERCHANT_SECRET_KEY}"'";
            update_option( $gateway->get_option_key(), $settings );
            echo "[OK] WayForPay gateway enabled with test credentials (id: {$gateway->id})\n";
            break;
        }
    }
    if ( ! $found ) {
        echo "[WARN] No WayForPay gateway with id=wayforpay found in WC payment_gateways() registry.\n";
    }
' --path=/var/www/html --allow-root

# ---------------------------------------------------------------------------
# MORKVA UA SHIPPING (Nova Poshta / Ukrposhta) — runs every boot
# ---------------------------------------------------------------------------
# Same rationale as the WayForPay block above: placed after first-run setup,
# gated on its own directory check rather than `wp core is-installed`, so it
# also runs correctly on the very first boot (right after WordPress/WooCommerce
# get created earlier in this same script execution).
echo "[INFO] Installing Morkva UA Shipping plugin..."

if [ -d /var/www/html/wp-content/plugins/morkva-ua-shipping ]; then
    echo "[INFO] Morkva UA Shipping already installed, activating..."
    wp plugin activate morkva-ua-shipping --path=/var/www/html --allow-root || true
else
    wp plugin install morkva-ua-shipping --activate --path=/var/www/html --allow-root
    echo "[OK] Morkva UA Shipping installed and activated."
fi

# Confirmed via wp eval against the real installed plugin:
#   docker compose exec wordpress wp eval \
#     'foreach (wp_load_alloptions() as $k => $v) { if (stripos($k, "mrkv") !== false) echo "$k\n"; }' \
#     --allow-root
# -> mrkv_api_fixed_np (flat string option, not a serialized settings array —
#    the mrkv_ua_shipping_settings guess returned false and was wrong).
if [ -n "${NOVA_POSHTA_API_KEY}" ]; then
    wp option update mrkv_api_fixed_np "${NOVA_POSHTA_API_KEY}" --path=/var/www/html --allow-root
    echo "[OK] Nova Poshta API key set (option: mrkv_api_fixed_np)."
else
    echo "[WARN] NOVA_POSHTA_API_KEY not set in environment — skipping API key configuration."
fi

# ---------------------------------------------------------------------------
# CHECKOUT PAGE — force classic [woocommerce_checkout] shortcode
# ---------------------------------------------------------------------------
# Morkva UA Shipping (and every UA Nova Poshta/Ukrposhta plugin checked at
# the time of writing) only injects its city/warehouse fields into the
# classic shortcode-based checkout — none of them support the WooCommerce
# Checkout block yet. Runs every boot, not just first-run, so it survives
# WooCommerce re-inserting its block-based checkout template after updates.
if wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
    CHECKOUT_PAGE_ID=$(wp post list \
        --post_type=page \
        --pagename=checkout \
        --field=ID \
        --allow-root \
        --path=/var/www/html 2>/dev/null | head -1)

    if [ -n "${CHECKOUT_PAGE_ID}" ]; then
        wp post update "${CHECKOUT_PAGE_ID}" --post_content='[woocommerce_checkout]' --path=/var/www/html --allow-root
        echo "[OK] Checkout page set to classic shortcode (ID: ${CHECKOUT_PAGE_ID})."
    else
        echo "[WARN] Checkout page not found — WooCommerce may not be fully activated yet."
    fi
fi

chown -R www-data:www-data /var/www/html/wp-content/uploads

echo "[INFO] Starting Apache..."
exec apache2-foreground