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

## Install the skills

Copy (or symlink) the skill folders into the directory your agent reads skills
from. From a clone of this repository:

**Claude Code** (personal, all projects):

```bash
mkdir -p ~/.claude/skills && cp -R skills/skillspector skills/skill-inspector ~/.claude/skills/
```

**Claude Code** (one project only): copy into `<project>/.claude/skills/` instead.

**Codex CLI and other tools that read `.agents/skills`**:

```bash
mkdir -p ~/.agents/skills && cp -R skills/skillspector skills/skill-inspector ~/.agents/skills/
```

For other agents, use the skills directory documented by that tool. Restart the
agent session after installing so it picks up the new skills.

## Use

Ask the agent in natural language, for example:

- "Scan `./downloads/some-skill` with SkillSpector and give me a JSON report."
- "Is this skill safe to install? https://github.com/user/my-skill"
- "Add a SkillSpector gate to CI that fails on any finding."

In Claude Code you can also invoke the skills directly with `/skillspector` or
`/skill-inspector`.

## Verify

You can scan the bundled skills with SkillSpector itself:

```bash
skillspector scan skills/ --recursive --no-llm
```
