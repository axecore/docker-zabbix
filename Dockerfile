FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    PHP_FPM=8.1 \
    ZBX_VER=7.0

# Paket dasar + PHP + MySQL + Zabbix (server, web, agent2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils ca-certificates curl gnupg lsb-release netcat-openbsd locales \
    supervisor nginx \
    php-fpm php-mysql php-xml php-bcmath php-ldap php-gd php-json php-mbstring php8.1-gettext \
    mysql-server mysql-client \
 && rm -rf /var/lib/apt/lists/*

# Repo Zabbix 7.0 + paket
RUN curl -fsSL "https://repo.zabbix.com/zabbix/${ZBX_VER}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZBX_VER}-1%2bubuntu22.04_all.deb" -o /tmp/zabbix-release.deb \
 && dpkg -i /tmp/zabbix-release.deb \
 && rm -f /tmp/zabbix-release.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      zabbix-server-mysql zabbix-sql-scripts zabbix-frontend-php zabbix-agent2 \
 && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -ri "s|^# *en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|" /etc/locale.gen \
 && sed -ri "s|^# *id_ID.UTF-8 UTF-8|id_ID.UTF-8 UTF-8|" /etc/locale.gen \
 && locale-gen en_US.UTF-8 id_ID.UTF-8 \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# PHP timezone
RUN sed -ri "s|^;?date.timezone =.*|date.timezone = ${TZ}|" /etc/php/${PHP_FPM}/fpm/php.ini

# max_input_time PHP -FPM
RUN printf "max_execution_time=300\nmax_input_time=300\nmemory_limit=256M\npost_max_size=32M\nupload_max_filesize=16M\ndate.timezone=${TZ}\n" \
    > /etc/php/8.1/fpm/conf.d/99-zabbix.ini

# Nginx site untuk Zabbix
RUN rm -f /etc/nginx/sites-enabled/default
COPY zabbix-nginx.conf /etc/nginx/sites-available/zabbix.conf
RUN ln -s /etc/nginx/sites-available/zabbix.conf /etc/nginx/sites-enabled/zabbix.conf

# Konfigurasi MySQL
COPY zbx.cnf /etc/mysql/mysql.conf.d/zbx.cnf

# Supervisor + Entrypoint
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Buat folder config frontend & symlink
RUN mkdir -p /etc/zabbix/web /usr/share/zabbix/conf \
 && ln -sf /etc/zabbix/web/zabbix.conf.php /usr/share/zabbix/conf/zabbix.conf.php \
 && chown -R www-data:www-data /etc/zabbix/web /usr/share/zabbix/conf

EXPOSE 8080 10051 10050
VOLUME ["/var/lib/mysql", "/var/lib/zabbix", "/var/log"]

HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD nc -z 127.0.0.1 10051 || exit 1
ENTRYPOINT ["/entrypoint.sh"]
