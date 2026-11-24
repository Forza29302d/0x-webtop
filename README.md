# Ubuntu Webtop Desktop in GitHub Codespaces

Run a full **Ubuntu + XFCE desktop** inside a GitHub Codespace and use it entirely from your browser — with **video, clipboard, and audio streaming natively in a single tab**, no local terminal, no SSH tunnels, and no extra client software. **Google Chrome** is installed automatically on first start.

This repo is a drop-in replacement for the classic noVNC approach used by [AndnixSH/codespace-desktop](https://github.com/AndnixSH/codespace-desktop/tree/main). That setup forwards a VNC session to a browser, which means **no sound**. Here the desktop is served by [LinuxServer.io's Webtop](https://github.com/linuxserver/docker-webtop) image (`lscr.io/linuxserver/webtop:ubuntu-xfce`), whose Selkies web client carries screen, clipboard, and Opus audio over the same connection.

## How it works

```
GitHub Codespace (Ubuntu dev container)
└── Docker-in-Docker
    └── lscr.io/linuxserver/webtop:ubuntu-xfce   →  https://<codespace>-3000.app.github.dev
        ├── /config       →  /workspaces/<repo>/webtop-config      (persistent)
        ├── /webtop-setup →  /workspaces/<repo>/webtop-setup:ro    (Chrome installer)
        └── port 3000 (web client: screen + clipboard + audio)
```

- `.devcontainer/devcontainer.json` starts the Codespace on an Ubuntu base image with the `docker-in-docker` feature, auto-forwards port `3000` (labelled **Webtop Desktop**), and on every start runs `docker start webtop || docker run ...` so the desktop comes back automatically.
- `webtop-setup/install-google-chrome.sh` is mounted into the container and run as root after each start. It installs Google Chrome from Google's official `.deb`, adds a menu entry and a desktop icon, and is idempotent.
- `.gitignore` excludes `webtop-config/`, so your desktop session, browser profiles, and caches never end up in the repo.
- Everything runs server-side in the Codespace; your browser only needs to render the page.

## Launch it

1. **Create the Codespace.** On GitHub, click **Code → Codespaces → Create codespace on main** (or open an existing one for this repo). The first build installs Docker-in-Docker and pulls the Webtop image (~1–2 GB), so give it a couple of minutes.
2. **Wait for the desktop container.** When the Codespace is ready, the `postStartCommand` creates (first run) or restarts (later runs) the `webtop` container in detached mode, then installs Chrome the first time. Confirm from the Codespace terminal with:
   ```bash
   docker ps --filter name=webtop
   ```

   The very first start is the slow one: it pulls the ~1.5 GB image, then downloads Chrome (~120 MB). That can take several minutes and the `postStartCommand` stays running until it finishes. Progress shows up in the **Dev Containers** log as `[webtop-setup]` lines; later starts only re-check that Chrome is present and take seconds.
3. **Open port 3000.** Go to the **Ports** tab in VS Code / the Codespaces UI. Port `3000` is forwarded automatically and labelled **Webtop Desktop**. Click the globe / **Open in Browser** icon next to it.
   - Port `3000` is configured as **public**: anyone who gets its URL can reach the desktop. Do not use this with sensitive data; change its visibility to **Private** in the Ports tab if you want access restricted to your GitHub account.
   - If the URL redirects to GitHub sign-in or shows `HTTP ERROR 401`, the existing forwarded port is still **Private**. In the Ports tab, open the context menu for port `3000` and change **Port Visibility** to **Public**. The `portsAttributes` setting applies when Codespaces forwards the port; it does not change an existing port's visibility.
   - If the port is not listed, add it manually: **Ports → Forward a Port → `3000`**.
   - No certificate warning: the container serves plain HTTP on 3000 and the Codespaces proxy terminates TLS for you. (If you ever see a self-signed cert warning, you are on port 3001 instead.)
4. **Start working.** You land directly on the XFCE desktop, with Chrome in the menu and a launcher on the desktop.

The Codespaces URL is HTTPS, which matters: browsers only expose audio and video decoding (WebCodecs) in a secure context, so the proxied port gives you sound without any extra TLS setup.

## Enable audio

Audio is off until you turn it on — browsers require a user gesture before playing sound.

1. **Click anywhere on the desktop page first.** Browsers block audio on tabs that have never been interacted with, and Codespaces tabs are often opened programmatically.
2. Open the web client's **sidebar** (use the handle at the edge of the screen). The audio toggle sits at the top, next to display, microphone, webcam, and gamepad toggles.
3. Turn **audio** on. If the session was started muted, you may also need to unmute the browser tab itself: right-click the tab → **Unmute site**, and check the site's sound permission in the address bar.
4. Play something inside the desktop (e.g. open Chrome and a video) to verify. Volume is controlled by the desktop's own mixer **and** your system volume.

The same sidebar gives you the **microphone**, **clipboard** (two-way sync, including an editable clipboard box), **file upload/download**, fullscreen, and display-scaling controls.

## Google Chrome

Chrome is installed by `webtop-setup/install-google-chrome.sh` the first time the container starts, and again automatically if the container is ever recreated. It appears as **Google Chrome** in the XFCE application menu and as an icon on the desktop.

A few deliberate choices:

- **`--no-sandbox`** — the container does not grant the namespaces Chrome's sandbox needs, so Chrome would refuse to start. This is fine for a disposable Codespace, but do not treat this browser as a hardened sandbox.
- **`--password-store=basic`** — there is no keyring daemon in the session, so this avoids the "unlock keyring" prompt on every launch.
- **amd64 only** — Google publishes no arm64 build. On arm64 Codespaces the installer logs a message and leaves the image's bundled browser in place.

The wrapper lives at `/usr/local/bin/google-chrome-stable`, so launching `google-chrome-stable` from a terminal picks up the same flags.

## Persistence across restarts

The container's `/config` directory is bind-mounted to `webtop-config/` inside this workspace:

```
-v /workspaces/${localWorkspaceFolderBasename}/webtop-config:/config
```

So browser profiles, bookmarks, desktop settings, installed desktop apps, and files in the home directory survive Codespace stop/start and container recreation. Because `webtop-config/` is git-ignored, that state stays local to your Codespace and is never committed.

> Note: Codespaces themselves are ephemeral. Deleting the Codespace deletes the workspace — and therefore `webtop-config/` — too. Commit anything you care about to git.

Chrome itself is *not* in `/config`; it lives in the container layer and is reinstalled by the setup script whenever the container is recreated.

## Customizing

Edit `.devcontainer/devcontainer.json`, then rebuild/recreate the Codespace:

| Setting | Current value | Notes |
| --- | --- | --- |
| Timezone | `TZ=Australia/Brisbane` | Any valid tz database name |
| User / group ID | `PUID=1000`, `PGID=1000` | Matches the `vscode` user; keeps file ownership sane |
| Shared memory | `--shm-size="2gb"` | Larger is better for browsers |
| Host port | `-p 3000:3000` | Keep `forwardPorts` in sync if you change it |
| Desktop flavor | `ubuntu-xfce` | Other tags: `ubuntu-kde`, `ubuntu-mate`, `alpine-xfce`, etc. |

If you change the container definition (flags, volumes, image tag), remove the old container once so the new flags apply:

```bash
docker rm -f webtop
```

Then run **Codespaces: Rebuild Container**, or reload the window to re-trigger `postStartCommand`.

To add more packages, append installs to `webtop-setup/install-google-chrome.sh` (or add a second script in `webtop-setup/` and call it from `postStartCommand`). Keep them idempotent: the script runs on every start, but the container layer resets on recreation.

## Useful commands (optional)

Run these in the Codespace terminal only if you want to inspect or restart things manually — normal use needs none of them.

```bash
docker logs -f webtop          # follow desktop logs
docker restart webtop          # restart the desktop
docker rm -f webtop            # delete it (config in webtop-config/ is kept)
docker exec -it webtop bash    # shell inside the desktop container
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Port 3000 shows nothing / connection refused | Container may still be pulling: `docker logs -f webtop`. Then reload the port URL. |
| "Site can't be reached" on the forwarded URL | Confirm `docker ps` shows `webtop` with `0.0.0.0:3000->3000/tcp`. |
| No sound | Click the page, open the sidebar, and switch the audio toggle on; check the tab isn't muted and the site has sound permission. |
| Chrome missing from the menu | Check the postStart output for `[webtop-setup]` lines, or run `docker exec -u root webtop /webtop-setup/install-google-chrome.sh` manually. |
| Chrome closes immediately | Launch it from a terminal to see the error: `docker exec -it -u abc webtop google-chrome-stable`. |
| Clipboard not syncing | Use the sidebar clipboard panel (paste into it with Ctrl/Cmd+V) — some browsers restrict direct clipboard access. |
| Desktop reset / settings lost | Verify `webtop-config/` exists in the workspace root and is being mounted (`docker inspect webtop`). |

## Credits

- [AndnixSH/codespace-desktop](https://github.com/AndnixSH/codespace-desktop/tree/main) — the original noVNC-based Codespace desktop this repo is modelled on.
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — the Webtop image that provides the desktop and native browser audio/video/clipboard.
