# Zabbix 7.0 Dockerbuild (ubuntu.22-04)
- edit .env
- mkdir -p ./ubuntu_data_mnt ./ubuntu_zbx_db ./ubuntu_zbx_web
- docker compose build --no-cache
- docker compose up -d
- http://localhost:8080 (default zabbix GUI)
