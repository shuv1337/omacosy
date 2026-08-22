# omacosy on macOS 27 beta — computer-use agent handoff

You are taking over a partially-verified install of **omacosy** (an
omarchy-style tiling desktop for macOS) on a Mac running **macOS 27.0
Golden Gate developer beta 6 (build 26A5416b)**, Apple silicon. The
machine is disposable — nuke-and-pave is acceptable — so prefer
progress over caution, but never delete user data outside the scope
below.

Your job: finish the interactive setup that only GUI actions can do,
then run the verification pass and report results.

---

## 1. Context — what was already done

Everything scriptable is complete. Do **not** re-run `install.sh`
unless told to; it is idempotent but slow (Homebrew + casks).

- Repo lives at `/Users/shuv/repos/omacosy`. Configs are symlinked into
  `~/.config/*`, helpers built to `~/.local/bin/` and
  `~/.local/share/omacosy/omacosy-bar.app`.
- Homebrew 6.0.18 installed at `/opt/homebrew`; all Brewfile packages
  present (`aerospace` 0.21.3-Beta, `karabiner-elements`, `ghostty`,
  `raycast`, fzf/eza/zoxide/ripgrep/bat/lazygit/btop/starship/jq).
- Five Swift helpers compile and run against the macOS 27 SDK.
  Private-framework surface (SkyLight, DisplayServices) verified working.
- All launch agents are loaded and running:
  `com.omacosy.bar`, `com.omacosy.borders`, `com.omacosy.ffm`,
  `com.acsandmann.swipe`, plus AeroSpace's app agent and Karabiner's
  `karabiner_console_user_server`.
- A bug was found and fixed during this session: the bar's Activity
  pill launched bare `btop`, which Ghostty runs through `login(1)`
  whose PATH excludes `/opt/homebrew/bin`. `helper/bar.swift` now
  resolves `/opt/homebrew/bin/btop` absolutely; rebuilt, signed,
  verified end-to-end. This fix is uncommitted in the repo — leave it.
- The temp passwordless-sudo entry created during install has been
  removed. You will have no sudo; nothing below needs it.
- `~/.local/state/omacosy/manifest` was corrected so `uninstall.sh`
  will NOT remove the pre-existing Homebrew. Do not reinstall that line.

## 2. Known-good baseline (verify first)

Run these in Terminal; all should succeed:

```sh
launchctl list | grep -E "omacosy|acsandmann|aerospace|karabiner"
# expect 5+ rows, PIDs non-dash

/opt/homebrew/bin/aerospace list-workspaces --all   # lists 1..9, 11..19
pgrep -fl omacosy-bar                                # bar process alive
tail -2 /tmp/omacosy-bar.err                         # no NEW lines after boot
```

Visually confirm on screen:

- A dark themed **bar** across the top of the display (workspaces pill,
  battery, clock). If instead you see Apple's native menu bar, the
  `_HIHideMenuBar` default has not applied — log out and back in
  (System Settings → Lock Screen → Log Out), then re-check.
- A colored **border ring** around the focused window.

## 3. Interactive grants (the actual work)

Open **System Settings → Privacy & Security**. Grant each of these;
macOS requires quitting/restarting the process after some grants —
commands provided. Adding an item: click `+`, navigate with
Cmd+Shift+G ("Go to folder") and paste the path.

### Accessibility
| App | Path |
|---|---|
| AeroSpace | `/Applications/AeroSpace.app` |
| AerospaceSwipe | `~/.local/share/aerospace-swipe/AerospaceSwipe.app` |
| omacosy-ffm | `~/.local/bin/omacosy-ffm` |

After granting, restart each:

```sh
launchctl kickstart -k gui/$(id -u)/com.omacosy.ffm
launchctl kickstart -k gui/$(id -u)/com.acsandmann.swipe
```

Verify: `tail -1 /tmp/omacosy-ffm.err` must NOT say "waiting for
Accessibility permission".

### Input Monitoring + driver extension (Karabiner)
1. Launch `/Applications/Karabiner-Elements.app`.
2. Approve the **system extension** prompt when it appears (needs
   Restart in older macOS; on 27 it may activate immediately).
3. In Privacy & Security → Input Monitoring, enable Karabiner entries.
4. Verify remap works: press **Caps Lock held + T** — a terminal or
   focused app should behave as if cmd+ctrl+alt+T were pressed.
   Caps Lock tapped alone = Escape.
5. Quit the Karabiner settings window when done (the service stays).

### Prompts that appear on use (grant as they come)
- **Bluetooth** (bar): click the bluetooth pill → grant.
- **Location** (bar): wi-fi popup network name. Refusing is fine —
  popup just says "wi-fi".
- **Screen Recording** (`omacosy-overview`): appears on first swipe-up.
  Grant, then the daemon must be restarted:
  `pkill -f omacosy-overview` (it is NOT launchd-managed; it relaunches
  from aerospace-swipe on next swipe-up — or start it manually:
  `~/.local/bin/omacosy-overview &`).

## 4. Verification pass — macOS 27 specific

Do each in order; record pass/fail. These target the private-API and
beta-sensitive surfaces.

1. **Super key**: hold Caps Lock, tap 2 — workspace switches to slot 2.
2. **Tiling**: open two Ghostty windows (Cmd+N) — they should split,
   new window beside/below per dwindle rule (wide→horizontal split).
3. **Focus follows mouse**: move cursor over the unfocused window —
   focus ring moves without clicking.
4. **Alt+Tab window cycling**: Alt+Tab cycles windows on this workspace.
5. **Trackpad swipes** (highest risk on 27 — raw MultitouchSupport):
   - 4-finger swipe left/right switches workspaces.
   - 4-finger swipe up opens the workspace overview with live window
     thumbnails; Esc dismisses. If cards show icons but NO live
     thumbnails, Screen Recording wasn't granted. If swipes do nothing
     at all, the MultitouchSupport patch broke on 27 — capture
     `/tmp` logs (`ls /tmp/omacosy-*`) and report.
6. **Bar interactions**: volume scroll on the volume pill; brightness
   scroll past minimum engages the gamma shade (screen dims BELOW
   normal min; scrolling back restores). Move mouse to very top edge —
   native-style reveal shows bar over fullscreen windows.
7. **Activity pill** (gear icon): floating btop window opens. (Was
   broken; fix applied — confirm still good.)
8. **Theme switch**: run `theme-next` — bar, border ring, and wallpaper
   change together.
9. **Wi-fi SSID**: click wi-fi pill — popup shows real network name
   (needs Location grant) or "wi-fi" fallback.
10. **Workspace overview drag**: in overview, drag a card to another
    position — workspaces reorder without losing windows.

## 5. Failure signatures → what they mean

| Symptom | Meaning |
|---|---|
| bar absent + `/tmp/omacosy-bar.err` says "no display matched an aerospace monitor" | AeroSpace not running/granted yet — fix that first, then `launchctl kickstart -k gui/$(id -u)/com.omacosy.bar` |
| ffm loops "waiting for Accessibility" | grant not applied to the right binary path (must be `~/.local/bin/omacosy-ffm`) |
| Swipes dead, everything else fine | MultitouchSupport regression on 27 — rebuild test: `cd ~/.local/share/aerospace-swipe && make install`, then re-grant Accessibility (signature changed) |
| Overview opens with blank cards | ScreenCaptureKit changed; check Console.app for `omacosy-overview` crashes |
| Brightness shade leaves screen dark | gamma not restored: `launchctl kickstart -k gui/$(id -u)/com.omacosy.bar` re-inits; log out also resets |

## 6. Housekeeping rules

- The repo has ONE uncommitted change (`helper/bar.swift`, btop path).
  Keep it; do not commit unless asked.
- A leftover Ghostty window titled `omacosy-activity-test` may exist —
  safe to close.
- `uninstall.sh` reverses everything (manifest-driven) — only run if
  explicitly asked.
- Do not create the NOPASSWD sudoers entry again; nothing here needs root.
- Report format: numbered list matching §4, each PASS/FAIL + one-line
  detail, then any console/log excerpts for failures.
