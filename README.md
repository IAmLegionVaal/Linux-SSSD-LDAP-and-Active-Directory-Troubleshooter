# Linux SSSD, LDAP and Active Directory Troubleshooter

A Linux support toolkit for diagnosing SSSD, Kerberos, LDAP and domain-integration problems and applying selected guarded repairs.

## Diagnostic script

```bash
chmod +x src/identity_troubleshooter.sh
sudo ./src/identity_troubleshooter.sh --user user@example.com --domain example.com
```

## Repair script

```bash
chmod +x src/identity_repair.sh
sudo ./src/identity_repair.sh --repair --dry-run
```

Examples:

```bash
sudo ./src/identity_repair.sh --fix-permissions
sudo ./src/identity_repair.sh --clear-cache
sudo ./src/identity_repair.sh --restart-sssd
sudo ./src/identity_repair.sh --restart-oddjob
sudo ./src/identity_repair.sh --destroy-ticket
```

## What the repair does

- Backs up `/etc/sssd` before configuration-related changes.
- Corrects standard SSSD configuration ownership and modes.
- Validates configuration with `sssctl config-check` when available.
- Stops SSSD, backs up cache databases, clears cached identity databases and starts SSSD again.
- Restarts and verifies SSSD and optional oddjobd services.
- Can destroy the current Kerberos ticket cache explicitly.
- Captures service, realm, Kerberos, permission and journal state before and after repair.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

Clearing SSSD caches can temporarily affect cached logons and identity resolution. The tool does not join or leave a domain, change passwords or request credentials.

## Author

Dewald Pretorius — L2 IT Support Engineer
