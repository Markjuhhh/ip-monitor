#!/bin/bash
set -euo pipefail

###### CONFIGURATIE ######
CTID=107
HOSTNAME="ip-monitor-mail"
TEMPLATE="local:vztmpl/alpine-3.18-default_*.tar.xz"
STORAGE="local-lvm"
PASSWORD="IZaltbommel1"
SMTP_HOST="smtp.jouwdomein.nl"
SMTP_PORT=587
SMTP_USER="mark.thuis.bot@gmail.com"
SMTP_PASS="GZaltbommel1"
EMAIL_TO="markvissers@hotmail.com"
##########################

# Controle CTID
if pct status "$CTID" &> /dev/null; then
  echo "Container ID $CTID bestaat al." >&2
  exit 1
fi

# Container aanmaken en starten
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --storage "$STORAGE" \
  --rootfs "$STORAGE":2 \
  --memory 128 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --password "$PASSWORD" \
  --unprivileged 1 \
  --ostype alpine
pct start "$CTID"

# Installatie binnen container
pct exec "$CTID" -- apk update
pct exec "$CTID" -- apk add curl bash nullmailer mailx

# Nullmailer configuratie
pct exec "$CTID" -- tee /etc/nullmailer/remotes > /dev/null <<EOF
$SMTP_HOST smtp --port=$SMTP_PORT --auth-login --user=$SMTP_USER --pass=$SMTP_PASS --starttls
EOF
pct exec "$CTID" -- tee /etc/nullmailer/adminaddr > /dev/null <<EOF
$EMAIL_TO
EOF
pct exec "$CTID" -- tee /etc/nullmailer/me > /dev/null <<EOF
$HOSTNAME
EOF
pct exec "$CTID" -- tee /etc/nullmailer/defaultdomain > /dev/null <<EOF
$(echo "$SMTP_HOST" | sed 's/^.*\.//')
EOF

# Script voor IP-check
pct exec "$CTID" -- mkdir -p /opt/ip-monitor/data
pct exec "$CTID" -- tee /opt/ip-monitor/check_ip_change.sh > /dev/null <<'EOF'
#!/bin/bash
IP_FILE="/opt/ip-monitor/data/current_ip.txt"
CURRENT_IP=$(curl -s https://ipinfo.io/ip)
OLD_IP=""
[ -f "$IP_FILE" ] && OLD_IP=$(cat "$IP_FILE")
if [ "$CURRENT_IP" != "$OLD_IP" ]; then
  echo "$CURRENT_IP" > "$IP_FILE"
  MESSAGE="📡 Publiek IP gewijzigd: $OLD_IP ➜ $CURRENT_IP"
  echo "$MESSAGE" | mailx -s "Publiek IP gewijzigd" "$EMAIL_TO"
fi
EOF
pct exec "$CTID" -- chmod +x /opt/ip-monitor/check_ip_change.sh

# Cronjob instellen
pct exec "$CTID" -- sh -c "echo '*/30 * * * * /opt/ip-monitor/check_ip_change.sh >/dev/null 2>&1' >> /etc/crontabs/root"

# Enable cron en nullmailer service
pct exec "$CTID" -- rc-update add crond default
pct exec "$CTID" -- rc-update add nullmailer default

# Start services
pct exec "$CTID" -- crond
pct exec "$CTID" -- /etc/init.d/nullmailer start

echo "✅ Container $CTID klaar. E-mail notificaties via nullmailer ingesteld."
