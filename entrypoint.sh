#!/usr/bin/env bash
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:=rootpass123}"
: "${MYSQL_DATABASE:=zabbix}"
: "${MYSQL_USER:=zabbix}"
: "${MYSQL_PASSWORD:=zabbixpass123}"
: "${ZBX_STARTPOLLERS:=10}"
: "${ZBX_DEBUGLEVEL:=3}"
: "${ZBX_AGENT_HOSTNAME:=Zabbix server}"
: "${TZ:=Asia/Jakarta}"

mkdir -p /run/mysqld /var/log/zabbix
chown -R mysql:mysql /run/mysqld /var/lib/mysql
chown -R zabbix:zabbix /var/lib/zabbix /var/log/zabbix || true

# fresh init
fresh_init=0
if [ ! -d "/var/lib/mysql/mysql" ]; then
  echo "[entrypoint] Initializing MySQL (fresh datadir)..."
  mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
  fresh_init=1
fi

# Start temporary mysqld
echo "[entrypoint] Starting temporary mysqld..."
/usr/sbin/mysqld \
  --datadir=/var/lib/mysql \
  --socket=/run/mysqld/mysqld.sock \
  --user=mysql --skip-networking &
MYSQL_PID=$!

# Wait ready
for i in {1..60}; do
  if mysqladmin --protocol=socket -S /run/mysqld/mysqld.sock ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

sock="--protocol=socket -S /run/mysqld/mysqld.sock"

# helper: eksekusi SQL sebagai root; coba tanpa password lalu dengan password
mysql_root_exec() {
  mysql $sock -uroot -e "$1" 2>/dev/null || mysql $sock -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "$1"
}

# Provision root, DB, users
echo "[entrypoint] Provisioning MySQL..."
if [ "$fresh_init" -eq 1 ]; then
  # root belum ada password → set sekarang
  mysql $sock -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; FLUSH PRIVILEGES;"
fi

# create DB & users
mysql_root_exec "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql_root_exec "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql_root_exec "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'         IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql_root_exec "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost', '${MYSQL_USER}'@'%'; FLUSH PRIVILEGES;"

# Import schema if table 'users' missing
echo "[entrypoint] Checking Zabbix schema..."
HAS_USERS=$(mysql $sock -N -B -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}' AND table_name='users';" || echo 0)

if [ "${HAS_USERS}" = "0" ]; then
  echo "[entrypoint] Importing Zabbix schema..."
  gunzip -c /usr/share/zabbix-sql-scripts/mysql/server.sql.gz \
    | mysql $sock --force -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}"
fi

# Stop temp mysqld
echo "[entrypoint] Stopping temporary mysqld..."
kill ${MYSQL_PID}
wait ${MYSQL_PID} || true

# zabbix_server.conf
cat >/etc/zabbix/zabbix_server.conf <<CONF
LogType=console
LogFile=/var/log/zabbix/zabbix_server.log
DBHost=127.0.0.1
DBName=${MYSQL_DATABASE}
DBUser=${MYSQL_USER}
DBPassword=${MYSQL_PASSWORD}
StartPollers=${ZBX_STARTPOLLERS}
DebugLevel=${ZBX_DEBUGLEVEL}
CacheSize=256M
CONF

# zabbix_agent2.conf
cat >/etc/zabbix/zabbix_agent2.conf <<CONF
PidFile=/var/run/zabbix/zabbix_agent2.pid
LogType=console
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=${ZBX_AGENT_HOSTNAME}
ListenPort=10050
Include=/etc/zabbix/zabbix_agent2.d/*.conf
CONF

mkdir -p /var/run/zabbix && chown -R zabbix:zabbix /var/run/zabbix

echo "[entrypoint] Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

