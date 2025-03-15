#!/usr/bin/env bash
# shfmt:

#
# HELPERS
#

CURRENT_DIR="$(readlink -e "${BASH_SOURCE[0]%/*}")"
TMUX_PRINTER="$CURRENT_DIR/tmux-printer/tmux-printer"

# $1: option
# $2: default value
tmux_get() {
    local value
    value="$(tmux show -gqv "$1")"
    [ -n "$value" ] && echo "$value" || echo "$2"
}

function set_tmux_env() {
    local option_name="$1"
    local final_value="$2"

    tmux setenv -g "$option_name" "$final_value"
}

function process_format() {
    echo -ne "$($TMUX_PRINTER "$1")"
}

function array_join() {
    local IFS="$1"
    shift
    echo "$*"
}

function gen_hint_map() {
    [[ -f "${CURRENT_DIR}/gen_hints.awk" ]] ||
        "${CURRENT_DIR}/gen_hints.py" >"${CURRENT_DIR}/gen_hints.awk"
}

#
# CONFIG
#

# Every pattern have be of form ((A)B) where:
#  - A is part that will not be highlighted (e.g. escape sequence, whitespace)
#  - B is part will be highlighted (can contain subgroups)
#
# Valid examples:
#   (( )([a-z]+))
#   (( )[a-z]+)
#   (( )(http://)[a-z]+)
#   (( )(http://)([a-z]+))
#   (( |^)([a-z]+))
#   (( |^)(([a-z]+)|(bar)))
#   ((( )|(^))|(([a-z]+)|(bar)))
#   (()([0-9]+))
#   (()[0-9]+)
#
# Invalid examples:
#   (([0-9]+))
#   ([0-9]+)
#   [0-9]+

FILE_CHARS="[[:alnum:]_.#$%&+=/@~-]"
FILE_START_CHARS="[[:space:]:<>)(&#'\"]"

# default patterns group
PATTERNS_LIST1=(
    "((^|$FILE_START_CHARS)$FILE_CHARS*/$FILE_CHARS+)"                                   # file paths with /
    "((^|\y|[^\\[])([1-9][0-9]*(\\.[0-9]+)?[kKmMgGtT])\\y)"                              # long numbers
    "((^|\y|[^\\[])[0-9]+\\.[0-9]{3,}|[0-9]{5,})"                                        # long numbers
    "(()[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"                   # UUIDs
    "(()[0-9a-f]{7,40})"                                                                 # hex numbers (e.g. git hashes)
    "(()(https?://|git@|git://|ssh://|ftp://|file:///)[[:alnum:]?=%/_.:,;~@!#$&)(*+-]*)" # URLs
    "(()[[:digit:]]{1,3}\\.[[:digit:]]{1,3}\\.[[:digit:]]{1,3}\\.[[:digit:]]{1,3})"      # IPv4 adresses
    "(()([[:digit:]a-f]{0,4}:){3,})([[:digit:]a-f]{1,4})"                                # IPv6 addresses
    "(()0x[0-9a-fA-F]+)"                                                                 # hex numbers
)

# alternative patterns group (shown after pressing the SPACE key)
PATTERNS_LIST2=(
    "((^|$FILE_START_CHARS)$FILE_CHARS*/$FILE_CHARS+)"                                   # file paths with /
    "((^|$FILE_START_CHARS)$FILE_CHARS{5,})"                                             # anything that looks like file/file path but not too short
    "(()(https?://|git@|git://|ssh://|ftp://|file:///)[[:alnum:]?=%/_.:,;~@!#$&)(*+-]*)" # URLs
)

# items that will not be hightlighted
BLACKLIST=(
    "(deleted|modified|renamed|copied|master|mkdir|[Cc]hanges|update|updated|committed|commit|working|discard|directory|staged|add/rm|checkout)"
)

# "-n M-c" for Alt-c without prefix
# "c" for prefix-c
picker_key_bind="$(tmux_get '@picker_key_bind' '-n M-c')"
picker_key_bind2="$(tmux_get '@picker_key_bind2' '-T copy-mode M-c')"
declare -a PICKER_KEY=("${picker_key_bind}" "${picker_key_bind2}")

#
# Setup
#

gen_hint_map

set_tmux_env PICKER_PATTERNS1 "$(array_join "|" "${PATTERNS_LIST1[@]}")"
set_tmux_env PICKER_PATTERNS2 "$(array_join "|" "${PATTERNS_LIST2[@]}")"
set_tmux_env PICKER_BLACKLIST_PATTERNS "$(array_join "|" "${BLACKLIST[@]}")"

# from old plugin
# set_tmux_env PICKER_COPY_COMMAND " xargs tmux send-keys -t \$current_pane_id"

# default? (requires xclip, not tested)
# set_tmux_env PICKER_COPY_COMMAND "xclip -f -in -sel primary | xclip -in -sel clipboard"

# set_tmux_env PICKER_COPY_COMMAND "xargs tmux send-keys"
# set_tmux_env PICKER_COPY_COMMAND "tmux load-buffer - && tmux paste-buffer"
# will this help with OSC52 being supported only in some terminal emulators?
# set_tmux_env PICKER_COPY_COMMAND "tmux load-buffer -w -t $(readlink /proc/self/fd/0) - && tmux paste-buffer"

# set_tmux_env PICKER_COPY_COMMAND "tee /tmp/t.txt | xargs tmux send-keys ; tmux load-buffer -w -t $(readlink /proc/self/fd/0) /tmp/t.txt ; rm -f /tmp/t.txt"
set_tmux_env PICKER_COPY_COMMAND "tmux load-buffer -w -t $(readlink /proc/self/fd/0) - && tmux paste-buffer"

# set_tmux_env PICKER_ALT_COPY_COMMAND "tmux load-buffer -w - && tmux delete-buffer -b register || true"
set_tmux_env PICKER_ALT_COPY_COMMAND "tmux load-buffer -w -t $(readlink /proc/self/fd/0) - && tmux paste-buffer"

set_tmux_env PICKER_COPY_COMMAND_UPPERCASE "bash -c 'arg=\$(cat -); arg="\${arg/#\~\\//\$HOME/}" ; arg="\${arg/#\~//home/}" ; tmux split-window -h -c \"#{pane_current_path}\" ${EDITOR} \"\$arg\"'"

#set_tmux_env PICKER_HINT_FORMAT "$(process_format "#[fg=color0,bg=color202,dim,bold]%s")"
#set_tmux_env PICKER_HINT_FORMAT "$(process_format "#[fg=black,bg=red,bold]%s")"
set_tmux_env PICKER_HINT_FORMAT "$(
    tput setaf 252
    tput setab 19
    echo -n '%s'
)"
set_tmux_env PICKER_HINT_PREFIX_FORMAT "$(
    tput setaf 252
    tput setab 88
    echo -n '%s'
)"
set_tmux_env PICKER_HINT_FORMAT_NOCOLOR "%s"

#set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(process_format "#[fg=black,bg=color227,normal]%s")"
set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(process_format "#[fg=black,bg=yellow,bold]%s")"
set_tmux_env PICKER_HIGHLIGHT_FORMAT "$(
    tput setaf 215
    tput setab 235
    echo -n '%s'
    tput sgr0
)"

#
# BIND
#

# shellcheck disable=SC2086
for key in "${PICKER_KEY[@]}"; do
    tmux bind ${key} run-shell "$CURRENT_DIR/tmux-picker.sh"
done
