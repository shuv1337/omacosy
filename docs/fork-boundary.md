# Fork boundary

This repository is a maintained fork of
[paulsp94/omacosy](https://github.com/paulsp94/omacosy). The product
keeps the upstream name — **omacosy** — because the fork is a
compatibility-preserving continuation, not a rebrand. What changes is
the owner, the support surface (macOS 27 beta), and a small set of
deliberate behavioral deltas. This document is the contract that keeps
those deltas from blurring during upstream merges. `./fork-check.sh`
enforces the machine-checkable parts.

## Provenance

- Upstream: `git@github.com:paulsp94/omacosy.git`, tracked as the
  `upstream` remote. Fork point: `6a4c89e`.
- License: MIT, copyright Paul Spende. The `LICENSE` file is preserved
  byte-for-byte; do not rewrite the copyright line.
- omacosy itself stands on [omarchy](https://omarchy.org)'s design;
  the README credits section must keep that attribution.

## Canonical identity (rename/own)

- Repository: `shuv1337/omacosy` — the README clone URL points here.
- Product, binary and command names are unchanged from upstream:
  `omacosy`, `omacosy-*` helpers, `theme-set`/`theme-next`.

## Deliberate deltas (fork-owned, survive every merge)

1. **Karabiner Super.** Caps Lock is the dedicated Super key, remapped
   to `cmd+ctrl+alt`. Keep Karabiner's config, install/uninstall round
   trip, and OmniWM's temporary executable-command rules in sync.
2. **Super bindings.** AeroSpace bindings use the upstream
   `cmd-ctrl-alt-*` chords so they match Karabiner and OmniWM's
   `Control+Option+Command` bindings.
3. **Night Owl theme** (`themes/night-owl/`) and the Night Owl
   Starship port (`config/starship.toml`).
4. **Hardened ffm build** in `install.sh`: staged build+sign in a
   temp dir, atomic rename, never corrupts the TCC-authorized binary.
5. **macOS 27 beta validation** documented in the README.

## Compatibility identifiers (preserve byte-for-byte)

Existing installs depend on these; renaming any of them breaks the
uninstall round-trip or a user's persisted state:

- launchd labels: `com.omacosy.bar`, `com.omacosy.borders`,
  `com.omacosy.ffm` (plus third-party `com.acsandmann.swipe`).
- Paths: `~/.local/share/omacosy` (repo/app home),
  `~/.local/state/omacosy/manifest` (uninstall manifest),
  `~/.local/bin/omacosy-*`, `/tmp/omacosy-*` logs.
- Theme convention: `~/.config/omarchy/current/theme` and the omarchy
  `colors.toml` format — external terminals follow it; every
  `themes/<name>/` ships `colors.toml`.
- Config link targets: `~/.config/aerospace`, `~/.config/ghostty`,
  `~/.config/starship.toml`, `~/.zshrc`.

## Upstream sync policy

Merges from upstream are expected and routine:

```sh
jj git fetch --all-remotes
jj new main main@upstream        # merge commit
# resolve conflicts per the delta rules above
./fork-check.sh                  # must pass before the merge lands
jj describe -m "merge: sync upstream <rev> — <summary>"
jj bookmark set main -r @ && jj git push
```

Conflict rules: upstream WM and Karabiner behavior wins; the Owl themes,
appearance sync, hardened FFM build, macOS 27 validation, `LICENSE`, and
credits survive every merge.

## Known incidental artifacts

- `handoff.md` is a frozen session document from the original macOS 27
  bring-up; it predates the Karabiner removal and describes Karabiner
  steps. Historical record — do not follow it for new installs, do not
  update it to match the current tree.
