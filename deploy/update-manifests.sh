#!/usr/bin/env bash
# Pull new manifests. rewinged picks up new/changed manifests live;
# removed manifests need: sudo systemctl restart rewinged
set -euo pipefail
git -C /var/lib/rewinged/repo pull --ff-only
