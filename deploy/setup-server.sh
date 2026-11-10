#!/usr/bin/env bash
# Idempotent setup of the ITPrise winget source (rewinged behind Caddy).
# Run on the VPS as a user with sudo (e.g. deploy):  bash setup-server.sh
# Re-run to upgrade rewinged (change REWINGED_VERSION) or to repair the setup.
set -euo pipefail

REWINGED_VERSION="${REWINGED_VERSION:-0.15.0}"
REPO_URL="https://github.com/itprise/winget.git"
HOST="winget.itprise.com"
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. service user and directories
id rewinged >/dev/null 2>&1 || sudo useradd --system --home-dir /var/lib/rewinged --shell /usr/sbin/nologin rewinged
sudo mkdir -p /opt/rewinged /var/lib/rewinged

# 2. rewinged binary, verified against the upstream checksum file
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
base="https://github.com/jantari/rewinged/releases/download/v${REWINGED_VERSION}"
zip="rewinged_${REWINGED_VERSION}_linux_amd64.zip"
curl -fsSL -o "$tmp/$zip" "$base/$zip"
curl -fsSL -o "$tmp/sums.txt" "$base/rewinged_${REWINGED_VERSION}_checksums.txt"
(cd "$tmp" && grep " $zip\$" sums.txt | sha256sum -c -)
(cd "$tmp" && unzip -o -q "$zip" rewinged)
sudo install -m 0755 "$tmp/rewinged" /opt/rewinged/rewinged

# 3. manifest repository (public, read-only clone, owned by deploy so it can git pull)
if [ ! -d /var/lib/rewinged/repo/.git ]; then
  sudo git clone --depth 1 "$REPO_URL" /var/lib/rewinged/repo
  sudo chown -R "$(id -un)":rewinged /var/lib/rewinged/repo
fi
git -C /var/lib/rewinged/repo pull --ff-only

# 4. systemd unit
sudo install -m 0644 "$DEPLOY_DIR/rewinged.service" /etc/systemd/system/rewinged.service
sudo systemctl daemon-reload
sudo systemctl enable rewinged
sudo systemctl restart rewinged

# 5. Caddy: add the site block to the shared instance, validate, then reload.
#    Rolls the block back if validation fails, so the other sites stay untouched.
site=/etc/caddy/sites-enabled/${HOST}.caddy
sudo install -m 0644 "$DEPLOY_DIR/${HOST}.caddy" "$site"
if sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
  sudo systemctl reload caddy
else
  sudo rm -f "$site"
  echo "caddy validate FAILED - site block removed, Caddy not reloaded" >&2
  exit 1
fi

echo "Done. Test: curl -s https://${HOST}/api/information"
