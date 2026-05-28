# Backlog: Insights 2026-05

Tarefas derivadas do `/insights` rodado em 2026-05-05 (287 sessoes,
Apr-May 2026) cruzado com `/apply-insights` filtrado para meta-projeto
(skills + hooks para Claude Code, sem app/DB).

Itens descartados na triagem (nao recriar):
- MCP Postgres — projeto nao tem DB
- `/diagnose` skill — `global/skills/bugfix/` ja cobre
- Pre-commit secret-scan — projeto nao lida com credenciais
- Status block hook — overhead para ciclo curto deste repo
- Spec→staging autonomous loop — sem staging

---

## T1 — CLAUDE.md: Release Safety Checklist

**Criticidade:** alta — cascata cstk v3.2.0→3.2.1→3.2.2 (3 patches em
sequencia por workflow file ausente do tag + URL v-prefix mismatch em
`install.sh`) e friction documentada e nao codificada. Custo de codificar
e zero; sem isso, proximo release repete.

**Acao:** adicionar secao em `CLAUDE.md` apos `## Renomeando uma skill`:

````markdown
## Release Safety Checklist

Antes de tagear `vX.Y.Z` e empurrar:

1. Verificar que `cli/VERSION` bate com a tag pretendida
2. Confirmar que `.github/workflows/release.yml` ja esta no commit que sera
   tageado (`git log --oneline <commit> -- .github/workflows/release.yml`).
   Tag em commit anterior ao workflow → release nao publica e exige patch
3. Validar `install.sh` localmente contra a release anterior:
   `curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh`
4. Apos tagear: `gh run watch` na pipeline antes de anunciar

Historico: v3.2.0→3.2.1→3.2.2 foi cascata de 3 patches em sequencia por
workflow ausente do tag + URL v-prefix mismatch em install.sh. Checklist
acima evita repetir.
````

**Definition of done:** secao presente em `CLAUDE.md`, commit dedicado.

---

## T2 — Hook PostToolUse: rodar teste do script editado

**Criticidade:** media — convencao `tests/test_<nome>.sh` ja existe e
`--check-coverage` enforce orfaos, mas execucao apos edit e manual.
Hook fecha o loop sem rodar suite inteira (~30-40s).

**Acao:** adicionar a `.claude/settings.local.json`:

````json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "f=\"$CLAUDE_TOOL_FILE_PATH\"; case \"$f\" in *global/skills/*/scripts/*.sh) n=$(basename \"$f\" .sh); t=\"tests/test_${n}.sh\"; [ -x \"$t\" ] && \"$t\" || true ;; *cli/lib/*.sh) n=$(basename \"$f\" .sh); t=\"tests/cstk/test_${n}.sh\"; [ -x \"$t\" ] && \"$t\" || true ;; esac"
          }
        ]
      }
    ]
  }
}
````

**Notas de implementacao:**
- Validar que `$CLAUDE_TOOL_FILE_PATH` e a env var correta para PostToolUse
  no harness atual; ajustar se mudou
- Falha silenciosa se teste nao existe (orfao e responsabilidade de
  `--check-coverage`)
- Roda apenas o teste do script editado, nao a suite inteira

**Definition of done:** editar um `.sh` com teste correspondente dispara
execucao do teste; editar `.sh` sem teste nao quebra fluxo.

---

## T3 — Hook PreToolUse: bloquear `cp -r global/skills/`

**Criticidade:** baixa-media — caminho deprecated em favor de `cstk update`.
Guard interrompe o reflexo antes do drift acontecer (causa #1 de "fix
funciona no repo mas nao na sessao", segundo CLAUDE.md).

**Acao:** adicionar a `.claude/settings.local.json`:

````json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$CLAUDE_TOOL_INPUT\" | grep -qE 'cp -r .*global/skills' && { echo 'BLOCKED: use \"cstk update\" — cp -r nao rastreia versao nem detecta drift (CLAUDE.md)'; exit 2; } || exit 0"
          }
        ]
      }
    ]
  }
}
````

**Definition of done:** tentativa de `cp -r global/skills/ ~/.claude/skills/`
e bloqueada com mensagem apontando para `cstk update`.

---

## T4 — CLAUDE.md: regra de sibling-path search ao editar skill

**Criticidade:** media — friction "sibling-path search after fix" no
`/insights` (fixes acertam um path mas perdem o irmao). Ja existe regra
para rename; falta a regra geral de edicao.

**Acao:** adicionar secao em `CLAUDE.md` perto de `## Renomeando uma skill`:

````markdown
## Editando uma skill

Antes de commitar uma edicao em `global/skills/<X>/`:

1. Se mudou `description` no frontmatter → atualizar `README.md`
   (lista de skills)
2. Se mudou comportamento publico → entrada no `CHANGELOG.md` + bump
   de versao
3. Se editou um `.sh` em `scripts/` → confirmar que
   `tests/test_<nome>.sh` ainda passa
4. Se a skill e mencionada por outras skills (campo `description`) →
   grep e revalidar
````

**Definition of done:** secao presente em `CLAUDE.md`, commit dedicado.

---

## Ordem sugerida de execucao

1. T1 (zero risco, alto valor — codifica friction de release ja vivida)
2. T4 (zero risco, mesmo padrao de T1 — pura documentacao)
3. T2 (precisa validar env var do hook — testar antes de commit)
4. T3 (validar que regex nao bloqueia comandos legitimos — ex: leitura
   `cat global/skills/X/SKILL.md` nao deveria casar, mas confirmar)

T2 e T3 podem entrar no mesmo commit de hooks. T1 e T4 podem entrar
juntos como "docs(claude-md): release checklist + sibling-path rule".
