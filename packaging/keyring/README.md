# karchy signing key (public half)

Created 2026-11-14: ed25519, fingerprint `70BC96FE5BD73CD9006C46D6BB27EDD9081A7977`, no expiry. The private half is the `KARCHY_SIGNING_KEY` secret on GitHub, with one backup on the NAS at `/mnt/truenas/homelab/backups/karchy/karchy-signing-key.asc`. The steps below are for replacing it.

CI signs every package and database of the `[karchy]` repositories with one
gpg key (D-61). Only its public half belongs here; the private half is the
GitHub Actions secret `KARCHY_SIGNING_KEY` and lives nowhere else.

One-time setup, on a machine you trust:

```bash
gpg --quick-generate-key "karchy package signing" ed25519 sign never
fpr=$(gpg --list-keys --with-colons "karchy package signing" | awk -F: '/^fpr/ { print $10; exit }')
gpg --export "$fpr" >packaging/keyring/karchy.gpg
printf '%s:4:\n' "$fpr" >packaging/keyring/karchy-trusted
: >packaging/keyring/karchy-revoked
gpg --export-secret-keys --armor "$fpr"   # paste into the KARCHY_SIGNING_KEY secret, then
                                          # store a backup offline and delete it from this machine
```

Set the repository variable `KARCHY_SIGNING_KEY_ID` to the fingerprint. With
`karchy.gpg` here, `packaging/build` builds `karchy-keyring`, and the installer
trusts the key straight from this folder (it ships with the installer).
