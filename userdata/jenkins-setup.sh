#!/bin/bash
set -euo pipefail

JENKINS_PORT="8080"

if [ "$EUID" -ne 0 ]; then
  echo "Run as root:"
  echo "sudo bash $0"
  exit 1
fi

echo "=== Install Java 21 ==="
apt update
apt install -y fontconfig openjdk-21-jre wget ca-certificates gnupg

java -version

echo "=== Add Jenkins LTS repository ==="
install -d -m 0755 /etc/apt/keyrings

wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

echo "=== Install Jenkins ==="
apt update
apt install -y jenkins

echo "=== Configure Jenkins port ==="
mkdir -p /etc/systemd/system/jenkins.service.d

cat >/etc/systemd/system/jenkins.service.d/override.conf <<EOT
[Service]
Environment="JENKINS_PORT=${JENKINS_PORT}"
EOT

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins

echo "=== Allow firewall if UFW exists ==="
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${JENKINS_PORT}/tcp || true
fi

echo "=== Jenkins status ==="
systemctl status jenkins --no-pager || true

echo
echo "Jenkins installed."
echo "Open: http://SERVER_PUBLIC_IP:${JENKINS_PORT}"
echo "Initial admin password:"
echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"