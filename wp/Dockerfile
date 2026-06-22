FROM wordpress:php8.3-apache

 USER root

# Install system dependencies and WP-CLI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        less \
        default-mysql-client \
        curl \
        ca-certificates \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        && \
    rm -rf /var/lib/apt/lists/*

# Download and install WP-CLI
RUN curl -o /usr/local/bin/wp -L https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x /usr/local/bin/wp

# Install additional PHP extensions.
# mysqli and pdo_mysql MUST be listed explicitly — any docker-php-ext-install
# call resets the active extension set, dropping base-image pre-builds.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install -j$(nproc) gd mysqli pdo_mysql

# Copy PHP overrides
COPY php-ini-overrides/ /usr/local/etc/php/conf.d/

# Copy setup script
COPY setup-wp.sh /usr/local/bin/setup-wp.sh
RUN chmod +x /usr/local/bin/setup-wp.sh

# Stay as root — setup-wp.sh needs to write into wp-content/plugins & themes.
# The script itself drops privileges to www-data before exec-ing apache2.
CMD ["/usr/local/bin/setup-wp.sh"]