# winget source (rewinged behind Caddy)

Serves a winget source at `https://winget.itprise.com/api`. Windows users
install ITPrise Studio with winget; the installer itself is downloaded from
the GitHub release of this repository (the manifest holds URL + SHA-256).

Server-specific details (IP, accounts, firewall, existing sites) are kept
privately and are intentionally not part of this public repository.

## Architecture

- `rewinged` (https://github.com/jantari/rewinged) listens on
  `127.0.0.1:8080` without TLS and reads manifests from a git checkout of
  this repository.
- An existing **Caddy** instance terminates TLS and proxies
  `winget.itprise.com` to `127.0.0.1:8080`.
- Manifests live in `manifests/` (winget community layout). Installers are
  NOT stored on the server; they are release assets of this repo.

## Rebuild on a new server

Prerequisites: Ubuntu/Debian host, DNS A/AAAA record for
`winget.itprise.com` pointing to it, ports 80 and 443 reachable, an admin
user with sudo, and Caddy running with `import /etc/caddy/sites-enabled/*.caddy`
in its Caddyfile.

```bash
scp -r deploy/ <admin>@winget.itprise.com:~/winget-deploy
ssh <admin>@winget.itprise.com 'bash ~/winget-deploy/setup-server.sh'
```

The script is idempotent. It installs `unzip` if missing, downloads rewinged
(`REWINGED_VERSION`, default 0.15.0) and verifies it against the upstream
checksum file, clones this repo to `/var/lib/rewinged/repo`, installs
`rewinged.service`, writes `/etc/caddy/sites-enabled/winget.itprise.com.caddy`,
runs `caddy validate` and only then reloads Caddy. If validation fails, the
site block is removed again and Caddy is not reloaded.

The site block has no `tls` line, so Caddy obtains a certificate via ACME.

Test:

```bash
curl -s https://winget.itprise.com/api/information
curl -s https://winget.itprise.com/api/packageManifests/ITPrise.Studio
```

## Publish a new version

1. Build and sign the installers, create the GitHub release `vX.Y.Z` in this
   repo with the MSI and compute its SHA-256.
2. Copy `manifests/i/ITPrise/Studio/<old>/` to `<new>/` and update
   `PackageVersion`, `InstallerUrl`, `InstallerSha256` and the MSI
   `ProductCode` (it changes per build; read it from the MSI) in all three
   YAML files.
3. Merge to `main`, then on the server run
   `bash /var/lib/rewinged/repo/deploy/update-manifests.sh`.
   rewinged picks up new manifests live; removed manifests need
   `sudo systemctl restart rewinged`.

## Client (Windows)

Adding a source needs an elevated (administrator) terminal:

```powershell
winget source add -n itprise -a https://winget.itprise.com/api -t "Microsoft.Rest"
winget install --source itprise ITPrise.Studio
```

## Pitfalls

- Scripts checked out with CRLF fail on Linux (`set: pipefail: invalid option
  name`); `.gitattributes` forces LF.
- `unzip` is not installed by default; the script installs it.
- `apt-get` may print `needrestart` notices about deferred restarts of
  unrelated services; they do not affect this setup.
- Only the MSI is listed in the manifest (winget wants one installer per
  architecture). The NSIS setup stays a plain release asset.
