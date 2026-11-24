# Handoff notes (agent/maintainer)

Context for whoever picks this up after a failure report. Written 2026-11-24.

## What this repo is

Codespaces-hosted Ubuntu XFCE desktop via `lscr.io/linuxserver/webtop:ubuntu-xfce`,
replacing the noVNC approach from AndnixSH/codespace-desktop (no audio there).
Chrome is installed by `webtop-setup/install-google-chrome.sh`.

Key design decisions, so they don't get "fixed" back:

- **Port 3000, not 3001.** The image exposes 3000 (HTTP) and 3001 (HTTPS). 3000 is
  used because the Codespaces proxy terminates TLS, giving the browser a secure
  context (required for WebCodecs/Opus audio) with no self-signed cert warning.
  `portsAttributes` must stay protocol-neutral; setting `"protocol": "https"`
  here was wrong and was removed.
- **`--security-opt seccomp=unconfined`** is required by the webtop image.
- **`${localWorkspaceFolderBasename}`** in `postStartCommand` is substituted by
  the devcontainer CLI (verified in `variableSubstitution.ts`: it walks every
  string in the config, lifecycle commands included). Do not replace it with
  `$PWD` guessing.
- **Chrome runs with `--no-sandbox`** (no namespaces available in the container)
  and `--password-store=basic` (no keyring daemon). Both are deliberate.
- **Chrome install is idempotent via a binary check** (`/opt/google/chrome/google-chrome`),
  not a marker in `/config`, because the container layer resets on recreation
  while `/config` persists.

## State at handoff

- `main` == `origin/main` == `205b7c8` (+ this notes commit).
- Nothing was ever run: no image pulled, no container created, `webtop-config/`
  does not exist in the repo and never did.
- Verified statically only:
  - image tag exists (amd64 + arm64), config exposes 3000/3001, `HOME=/config`,
    s6 `/init`, Selkies env (`PULSE_RUNTIME_PATH=/defaults`)
  - Chrome `.deb` URL returns 200
  - devcontainer JSON parses, script passes `bash -n`, mode `100755` committed
- **Not verified end-to-end:** first boot, apt install of Chrome, audio playback.
  Those are the likely failure points.

## If the user reports a failure

Ask for the **Dev Containers** log (it contains `[webtop-setup]` lines) and
`docker ps -a --filter name=webtop`. Then:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `postStartCommand` fails at the last step, `/webtop-setup/install-google-chrome.sh: not found` | container predates the `webtop-setup` mount | `docker rm -f webtop`, reload window |
| Chrome step fails, apt output present | dependency/postinst issue on the Ubuntu base | rerun `docker exec -u root webtop /webtop-setup/install-google-chrome.sh`; check `apt-get install /tmp/google-chrome.deb` output |
| Port 3000 unreachable | container not running or pull still in progress | `docker ps`, `docker logs webtop` |
| Page loads, no sound | Selkies audio toggle off, or tab muted, or page never clicked | sidebar top audio toggle; unmute site; click the page |
| Chrome absent on arm64 Codespace | no Google arm64 build; script exits 0 by design | expected; bundled browser is the fallback |
| Container starts but ignores new flags | `docker start` reuses existing container | `docker rm -f webtop` |

## Constraints

- The user asked, for the initial generation, that Docker never be pulled/run in
  the assistant environment. Any actual container run needs their OK first.
- Prefer `docker manifest inspect` / registry API for image questions; that is
  not a pull.
