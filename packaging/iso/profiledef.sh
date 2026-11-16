# shellcheck shell=bash disable=SC2034
# karchy's changes to archiso's releng profiledef.sh: packaging/iso/build
# appends this file to releng's, so these assignments win. The build adds a
# file_permissions entry for each executable in the installer it copies in.

iso_name="karchy"
iso_label="KARCHY_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="karchy <https://github.com/Nulifyer/karchy>"
iso_application="karchy installer"
file_permissions+=(
  ["/usr/local/bin/karchy-install"]="0:0:755"
  ["/usr/local/bin/karchy-iso-start"]="0:0:755"
)
