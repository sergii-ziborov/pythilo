#!/bin/sh
# Stage a reviewed Linux image, then deploy through Hostwatch MCP.
set -eu
host=${PYTHILO_HOST:-root@2.29.175.213}
key=${PYTHILO_SSH_KEY:-$HOME/.ssh/hetzner-prod}
node=${PYTHILO_HOSTWATCH_NODE:-fe8b3706-3da6-47f8-875c-ce86a0cb8114}
tag=$(date -u +%Y%m%d%H%M%S)
stage=/srv/apps/pythilo/releases/$tag
[ "$#" -eq 0 ] || { echo 'Ingress is managed separately; this script takes no flags.' >&2; exit 2; }
[ -f release/standalone/server.js ] || { echo 'Prepare the server release first.' >&2; exit 1; }
[ -f hetzner/Containerfile ] || { echo 'Missing Linux container profile.' >&2; exit 1; }
case "$node" in ''|*[!A-Za-z0-9._:-]*) echo 'Invalid Hostwatch node ID.' >&2; exit 2;; esac
if [ "$host" != root@2.29.175.213 ] && [ -z "${PYTHILO_HOSTWATCH_NODE:-}" ]; then
  echo 'Set PYTHILO_HOSTWATCH_NODE when overriding the destination host.' >&2
  exit 2
fi
transport=$(mktemp)
trap 'rm -f "$transport"' EXIT HUP INT TERM
export PYTHILO_DEPLOY_KEY="$key"
cat > "$transport" <<'SSH'
#!/bin/sh
exec ssh -i "$PYTHILO_DEPLOY_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "$@"
SSH
chmod 700 "$transport"
"$transport" "$host" "mkdir -p $stage"
rsync -a -e "$transport" release/standalone/ "$host:$stage/"
rsync -a -e "$transport" release/static/ "$host:$stage/.next/static/"
rsync -a -e "$transport" release/public/ "$host:$stage/public/"
rsync -a -e "$transport" hetzner/Containerfile "$host:$stage/Containerfile"
"$transport" "$host" "set -e
podman build --pull=never --cpu-period 100000 --cpu-quota 100000 --memory 768m -t localhost/pythilo-web:release-$tag $stage
podman tag localhost/pythilo-web:release-$tag localhost/pythilo-web:current
podman image inspect localhost/pythilo-web:current --format '{{.Id}}'"
echo "Staged $tag on $host. The running application has not been replaced."
echo "Hostwatch deployment_preview: nodeId=$node, args.id=pythilo-web."
echo 'Use deployment_update with its sourceDigest/revision and a stable key; follow image_publish_status.'
