#!/usr/bin/env python3
"""Audit + correctifs VPS. Usage: PQ_SSH_PASSWORD=xxx python deploy/remote_audit_fix.py"""
import os
import sys

try:
    import paramiko
except ImportError:
    print("pip install paramiko")
    sys.exit(1)

HOST = os.environ.get("PQ_SSH_HOST", "185.194.218.27")
USER = os.environ.get("PQ_SSH_USER", "root")
PASSWORD = os.environ.get("PQ_SSH_PASSWORD", "")

if not PASSWORD:
    print("Définir PQ_SSH_PASSWORD")
    sys.exit(1)

APACHE_SSL = r'''<IfModule mod_ssl.c>
<VirtualHost *:443>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
        ServerName powerquest.robinmatelot.codes

        <Directory /var/www/html>
                Header set Cross-Origin-Opener-Policy "same-origin"
                Header set Cross-Origin-Embedder-Policy "require-corp"
        </Directory>

        ProxyRequests Off
        ProxyPreserveHost On
        SSLProxyEngine On
        ProxyTimeout 3600

        <Location /v2>
                ProxyPass http://127.0.0.1:7360/v2
                ProxyPassReverse http://127.0.0.1:7360/v2
                RequestHeader unset Accept-Encoding
                SetEnv no-gzip 1
        </Location>

        <Location /healthcheck>
                ProxyPass http://127.0.0.1:7360/healthcheck
                ProxyPassReverse http://127.0.0.1:7360/healthcheck
                RequestHeader unset Accept-Encoding
                SetEnv no-gzip 1
        </Location>

        RedirectMatch 301 ^/game$ /game/

        RewriteEngine On
        RewriteCond %{HTTP:Upgrade} =websocket [NC,OR]
        RewriteCond %{HTTP:Upgrade} websocket [NC]
        RewriteCond %{HTTP:Connection} upgrade [NC,OR]
        RewriteCond %{HTTP:Connection} Upgrade [NC]
        RewriteRule ^/game/?(.*)$ ws://127.0.0.1:9080/$1 [P,L]

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

        SSLCertificateFile /etc/letsencrypt/live/powerquest.robinmatelot.codes/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/powerquest.robinmatelot.codes/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
</VirtualHost>
</IfModule>
'''

SERVICE = """[Unit]
Description=Power Quest Game Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/root/deploy
Environment=GODOT_SILENCE_ROOT_WARNING=1
ExecStart=/root/deploy/power_quest_server.x86_64 --headless -- --server --port 9080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"""


def run():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PASSWORD, timeout=25)

    sftp = c.open_sftp()
    with sftp.file("/etc/apache2/sites-available/000-default-le-ssl.conf", "w") as f:
        f.write(APACHE_SSL)
    with sftp.file("/etc/systemd/system/powerquest-game.service", "w") as f:
        f.write(SERVICE)
    local_lobby = os.path.join(os.path.dirname(__file__), "nakama", "modules", "lobby.lua")
    if os.path.isfile(local_lobby):
        sftp.put(local_lobby, "/root/deploy/nakama/modules/lobby.lua")
    sftp.close()

    cmds = r"""
set -e
a2enmod proxy proxy_http proxy_wstunnel headers rewrite ssl 2>/dev/null || true
chmod 755 /root/deploy/power_quest_server.x86_64
test -x /root/deploy/power_quest_server.x86_64 || { echo 'Binaire non executable'; exit 1; }
fuser -k 9080/tcp 2>/dev/null || true
systemctl daemon-reload
systemctl restart powerquest-game
sleep 2
cd /root/deploy && docker compose restart nakama 2>/dev/null || true
sleep 3
apache2ctl configtest
systemctl reload apache2
echo '=== STATUS ==='
systemctl is-active powerquest-game
ss -tlnp | grep -E '9080|7360'
echo '=== NAKAMA PING ==='
curl -s -m 5 -X POST 'http://127.0.0.1:7360/v2/rpc/ping?unwrap&http_key=defaultkey' \
  -H 'Content-Type: application/json' -d '""' || true
echo
echo '=== WSS TEST (GET, pas HEAD) ==='
curl -s -m 8 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://powerquest.robinmatelot.codes/game/ | head -5
echo '=== APACHE ERR ==='
tail -5 /var/log/apache2/error.log
"""
    _, stdout, stderr = c.exec_command(cmds, timeout=120)
    sys.stdout.buffer.write(stdout.read())
    err = stderr.read()
    if err.strip():
        sys.stdout.buffer.write(b"\nSTDERR:\n" + (err if isinstance(err, bytes) else err.encode()))
    c.close()
    print("\nDone.")


if __name__ == "__main__":
    run()
