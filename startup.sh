#!/bin/sh -e

while ! pg_isready -h $TTRSS_DB_HOST -U $TTRSS_DB_USER; do
	echo waiting until $TTRSS_DB_HOST is ready...
	sleep 3
done

# We don't need those here (HTTP_HOST would cause false SELF_URL_PATH check failures)
unset HTTP_PORT
unset HTTP_HOST

if ! id ttrss >/dev/null 2>&1; then
	# what if i actually need a duplicate GID/UID group?

	addgroup -g $OWNER_GID ttrss || echo ttrss:x:$OWNER_GID:ttrss | \
		tee -a /etc/group

	adduser -D -h /var/www/html -G ttrss -u $OWNER_UID ttrss || \
		echo ttrss:x:$OWNER_UID:$OWNER_GID:Linux User,,,:/var/www/html:/bin/ash | tee -a /etc/passwd
fi

update-ca-certificates || true

DST_DIR=/var/www/html/tt-rss
SRC_REPO=https://git.tt-rss.org/fox/tt-rss.git

[ -e $DST_DIR ] && rm -f $DST_DIR/.app_is_ready

export PGPASSWORD=$TTRSS_DB_PASS

psql -q -h "$TTRSS_DB_HOST" -U "$TTRSS_DB_USER" -c "create database $TTRSS_DB_NAME owner = $TTRSS_DB_USER;"

PSQL="psql -q -h $TTRSS_DB_HOST -U $TTRSS_DB_USER $TTRSS_DB_NAME"

if [ ! -d $DST_DIR/.git ]; then
	mkdir -p $DST_DIR
	chown ttrss:ttrss $DST_DIR

	echo cloning tt-rss source from $SRC_REPO to $DST_DIR...
	sudo -u ttrss git clone --depth 1 $SRC_REPO $DST_DIR || echo error: failed to clone master repository.
else
	echo updating tt-rss source in $DST_DIR from $SRC_REPO...

	chown -R ttrss:ttrss $DST_DIR
	cd $DST_DIR && \
		sudo -u ttrss git config core.filemode false && \
		sudo -u ttrss git config pull.rebase false && \
		sudo -u ttrss git pull origin master || echo error: unable to update master repository.
fi

if [ ! -e $DST_DIR/index.php ]; then
	echo "error: tt-rss index.php missing (git clone failed?), unable to continue."
	exit 1
fi

if [ ! -d $DST_DIR/plugins.local/nginx_xaccel ]; then
	echo cloning plugins.local/nginx_xaccel...
	sudo -u ttrss git clone https://git.tt-rss.org/fox/ttrss-nginx-xaccel.git \
		$DST_DIR/plugins.local/nginx_xaccel ||  echo warning: failed to clone nginx_xaccel.
else
	if [ -z "$TTRSS_NO_STARTUP_PLUGIN_UPDATES" ]; then
		echo updating all local plugins...

		find $DST_DIR/plugins.local/ -maxdepth 1 -mindepth 1 -type d | while read PLUGIN; do
			if [ -d $PLUGIN/.git ]; then
				echo updating $PLUGIN...

				cd $PLUGIN && \
					sudo -u ttrss git config core.filemode false && \
					sudo -u ttrss git config pull.rebase false && \
					sudo -u ttrss git pull origin master || echo warning: attempt to update plugin $PLUGIN failed.
			fi
		done
	else
		echo updating plugins.local/nginx_xaccel...

		cd $DST_DIR/plugins.local/nginx_xaccel && \
			sudo -u ttrss git config core.filemode false && \
			sudo -u ttrss git config pull.rebase false && \
			sudo -u ttrss git pull origin master || echo warning: attempt to update plugin nginx_xaccel failed.
	fi
fi

cp ${SCRIPT_ROOT}/config.docker.php $DST_DIR/config.php
chmod 644 $DST_DIR/config.php

for d in cache lock feed-icons; do
	chmod 777 $DST_DIR/$d
	find $DST_DIR/$d -type f -exec chmod 666 {} \;
done

chown -R ttrss:ttrss $DST_DIR /var/log/php81

$PSQL -c "create extension if not exists pg_trgm"

RESTORE_SCHEMA=${SCRIPT_ROOT}/restore-schema.sql.gz

if [ -r $RESTORE_SCHEMA ]; then
	$PSQL -c "drop schema public cascade; create schema public;"
	zcat $RESTORE_SCHEMA | $PSQL
fi

# this was previously generated
rm -f $DST_DIR/config.php.bak

if [ ! -z "${TTRSS_CORE_DUMPS_ENABLED}" ]; then
	apk add gdb

	echo "don't forget to enable core dumps on the host:"
	echo "echo '/tmp/core-%e.%p' > /proc/sys/kernel/core_pattern"
	echo "then run gdb /usr/sbin/php-fpm81 /tmp/coredump-php-fpm-xyz"

	# enable core dumps
	sed -i.bak \
	-e 's/;\(rlimit_core\) = .*/\1 = unlimited/' \
	-e 's/; *\(process.dumpable\) = .*/\1 = yes/' \
			/etc/php81/php-fpm.d/www.conf
fi

if [ ! -z "${TTRSS_XDEBUG_ENABLED}" ]; then
	if [ -z "${TTRSS_XDEBUG_HOST}" ]; then
		export TTRSS_XDEBUG_HOST=$(ip ro sh 0/0 | cut -d " " -f 3)
	fi
	echo enabling xdebug with the following parameters:
	env | grep TTRSS_XDEBUG
	cat > /etc/php81/conf.d/50_xdebug.ini <<EOF
zend_extension=xdebug.so
xdebug.mode=debug
xdebug.start_with_request = yes
xdebug.client_port = ${TTRSS_XDEBUG_PORT}
xdebug.client_host = ${TTRSS_XDEBUG_HOST}
EOF
fi

sed -i.bak "s/^\(memory_limit\) = \(.*\)/\1 = ${PHP_WORKER_MEMORY_LIMIT}/" \
	/etc/php81/php.ini

sed -i.bak "s/^\(pm.max_children\) = \(.*\)/\1 = ${PHP_WORKER_MAX_CHILDREN}/" \
	/etc/php81/php-fpm.d/www.conf

sudo -Eu ttrss php81 $DST_DIR/update.php --update-schema=force-yes

if [ ! -z "$ADMIN_USER_PASS" ]; then
	sudo -Eu ttrss php81 $DST_DIR/update.php --user-set-password "admin:$ADMIN_USER_PASS"
else
	if sudo -Eu ttrss php81 $DST_DIR/update.php --user-check-password "admin:password"; then
		RANDOM_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')

		echo "*****************************************************************************"
		echo "* Setting initial built-in admin user password to '$RANDOM_PASS'        *"
		echo "* If you want to set it manually, use ADMIN_USER_PASS environment variable. *"
		echo "*****************************************************************************"

		sudo -Eu ttrss php81 $DST_DIR/update.php --user-set-password "admin:$RANDOM_PASS"
	fi
fi

if [ ! -z "$ADMIN_USER_ACCESS_LEVEL" ]; then
	sudo -Eu ttrss php81 $DST_DIR/update.php --user-set-access-level "admin:$ADMIN_USER_ACCESS_LEVEL"
fi

if [ ! -z "$AUTO_CREATE_USER" ]; then
	sudo -Eu ttrss /bin/sh -c "php81 $DST_DIR/update.php --user-exists $AUTO_CREATE_USER ||
		php81 $DST_DIR/update.php --force-yes --user-add \"$AUTO_CREATE_USER:$AUTO_CREATE_USER_PASS:$AUTO_CREATE_USER_ACCESS_LEVEL\""
fi

rm -f /var/log/ttrss/error.log && mkfifo /var/log/ttrss/error.log && chown ttrss:ttrss /var/log/ttrss/error.log

(tail -q -f /var/log/ttrss/error.log >> /proc/1/fd/2) &

unset ADMIN_USER_PASS
unset AUTO_CREATE_USER_PASS

# cleanup any old lockfiles
rm -vf -- /var/www/html/tt-rss/lock/*.lock

touch $DST_DIR/.app_is_ready

exec /usr/sbin/php-fpm81 --nodaemonize --force-stderr -R
