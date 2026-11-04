#!/bin/bash
# Records the demo in docs/: stacks, focus, thirds, halves, maximize and the window picker, with
# the hotkey for each step shown on screen.
#
#   Contrib/demo/record.sh [output dir]        default: docs
#
# Writes demo.mp4, demo.gif, stacks.png, thirds.png and picker.png.
#
# Needs the agent running with its Accessibility grant, Screen Recording for the terminal this
# runs in, ffmpeg and kitty on PATH, and TextEdit not running.
#
# While it records, every application is hidden and the desktop is covered, and the only windows
# on screen are TextEdit documents holding copies of this repository's sources and a terminal
# running `spikot-wm list`, so nothing personal is captured. Everything is put back on exit,
# including after an error or Ctrl-C.
#
# The keys shown are the ones the config binds to each command, read from `spikot-wm config`; a
# step whose command has no binding shows the command line instead. The commands themselves go
# over the CLI or the agent's socket, because posted key events do not trigger Carbon hotkeys
# (see manual-tests.org). Keys typed into the picker are posted for real, through the agent's
# `exec`: posting needs Accessibility, and a child of the agent has the agent's grant. The agent
# is activated with `open` before a picker opens, because a picker opened from the socket cannot
# otherwise become the key window and is dismissed after 0.4 s.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=$(mkdir -p "${1:-$repo/docs}" && cd "${1:-$repo/docs}" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/spikot-demo.XXXXXX")
wm=$(command -v spikot-wm) || { echo "record.sh: spikot-wm is not on PATH" >&2; exit 1; }
socket=${SPIKOT_SOCKET:-$HOME/.local/state/spikot-wm/agent.sock}
agent_bundle=org.traf.spikot-wm

die() { echo "record.sh: $*" >&2; exit 1; }
command -v ffmpeg >/dev/null || die "ffmpeg is not on PATH"
kitty=$(command -v kitty) || die "kitty is not on PATH"
pgrep -xq TextEdit && die "TextEdit is running; quit it first, so its documents are neither captured nor closed"
# doctor exits non-zero when any check fails, and Accessibility does for a terminal without its
# own grant, so its output is read rather than its status.
doctor=$("$wm" doctor 2>/dev/null || true)
grep -q '^agent .*running' <<<"$doctor" || die "the agent is not running"

for tool in apps overlay; do
    swiftc -swift-version 5 -O -o "$work/$tool" "$here/$tool.swift" 2>&1 | grep -v 'ld: warning' || true
    [ -x "$work/$tool" ] || die "could not build $tool.swift"
done
"$wm" config | sed 1d > "$work/config.json"

# --- talking to the agent -------------------------------------------------------------------

# ipc <cmd> [key=value...]: one request over the agent's socket.
ipc() {
    python3 - "$socket" "$@" <<'EOF'
import json, socket, sys
path, cmd, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
s = socket.socket(socket.AF_UNIX)
s.connect(path)
request = {"v": 1, "id": "demo", "cmd": cmd, "args": dict(p.split("=", 1) for p in pairs)}
s.sendall((json.dumps(request) + "\n").encode())
reply = json.loads(s.makefile().readline())
if not reply.get("ok"):
    sys.exit("agent refused %s: %s" % (cmd, reply))
EOF
}

binding() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["hotkeys"].get(sys.argv[2], ""))' \
        "$work/config.json" "$1"
}

# run <window id or -> <command words...>: what a hotkey bound to that command would do.
run() {
    local window=$1; shift
    case $1 in
        pick)
            open -b "$agent_bundle"; sleep 0.4
            if [ $# -gt 1 ]; then ipc pick app="$2"; else ipc pick; fi ;;
        launch)
            open -b "$agent_bundle"; sleep 0.4
            "$wm" "$@" >/dev/null ;;
        place)
            "$wm" "$@" --window "$window" >/dev/null ;;
        *)
            "$wm" "$@" >/dev/null ;;
    esac
}

# --- the steps the demo is written in -------------------------------------------------------

show() {
    [ -e "$work/leaked" ] && die "a window that is not part of the demo appeared, so nothing was kept: $(cat "$work/leaked")"
    printf '%s\t%s\n' "$1" "$2" >&3
}

# press <key> [window]: show a configured hotkey and do what the config binds it to.
press() {
    local command
    command=$(binding "$1")
    [ -n "$command" ] || die "the config binds nothing to $1"
    show "$1" "$command"
    # shellcheck disable=SC2086 # the bound command is split into words, as the agent does
    run "${2:--}" $command
    sleep 2.4
}

# cli <window or -> <words...>: a step with no binding, shown as its command line.
cli() {
    local window=$1; shift
    show "" "spikot-wm $*"
    run "$window" "$@"
    sleep 2.4
}

# keys <key or text...>: keys typed into the picker. Text is shown one cap per character.
keys() {
    local shown=() token
    for token in "$@"; do
        case $token in
            return|escape|up|down|left|right|tab|space|delete) shown+=("$token") ;;
            *) shown+=($(printf '%s' "$token" | sed 's/./& /g')) ;;
        esac
    done
    show "${shown[*]}" "${caption:-}"
    ipc exec command="$work/apps keys $*"
    sleep 1.4
}

front() { "$wm" focus --window "$1" >/dev/null; sleep 0.8; }

still() { screencapture -x -R"$crop" "$work/$1.png"; }

window_id() { "$wm" list | awk -F'\t' -v app="$1" -v title="$2" '$3 == app && $5 == title { print $1; exit }'; }

# Every window on screen that is not one of the demo's. TextEdit was not running before the
# demo opened its documents, so any TextEdit window is one of them.
foreign_windows() {
    "$wm" list | awk -F'\t' 'NR > 1 && $3 != "TextEdit" && !($3 == "kitty" && $5 == "spikot-wm list") {
        print $3 " \"" $5 "\"" }'
}

# Runs for as long as the recording does. A window that is not the demo's, such as an application
# coming back from hidden, stops the recording, and `show` then ends the script without keeping
# any of it.
watch_windows() {
    local leaked
    while sleep 0.5; do
        leaked=$(foreign_windows)
        [ -z "$leaked" ] && continue
        printf '%s\n' "$leaked" > "$work/leaked"
        kill -INT "$recorder"
        return
    done
}

# hide_everything [pid...]: hide every application but those, until no window is on screen but
# the demo's. Hiding the active application makes macOS activate, and so unhide, another one,
# so this goes round more than once.
hide_everything() {
    for _ in $(seq 10); do
        "$work/apps" hide "$work/hidden" "$@" >/dev/null
        sleep 0.6
        [ -z "$(foreign_windows)" ] && return
    done
    die "could not hide every window; still on screen: $(foreign_windows)"
}

# --- set up, and put everything back on exit ------------------------------------------------

spelling=$(defaults read com.apple.TextEdit CheckSpellingWhileTyping 2>/dev/null || echo absent)

cleanup() {
    set +e
    exec 3>&-
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    [ -n "${recorder:-}" ] && kill -INT "$recorder" 2>/dev/null && wait "$recorder"
    [ -n "${terminal_pid:-}" ] && kill "$terminal_pid"
    [ -n "${opened_textedit:-}" ] && pkill -x TextEdit
    [ -n "${spelling_written:-}" ] && case $spelling in
        absent) defaults delete com.apple.TextEdit CheckSpellingWhileTyping 2>/dev/null ;;
        1) defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool true ;;
        *) defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool false ;;
    esac
    "$work/apps" show "$work/hidden" >/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

hide_everything
mkfifo "$work/keys"
"$work/overlay" < "$work/keys" &
exec 3>"$work/keys"

# Each document is one of this repository's sources as rich text, on a page of its own colour
# under a heading with its name, so the three TextEdit windows can be told apart at a glance.
python3 - "$repo/Sources/StateCore" "$work" <<'PYTHON'
import html, sys
sources, work = sys.argv[1:]
for name, page, ink in [("geometry", "#dbeafe", "#1e3a8a"), ("hotkeys", "#dcfce7", "#14532d"),
                        ("placement", "#fef3c7", "#78350f")]:
    code = html.escape(open(f"{sources}/{name}.swift").read())
    open(f"{work}/{name}.html", "w").write(
        f'<html><body style="background-color:{page}">'
        f'<h1 style="font-family:Helvetica;font-size:28px;color:{ink}">{name}.swift</h1>'
        f'<pre style="font-family:Menlo;font-size:12px">{code}</pre></body></html>')
PYTHON
for name in geometry hotkeys placement; do
    textutil -convert rtf "$work/$name.html" -output "$work/$name.rtf"
done
# TextEdit underlines most identifiers in code. Its preferences live in its sandbox container,
# which macOS may refuse to let this terminal write, so this is best-effort.
if defaults write com.apple.TextEdit CheckSpellingWhileTyping -bool false 2>/dev/null; then
    spelling_written=1
else
    echo "record.sh: could not turn off TextEdit's spell checking; misspelling marks will show" >&2
fi
opened_textedit=1
open -F -a TextEdit "$work/geometry.rtf" "$work/hotkeys.rtf" "$work/placement.rtf"
# A kitty of its own, without the user's configuration, whatever kitty is already running.
PATH="$(dirname "$wm"):/usr/bin:/bin" "$kitty" --config NONE --title "spikot-wm list" \
    -o font_size=14 -o confirm_os_window_close=0 -o remember_window_size=no \
    bash --noprofile --norc "$here/term.sh" >/dev/null 2>&1 &
terminal_pid=$!

for _ in $(seq 40); do
    G=$(window_id TextEdit geometry.rtf); H=$(window_id TextEdit hotkeys.rtf)
    P=$(window_id TextEdit placement.rtf); L=$(window_id kitty "spikot-wm list")
    [ -n "$G" ] && [ -n "$H" ] && [ -n "$P" ] && [ -n "$L" ] && break
    sleep 0.5
done
[ -n "$L" ] || die "the demo windows did not appear"
# Again, now that the demo's own processes can be told apart: starting them can bring back an
# application hidden earlier.
hide_everything "$(pgrep -x TextEdit)" "$terminal_pid"

crop=$("$work/apps" crop)
screencapture -x -v -R"$crop" "$work/demo.mov" &
recorder=$!
watch_windows &
watcher=$!
sleep 1.5

# --- the demo -------------------------------------------------------------------------------

# One window per column, and the third document in the first column under the first.
front "$G"; cli "$G" place 0
front "$L"; cli "$L" place 1
front "$H"; cli "$H" place 2
front "$P"; cli "$P" place 0
sleep 0.6; still stacks

# Focus moves between columns, and up and down within one.
press alt-l
press alt-l
press alt-h
press alt-h
press alt-j
press alt-k

# A third and two thirds fill the width, either way round.
front "$G"; press cmd-shift-3 "$G"
front "$L"; press cmd-shift-7 "$L"
still thirds
press cmd-shift-6 "$L"
front "$G"; press cmd-shift-5 "$G"

# Halves.
front "$H"; press cmd-shift-1 "$H"
front "$P"; press cmd-shift-2 "$P"

# Maximize, and back to where the window was.
front "$L"; press cmd-alt-f "$L"
cli "$L" place restore

# The picker over every window: move down the list, or type to filter.
press alt-v
still picker
caption="move" keys down down
caption="pick" keys return
sleep 0.6
press alt-v
caption="filter" keys geo
caption="pick" keys return
sleep 0.6

# The picker over one application's windows, which launch shows when it has several.
front "$L"
cli - launch TextEdit
caption="move" keys down
caption="pick" keys return
sleep 0.6

# Back to the columns.
front "$G"; cli "$G" place 0
front "$L"; cli "$L" place 1
front "$H"; cli "$H" place 2
sleep 1

[ -e "$work/leaked" ] && die "a window that is not part of the demo appeared, so nothing was kept: $(cat "$work/leaked")"
kill "$watcher"; watcher=
kill -INT "$recorder"; wait "$recorder"; recorder=

for name in stacks thirds picker; do
    sips -Z 1800 "$work/$name.png" --out "$out/$name.png" >/dev/null
done

ffmpeg -v error -y -i "$work/demo.mov" -vf "scale=1800:-2" -c:v libx264 -pix_fmt yuv420p -crf 22 \
    -movflags +faststart "$out/demo.mp4"
ffmpeg -v error -y -i "$work/demo.mov" \
    -vf "fps=10,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
    "$out/demo.gif"
ls -l "$out"/demo.mp4 "$out"/demo.gif "$out"/{stacks,thirds,picker}.png
