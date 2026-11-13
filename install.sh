#!/bin/zsh
# Builds Side Edit into ~/Applications and (after asking) makes it the default app for common text/code files.
# Usage: ./install.sh [--yes]   (--yes skips the question)
set -euo pipefail
cd "$(dirname "$0")"
command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install' first."; exit 1; }
APP=~/Applications/"Side Edit.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/SideEdit" main.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

if [[ "${1:-}" != "--yes" ]]; then
  echo "Side Edit is built. Make it the default app for .md .json .yaml .py .sh .js .go .rs .sql .env .log .txt and ~30 more text/code types?"
  echo "Double-click then opens the side panel; hold ⌘ or ⇧ to use the usual app. Undo any time with ./uninstall.sh"
  read "?[y/N] " ans
  [[ "$ans" == [yY]* ]] || { echo "Left your defaults alone. Open files with right-click > Open With > Side Edit."; exit 0; }
fi

# Folders are not touched: Finder keeps opening them; use Open With › Antigravity for those.
swift - "$APP" <<'EOF'
import AppKit
import UniformTypeIdentifiers
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let ids = ["net.daringfireball.markdown", "public.plain-text", "public.json", "public.yaml",
           "public.python-script", "public.shell-script", "public.zsh-script", "com.netscape.javascript-source", "public.swift-source"]
// Extensions with no (or a dynamic) system type, e.g. go. Left out on purpose: ts (MPEG video), html/csv/svg (other apps own them).
let exts = ["go", "rs", "tsx", "jsx", "mjs", "cjs", "css", "scss", "c", "h", "cpp", "hpp", "java", "kt", "rb", "php", "sql", "toml", "ini",
            "cfg", "conf", "env", "log", "txt", "sh", "bash", "zsh", "lua", "r", "scala", "dart", "vue", "svelte", "tf", "gradle"]
let types = ids.map { UTType($0) } + exts.map { UTType(filenameExtension: $0) }
var pending = 0
for (i, t) in types.enumerated() {
    guard let t else { print("skip \(i)"); continue }
    let id = t.identifier
    pending += 1
    NSWorkspace.shared.setDefaultApplication(at: app, toOpen: t) { err in
        print(id, err.map { "FAILED: \($0.localizedDescription)" } ?? "ok"); DispatchQueue.main.async { pending -= 1 }
    }
}
while pending > 0 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
EOF
