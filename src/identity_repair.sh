#!/usr/bin/env bash
set -u

REPAIR=false
FIX_PERMISSIONS=false
CLEAR_CACHE=false
RESTART_SSSD=false
RESTART_ODDJOB=false
KDESTROY_USER=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage(){ cat <<'EOF'
Usage: identity_repair.sh [options]

  --repair             Back up SSSD config, fix permissions, clear caches and restart SSSD.
  --fix-permissions    Set standard ownership/mode on /etc/sssd/sssd.conf and conf.d files.
  --clear-cache        Stop SSSD, back up and clear SSSD cache databases, then start SSSD.
  --restart-sssd       Restart and verify SSSD.
  --restart-oddjob     Restart oddjobd when installed.
  --destroy-ticket     Destroy the current user's Kerberos ticket cache.
  --dry-run            Show commands without changing identity services.
  --yes                Skip confirmation prompts.
  --output DIR         Save logs, backups and verification output in DIR.
EOF
}
while [ "$#" -gt 0 ]; do case "$1" in
  --repair) REPAIR=true; shift;; --fix-permissions) FIX_PERMISSIONS=true; shift;;
  --clear-cache) CLEAR_CACHE=true; shift;; --restart-sssd) RESTART_SSSD=true; shift;;
  --restart-oddjob) RESTART_ODDJOB=true; shift;; --destroy-ticket) KDESTROY_USER=true; shift;;
  --dry-run) DRY_RUN=true; shift;; --yes) ASSUME_YES=true; shift;;
  --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;; esac; done
if ! $REPAIR && ! $FIX_PERMISSIONS && ! $CLEAR_CACHE && ! $RESTART_SSSD && ! $RESTART_ODDJOB && ! $KDESTROY_USER; then echo "Choose at least one repair action." >&2; exit 2; fi
if $REPAIR || $FIX_PERMISSIONS || $CLEAR_CACHE || $RESTART_SSSD; then systemctl cat sssd.service >/dev/null 2>&1 || { echo "sssd.service is required." >&2; exit 3; }; fi
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./identity-repair-$STAMP}"; BACKUP_DIR="$OUTPUT_DIR/backup"; mkdir -p "$BACKUP_DIR"; LOG="$OUTPUT_DIR/repair.log"; BEFORE="$OUTPUT_DIR/before.txt"; AFTER="$OUTPUT_DIR/after.txt"; : >"$LOG"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
confirm(){ $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
run(){ local d="$1"; shift; ACTIONS=$((ACTIONS+1)); log "$d"; if $DRY_RUN; then printf 'DRY-RUN:' >>"$LOG"; printf ' %q' "$@" >>"$LOG"; printf '\n' >>"$LOG"; return 0; fi; if "$@" >>"$LOG" 2>&1; then log "SUCCESS: $d"; else FAILURES=$((FAILURES+1)); log "WARNING: $d failed"; return 1; fi; }
root(){ local d="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run "$d" "$@"; else run "$d" sudo "$@"; fi; }
collect(){ local f="$1"; { echo "Collected: $(date -Is)"; systemctl status sssd --no-pager -l 2>&1 || true; echo; sssctl config-check 2>&1 || true; echo; realm list 2>&1 || true; echo; klist 2>&1 || true; echo; stat -c '%a %U:%G %n' /etc/sssd/sssd.conf /etc/sssd/conf.d/* 2>/dev/null || true; echo; journalctl -u sssd -n 150 --no-pager 2>&1 || true; } >"$f"; }
collect "$BEFORE"; [ -d /etc/sssd ] && tar -C / -czf "$BACKUP_DIR/etc-sssd.tgz" etc/sssd 2>/dev/null || true
confirm "Apply the selected identity-service repairs? Cached logons may be temporarily unavailable." || { log "Repair cancelled."; exit 10; }
$REPAIR && { FIX_PERMISSIONS=true; CLEAR_CACHE=true; RESTART_SSSD=true; }
if $FIX_PERMISSIONS; then [ -f /etc/sssd/sssd.conf ] && { root "Setting sssd.conf ownership" chown root:root /etc/sssd/sssd.conf || true; root "Setting sssd.conf mode" chmod 600 /etc/sssd/sssd.conf || true; }; if [ -d /etc/sssd/conf.d ]; then while IFS= read -r f; do root "Setting ownership on $f" chown root:root "$f" || true; root "Setting mode on $f" chmod 600 "$f" || true; done < <(find /etc/sssd/conf.d -maxdepth 1 -type f -print); fi; command -v sssctl >/dev/null 2>&1 && run "Validating SSSD configuration" sssctl config-check || true; fi
if $CLEAR_CACHE; then root "Stopping SSSD" systemctl stop sssd || true; if ! $DRY_RUN && [ -d /var/lib/sss/db ]; then tar -C /var/lib/sss -czf "$BACKUP_DIR/sss-cache.tgz" db mc 2>/dev/null || true; fi; root "Clearing SSSD cache databases" find /var/lib/sss/db /var/lib/sss/mc -maxdepth 1 -type f -delete || true; root "Starting SSSD" systemctl start sssd || true; fi
$RESTART_SSSD && root "Restarting SSSD" systemctl restart sssd || true
if $RESTART_ODDJOB; then if systemctl list-unit-files oddjobd.service >/dev/null 2>&1; then root "Restarting oddjobd" systemctl restart oddjobd || true; else FAILURES=$((FAILURES+1)); log "WARNING: oddjobd is not installed."; fi; fi
if $KDESTROY_USER; then command -v kdestroy >/dev/null 2>&1 && run "Destroying current Kerberos ticket cache" kdestroy || { FAILURES=$((FAILURES+1)); log "WARNING: kdestroy is not available."; }; fi
$DRY_RUN || sleep 3; collect "$AFTER"; if $REPAIR || $CLEAR_CACHE || $RESTART_SSSD; then systemctl is-active --quiet sssd || { FAILURES=$((FAILURES+1)); log "WARNING: SSSD is not active."; }; fi; [ "$FAILURES" -eq 0 ] || exit 20; log "Identity repair completed successfully. Actions performed: $ACTIONS"
