# audiobookshelf-for-tos

> TerraMaster TOS 7 App Center — **Docker application** package for
> [Audiobookshelf](https://github.com/advplyr/audiobookshelf).

## What this is

A four-file TOS Docker application archive (`audiobookshelfdocker.tar.gz`) that installs
Audiobookshelf on TOS 7 through the App Center:

- `config.ini` — TOS application metadata (`application_type: docker`, id `audiobookshelfdocker`)
- `audiobookshelfdocker.lang` — 23-language superset (TOS requires 14)
- `audiobookshelfdocker.svg` — application icon (1438 bytes, 3 SVG elements)
- `docker-compose.yml` — one service, image `moechz/audiobookshelf:2.37.2`

## How it works

| | |
|---|---|
| Container image | `moechz/audiobookshelf:2.37.2` (Docker Hub, used unmodified) |
| Open | `http://<NAS-IP>:8159/` (container port 80) |
| Runs as | non-root, `user: "1000:1000"` |
| Persistent data | `/config` → `/Volume1/DockerAppData/audiobookshelfdocker/config`, `/metadata` → `/Volume1/DockerAppData/audiobookshelfdocker/metadata`, `/audiobooks` → `/Volume1/DockerAppData/audiobookshelfdocker/audiobooks` |
| Logs | `docker logs audiobookshelfdocker` (stdout/stderr) |



## Design highlights

- **Non-root.** `user: "1000:1000"`; verified on real hardware (the container reports uid 1000).
- **Fixed image tag, never `:latest`**, Docker Hub only, no `privileged`, no `network_mode: host`, and no Docker socket, no `cap_add`.
- **Health check** probing the service on container port 80.
- **Deterministic build**: GNU tar with uid/gid 0 and zeroed timestamps, gzip without a timestamp, plus the review-standards self-check above.

## Runtime file manifest

Everything the application writes on the NAS lives inside its own data
directory; the container-internal `/tmp` is discarded with the container. The
table lists what is created and how it behaves. Nothing else is written.

| Path | Purpose | Created when | Growth bound | Lifecycle |
|---|---|---|---|---|
| `/Volume1/DockerAppData/audiobookshelfdocker/config` | Audiobookshelf application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |
| `/Volume1/DockerAppData/audiobookshelfdocker/metadata` | Audiobookshelf application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |
| `/Volume1/DockerAppData/audiobookshelfdocker/audiobooks` | Audiobookshelf application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |

## Privacy

This application runs entirely on your NAS. **The developer does not collect, receive or
have access to any data processed by the application.** No telemetry, no analytics, no
account.

| Topic | Detail |
|---|---|
| Data processed | Configuration, database, caches, logs and the files you create with the app. |
| Where it is stored | `/Volume1/DockerAppData/audiobookshelfdocker/{config,metadata,audiobooks}` (database, metadata, library). |
| Retention period | Until **you** delete it; logs are rotated or size-limited by the application. |
| Your rights | Access/export by copying the data location; correct in the app; delete with `apt purge` / “delete data”. |
| Deletion channel | Remove the data yourself, or email **moechz@163.com** (answered within 30 days). |
| Security measures | Dedicated unprivileged system user, only the required ports, rebuilt on upstream fixes. |
| Children | Not directed at children. |

**Full privacy policy:** [PRIVACY.md](PRIVACY.md) — <https://github.com/Moechz/audiobookshelf/blob/main/PRIVACY.md>

## Third-party services (API disclosure)

The developer operates no server in this path. The app contacts only the services you
configure. Full table in [PRIVACY.md](PRIVACY.md) §6.

## Licence and attributions

| Component | Licence | Notes |
|---|---|---|
| Audiobookshelf | GPL-3.0 | upstream application |
| This packaging | GPL-3.0 (see `LICENSE`) | TOS metadata, units, scripts, translations, icon |

“Audiobookshelf”, “TerraMaster” and “TOS” are trademarks of their respective owners. This is an
independent community package by Moechz. Full details: [NOTICE.md](NOTICE.md).

## Support

- Email: moechz@163.com
- Privacy: [PRIVACY.md](PRIVACY.md) · Licence: [NOTICE.md](NOTICE.md)

## Build

```bash
scripts/build.sh                  # -> out/audiobookshelfdocker.tar.gz + .sha256
scripts/build.sh 2.37.2-2   # packaging iteration bump
scripts/build.sh 2.37.2-1 aarch64
```

The build stages the four files, substitutes the version/platform placeholders,
removes CRLF/BOM/AppleDouble, then runs
`tools/verify.py`, a review-standards self-check (archive layout, JSON validity,
required fields, 14+ language coverage, version consistency, Docker-Hub-only
images, fixed tag, reserved/recommended host ports, non-root user, per-service
healthcheck/TZ/restart, data path below the application data root, never the
`/Volume*` wildcard, comment-free sequence blocks, `x-app-meta` position, no
literal secrets and the SVG size/element limits).

## Local verification

```bash
./TOSAppSelfTestingTool -c out/audiobookshelfdocker.tar.gz   # official spec check
bash test/install-and-verify.sh                  # on-device E2E (needs root)
```

> Docker applications cannot be side-loaded through the App Center's manual
> install page (it accepts `.deb` only); the official self-testing tool's `-i`
> mode or `docker compose` are the only ways to install one for testing.

## Store submission checklist

1. Public GitHub repo (code + README only).
2. Release **tag `v2.37.2-1`**, assets `audiobookshelfdocker.tar.gz` +
   `audiobookshelfdocker.tar.gz.sha256` (Docker asset naming: `<app_id>.tar.gz`, **no
   platform suffix**).
3. Developer platform → Add Application: ID `audiobookshelfdocker`, package type Docker,
   repository URL, architecture `x86_64`.
4. Version Management → Add Version `2.37.2-1` → automated validation → review.

## License / branding

Audiobookshelf is distributed by its upstream authors under **GPL-3.0**. The container image is the official image from Docker Hub (`moechz/audiobookshelf:2.37.2`) and is used unmodified; no upstream source code is redistributed here. This packaging is an independent community submission by Moechz and is not affiliated with the upstream project or TerraMaster.

## Limitations

- The application runs inside a container; data lives in the application data directory (`/Volume1/DockerAppData/audiobookshelfdocker/`) as described above.

---

Packaged for TOS 7 by Moechz. Upstream image used unmodified from Docker Hub.
