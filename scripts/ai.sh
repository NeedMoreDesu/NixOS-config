#!/usr/bin/env bash
set -euo pipefail

# Local AI service toggle. The registry is intentionally plain data: keep it
# in sync with the systemd user services in home/local-ai.nix and
# home/embeddings.nix.
#
#   unit|kind|rank|label|aliases|fetch-command|model-path
#
# rank is only used by -e/--embeddings and -l/--llm to pick the best service
# of that kind (lower wins).
services=(
  "llama-inkling|llm|10|Inkling 2 Mini|inkling incl ink|fetch-inkling|$HOME/models/inkling-2-mini/Inkling-2-Mini-UD-Q4_K_M.gguf"
  "llama-embed|embeddings|10|EmbeddingGemma 2|embeddinggemma embedding embed emb gemma|fetch-embeddinggemma2|$HOME/models/embeddinggemma-2/embeddinggemma-2-Q8_0.gguf"
)

usage() {
  cat <<'EOF'
usage: ai [on|off|restart|status|list] [TARGET...]

  on [TARGET...]       start and enable (no target: all services)
  off [TARGET...]      stop and disable
  restart [TARGET...]  restart
  status [TARGET...]   show service state
  list                 list known services

targets (on/off/restart/status):
  -e, --embeddings     best embedding service
  -l, --llm            best LLM service
  -a, --all            every service
  NAME                 case-insensitive partial match on unit, label or alias
                       (e.g. gemma, InCl, llama)

examples:
  ai on
  ai off
  ai on -e
  ai on -l
  ai on gemma
  ai off incl
  ai status InCl
  ai status GEMMA
EOF
}

die() {
  echo "ai: $*" >&2
  exit 2
}

declare -a sel=()

add() {
  local u
  for u in "${sel[@]}"; do
    [[ $u == "$1" ]] && return
  done
  sel+=("$1")
}

best_of_kind() {
  local want=$1 entry unit kind rank label aliases hint model best="" best_rank=""
  while IFS='|' read -r unit kind rank label aliases hint model; do
    [[ $kind == "$want" ]] || continue
    if [[ -z $best || $rank -lt $best_rank ]]; then
      best=$unit
      best_rank=$rank
    fi
  done <<<"$(printf '%s\n' "${services[@]}")"
  [[ -n $best ]] || die "no service of kind '$want' is configured"
  add "$best"
}

add_all() {
  local entry unit kind rank label aliases hint model
  while IFS='|' read -r unit kind rank label aliases hint model; do
    add "$unit"
  done <<<"$(printf '%s\n' "${services[@]}")"
}

# Partial, case-insensitive match on unit + label + aliases. Hyphens,
# underscores and spaces are ignored so "embeddinggemma" also matches
# "embedding-gemma". Too-short names are rejected: use -e/-l instead of a
# one-letter pattern that would match half the registry.
add_name() {
  local q=${1,,} entry unit kind rank label aliases hint model hay compact
  if [[ ${#q} -gt 1 ]]; then
    while IFS='|' read -r unit kind rank label aliases hint model; do
      hay="${unit,,} ${label,,} ${aliases,,}"
      compact=${hay//[-_ ]/}
      if [[ $hay == *"$q"* || $compact == *"${q//[-_ ]/}"* ]]; then
        add "$unit"
      fi
    done <<<"$(printf '%s\n' "${services[@]}")"
  else
    die "target '$1' is too short; use -e/--embeddings or -l/--llm"
  fi
}

resolve_targets() {
  local t
  for t in "$@"; do
    case "$t" in
      -e | --embedding | --embeddings) best_of_kind embeddings ;;
      -l | --llm | --llms) best_of_kind llm ;;
      -a | --all | all | everything | '*') add_all ;;
      *) add_name "$t" ;;
    esac
  done
}

info() {
  local unit=$1 entry kind rank label aliases hint model
  while IFS='|' read -r entry_unit kind rank label aliases hint model; do
    [[ $entry_unit == "$unit" ]] || continue
    printf '  %-14s %s  (%s)\n' "$unit" "$label" "$hint"
    if [[ ! -e $model ]]; then
      printf '    model missing: %s\n    fetch with: %s\n' "$model" "$hint"
    fi
    return
  done <<<"$(printf '%s\n' "${services[@]}")"
}

state() {
  local unit=$1 active enabled
  active=$(systemctl --user is-active "$unit" 2>/dev/null || true)
  enabled=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
  printf '%-14s %-9s %-9s\n' "$unit" "${active:-unknown}" "${enabled:-unknown}"
}

do_status() {
  local unit
  if ((${#sel[@]})); then
    printf '%-14s %-9s %-9s\n' UNIT ACTIVE ENABLED
    for unit in "${sel[@]}"; do state "$unit"; done
  else
    printf '%-14s %-9s %-9s\n' UNIT ACTIVE ENABLED
    for unit in "${services[@]%%|*}"; do state "$unit"; done
  fi
}

do_list() {
  local unit kind rank label aliases hint model
  printf '%-14s %-11s %s\n' UNIT KIND LABEL
  while IFS='|' read -r unit kind rank label aliases hint model; do
    printf '%-14s %-11s %s\n' "$unit" "$kind" "$label"
  done <<<"$(printf '%s\n' "${services[@]}")"
}

action=${1:-}
case "$action" in
  on | off | restart | status)
    shift
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
      die "run as your user, not root/sudo (systemctl --user target)"
    fi
    if ! systemctl --user show-environment >/dev/null 2>&1; then
      die "cannot reach the systemd user manager (no user session bus?)"
    fi
    resolve_targets "$@"
    # No target: operate on everything (status already means all).
    if ((${#sel[@]} == 0)) && [[ $action != status ]]; then add_all; fi
    ;;
  list)
    do_list
    exit 0
    ;;
  "" | -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ $action == status ]]; then
  do_status
  exit 0
fi

failed=0
for unit in "${sel[@]}"; do
  echo "== $unit"
  info "$unit"
  unit_file="$HOME/.config/systemd/user/$unit.service"
  case "$action" in
    on)
      if [[ ! -e $unit_file ]]; then
        echo "ai: $unit is not installed at $unit_file" >&2
        echo "ai: run 'nyx' to relink the home-manager unit" >&2
        failed=1
        continue
      fi
      systemctl --user daemon-reload
      if systemctl --user enable --now "$unit"; then
        if ! systemctl --user is-active --quiet "$unit"; then
          echo "ai: $unit did not become active (missing model? see hint above)" >&2
          failed=1
        fi
      else
        failed=1
      fi
      ;;
    off)
      # Do NOT use `systemctl disable`: home-manager installs the unit as a
      # symlink into /nix/store, and disable removes that symlink, making the
      # unit disappear until the next home-manager activation. Stop it and
      # only drop the default.target wants link so the next login stays off.
      systemctl --user stop "$unit" || failed=1
      rm -f "$HOME/.config/systemd/user/default.target.wants/$unit.service"
      ;;
    restart)
      if [[ ! -e $unit_file ]]; then
        echo "ai: $unit is not installed at $unit_file" >&2
        echo "ai: run 'nyx' to relink the home-manager unit" >&2
        failed=1
        continue
      fi
      systemctl --user daemon-reload
      if systemctl --user restart "$unit"; then
        if ! systemctl --user is-active --quiet "$unit"; then
          echo "ai: $unit did not become active (missing model? see hint above)" >&2
          failed=1
        fi
      else
        failed=1
      fi
      ;;
    status)
      if [[ ! -e $unit_file ]]; then
        printf '%-14s %-9s %-9s\n' "$unit" "missing" "missing"
        continue
      fi
      state "$unit"
      ;;
  esac
done

exit "$failed"
