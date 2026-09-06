#!/usr/bin/env bash
# Install rrun: symlink the script into ~/.local/bin and seed ~/.config/rrun/config.
# From a checkout:  ./install.sh      Without one:  curl -fsSL <raw install.sh url> | bash
set -euo pipefail
repo="${RRUN_REPO:-git@github.com:longcw/rrun.git}"
src="${RRUN_SRC:-$HOME/code/rrun}"
bin="${RRUN_BIN:-$HOME/.local/bin}"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [ -n "$here" ] && [ -f "$here/rrun" ]; then src="$here"; elif [ ! -f "$src/rrun" ]; then git clone "$repo" "$src"; fi
mkdir -p "$bin" "$HOME/.config/rrun"
ln -sf "$src/rrun" "$bin/rrun"
[ -e "$HOME/.config/rrun/config" ] || cp "$src/config.example" "$HOME/.config/rrun/config"
echo "rrun -> $bin/rrun (from $src); config: ~/.config/rrun/config"
case ":$PATH:" in *":$bin:"*) ;; *) echo "note: $bin is not on your PATH" ;; esac
