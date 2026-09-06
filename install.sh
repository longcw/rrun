#!/usr/bin/env bash
# Install rrun: put the single script in ~/.local/bin and seed ~/.config/rrun/config. No checkout is kept.
#   curl -fsSL https://raw.githubusercontent.com/longcw/rrun/main/install.sh | bash          (public repo)
#   gh api repos/longcw/rrun/contents/install.sh -H 'Accept: application/vnd.github.raw' | bash   (private repo)
#   ./install.sh                                                                             (from a checkout)
set -euo pipefail
repo="${RRUN_REPO:-longcw/rrun}"
ref="${RRUN_REF:-main}"
bin="${RRUN_BIN:-$HOME/.local/bin}"
mkdir -p "$bin" "$HOME/.config/rrun"
rm -f "$bin/rrun"   # may be a symlink from an older install

here="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || true)"
if [ -n "$here" ] && [ -f "$here/rrun" ]; then
    cp "$here/rrun" "$bin/rrun"
elif curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/rrun" -o "$bin/rrun.tmp" 2>/dev/null; then
    mv "$bin/rrun.tmp" "$bin/rrun"
elif command -v gh >/dev/null && gh api "repos/$repo/contents/rrun?ref=$ref" -H 'Accept: application/vnd.github.raw' > "$bin/rrun.tmp" 2>/dev/null; then
    mv "$bin/rrun.tmp" "$bin/rrun"
else
    rm -f "$bin/rrun.tmp"
    tmp="$(mktemp -d)"
    git clone -q --depth 1 --branch "$ref" "git@github.com:$repo.git" "$tmp/rrun"
    cp "$tmp/rrun/rrun" "$bin/rrun"
    rm -rf "$tmp"
fi
chmod +x "$bin/rrun"

[ -e "$HOME/.config/rrun/config" ] || cat > "$HOME/.config/rrun/config" <<'CFG'
# rrun hosts: one `name = ssh-target [ssh options]` per line, and which one is the default.
# `rrun -H <name>` picks one; `rrun -H user@host -p 22 -i ~/.ssh/key <cmd>` needs no entry here.
# vps = root@vps.example.com -p 22 -i ~/.ssh/id_ed25519
# default = vps
CFG

echo "installed $("$bin/rrun" -V) at $bin/rrun; hosts: ~/.config/rrun/config"
case ":$PATH:" in *":$bin:"*) ;; *) echo "note: $bin is not on your PATH" ;; esac
