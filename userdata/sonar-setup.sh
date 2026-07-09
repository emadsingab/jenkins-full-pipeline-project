#!/bin/bash
set -euo pipefail

SONAR_VERSION="26.7.0.124771"
SONAR_ZIP="sonarqube-${SONAR_VERSION}.zip"
SONAR_URL="https://binaries.sonarsource.com/Distribution/sonarqube/${SONAR_ZIP}"

SONAR_USER="sonar"
SONAR_GROUP="sonar"
SONAR_HOME="/opt/sonarqube"
SONAR_DB="sonarqube"
SONAR_DB_USER="sonar"
SONAR_DB_PASSWORD="admin123"
TMP_DIR="/tmp/sonarqube-install"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root:"
  echo "sudo bash $0"
  exit 1
fi

# Backup old config files
cp /etc/sysctl.conf /root/sysctl.conf_backup_$(date +%F_%H-%M-%S) 2>/dev/null || true
cp /etc/security/limits.conf /root/limits.conf_backup_$(date +%F_%H-%M-%S) 2>/dev/null || true

# Kernel parameters required by Elasticsearch inside SonarQube
cat >/etc/sysctl.d/99-sonarqube.conf <<EOT
vm.max_map_count=262144
fs.file-max=65536
EOT

sysctl --system

# User limits
cat >/etc/security/limits.d/99-sonarqube.conf <<EOT
${SONAR_USER}   -   nofile   65536
${SONAR_USER}   -   nproc    4096
EOT

# Install required packages
apt-get update -y
apt-get install -y wget curl unzip gnupg ca-certificates lsb-release nginx ufw openjdk-21-jdk

java -version

# Install PostgreSQL from official PGDG repository
install -d /usr/share/postgresql-common/pgdg

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg

echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

apt-get update -y
apt-get install -y postgresql-16 postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

# Create database user and database
cd /tmp
sudo -u postgres psql <<EOT
DO
\$\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = '${SONAR_DB_USER}'
   ) THEN
      CREATE ROLE ${SONAR_DB_USER} LOGIN PASSWORD '${SONAR_DB_PASSWORD}';
   ELSE
      ALTER ROLE ${SONAR_DB_USER} WITH LOGIN PASSWORD '${SONAR_DB_PASSWORD}';
   END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${SONAR_DB} OWNER ${SONAR_DB_USER}'
WHERE NOT EXISTS (
   SELECT FROM pg_database WHERE datname = '${SONAR_DB}'
)\gexec

GRANT ALL PRIVILEGES ON DATABASE ${SONAR_DB} TO ${SONAR_DB_USER};
EOT

systemctl restart postgresql

# Create sonar group/user if not exists
if ! getent group "$SONAR_GROUP" >/dev/null; then
  groupadd "$SONAR_GROUP"
fi

if ! id "$SONAR_USER" >/dev/null 2>&1; then
  useradd -c "SonarQube User" -d "$SONAR_HOME" -g "$SONAR_GROUP" -s /bin/bash "$SONAR_USER"
fi

# Download and install SonarQube
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

wget "$SONAR_URL" -O "$SONAR_ZIP"

systemctl stop sonarqube 2>/dev/null || true

rm -rf "$SONAR_HOME"
unzip -q "$SONAR_ZIP" -d /opt/
mv "/opt/sonarqube-${SONAR_VERSION}" "$SONAR_HOME"

chown -R "$SONAR_USER:$SONAR_GROUP" "$SONAR_HOME"

# Configure SonarQube
cp "$SONAR_HOME/conf/sonar.properties" "/root/sonar.properties_backup_$(date +%F_%H-%M-%S)" 2>/dev/null || true

cat >"$SONAR_HOME/conf/sonar.properties" <<EOT
sonar.jdbc.username=${SONAR_DB_USER}
sonar.jdbc.password=${SONAR_DB_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost:5432/${SONAR_DB}

sonar.web.host=127.0.0.1
sonar.web.port=9000

sonar.search.javaOpts=-Xms512m -Xmx512m -XX:+HeapDumpOnOutOfMemoryError
sonar.web.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError

sonar.log.level=INFO
sonar.path.logs=logs
EOT

chown "$SONAR_USER:$SONAR_GROUP" "$SONAR_HOME/conf/sonar.properties"

# Create systemd service
cat >/etc/systemd/system/sonarqube.service <<EOT
[Unit]
Description=SonarQube service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=forking
User=${SONAR_USER}
Group=${SONAR_GROUP}

Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64"
Environment="PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ExecStart=${SONAR_HOME}/bin/linux-x86-64/sonar.sh start
ExecStop=${SONAR_HOME}/bin/linux-x86-64/sonar.sh stop

Restart=on-failure
RestartSec=10

LimitNOFILE=65536
LimitNPROC=4096

TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable sonarqube
systemctl restart sonarqube

# Configure Nginx reverse proxy
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

cat >/etc/nginx/sites-available/sonarqube <<'EOT'
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/sonar.access.log;
    error_log  /var/log/nginx/sonar.error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_redirect off;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOT

ln -sfn /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube

nginx -t
systemctl enable nginx
systemctl restart nginx

# Firewall
ufw allow 80/tcp || true
ufw allow 9000/tcp || true

echo "SonarQube installation completed."
echo "Open via Nginx: http://SERVER_IP"
echo "Direct port: http://SERVER_IP:9000"
echo "Default login:"
echo "username: admin"
echo "password: admin"