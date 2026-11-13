#!/bin/zsh
# Removes Side Edit. File types it was default for fall back to the next app macOS knows for them.
set -euo pipefail
pkill SideEdit 2>/dev/null || true
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u ~/Applications/"Side Edit.app" 2>/dev/null || true
rm -rf ~/Applications/"Side Edit.app"
echo "Removed. If a file type still opens oddly: Get Info > Open with > pick an app > Change All."
echo "Optional: rm -rf ~/.config/side-edit"
