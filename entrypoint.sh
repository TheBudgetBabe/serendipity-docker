#!/bin/bash
# vim: set ts=8 tw=0 noet :

set -e -o pipefail

# Relocate the PHP code according to the given URI
s9yUri=${SERENDIPITY_URI:-/}
s9yUri=${s9yUri%/}
s9yUri=${s9yUri#/}

[[ -n "$s9yUri" ]] && mkdir -p /var/www/html/$s9yUri
tar -c -f - -C /usr/src/serendipity . | tar -x -f - -C /var/www/html/$s9yUri

# Setup memory and size limits
maxSize=${MAX_SIZE:-10}
[[ $maxSize -gt 128 ]] && memLimit=$maxSize

cat >>/var/www/html/$s9yUri/.htaccess <<-EOF
	php_value memory_limit ${memLimit:-128}M
	php_value upload_max_filesize ${maxSize}M
	php_value post_max_size ${maxSize}M
EOF

cat >/etc/apache2/apache2.conf <<-EOF
	Mutex file:/var/lock/apache2 default
	PidFile /var/run/apache2/apache2.pid
	Timeout 300
	KeepAlive On
	MaxKeepAliveRequests 100
	KeepAliveTimeout 5
	User www-data
	Group www-data
	ErrorLog /proc/self/fd/2
	LogLevel ${LOG_LEVEL:-warn}

	IncludeOptional mods-enabled/*.load
	IncludeOptional mods-enabled/*.conf

	ServerName ${SERVER_NAME:-localhost}
	ServerAdmin ${SERVER_ADMIN:-webmaster@localhost}
	Listen 80
	HostnameLookups Off

	<Directory />
		Options FollowSymLinks
		AllowOverride None
		Require all denied
	</Directory>

	<Directory /var/www/>
		AllowOverride All
		Require all granted
	</Directory>

	DocumentRoot /var/www/html

	AccessFileName .htaccess
	<FilesMatch "^\\.ht">
		Require all denied
	</FilesMatch>

	LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined
	CustomLog /proc/self/fd/1 combined

	<FilesMatch \\.php$>
		SetHandler application/x-httpd-php
	</FilesMatch>

	DirectoryIndex disabled
	DirectoryIndex index.php index.html

	IncludeOptional conf-enabled/*.conf
EOF

# Change ownership to enable online updates
chown -R www-data /var/www/html

: "${APACHE_CONFDIR:=/etc/apache2}"
: "${APACHE_ENVVARS:=$APACHE_CONFDIR/envvars}"
if test -f "$APACHE_ENVVARS"; then
	. "$APACHE_ENVVARS"
fi

# Apache gets grumpy about PID files pre-existing
: "${APACHE_PID_FILE:=${APACHE_RUN_DIR:=/var/run/apache2}/apache2.pid}"
rm -f "$APACHE_PID_FILE"

# Hand over to apache as PID 1
exec apache2 -DFOREGROUND
