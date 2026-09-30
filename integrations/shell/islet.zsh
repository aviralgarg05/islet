# Islet for zsh: commands that run longer than ISLET_MIN_SECONDS show in the notch while they
# run, then report success or failure. Add to ~/.zshrc:  source /path/to/islet.zsh
ISLET_MIN_SECONDS=${ISLET_MIN_SECONDS:-10}
zmodload zsh/datetime 2>/dev/null

_islet_preexec() {
  _islet_cmd=$1
  _islet_start=$EPOCHREALTIME
  _islet_id="shell-$$-${RANDOM}"
  # Announce only if still running after the threshold, so quick commands never flash.
  ( sleep $ISLET_MIN_SECONDS && isletctl set "$_islet_id" --title "${1[1,60]}" --subtitle "Running in ${PWD:t}" \
      --icon sf:terminal.fill --progress -1 --source shell --sneak false >/dev/null 2>&1 ) &!
  _islet_timer=$!
}

_islet_precmd() {
  local rc=$?
  [[ -z $_islet_start ]] && return
  kill $_islet_timer 2>/dev/null
  local elapsed=$(( EPOCHREALTIME - _islet_start ))
  if (( elapsed >= ISLET_MIN_SECONDS )); then
    local mins=$(( ${elapsed%.*} / 60 )) secs=$(( ${elapsed%.*} % 60 ))
    if (( rc == 0 )); then
      isletctl set "$_islet_id" --title "${_islet_cmd[1,60]}" --subtitle "Finished in ${mins}m ${secs}s" \
        --state success --progress 1 --trailing Done --ttl 15 --source shell >/dev/null 2>&1 &!
    else
      isletctl set "$_islet_id" --title "${_islet_cmd[1,60]}" --subtitle "Failed (exit $rc) after ${mins}m ${secs}s" \
        --state failure --priority high --trailing Failed --ttl 60 --source shell >/dev/null 2>&1 &!
    fi
  fi
  unset _islet_start _islet_cmd
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _islet_preexec
add-zsh-hook precmd _islet_precmd
