# Codex Skills

This directory contains Codex skill adaptations of the CSTK Claude Code skills.

The skill folders are prefixed with `cstk-` to avoid collisions with built-in or
locally installed Codex skills such as `plan`, `image`, or `bugfix`.

To use them in a Codex workspace, copy the desired folders from `codex/skills/`
into a discovered Codex skills directory, for example:

```bash
cp -R codex/skills/cstk-* ~/.codex/skills/
```

Each skill includes `agents/openai.yaml` metadata and keeps supporting resources
such as `scripts/`, `references/`, `templates/`, and `examples/` when present in
the source CSTK skill.
