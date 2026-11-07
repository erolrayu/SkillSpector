#!/usr/bin/env bash
# Install an agent skill only after SkillSpector has scanned it.
#
# The skill is copied (or cloned/extracted) into a temporary staging directory,
# scanned with `skillspector scan --no-llm`, and copied into the agent's skills
# directory only when the scan passes or the user explicitly confirms.
# Nothing from the skill is executed.
#
# Usage: scripts/install-skill.sh [options] SOURCE
#   SOURCE        Local skill directory, SKILL.md file, .zip archive, or Git URL.
# Options:
#   --agent A     claude (default: ~/.claude/skills), agents (~/.agents/skills),
#                 project (./.claude/skills), or a directory path.
#   --path SUB    Skill subdirectory inside SOURCE (for repos with several skills).
#   --name NAME   Installed folder name (default: SKILL.md `name`, else folder name).
#   --strict      Also fail on any finding and on incomplete coverage.
#   --yes         Install CAUTION results without asking (never overrides a failed gate).
#   --force       Allow installing a skill that failed the gate, after typing "install".
#   --replace     Replace an already installed skill (the old copy is backed up).
#   --llm         Also run LLM analysis (uses your SKILLSPECTOR_PROVIDER settings).
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 2; }
info() { printf '==> %s\n' "$*"; }

agent="claude" sub="" name="" strict=0 yes=0 force=0 replace=0 llm=0 source=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) agent="${2:?}"; shift 2 ;;
    --path) sub="${2:?}"; shift 2 ;;
    --name) name="${2:?}"; shift 2 ;;
    --strict) strict=1; shift ;;
    --yes) yes=1; shift ;;
    --force) force=1; shift ;;
    --replace) replace=1; shift ;;
    --llm) llm=1; shift ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [[ -z "$source" ]] || die "only one SOURCE is allowed"; source="$1"; shift ;;
  esac
done
[[ -n "$source" ]] || die "missing SOURCE (see --help)"
command -v skillspector >/dev/null 2>&1 || die "skillspector not found. Install it with:
  uv tool install git+https://github.com/NVIDIA/skillspector.git"
command -v python3 >/dev/null 2>&1 || die "python3 is required to read the scan report"

case "$agent" in
  claude) dest_root="$HOME/.claude/skills" ;;
  agents) dest_root="$HOME/.agents/skills" ;;
  project) dest_root="$PWD/.claude/skills" ;;
  *) dest_root="$agent" ;;
esac

stage="$(mktemp -d "${TMPDIR:-/tmp}/skill-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
src_dir="$stage/src"

# 1. Stage the skill without running anything from it.
if [[ "$source" =~ ^(https?://|git@|ssh://) ]] && [[ ! "$source" =~ \.zip$ ]]; then
  info "Cloning $source"
  GIT_TERMINAL_PROMPT=0 git -c core.hooksPath=/dev/null clone --quiet --depth 1 --no-recurse-submodules "$source" "$src_dir"
  rm -rf "$src_dir/.git"
elif [[ "$source" == *.zip ]]; then
  [[ -f "$source" ]] || die "zip archive not found: $source (download it first)"
  info "Pre-scanning archive $source"
  set +e; skillspector scan "$source" --no-llm --format json --output "$stage/zip.json" >/dev/null; rc=$?; set -e
  [[ $rc -ne 2 ]] || die "SkillSpector could not scan the archive; not installing"
  python3 -I - "$source" "$src_dir" <<'PY'
import sys, zipfile
# zipfile strips absolute paths and ".." components, so members stay inside the target.
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
elif [[ -d "$source" ]]; then
  cp -R "$source" "$src_dir"
elif [[ -f "$source" ]]; then
  mkdir -p "$src_dir" && cp "$source" "$src_dir/SKILL.md"
else
  die "SOURCE not found: $source"
fi

skill_dir="$src_dir"
[[ -z "$sub" ]] || skill_dir="$src_dir/$sub"
if [[ ! -f "$skill_dir/SKILL.md" ]]; then
  # Archives often wrap the skill in a single top-level folder.
  mapfile -t found < <(cd "$skill_dir" && find . -mindepth 2 -maxdepth 4 -name SKILL.md -not -path '*/.git/*' | sed 's|/SKILL.md$||; s|^\./||' | sort)
  if [[ ${#found[@]} -eq 1 ]]; then
    skill_dir="$skill_dir/${found[0]}"
  elif [[ ${#found[@]} -gt 1 ]]; then
    printf 'Several skills found; choose one with --path:\n' >&2; printf '  %s\n' "${found[@]}" >&2; exit 2
  else
    die "no SKILL.md found in $source${sub:+/$sub}"
  fi
fi

if [[ -z "$name" ]]; then
  name="$(sed -n '1,/^---$/{s/^name:[[:space:]]*["'\'']\{0,1\}\([A-Za-z0-9._-]*\).*/\1/p}' "$skill_dir/SKILL.md" | head -n1)"
  [[ -n "$name" ]] || name="$(basename "$skill_dir")"
  [[ "$name" != "src" ]] || name="$(basename "${source%/}" .zip)"; name="${name%.git}"
fi
[[ "$name" =~ ^[A-Za-z0-9._-]+$ && "$name" != "." && "$name" != ".." ]] || die "invalid skill name: $name (use --name)"

# 2. Scan exactly the files that would be installed.
report_dir="${SKILLSPECTOR_REPORT_DIR:-$HOME/.skillspector/reports}"
mkdir -p "$report_dir"
report="$report_dir/$name-$(date +%Y%m%d-%H%M%S).json"
args=(scan "$skill_dir" --format json --output "$report")
[[ $llm -eq 1 ]] || args+=(--no-llm)
[[ $strict -eq 0 ]] || args+=(--fail-on-findings --fail-on-incomplete)
info "Scanning '$name' with SkillSpector"
set +e; skillspector "${args[@]}" >/dev/null; rc=$?; set -e
[[ $rc -ne 2 && -s "$report" ]] || die "scan failed (exit $rc); not installing"

recommendation="$(python3 -I - "$report" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
risk = r.get("risk_assessment", {})
print(f"\nRisk: {risk.get('score')}/100 | {risk.get('severity')} | {risk.get('recommendation')}", file=sys.stderr)
order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
issues = sorted(r.get("issues", []), key=lambda i: order.get(i.get("severity"), 9))
for i in issues[:20]:
    loc = i.get("location") or {}
    msg = " ".join(str(i.get("finding") or i.get("pattern") or i.get("category") or "").split())[:100]
    print(f"  [{i.get('severity')}] {i.get('id')} {loc.get('file')}:{loc.get('start_line')} {msg}", file=sys.stderr)
if len(issues) > 20:
    print(f"  ... and {len(issues) - 20} more", file=sys.stderr)
high = any(i.get("severity") in ("HIGH", "CRITICAL") for i in issues)
rec = risk.get("recommendation", "UNKNOWN")
print("CAUTION" if rec == "SAFE" and high else rec)
PY
)"
info "Report saved to $report"

# 3. Decide.
if [[ $rc -eq 1 || "$recommendation" == "DO_NOT_INSTALL" ]]; then
  printf '\nBLOCKED: SkillSpector did not pass this skill.\n' >&2
  [[ $force -eq 1 ]] || { printf 'Review the report; use --force to install anyway.\n' >&2; exit 1; }
  read -r -p 'Type "install" to install it anyway: ' answer
  [[ "$answer" == "install" ]] || { echo "Not installed."; exit 1; }
elif [[ "$recommendation" != "SAFE" && $yes -eq 0 ]]; then
  read -r -p "Result is $recommendation. Install '$name'? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Not installed."; exit 1; }
fi

# 4. Install.
dest="$dest_root/$name"
mkdir -p "$dest_root"
if [[ -e "$dest" ]]; then
  [[ $replace -eq 1 ]] || die "$dest already exists (use --replace)"
  # Keep backups outside the skills directory so the agent does not load them.
  backup_root="$HOME/.skillspector/backups"; mkdir -p "$backup_root"
  backup="$backup_root/$name-$(date +%Y%m%d-%H%M%S)"
  mv "$dest" "$backup"; info "Previous version moved to $backup"
fi
cp -R "$skill_dir" "$dest"
info "Installed '$name' to $dest (restart your agent session to load it)"
