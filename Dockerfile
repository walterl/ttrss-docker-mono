FROM nginx:alpine AS base
LABEL org.opencontainers.image.version="0.1.1"
LABEL org.opencontainers.image.authors="Walter Leibbrandt"
LABEL org.opencontainers.image.source="https://github.com/walterl/ttrss-docker-mono"

ENV SCRIPT_ROOT=/opt/tt-rss

RUN apk add --no-cache dcron php81 php81-fpm \
	php81-pdo php81-gd php81-pgsql php81-pdo_pgsql \
	php81-mbstring php81-intl php81-xml php81-curl \
	php81-session php81-tokenizer php81-dom php81-fileinfo php81-ctype \
	php81-json php81-iconv php81-pcntl php81-posix php81-zip php81-exif \
	php81-openssl git postgresql-client sudo php81-pecl-xdebug rsync \
	supervisor && \
	sed -i 's/\(memory_limit =\) 128M/\1 256M/' /etc/php81/php.ini && \
	sed -i -e 's/^listen = 127.0.0.1:9000/listen = 9000/' \
		-e 's/;\(clear_env\) = .*/\1 = no/i' \
		-e 's/^\(user\|group\) = .*/\1 = ttrss/i' \
		-e 's/;\(php_admin_value\[error_log\]\) = .*/\1 = \/var\/log\/ttrss\/error.log/' \
		-e 's/;\(php_admin_flag\[log_errors\]\) = .*/\1 = on/' \
			/etc/php81/php-fpm.d/www.conf && \
	mkdir -p /var/www /var/log/ttrss ${SCRIPT_ROOT}/config.d

ADD startup.sh ${SCRIPT_ROOT}
ADD updater.sh ${SCRIPT_ROOT}
ADD config.docker.php ${SCRIPT_ROOT}
ADD backup.sh /etc/periodic/weekly/backup
COPY supervisord.conf /etc/supervisor/
COPY nginx.conf /etc/nginx/nginx.conf

ENV OWNER_UID=1010
ENV OWNER_GID=1010

ENV PHP_WORKER_MAX_CHILDREN=5
ENV PHP_WORKER_MEMORY_LIMIT=256M

# these are applied on every startup, if set
ENV ADMIN_USER_PASS=
# see classes/UserHelper.php ACCESS_LEVEL_*
# setting this to -2 would effectively disable built-in admin user
# unless single user mode is enabled
ENV ADMIN_USER_ACCESS_LEVEL=

# these are applied unless user already exists
ENV AUTO_CREATE_USER=
ENV AUTO_CREATE_USER_PASS=
ENV AUTO_CREATE_USER_ACCESS_LEVEL="0"

# TODO: remove prefix from container variables not used by tt-rss itself:
#
# - TTRSS_NO_STARTUP_PLUGIN_UPDATES -> NO_STARTUP_PLUGIN_UPDATES
# - TTRSS_XDEBUG_... -> XDEBUG_...

# don't try to update local plugins on startup (except for nginx_xaccel)
ENV TTRSS_NO_STARTUP_PLUGIN_UPDATES=

# TTRSS_XDEBUG_HOST defaults to host IP if unset
ENV TTRSS_XDEBUG_ENABLED=
ENV TTRSS_XDEBUG_HOST=
ENV TTRSS_XDEBUG_PORT="9000"

ENV TTRSS_DB_TYPE="pgsql"
ENV TTRSS_DB_HOST="db"
ENV TTRSS_DB_PORT="5432"
ENV TTRSS_DB_USER="ttrss"
ENV TTRSS_DB_PASS=

ENV TTRSS_SELF_URL_PATH=
ENV TTRSS_MYSQL_CHARSET="UTF8"
ENV TTRSS_PHP_EXECUTABLE="/usr/bin/php81"
ENV TTRSS_PLUGINS="auth_internal, note, nginx_xaccel"

VOLUME ${SCRIPT_ROOT}/config.d
VOLUME /backups

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
