#!/bin/bash
# play.sh — fast terminal music player
# deps: yt-dlp, mpv, jq, socat, bc

# ─── Config ───────────────────────────────────────────────────────────────────
SOCK="/tmp/play.sock"
REC_FILE="/tmp/play.rec"          # background recommendation drop-file

# ─── State ────────────────────────────────────────────────────────────────────
declare -a IDS=()
declare -a TITLES=()
IDX=0
PLAYING=false
REPEAT=false
FETCHING=false

# ─── Cleanup ──────────────────────────────────────────────────────────────────
_quit() {
    echo -e "\n\e[33mBye.\e[0m"
    socat_cmd '{"command":["quit"]}' 2>/dev/null
    rm -f "$SOCK" "$REC_FILE" "$REC_FILE.seen"
    pkill -x mpv 2>/dev/null
    exit 0
}
trap _quit SIGINT SIGTERM

# ─── MPV helpers ──────────────────────────────────────────────────────────────
socat_cmd() { [[ -S "$SOCK" ]] && printf '%s\n' "$1" | socat - "$SOCK" 2>/dev/null; }

mpv_get() {
    local r
    r=$(printf '{"command":["get_property","%s"]}\n' "$1" | socat - "$SOCK" 2>/dev/null)
    jq -r '.data // empty' <<< "$r"
}

# Start mpv once; wait max 2s for socket
_start_mpv() {
    pgrep -x mpv &>/dev/null && return
    mpv \
        --idle=yes \
        --input-ipc-server="$SOCK" \
        --audio-display=no \
        --no-terminal \
        --really-quiet \
        --cache=yes \
        --demuxer-max-bytes=2MiB \
        --demuxer-readahead-secs=8 \
        --ytdl-format="bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio" \
        2>/dev/null &
    local i=0
    until [[ -S "$SOCK" ]] || (( i++ >= 20 )); do sleep 0.1; done
}

# ─── Playback ─────────────────────────────────────────────────────────────────
_play() {
    [[ $IDX -ge ${#IDS[@]} ]] && return
    _start_mpv
    local id="${IDS[$IDX]}"
    local title="${TITLES[$IDX]}"
    echo "$id" >> "$REC_FILE.seen"
    echo -e "\r\e[K\e[35m▶  \e[0m$title"
    socat_cmd "{\"command\":[\"loadfile\",\"https://www.youtube.com/watch?v=$id\"]}"
    PLAYING=true
}

# ─── Search — fastest: flat-playlist, no extra metadata ───────────────────────
_search() {
    yt-dlp \
        --quiet --no-warnings \
        --flat-playlist \
        --no-playlist \
        --print "%(id)s" \
        --print "%(title)s" \
        "ytsearch1:$1" 2>/dev/null
}

# ─── Add song ─────────────────────────────────────────────────────────────────
cmd_add() {
    [[ -z "$1" ]] && echo "Usage: add <search query>" && return
    echo -e "\e[36m⏳ Searching…\e[0m"
    local out; out=$(_search "$1")
    local id; id=$(sed -n '1p' <<< "$out")
    local title; title=$(sed -n '2p' <<< "$out")
    if [[ -z "$id" ]]; then
        echo -e "\e[31m✗ Not found\e[0m"; return
    fi
    IDS+=("$id"); TITLES+=("$title")
    echo -e "\e[32m+ $title\e[0m"
    $PLAYING || _play
}

# ─── Autoplay: fetch radio recommendation in background ───────────────────────
_fetch_rec() {
    $FETCHING && return
    [[ ${#IDS[@]} -eq 0 ]] && return
    FETCHING=true
    local cur_id="${IDS[$IDX]}"
    (
        local out
        out=$(yt-dlp --quiet --no-warnings --flat-playlist \
            --print "%(id)s|%(title)s" \
            --playlist-items 2-10 \
            "https://www.youtube.com/watch?v=${cur_id}&list=RD${cur_id}" 2>/dev/null)
        while IFS= read -r line; do
            local vid="${line%%|*}"
            [[ -z "$vid" ]] && continue
            if ! grep -qF "$vid" "$REC_FILE.seen" 2>/dev/null; then
                echo "$line" > "$REC_FILE"
                break
            fi
        done <<< "$out"
    ) &
    FETCHING=false
}

_consume_rec() {
    [[ ! -f "$REC_FILE" ]] && return
    local line; line=$(< "$REC_FILE"); rm -f "$REC_FILE"
    [[ -z "$line" ]] && return
    local id="${line%%|*}"; local title="${line#*|}"
    IDS+=("$id"); TITLES+=("$title")
    echo -e "\r\e[K\e[33m↻  Autoplay queued: $title\e[0m"
}

# ─── Navigation ───────────────────────────────────────────────────────────────
cmd_next() {
    if (( IDX + 1 >= ${#IDS[@]} )); then
        _fetch_rec
        local wait=0
        until [[ -f "$REC_FILE" ]] || (( wait++ >= 30 )); do sleep 0.1; done
        _consume_rec
    fi
    (( IDX++ )); _play
}

cmd_prev() {
    if (( IDX > 0 )); then (( IDX-- )); _play
    else echo "Already at first track."; fi
}

# ─── Queue display ────────────────────────────────────────────────────────────
cmd_queue() {
    echo -e "\e[34m─── Queue ───\e[0m"
    if [[ ${#TITLES[@]} -eq 0 ]]; then
        echo "  (empty)"; return
    fi
    for i in "${!TITLES[@]}"; do
        if (( i == IDX )); then
            echo -e " \e[32m▶ [$((i+1))] ${TITLES[$i]}\e[0m"
        else
            echo "   [$((i+1))] ${TITLES[$i]}"
        fi
    done
}

# ─── Status line ──────────────────────────────────────────────────────────────
cmd_status() {
    if ! $PLAYING; then echo "Not playing."; return; fi
    local pos; pos=$(mpv_get "time-pos")
    local dur; dur=$(mpv_get "duration")
    local paused; paused=$(mpv_get "pause")
    local state="▶"
    [[ "$paused" == "true" ]] && state="⏸"
    printf "%s  %s  [%s / %s]\n" \
        "$state" "${TITLES[$IDX]}" \
        "$(printf '%d:%02d' $(( ${pos%.*} / 60 )) $(( ${pos%.*} % 60 )) 2>/dev/null)" \
        "$(printf '%d:%02d' $(( ${dur%.*} / 60 )) $(( ${dur%.*} % 60 )) 2>/dev/null)"
}

# ─── Help ─────────────────────────────────────────────────────────────────────
_help() {
    cat <<'EOF'

  add <query>   search & queue a song
  next / prev   skip tracks
  pause         pause playback
  resume        resume playback
  status        show current track + time
  repeat        toggle repeat current track
  queue         show queued tracks
  help          show this
  q / quit      exit

EOF
}

# ─── Boot ─────────────────────────────────────────────────────────────────────
pkill -x mpv 2>/dev/null
rm -f "$SOCK" "$REC_FILE" "$REC_FILE.seen"
_start_mpv   # warm up mpv before first song so first add is instant

echo -e "\e[36m♪  Terminal Player\e[0m  (type \e[33mhelp\e[0m)"

# ─── Main loop ────────────────────────────────────────────────────────────────
while true; do
    _consume_rec

    if $PLAYING && [[ -S "$SOCK" ]]; then
        rem=$(mpv_get "time-remaining")
        if [[ -n "$rem" && "$rem" != "null" ]]; then
            # Pre-fetch 15s before end so next track is ready
            if (( $(bc -l <<< "$rem < 15") )) && (( IDX + 1 >= ${#IDS[@]} )); then
                _fetch_rec
            fi
            # Advance when < 1s left
            if (( $(bc -l <<< "$rem < 1") )); then
                if $REPEAT; then
                    _play
                else
                    _consume_rec
                    (( IDX++ )); _play
                fi
            fi
        fi
    fi

    echo -ne "\r\e[K\e[36m❯ \e[0m"
    if read -r -t 1 input; then
        [[ -z "$input" ]] && continue
        cmd="${input%% *}"
        arg="${input#* }"; [[ "$arg" == "$cmd" ]] && arg=""
        case "$cmd" in
            add)    cmd_add "$arg" ;;
            next)   cmd_next ;;
            prev)   cmd_prev ;;
            pause)  socat_cmd '{"command":["set_property","pause",true]}' ;;
            resume) socat_cmd '{"command":["set_property","pause",false]}' ;;
            status) cmd_status ;;
            repeat)
                if $REPEAT; then REPEAT=false; echo "Repeat OFF"
                else REPEAT=true; echo "Repeat ON"; fi ;;
            queue)  cmd_queue ;;
            help)   _help ;;
            q|quit) _quit ;;
            *)      echo "Unknown: '$cmd'  (type help)" ;;
        esac
    fi
done
