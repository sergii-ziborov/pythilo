#!/bin/sh
# Ships site/release/ (from scripts/prepare-server-release.mjs) to the Hetzner
# analytics node and switches the running site to it. Run from site/.
#
#   sh hetzner/deploy.sh            copy, switch, restart, check
#   sh hetzner/deploy.sh --nginx    also install the nginx site (after the certificate exists)
#
# PYTHILO_HOST and PYTHILO_SSH_KEY override where it goes.
set -eu

host=${PYTHILO_HOST:-root@46.225.60.104}
key=${PYTHILO_SSH_KEY:-$HOME/.ssh/hetzner-prod}
domain=${PYTHILO_DOMAIN:-pythilo.com}
tag=$(date -u +%Y%m%d%H%M%S)
ssh="ssh -i $key -o BatchMode=yes"

[ -f release/standalone/server.js ] || { echo "Run pnpm build and node scripts/prepare-server-release.mjs first." >&2; exit 1; }

# The server runs standalone/server.js with the static files and public/ beside it.
$ssh "$host" "mkdir -p /opt/pythilo/releases/$tag"
rsync -a --delete -e "$ssh" release/standalone/ "$host:/opt/pythilo/releases/$tag/"
rsync -a --delete -e "$ssh" release/static/ "$host:/opt/pythilo/releases/$tag/.next/static/"
rsync -a --delete -e "$ssh" release/public/ "$host:/opt/pythilo/releases/$tag/public/"
rsync -a -e "$ssh" hetzner/pythilo-site.service "$host:/etc/systemd/system/pythilo-site.service"

if [ "${1:-}" = "--nginx" ]; then
  sed "s/__PYTHILO_DOMAIN__/$domain/g" hetzner/pythilo.nginx | $ssh "$host" "cat > /etc/nginx/sites-available/pythilo"
  $ssh "$host" "mkdir -p /var/log/pythilo && ln -sfn /etc/nginx/sites-available/pythilo /etc/nginx/sites-enabled/pythilo && nginx -t && systemctl reload nginx"
fi

$ssh "$host" "set -e
chmod -R go+rX /opt/pythilo/releases/$tag
ln -sfn /opt/pythilo/releases/$tag /opt/pythilo/current
systemctl daemon-reload
systemctl enable pythilo-site.service >/dev/null 2>&1
systemctl restart pythilo-site.service
for i in 1 2 3 4 5 6 7 8 9 10; do curl -fsS http://127.0.0.1:3212/healthz/ >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:3212/healthz/
# Keep the three newest releases.
ls -1dt /opt/pythilo/releases/* | tail -n +4 | xargs -r rm -rf"
echo
echo "Deployed $tag to $host."
