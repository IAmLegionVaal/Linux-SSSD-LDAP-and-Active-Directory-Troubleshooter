# Linux SSSD, LDAP and Active Directory Troubleshooter

A read-only Bash toolkit for collecting SSSD, Kerberos, LDAP, DNS, NSS, PAM, realm-join, and access-policy evidence.

## Usage

```bash
chmod +x src/identity_troubleshooter.sh
sudo ./src/identity_troubleshooter.sh --user user@example.com --domain example.com
```

## Checks performed

- SSSD service, domains, configuration permissions, and logs
- Realm and domain join status
- Kerberos configuration, tickets, and KDC DNS records
- LDAP and identity lookups
- NSS and PAM configuration
- Time synchronisation and DNS dependencies
- Text, CSV, and JSON reports

## Safety

The script never joins or leaves a domain, clears caches, changes passwords, obtains credentials, or modifies identity configuration.

## Author

Dewald Pretorius — L2 IT Support Engineer
