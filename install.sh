#!/usr/bin/env bash
# Rounds-Linux installer: puts the `sips` stand-in and the `rounds` launcher on your PATH and checks
# what Rounds needs.
# Rounds itself is by Kris Puckett: https://github.com/krispuckett/rounds
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dest="${ROUNDS_LINUX_DEST:-${SIPS_DEST:-$HOME/.local/bin}}"
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

echo "Rounds-Linux"

# 1. Node 20+
if command -v node >/dev/null; then
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if ((major >= 20)); then ok "Node $(node --version)"; else warn "Node $(node --version) is too old; Rounds needs 20 or newer"; fi
else
  warn "Node is not installed; Rounds needs Node 20 or newer"
fi

# 2. libvips, which the sips stand-in uses
if command -v vips >/dev/null && command -v vipsheader >/dev/null; then
  ok "libvips $(vips --version 2>/dev/null | head -1 | sed 's/^vips-//')"
else
  warn "libvips is missing. Install it first:"
  echo "      Arch/CachyOS:   sudo pacman -S libvips"
  echo "      Debian/Ubuntu:  sudo apt install libvips-tools"
  echo "      Fedora:         sudo dnf install vips-tools"
  exit 1
fi

# 3. The sips stand-in and the rounds launcher (each marked, so we never overwrite someone else's)
mkdir -p "$dest"
put() { # put <file> <marker>
  if [[ -e "$dest/$1" ]] && ! grep -q "$2" "$dest/$1" 2>/dev/null; then
    warn "$dest/$1 already exists and isn't from Rounds-Linux; leaving it alone"; return 1
  fi
  install -m 755 "$here/bin/$1" "$dest/$1"
  ok "$1 installed at $dest/$1"
}
put sips "libvips stand-in" || exit 1
put rounds "from Rounds-Linux" || true
case ":$PATH:" in *":$dest:"*) ;; *) warn "$dest is not on your PATH; add it so Rounds can find sips" ;; esac
[[ "$(command -v sips || true)" == "$dest/sips" ]] || warn "another sips comes first on your PATH: $(command -v sips)"

# 4. A Chromium-based browser for page previews
found=""
for b in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable brave-browser brave; do
  command -v "$b" >/dev/null && { found="$b"; break; }
done
if [[ -n "${ROUNDS_BROWSER:-}" ]]; then
  ok "ROUNDS_BROWSER is set: $ROUNDS_BROWSER"
elif [[ -n "$found" ]]; then
  ok "Rounds will find $found for page previews"
else
  warn "No Chrome/Chromium/Edge/Brave on PATH, so page previews will be off."
  echo "      Any other Chromium-based browser works (Helium, Vivaldi, an AppImage...). Point Rounds at it:"
  echo "      bash/zsh:  export ROUNDS_BROWSER=/path/to/browser   (add to ~/.bashrc or ~/.zshrc)"
  echo "      fish:      set -Ux ROUNDS_BROWSER /path/to/browser"
fi

echo
echo "Done. Next:"
if [[ -f "${ROUNDS_HOME:-$HOME/.rounds}/app/bin/rounds.mjs" ]]; then
  echo "  rounds              open the canvas (runs your local copy, offline)"
  echo "  rounds upgrade      see what's new in Rounds and choose whether to install it"
else
  echo "  npx --allow-git=root github:krispuckett/rounds --demo   try it on sample work"
  echo "  cd ~ && npx --allow-git=root github:krispuckett/rounds init   set it up for real"
  echo "  then: rounds              open the canvas"
  echo "(npm 12+ blocks packages from GitHub unless you add --allow-git=root)"
fi
