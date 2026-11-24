# A cancelled password dialog no longer counts as a failed login (D-163):
# polkit's PAM service checks passwords with karchy's auth lines
# (/etc/pam.d/karchy-polkit-auth, in karchy-settings). /etc/pam.d/polkit-1 is
# written where there is none, or its `auth include system-auth` line is
# pointed there, keeping fingerprint or FIDO2 lines added above it. The
# helper changes nothing the second time.
[[ -x /usr/lib/karchy/polkit-pam && -f /etc/pam.d/karchy-polkit-auth ]] ||
  { echo "karchy-settings has no polkit password check yet"; exit 1; }
sudo /usr/lib/karchy/polkit-pam
