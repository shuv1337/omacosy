#!/usr/bin/env bash
# fork-check.sh — executable fork-boundary contract (docs/fork-boundary.md).
# Runs anywhere bash + grep exist (Linux CI or the Mac). Exit 0 = contract holds.
set -u
cd "$(dirname "$0")"

fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
ok()   { echo "  ok: $*"; }

# ---- 1. No Karabiner in executable surfaces (fork delta #1) ----
exec_surfaces=(install.sh uninstall.sh Brewfile macos-defaults.sh helper bin config zsh themes patches)
if grep -rin "karabiner" "${exec_surfaces[@]}" 2>/dev/null; then
  fail "Karabiner reference in an executable surface (allowed only in *.md)"
else
  ok "no Karabiner in executable surfaces"
fi
[ -e config/karabiner ] && fail "config/karabiner exists" || ok "config/karabiner absent"
grep -qi "capslock\|hidsystem" helper/main.swift \
  && fail "capslock/IOHIDSystem back in helper/main.swift" \
  || ok "no capslock subcommand in helper/main.swift"

# ---- 2. Super-direct bindings (fork delta #2) ----
tpl=config/aerospace/aerospace.template.toml
if grep -qE "^cmd-ctrl-alt" "$tpl"; then
  fail "cmd-ctrl-alt binding in $tpl (fork uses Super-direct cmd-* chords)"
else
  ok "all bindings Super-direct in $tpl"
fi
grep -q "^cmd-enter = 'exec-and-forget \$HOME/.local/bin/omacosy-spawn" "$tpl" \
  || fail "cmd-enter must spawn the terminal through omacosy-spawn"
grep -qE "<<<<<<<|>>>>>>>" "$tpl" && fail "conflict markers left in $tpl"

# ---- 3. Fork-owned surfaces present (deltas #3, #4) ----
[ -f themes/night-owl/colors.toml ] || fail "themes/night-owl missing"
[ -f themes/light-owl/colors.toml ] || fail "themes/light-owl missing"
grep -q 'AppleInterfaceStyle' bin/theme-sync || fail "system appearance sync missing"
grep -q "FFM_BUILD_DIR" install.sh || fail "staged ffm build gone from install.sh"

# ---- 4. Compatibility identifiers preserved ----
for label in com.omacosy.bar com.omacosy.borders com.omacosy.ffm; do
  grep -q "$label" install.sh || fail "launchd label $label missing from install.sh"
done
grep -q '\.local/state/omacosy' install.sh || fail "manifest path renamed in install.sh"
grep -q 'omarchy/current/theme' bin/theme-set || fail "omarchy theme convention gone from theme-set"
for t in themes/*/; do
  [ -f "$t/colors.toml" ] || fail "$t lacks colors.toml (omarchy format contract)"
done
ok "launchd labels, state path, theme convention intact"

# ---- 5. Provenance ----
grep -q "Copyright (c) 2026 Paul Spende" LICENSE || fail "upstream copyright line altered in LICENSE"
grep -q "omarchy.org" README.md || fail "omarchy attribution missing from README"
grep -q "github.com/shuv1337/omacosy" README.md || fail "README clone URL is not the fork"
ok "license, attribution, canonical repo URL intact"

# ---- 6. Shell syntax on everything we ship ----
for f in install.sh uninstall.sh macos-defaults.sh fork-check.sh bin/*; do
  bash -n "$f" 2>/dev/null || fail "bash syntax error: $f"
done
ok "shell syntax clean"

if [ "$fails" -gt 0 ]; then
  echo "fork-check: $fails failure(s) — see docs/fork-boundary.md" >&2
  exit 1
fi
echo "fork-check: contract holds"
