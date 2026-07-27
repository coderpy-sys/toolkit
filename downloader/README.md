# Convoy Templates Downloader (vendored)

Vendored from [ConvoyPanel/downloader](https://github.com/ConvoyPanel/downloader).

Used by `potterhead.sh` **Option 6 → d** to compile from source on the Proxmox host
instead of downloading the `downloader_x86` GitHub Release binary (which is often unavailable).

## What it does

1. Reads `https://images.cdn.convoypanel.com/images.json` (or a custom URL)
2. Downloads each template `.vma` / `.vma.zst` backup from the CDN
3. Restores with `qmrestore` onto your chosen storage

## Build on Proxmox

```bash
cd downloader
bash build.sh
# → target/release/downloader

./target/release/downloader
# or:
CONVOY_STORAGE=local-lvm ./target/release/downloader --storage=local-lvm
./target/release/downloader --storage=local-lvm https://images.cdn.convoypanel.com/images.json
```

Selective installs (all / by group / by number) are handled by `potterhead.sh` Option 6
using the same CDN backups + `qmrestore` path — no release binary required.
