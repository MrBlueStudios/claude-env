#!/usr/bin/env bash
# compliance-scan — fast, deterministic grep for legal/privacy red flags in a web repo.
# Advisory by default; --strict exits 1 when a HIGH pattern is found (for pre-commit/CI).
# It finds *candidates*. A hit is not a violation; a clean run is not legal clearance.
set -uo pipefail

STRICT=0
[ "${1:-}" = "--strict" ] && { STRICT=1; shift; }
ROOT="${1:-.}"
HIGH_HITS=0

RG=(rg --line-number --no-heading --color=never --hidden
  --glob '!.git' --glob '!node_modules' --glob '!dist' --glob '!build' --glob '!.svelte-kit'
  --glob '!*.lock' --glob '!package-lock.json' --glob '!*.md' --glob '!*.min.*' --glob '!.venv'
  --glob '!**/tests/**' --glob '!**/test_*' --glob '!**/*.test.*' --glob '!**/*.spec.*')

check() { # severity label pattern
  local sev="$1" label="$2" pat="$3" out
  out="$("${RG[@]}" -i -e "$pat" "$ROOT" 2>/dev/null | cut -c1-200)"
  [ -z "$out" ] && return
  printf '\n[%s] %s\n%s\n' "$sev" "$label" "$(echo "$out" | head -8)"
  local n; n=$(echo "$out" | wc -l)
  [ "$n" -gt 8 ] && echo "  … $((n - 8)) more"
  [ "$sev" = HIGH ] && HIGH_HITS=$((HIGH_HITS + n))
}

absent() { # severity label pattern — flag when a pattern is MISSING but a trigger exists
  local sev="$1" label="$2" pat="$3"
  "${RG[@]}" -qi -e "$pat" "$ROOT" 2>/dev/null && return
  printf '\n[%s] %s\n' "$sev" "$label"
  [ "$sev" = HIGH ] && HIGH_HITS=$((HIGH_HITS + 1))
}

echo "compliance-scan: $(cd "$ROOT" && pwd)"

# GDPR: third-party requests that leak visitor IPs before consent
check HIGH "Hotlinked web fonts (self-host instead — LG München I, 3 O 17493/20)" \
  'fonts\.(googleapis|gstatic)\.com|use\.typekit\.net|fonts\.bunny\.net'
check MED  "Third-party script/style CDN (self-host or bundle)" \
  'cdn\.jsdelivr\.net|unpkg\.com|cdnjs\.cloudflare\.com|code\.jquery\.com'
check HIGH "Analytics / tracking tag (needs consent gate + privacy-policy entry)" \
  'googletagmanager|google-analytics|gtag\(|connect\.facebook\.net|hotjar|clarity\.ms|plausible\.io|umami|posthog'
check HIGH "Session replay (needs consent + input masking)" \
  'fullstory|logrocket|mouseflow|smartlook|replayIntegration|session_recording|rrweb'
check MED  "Third-party embed (click-to-load placeholder recommended)" \
  'youtube\.com/embed|youtube-nocookie|maps\.googleapis|google\.com/maps/embed|calendly\.com|gravatar\.com'

# Uploads / UGC → takedown route (EU DSA notice-and-action; DMCA agent only if US-facing UGC)
check MED  "File upload / user content (needs notice-and-action contact + ToS clause)" \
  'type="file"|UploadFile|multipart/form-data|FormData\('

# Payments → renewal terms beside the pay button, cancellation path
if "${RG[@]}" -qi -e 'stripe|mollie|paddle|lemonsqueezy' "$ROOT" 2>/dev/null; then
  check INFO "Payment provider references (verify renewal price/interval/cancel terms next to pay button)" \
    'checkout\.sessions|createCheckoutSession|stripe\.checkout|mollie.*payments|subscription'
fi

# Email → unsubscribe + postal address (Gmail/Yahoo bulk-sender rules, CAN-SPAM for US recipients, Tw 11.7 NL)
SEND_PAT='smtplib|send_message\(|sendmail|resend\.|postmark|mailgun|sendgrid|ses\.send|gmail\.users\.messages'
MKT_PAT='newsletter|campaign|drip|broadcast|outreach|cold.?(e-?mail|outreach)|unsubscribe_text'
mapfile -t SENDERS < <("${RG[@]}" -li -e "$SEND_PAT" "$ROOT" 2>/dev/null)
if [ "${#SENDERS[@]}" -gt 0 ]; then
  # marketing intent is judged only in the sending code and mail/sequence/campaign paths,
  # so an unrelated regex mentioning "newsletter" elsewhere doesn't trip it
  if rg -qi -e "$MKT_PAT" "${SENDERS[@]}" 2>/dev/null \
     || "${RG[@]}" -qi -e "$MKT_PAT" --glob '**/*{mail,outreach,campaign,newsletter,sequence}*/**' "$ROOT" 2>/dev/null; then
    # templates are often Markdown, so these two checks include *.md
    "${RG[@]}" --glob '*.md' -qi -e 'unsubscribe|afmelden|uitschrijven|opt.?out' "$ROOT" 2>/dev/null \
      || { printf '\n[HIGH] Marketing/cold email with no unsubscribe or opt-out text anywhere\n'; HIGH_HITS=$((HIGH_HITS + 1)); }
    "${RG[@]}" --glob '*.md' -qi -e 'physical_address|postal address|postadres|vestigingsadres' "$ROOT" 2>/dev/null \
      || printf '\n[MED] Marketing/cold email with no postal-address field found\n'
    absent MED "No List-Unsubscribe header (mandatory for Gmail/Yahoo bulk senders, expected for all cold email)" 'List-Unsubscribe'
    absent MED "No RFC 8058 List-Unsubscribe-Post one-click header" 'List-Unsubscribe-Post'
  else
    echo; echo "[INFO] Sends email; looks transactional-only (List-Unsubscribe not required — re-check if any message markets)"
  fi
fi

# Signup → age / business-use statement
if "${RG[@]}" -qi -e 'type="password"|/signup|/register|create.account|magic.?link|hash_password' "$ROOT" 2>/dev/null; then
  absent MED "Signup flow but no age/business-use statement found" \
    '18\+|at least (16|18)|minimum age|business use only|zakelijk gebruik|ondernemer'
fi

# Legal pages and security contact
absent MED  "No privacy policy page found" 'privacy|privacybeleid|privacyverklaring'
absent LOW  "No terms page found" 'terms|voorwaarden'
absent LOW  "No security.txt found" 'security\.txt|Contact: mailto'

echo
if [ "$HIGH_HITS" -gt 0 ]; then
  echo "HIGH findings: $HIGH_HITS"
  [ "$STRICT" = 1 ] && exit 1
else
  echo "No HIGH findings."
fi
exit 0
