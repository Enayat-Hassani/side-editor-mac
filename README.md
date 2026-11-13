# Side Edit

A tiny macOS text editor that opens as a panel over the right side of your Finder window, where the preview pane sits. Fix a line in a `.md`, `.env`, `.json` or `.yaml` file without leaving Finder or opening a full editor.

- **Double-click** a file: the side panel opens next to it (also works with Finder in full screen).
- **⌘ or ⇧ + double-click**: opens the file in its usual app instead.
- **Esc, ⌘W, ⌘S, or clicking back into Finder**: saves and closes. No save prompts.
- **⌘E**: open the current file in its usual app. **⌘⌫**: move the file to the Trash.
- No Dock icon, no windows left behind. Plain text only, no syntax highlighting (Markdown headings are styled).

## Install

Needs macOS 13+ and the Swift compiler (`xcode-select --install`).

```bash
git clone <this repo> && cd side-editor-mac
./install.sh
```

The script builds `~/Applications/Side Edit.app`, then asks before making it the default app for about 40 text and code types (md, json, yaml, py, sh, js, go, rs, sql, env, log, txt and more). Say no and use right-click > Open With instead. `./install.sh --yes` skips the question. Folders and `.ts`, `.html`, `.csv`, `.svg` files are left alone.

## Usual apps

⌘E and ⌘-double-click use the first installed app from a list: `.sql` goes to MySQL Workbench or DBeaver, everything else to VS Code or Antigravity. Change it in `~/.config/side-edit/apps.json`:

```json
{ "sql": ["TablePlus"], "default": ["Zed", "Visual Studio Code"] }
```

Keys are file extensions; `default` covers the rest. Values are app names from `/Applications` or `~/Applications`, without `.app`.

## Uninstall

```bash
./uninstall.sh
```

File types fall back to the next app macOS knows for them. If one still opens oddly: Get Info > Open with > choose an app > Change All.

## Limits

- UTF-8 files only; other encodings show an error.
- The panel position follows the frontmost Finder window; with no Finder window it centres on screen.
- The app is ad-hoc signed locally, so there is no pre-built download.

MIT licensed.
