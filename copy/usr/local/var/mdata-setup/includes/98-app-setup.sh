#!/usr/bin/bash

echo "* Start postgresql"
systemctl daemon-reload
pg_createcluster 15 main --start || true
DB_PWD=$(openssl rand -hex 24)
sudo -u postgres psql -c "CREATE USER dendrite;" || true
sudo -u postgres psql -c "ALTER USER dendrite WITH PASSWORD '${DB_PWD}';" || true
sudo -u postgres createdb -O dendrite -E UTF-8 dendrite || true
for i in appservice federationapi mediaapi mscs roomserver syncapi keyserver userapi; do
    sudo -u postgres createdb -O dendrite -E UTF-8 dendrite_$i || true
done

echo "* Setup dendrite"
DOMAIN=$(/native/usr/sbin/mdata-get dendrite_domain)
USER_SHORT=$(/native/usr/sbin/mdata-get user_shortname)
USER_PWD=$(/native/usr/sbin/mdata-get dendrite_password)
SHARED_SECRET=$(openssl rand -hex 24)

sed -i \
    -e "s/server_name: localhost/server_name: matrix.autic.com/" \
    -e "s#private_key: matrix_key.pem#private_key: /etc/matrix_key.pem#" \
    -e "s#connection_string: postgresql://username:password@hostname/dendrite?sslmode=disable#connection_string: postgresql://dendrite:${DB_PWD}@127.0.0.1/dendrite?sslmode=disable#" \
    -e "s/    addresses:/    in_memory: false/" \
    -e "s#    storage_path: ./#    storage_path: /home/dendrite/#" \
    -e "#base_path: ./media_store#base_path: /home/dendrite/media_store#" \
    -e "s#path: ./logs#path: /var/log/dentrite/#" \
    -e "s/registration_shared_secret: \"\"/registration_shared_secret: \"${SHARED_SECRET}\"/" \
    -e "s/cache_size: 256/cache_size: 4096/" \
    -e "s/dns_cache:\n    enabled: false/dns_cache:\n    enabled: true/" \
    /etc/dendrite.yaml
chown -R dendrite:root /etc/dendrite.yaml
chmod 0640 /etc/dendrite.yaml

echo "* Setup admin account"
create-account -config "/etc/dendrite.yaml" -username "${USER_SHORT}" -password "${USER_PWD}" -admin || true
      
echo "* Setup postgresql backup"
mkdir -p /var/lib/postgresql/backups
chown postgres:postgres /var/lib/postgresql/backups
echo "0 1 * * * /usr/local/bin/psql_backup" >> /var/spool/cron/crontabs/postgres
echo "0 2 1 * * /usr/bin/vacuumdb --all" >> /var/spool/cron/crontabs/postgres
chown postgres:crontab /var/spool/cron/crontabs/postgres
chmod 0600 /var/spool/cron/crontabs/postgres

echo "* Seup hostname for nginx"
sed -i "s/my.hostname.com/${DOMAIN}/g" /etc/nginx/sites-available/dendrite

echo "* Create http-basic password for backup area"
if [[ ! -f /etc/nginx/.htpasswd ]]; then
  if /native/usr/sbin/mdata-get dendrite_backup_pwd 1>/dev/null 2>&1; then
    /native/usr/sbin/mdata-get dendrite_backup_pwd | shasum | awk '{print $1}' | htpasswd -c -i /etc/nginx/.htpasswd "pg-backup"
    chmod 0640 /etc/nginx/.htpasswd
    chown root:www-data /etc/nginx/.htpasswd
    usermod -a -G postgres www-data
  fi
fi

echo "* Start dendrite"
systemctl enable dendrite || true
systemctl start dendrite || true
systemctl restart nginx || true

exit 0