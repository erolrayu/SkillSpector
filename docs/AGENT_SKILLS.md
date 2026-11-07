# Agent skills

SkillSpector ships two agent skills under [`skills/`](../skills/) that let coding
agents (Claude Code, Codex CLI, Gemini CLI, OpenCode, and other tools that read
`SKILL.md` folders) use SkillSpector from inside a session.

| Skill | Use it for |
|---|---|
| [`skillspector`](../skills/skillspector/SKILL.md) | Running the `skillspector` CLI: scans, output formats, exit-code gating, and baselines. |
| [`skill-inspector`](../skills/skill-inspector/SKILL.md) | A full install decision (`APPROVE` / `CAUTION` / `REJECT`) that combines a SkillSpector scan with a source-aware semantic review. |

Both skills default to static analysis (`--no-llm`) and never run code from the
skill being scanned.

## Prerequisite

Install the CLI so the agent can call it:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git
```

## Where skills are installed

| Agent | Personal (all projects) | One project only |
|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | `<project>/.claude/skills/<name>/SKILL.md` |
| Codex CLI and other `.agents/skills` readers | `~/.agents/skills/<name>/SKILL.md` | `<project>/.agents/skills/<name>/SKILL.md` |

Each skill is a folder that contains a `SKILL.md` at its top level. For other
agents, use the skills directory that tool documents. Restart the agent session
after installing so it picks up new skills.

## Install every skill through a SkillSpector scan

[`scripts/install-skill.sh`](../scripts/install-skill.sh) copies, clones, or
extracts a skill into a temporary staging directory, scans exactly those files
with `skillspector scan --no-llm`, and installs the skill only when the scan
passes. Nothing from the skill is executed.

```bash
# Local folder, SKILL.md, or zip archive -> ~/.claude/skills/<name>
scripts/install-skill.sh ./downloads/some-skill
scripts/install-skill.sh ./some-skill.zip

# Git repository; use --path when the repository holds several skills
scripts/install-skill.sh --path skills/skill-inspector https://github.com/NVIDIA/skillspector.git

# Install for Codex CLI, or into the current project's .claude/skills
scripts/install-skill.sh --agent agents ./downloads/some-skill
scripts/install-skill.sh --agent project ./downloads/some-skill
```

Install the skills bundled in this repository the same way:

```bash
scripts/install-skill.sh skills/skillspector
scripts/install-skill.sh skills/skill-inspector
```

Decision rules:

| Scan result | What happens |
|---|---|
| `SAFE` and no HIGH/CRITICAL finding | Installed. |
| `CAUTION`, or `SAFE` with a HIGH/CRITICAL finding | You are asked `[y/N]` (`--yes` accepts). |
| `DO_NOT_INSTALL`, risk score > 50, or a `--strict` gate fails | Blocked (exit 1). `--force` installs only after you type `install`. |
| Scan error | Not installed (exit 2). |

Other options: `--strict` (also fail on any finding and on incomplete
coverage), `--replace` (replace an installed skill; the old copy is moved to
`~/.skillspector/backups/`), `--name NAME`, and `--llm` (add LLM analysis with
your `SKILLSPECTOR_PROVIDER` settings). JSON reports are kept in
`~/.skillspector/reports/` (override with `SKILLSPECTOR_REPORT_DIR`).

## Re-scan installed skills

Skills installed some other way (by hand, by an agent, or before you adopted
the install script) are not scanned automatically. Audit them regularly, and
after every SkillSpector update, with
[`scripts/audit-installed-skills.sh`](../scripts/audit-installed-skills.sh):

```bash
scripts/audit-installed-skills.sh                       # ~/.claude/skills, ~/.agents/skills, ./.claude/skills
scripts/audit-installed-skills.sh /path/to/skills-dir   # any directory of skill folders
```

It prints one line per skill, marks risky ones with `!!`, saves JSON reports,
and exits `1` when any skill fails the SkillSpector gate.

## Use

Ask the agent in natural language, for example:

- "Scan `./downloads/some-skill` with SkillSpector and give me a JSON report."
- "Is this skill safe to install? https://github.com/user/my-skill"
- "Install this skill for me: https://github.com/user/my-skill" (the `skillspector`
  skill scans it first and installs only after a passing scan or your approval)
- "Add a SkillSpector gate to CI that fails on any finding."

In Claude Code you can also invoke the skills directly with `/skillspector` or
`/skill-inspector`.

## Verify

You can scan the bundled skills with SkillSpector itself:

```bash
skillspector scan skills/ --recursive --no-llm
```
