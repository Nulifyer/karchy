# Agent skills (D-115): link the skills karchy's packages ship into
# ~/.agents/skills and for Claude Code, and start watching for packages that
# add or remove one. New installs get both from the installer and the session.
karchy-agent-skills
if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user start karchy-agent-skills.path 2>/dev/null || true
fi
