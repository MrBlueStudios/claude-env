# claude-guard: PreToolUse policy for Claude Code's Bash tool.
#
# Installed through /etc/claude-code/managed-settings.json (modules/system/claude-code-policy.nix),
# so no session or project setting can switch it off. Reads the hook payload on stdin.
#   - no output, exit 0  -> no opinion; the normal permission flow continues
#   - JSON "deny"        -> the command never runs
#   - JSON "ask"         -> you are asked, even in auto-accept modes
# Tested by modules/system/claude-code/guard-test.sh (`just test-guard`).

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
[ "$tool" = "Bash" ] || exit 0
cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"
home="${HOME:-/nonexistent}"

decide() {
  jq -cn --arg d "$1" --arg r "claude-guard: $2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}
deny() { decide deny "$1"; }
ask() { decide ask "$1"; }
has() { grep -qP -- "$1" <<<"$cmd"; }

# ── Always denied ───────────────────────────────────────────────────────────
has ':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:' && deny "fork bomb"
has '(^|[\s;&|(])mkfs(\.\w+)?(\s|$)' && deny "filesystem format (mkfs)"
has '\bdd\b[^;&|]*\bof=/dev/' && deny "raw write to a block device (dd of=/dev/...)"
has '\b(curl|wget)\b[^;&]*\|\s*(sudo\s+)?((ba|z|da|k)?sh|python3?|perl)\b' && deny "piping a download into a shell"
has '\b(ba|z)?sh\s+(-c\s+)?["'"'"']?\$\(\s*(curl|wget)\b' && deny "running a downloaded script"
has '<\(\s*(curl|wget)\b' && deny "running a downloaded script"
has '\bchmod\s+(-\w*R\w*\s+)+0?777\s+/(\s|$)' && deny "recursive chmod 777 on /"

# Reading secrets: .env files (but not .env.example/.sample/.template/.dist), decrypted agenix
# secrets, and SSH private keys (public .pub keys stay readable).
reader='\b(cat|less|more|head|tail|bat|batcat|cp|mv|scp|rsync|base64|xxd|od|strings|grep|rg|sed|awk|nl|tac|tee|curl)\b[^;&|]*'
has "${reader}/run/agenix/" && deny "reading decrypted agenix secrets"
has "${reader}/\\.ssh/id_[\\w-]++(?!\\.pub)" && deny "reading an SSH private key"
has "${reader}(^|[\\s/'\"])\\.env(?!\\.(example|sample|template|dist)\\b)(\\.[\\w-]+)?(?=\$|[\\s'\";|&)])" &&
  deny "reading a .env file (use .env.example, or ask Léon for the value)"

# Force-push: never to main/master, ask otherwise.
if has '\bgit\s+push\b' && has '(\s-f\b|\s--force\b|\s--force-with-lease\b|\s\+\S)'; then
  has '\b(main|master)\b' && deny "force-push to main/master"
  ask "force-push rewrites remote history"
fi

# Destructive rm anywhere in the string, including inside `bash -c "..."`.
rm_flags='\brm\s+(-\S+\s+)*-[a-zA-Z]*[rR][a-zA-Z]*\s+(-\S+\s+)*'
has "${rm_flags}[\"']?(/|~|\\\$HOME|\\\$\\{HOME\\})/?\\*?[\"']?(\\s|\$|;|&|\\|)" &&
  deny "recursive rm of / or your home directory"

# ── Per-command rm analysis ─────────────────────────────────────────────────
# shellcheck disable=SC2016,SC2088  # literal ~ and $HOME in the command text, on purpose
expand() {
  local t="$1"
  t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"
  case "$t" in
    "~") t="$home" ;;
    "~/"*) t="$home/${t#\~/}" ;;
    '$HOME'|'${HOME}') t="$home" ;;
    '$HOME/'*) t="$home/${t#\$HOME/}" ;;
    '${HOME}/'*) t="$home/${t#\$\{HOME\}/}" ;;
  esac
  while [ "${#t}" -gt 1 ] && [ "${t%/}" != "$t" ]; do t="${t%/}"; done
  printf '%s' "$t"
}

protected='^(/|/\*|/(bin|boot|etc|home|lib|lib64|nix|opt|root|run|srv|sys|usr|var)(/\*)?|/nix/(store|var)(/\*)?|/etc/nixos(/\*)?)$'

check_rm() { # args: the words of one simple command
  local -a words=("$@")
  local n=${#words[@]} i=0 recursive=0 endopts=0 t
  # skip wrappers (sudo and its flags, env, nice, ...) and VAR=value prefixes
  while [ "$i" -lt "$n" ]; do
    case "${words[$i]}" in
      sudo|doas)
        i=$((i + 1))
        while [ "$i" -lt "$n" ] && [[ "${words[$i]}" == -* ]]; do i=$((i + 1)); done
        ;;
      command|nice|time|nohup|env|*=*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  case "${words[$i]:-}" in rm|*/rm) ;; *) return 0 ;; esac
  local -a targets=()
  for t in "${words[@]:$((i + 1))}"; do
    if [ "$endopts" = 0 ] && [ "$t" = "--" ]; then endopts=1; continue; fi
    if [ "$endopts" = 0 ] && [[ "$t" == -* ]]; then
      if [[ "$t" =~ ^-[a-zA-Z]*[rR] || "$t" == --recursive ]]; then recursive=1; fi
      continue
    fi
    targets+=("$t")
  done
  if [ "$recursive" = 0 ]; then return 0; fi
  for t in "${targets[@]}"; do
    t="$(expand "$t")"
    if [ "$t" = "$home" ] || [ "$t" = "$home/*" ]; then deny "recursive rm of your home directory"; fi
    if grep -qP -- "$protected" <<<"$t"; then deny "recursive rm of a system directory ($t)"; fi
    # shellcheck disable=SC2016
    case "$t" in
      *'$'*) ask "recursive rm of a path built from a variable ($t)" ;;
      *..*) ask "recursive rm of a path containing .. ($t)" ;;
      '*') ask "recursive rm of everything in ${cwd:-the current directory}" ;;
      /tmp/*|/var/tmp/*) ;;
      /*)
        if [ -z "$cwd" ] || [[ "$t/" != "$cwd/"* ]]; then
          ask "recursive rm outside the current project ($t)"
        fi
        ;;
    esac
  done
  return 0
}

# Split on ; && || | and newlines, then look at each simple command.
segments="$(sed -E 's/(\|\||&&|;|\|)/\n/g' <<<"$cmd")"
while IFS= read -r seg; do
  read -ra words <<<"$seg" || true
  if [ "${#words[@]}" -gt 0 ]; then check_rm "${words[@]}"; fi
done <<<"$segments"

has '\bxargs\b[^;&|]*\brm\s+(-\S+\s+)*-[a-zA-Z]*[rR]' && ask "recursive rm fed by xargs"

# ── Ask first ───────────────────────────────────────────────────────────────
has '\b(nh\s+os|nixos-rebuild)\s+(switch|boot|test)\b' && ask "activating a new NixOS generation"

exit 0
