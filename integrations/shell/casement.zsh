# Casement for zsh: commands that run longer than CASEMENT_MIN_SECONDS show in the notch while they
# run, then report success or failure. Add to ~/.zshrc:  source /path/to/casement.zsh
CASEMENT_MIN_SECONDS=${CASEMENT_MIN_SECONDS:-10}
zmodload zsh/datetime 2>/dev/null

_casement_preexec() {
  _casement_cmd=$1
  _casement_start=$EPOCHREALTIME
  _casement_id="shell-$$-${RANDOM}"
  # Announce only if still running after the threshold, so quick commands never flash.
  ( sleep $CASEMENT_MIN_SECONDS && casementctl set "$_casement_id" --title "${1[1,60]}" --subtitle "Running in ${PWD:t}" \
      --icon sf:terminal.fill --progress -1 --source shell --sneak false >/dev/null 2>&1 ) &!
  _casement_timer=$!
}

_casement_precmd() {
  local rc=$?
  [[ -z $_casement_start ]] && return
  kill $_casement_timer 2>/dev/null
  local elapsed=$(( EPOCHREALTIME - _casement_start ))
  if (( elapsed >= CASEMENT_MIN_SECONDS )); then
    local mins=$(( ${elapsed%.*} / 60 )) secs=$(( ${elapsed%.*} % 60 ))
    if (( rc == 0 )); then
      casementctl set "$_casement_id" --title "${_casement_cmd[1,60]}" --subtitle "Finished in ${mins}m ${secs}s" \
        --state success --progress 1 --trailing Done --ttl 15 --source shell >/dev/null 2>&1 &!
    else
      casementctl set "$_casement_id" --title "${_casement_cmd[1,60]}" --subtitle "Failed (exit $rc) after ${mins}m ${secs}s" \
        --state failure --priority high --trailing Failed --ttl 60 --source shell >/dev/null 2>&1 &!
    fi
  fi
  unset _casement_start _casement_cmd
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _casement_preexec
add-zsh-hook precmd _casement_precmd
