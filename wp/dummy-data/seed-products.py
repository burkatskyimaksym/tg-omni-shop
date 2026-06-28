#!/usr/bin/env python3
"""
seed-products.py — Data-driven WooCommerce product seeder.

Reads wp/dummy-data/products.json and creates variable products with
size variations in WooCommerce via WP-CLI. Fully idempotent: existing
SKUs and already-imported images are detected and skipped.

Usage (called by seed-products.sh):
    python3 /var/www/html/wp-content/dummy-data/seed-products.py
"""

import json
import subprocess
import sys
import os

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR      = "/var/www/html"
DATA_DIR      = "/var/www/html/wp-content/dummy-data"
IMAGES_DIR    = os.path.join(DATA_DIR, "products", "images")
PRODUCTS_JSON = os.path.join(DATA_DIR, "products.json")

WP_BASE = ["wp", "--allow-root", f"--path={BASE_DIR}", "--user=admin"]


# ── WP-CLI helpers ────────────────────────────────────────────────────────────

def wp(*args, json_output=False, porcelain=False, silent=False):
    """Run a WP-CLI command; return stdout string or parsed JSON."""
    cmd = WP_BASE + list(args)
    if json_output:
        cmd += ["--format=json"]
    if porcelain:
        cmd += ["--porcelain"]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0 and not silent:
        print(f"  [WARN] WP-CLI returned {result.returncode}: {result.stderr.strip()}")

    out = result.stdout.strip()
    if json_output and out:
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return None
    return out


# ── Image handling ────────────────────────────────────────────────────────────

def import_image(filename, title):
    """
    Import an image into the WP media library.
    Skips import if an attachment with the exact same title already exists.
    Returns attachment ID (str) or None if the file is missing.
    """
    path = os.path.join(IMAGES_DIR, filename)
    if not os.path.isfile(path):
        print(f"    [WARN] Image not found: {path} — skipping.")
        return None

    # Fetch attachments with this title and match exactly in Python
    # (wp post list --post_title does LIKE, not exact match)
    rows = wp(
        "post", "list",
        "--post_type=attachment",
        f"--post_title={title}",
        "--fields=ID,post_title",
        json_output=True,
        silent=True,
    )
    if rows:
        for row in rows:
            if row.get("post_title", "").strip() == title.strip():
                attach_id = str(row["ID"])
                print(f"    [SKIP] Image '{title}' already exists (ID: {attach_id})")
                return attach_id

    attach_id = wp("media", "import", path, f"--title={title}", porcelain=True)
    if attach_id:
        print(f"    [IMG]  Imported '{title}' → ID: {attach_id}")
    return attach_id or None


# ── Category handling ─────────────────────────────────────────────────────────

def ensure_category(name):
    """Return category ID, creating it if it doesn't exist."""
    rows = wp("wc", "product_cat", "list", f"--search={name}", json_output=True, silent=True)
    if rows:
        for row in rows:
            if row.get("name", "").lower() == name.lower():
                return str(row["id"])

    cat_id = wp("wc", "product_cat", "create", f"--name={name}", porcelain=True)
    print(f"    [CAT]  Created category '{name}' (ID: {cat_id})")
    return cat_id


# ── Product handling ──────────────────────────────────────────────────────────

def product_exists(sku):
    """Return product ID if a product with this SKU already exists, else None."""
    rows = wp("wc", "product", "list", f"--sku={sku}", json_output=True, silent=True)
    if rows:
        return str(rows[0]["id"])
    return None


def create_variable_product(p, category_ids, featured_image_id, gallery_ids):
    """Create the parent variable product and return its ID."""
    categories_json = json.dumps([{"id": int(cid)} for cid in category_ids])

    attributes_json = json.dumps([{
        "name": "size",
        "visible": True,
        "variation": True,
        "options": [v["size"] for v in p["variations"]]
    }])

    cmd_args = [
        "wc", "product", "create",
        f"--name={p['name']}",
        "--type=variable",
        f"--sku={p['sku']}",
        f"--description={p.get('description', '')}",
        f"--short_description={p.get('short_description', '')}",
        "--manage_stock=true",
        f"--stock_quantity={p.get('stock', 0)}",
        "--status=publish",
        f"--categories={categories_json}",
        f"--attributes={attributes_json}",
    ]

    if p.get("tags"):
        tags_json = json.dumps([{"name": t} for t in p["tags"]])
        cmd_args.append(f"--tags={tags_json}")

    if p.get("weight"):
        cmd_args.append(f"--weight={p['weight']}")

    product_id = wp(*cmd_args, porcelain=True)

    if not product_id:
        print(f"  [ERROR] Failed to create product '{p['name']}' — skipping.")
        return None

    # low_stock_amount is not in WC REST API — set via post meta directly
    wp("post", "meta", "update", product_id, "_low_stock_amount",
       str(p.get("low_stock_amount", 10)))

    # Set featured image and gallery via post meta
    if featured_image_id:
        wp("post", "meta", "update", product_id, "_thumbnail_id", featured_image_id)

    if gallery_ids:
        wp("post", "meta", "update", product_id, "_product_image_gallery",
           ",".join(gallery_ids))

    return product_id


def variation_exists(parent_id, var_sku):
    """Return variation ID if it already exists under this parent, else None."""
    rows = wp("wc", "product_variation", "list", parent_id, json_output=True, silent=True)
    if rows:
        for v in rows:
            if v.get("sku") == var_sku:
                return str(v["id"])
    return None


def create_variation(parent_id, parent_sku, variation, image_id):
    """
    Create a single product variation.

    Valid wc product_variation create params (WC REST API v3):
      --sku, --regular_price, --sale_price, --attributes, --description, --image
    NOT valid: --status, --stock_status (these are set on the parent product)
    """
    var_sku = f"{parent_sku}-{variation['sku_suffix']}"

    if variation_exists(parent_id, var_sku):
        print(f"    [SKIP] Variation '{var_sku}' already exists")
        return

    cmd_args = [
        "wc", "product_variation", "create", parent_id,
        f"--sku={var_sku}",
        f"--regular_price={variation['price']:.2f}",
        f"--attributes=[{{\"name\":\"size\",\"option\":\"{variation['size']}\"}}]",
        f"--description={variation.get('description', '')}",
    ]

    if variation.get("sale_price") is not None:
        cmd_args.append(f"--sale_price={variation['sale_price']:.2f}")

    # Attach image inline if available (supported param)
    if image_id:
        cmd_args.append(f"--image={{\"id\":{image_id}}}")

    var_id = wp(*cmd_args, porcelain=True)

    if var_id:
        print(f"    [VAR]  Created variation '{var_sku}' (size={variation['size']}, ID: {var_id})")
    else:
        print(f"    [ERROR] Failed to create variation '{var_sku}'")


# ── Main ──────────────────────────────────────────────────────────────────────

def seed():
    if not os.path.isfile(PRODUCTS_JSON):
        print(f"[ERROR] {PRODUCTS_JSON} not found — nothing to seed.")
        sys.exit(1)

    with open(PRODUCTS_JSON) as f:
        products = json.load(f)

    print(f"[SEED] Found {len(products)} product(s) in products.json")

    for p in products:
        sku  = p["sku"]
        name = p["name"]
        print(f"\n[SEED] ── {name} ({sku}) {'─' * max(1, 50 - len(name) - len(sku))}")

        existing_id = product_exists(sku)
        if existing_id:
            print(f"  [SKIP] Product already exists (ID: {existing_id})")
            continue

        # 1. Resolve/create categories
        category_ids = [ensure_category(cat) for cat in p.get("categories", [])]

        # 2. Import featured image (M variant by convention)
        featured_image_id = None
        if p.get("featured_image"):
            featured_image_id = import_image(p["featured_image"], f"{name} Featured")

        # 3. Import variation images
        variation_image_ids = {}
        gallery_ids = []
        for v in p.get("variations", []):
            if v.get("image"):
                img_id = import_image(v["image"], f"{name} Size {v['size']}")
                variation_image_ids[v["size"]] = img_id
                if img_id:
                    gallery_ids.append(img_id)

        # 4. Create parent variable product
        product_id = create_variable_product(p, category_ids, featured_image_id, gallery_ids)
        if not product_id:
            continue

        print(f"  [PROD] Created '{name}' (ID: {product_id})")

        # 5. Create variations
        for v in p.get("variations", []):
            img_id = variation_image_ids.get(v["size"])
            create_variation(product_id, sku, v, img_id)

    print(f"\n[SEED] ✓ Done.")


if __name__ == "__main__":
    seed()