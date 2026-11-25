# Plan 12/14: supply a reviewed official WordPress Apache image by immutable digest.
ARG WORDPRESS_BASE_IMAGE
FROM ${WORDPRESS_BASE_IMAGE}
COPY php/strathost-access.php /usr/src/wordpress/wp-content/mu-plugins/strathost-access.php
COPY php/strathost-health.php /usr/src/wordpress/strathost-health.php
COPY php/db.php /usr/src/wordpress/wp-content/db.php
# Verify PHP/OpenSSL/mysqli in the selected base before publishing the built image.
RUN php -r 'exit(extension_loaded("openssl") && extension_loaded("mysqli") ? 0 : 1);'
RUN php -l /usr/src/wordpress/wp-content/db.php \
    && php -l /usr/src/wordpress/wp-content/mu-plugins/strathost-access.php \
    && php -l /usr/src/wordpress/strathost-health.php
