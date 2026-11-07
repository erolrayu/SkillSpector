#!/usr/bin/env bash
# Re-scan every installed agent skill with SkillSpector (static analysis only).
#
# Usage: scripts/audit-installed-skills.sh [SKILLS_DIR ...]
# Default directories: ~/.claude/skills, ~/.agents/skills, ./.claude/skills
# Exits 1 when any skill fails the SkillSpector gate, 2 on scan errors.
set -uo pipefail

command -v skillspector >/dev/null 2>&1 || { echo "error: skillspector not found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 2; }

dirs=("$@")
[[ ${#dirs[@]} -gt 0 ]] || dirs=("$HOME/.claude/skills" "$HOME/.agents/skills" "$PWD/.claude/skills")
report_dir="${SKILLSPECTOR_REPORT_DIR:-$HOME/.skillspector/reports}"
mkdir -p "$report_dir"
status=0 scanned=0

for d in "${dirs[@]}"; do
  [[ -d "$d" ]] || continue
  scanned=1
  report="$report_dir/audit-$(basename "$(dirname "$d")" | tr -dc 'A-Za-z0-9._-')-$(date +%Y%m%d-%H%M%S).json"
  echo "==> Scanning $d"
  skillspector scan "$d" --recursive --max-skills 500 --no-llm --format json --output "$report" >/dev/null
  rc=$?
  [[ $rc -le $status || $status -eq 2 ]] || status=$rc
  if [[ ! -s "$report" ]]; then echo "    scan failed (exit $rc)"; status=2; continue; fi
  python3 -I - "$report" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
skills = r.get("skills") if r.get("multi_skill") else [r]
for s in skills or []:
    risk = s.get("risk_assessment", {})
    issues = s.get("issues", [])
    high = sum(i.get("severity") in ("HIGH", "CRITICAL") for i in issues)
    mark = "!!" if risk.get("recommendation") == "DO_NOT_INSTALL" or high else "  "
    name = s.get("name") or (s.get("skill") or {}).get("name")
    print(f"  {mark} {str(name):30} {risk.get('score'):>3}/100 {risk.get('recommendation'):15} HIGH/CRITICAL: {high}")
if r.get("skills_omitted"):
    print(f"  (omitted: {r.get('skills_omitted')})")
PY
  echo "    report: $report"
done

[[ $scanned -eq 1 ]] || echo "No skills directories found."
exit $status
