#!/usr/bin/env bash
set -u
USER_QUERY=""
DOMAIN=""
HOURS=24
OUTPUT_DIR=""
usage(){ echo "Usage: identity_troubleshooter.sh [--user USER] [--domain DOMAIN] [--hours N] [--output DIR]"; }
while [[ $# -gt 0 ]]; do case "$1" in --user) USER_QUERY="${2:-}"; shift 2;; --domain) DOMAIN="${2:-}"; shift 2;; --hours) HOURS="${2:-24}"; shift 2;; --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./identity-troubleshooting-$STAMP}"; mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/identity-report.txt"; CSV="$OUTPUT_DIR/checks.csv"; JSON="$OUTPUT_DIR/summary.json"; ERRORS="$OUTPUT_DIR/command-errors.log"; :>"$REPORT"; :>"$ERRORS"
echo 'check,status,detail' > "$CSV"
section(){ t="$1"; shift; { printf '\n===== %s =====\n' "$t"; "$@"; } >>"$REPORT" 2>>"$ERRORS" || true; }
record(){ printf '"%s","%s","%s"\n' "$1" "$2" "$(printf '%s' "$3" | sed 's/"/""/g')" >> "$CSV"; }
section "Metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; id; timedatectl 2>/dev/null || true'
section "SSSD service" bash -c 'systemctl status sssd --no-pager -l 2>/dev/null || true; systemctl is-enabled sssd 2>/dev/null || true'
section "SSSD configuration" bash -c 'stat -c "%A %U:%G %a %n" /etc/sssd/sssd.conf 2>/dev/null || true; grep -Ev "^[[:space:]]*(#|$)" /etc/sssd/sssd.conf 2>/dev/null | sed -E "s/(ldap_default_authtok|krb5_keytab|password)[[:space:]]*=.*/\1 = REDACTED/I" || true'
section "SSSD domain status" bash -c 'sssctl domain-list 2>/dev/null || true; sssctl domain-status --all 2>/dev/null || true; sssctl config-check 2>/dev/null || true'
section "Realm status" bash -c 'realm list 2>/dev/null || true; adcli info 2>/dev/null || true'
section "Kerberos configuration" bash -c 'cat /etc/krb5.conf 2>/dev/null || true; klist 2>/dev/null || true'
section "NSS configuration" bash -c 'grep -E "^(passwd|group|shadow):" /etc/nsswitch.conf 2>/dev/null || true'
section "PAM configuration" bash -c 'grep -R "pam_sss" /etc/pam.d 2>/dev/null || true'
section "Recent SSSD and auth events" bash -c "journalctl --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'sssd|krb5|ldap|gssapi|pam_sss|realm|adcli|authentication failure' | tail -n 3000 || true"

SSSD_ACTIVE=false; systemctl is-active --quiet sssd 2>/dev/null && SSSD_ACTIVE=true
CONFIG_MODE=$(stat -c '%a' /etc/sssd/sssd.conf 2>/dev/null || echo missing)
CONFIG_SAFE=false; [[ "$CONFIG_MODE" == 600 ]] && CONFIG_SAFE=true
USER_LOOKUP=false
if [[ -n "$USER_QUERY" ]]; then section "User lookup" getent passwd "$USER_QUERY"; getent passwd "$USER_QUERY" >/dev/null 2>&1 && USER_LOOKUP=true; command -v id >/dev/null && section "User identity" id "$USER_QUERY"; fi
DNS_OK=false
if [[ -n "$DOMAIN" ]]; then section "Domain DNS" bash -c "getent hosts '$DOMAIN'; dig +short _kerberos._tcp.$DOMAIN SRV 2>/dev/null; dig +short _ldap._tcp.$DOMAIN SRV 2>/dev/null"; getent hosts "$DOMAIN" >/dev/null 2>&1 && DNS_OK=true; fi
record sssd_service "$SSSD_ACTIVE" "systemctl is-active sssd"
record sssd_config_mode "$CONFIG_SAFE" "$CONFIG_MODE"
record user_lookup "$USER_LOOKUP" "$USER_QUERY"
record domain_dns "$DNS_OK" "$DOMAIN"
OVERALL="Healthy"; ! $SSSD_ACTIVE && OVERALL="Attention required"
cat > "$JSON" <<EOF
{"collected_at":"$(date -Is)","hostname":"$(hostname -f 2>/dev/null || hostname)","sssd_active":$SSSD_ACTIVE,"sssd_config_mode":"$CONFIG_MODE","user":"$USER_QUERY","user_lookup_successful":$USER_LOOKUP,"domain":"$DOMAIN","domain_dns_successful":$DNS_OK,"overall_status":"$OVERALL"}
EOF
printf '\nIdentity diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
