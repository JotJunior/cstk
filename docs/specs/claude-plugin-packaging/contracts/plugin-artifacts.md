# Contract: Artefatos de Plugin publicados pelo cstk

Artefatos **novos** criados por esta feature no repo do toolkit. Todos sao
`[PROPOSTA — a validar na implementacao]` quanto aos VALORES; o SCHEMA de
cada um e `[REAL]`, extraido de arquivos reais (fontes S1-S3 de
`research.md`) — nenhum campo foi suposto.

## Artefato 1: `.claude-plugin/marketplace.json` (raiz do repo)

**Consumidor**: mecanismo nativo `/plugin marketplace add` + `/plugin install`.
**Producer**: mantido a mao, validado no CI, atualizado em lockstep com a tag.

```json
{
  "name": "cstk",
  "owner": { "name": "JotJunior" },
  "description": "Toolkit de documentacao e Spec-Driven Development para Claude Code",
  "plugins": [
    {
      "name": "cstk",
      "description": "Pipeline SDD completa (briefing -> review-features), orquestradores autonomos 00c e guardas enforced",
      "source": "./plugins/cstk",
      "version": "<tag SemVer sem o prefixo v>",
      "category": "development"
    },
    {
      "name": "cstk-language-go",
      "description": "Perfil Go do cstk: skills e hooks especificos de linguagem",
      "source": "./plugins/cstk-language-go",
      "version": "<tag SemVer sem o prefixo v>",
      "category": "development"
    }
  ]
}
```

### Invariantes (gate de CI)

| Id | Invariante | Falha |
|----|-----------|-------|
| MP-1 | JSON parseavel | erro |
| MP-2 | `.plugins \| length == 2` | erro (FR-003 exige exatamente 2) |
| MP-3 | Todo `source` string resolve para diretorio existente no repo | erro |
| MP-4 | Todo `source` aponta para diretorio que contem `.claude-plugin/plugin.json` | erro |
| MP-5 | `.plugins[].version` == tag do release corrente (sem `v`) | erro no release; aviso fora dele |
| MP-6 | `.plugins[].name` unico | erro |

> MP-5 e o mecanismo de lockstep (FR-003). Roda no workflow de release;
> fora de release e apenas aviso, para nao travar o dev-loop em `main`.

## Artefato 2: `plugins/cstk/.claude-plugin/plugin.json`

```json
{
  "name": "cstk",
  "description": "Toolkit de documentacao e SDD para Claude Code",
  "author": { "name": "JotJunior" }
}
```

**Nota de veracidade**: nao ha campo enumerando `skills/`/`commands/`/
`agents/`. Manifestos oficiais reais (S2, ex. `plugin-dev`) nao os
declaram — a descoberta e por convencao de diretorio. Inventar um campo de
entry points seria fabricar schema.

## Artefato 3: `plugins/cstk-language-go/.claude-plugin/plugin.json`

```json
{
  "name": "cstk-language-go",
  "description": "Perfil Go do cstk",
  "author": { "name": "JotJunior" }
}
```

## Artefato 4: `plugins/cstk/hooks/hooks.json`

```json
{
  "description": "Guardas enforced do cstk: interceptacao de Bash + metricas de tool call",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "sh \"${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "sh \"${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "sh \"${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Invariantes

| Id | Invariante | Razao |
|----|-----------|-------|
| HK-1 | Conjunto de eventos/matchers **identico** ao `settings.snippet.json` classico | FR-005: efeito equivalente a uma unica camada |
| HK-2 | `posttooluse-loose-usage.sh` **ausente** | Opt-in explicito nao vira default (research.md D2) |
| HK-3 | Todo `command` invoca via `sh "<path>"` | Cobre A5 (bit `+x` pode nao sobreviver ao cache) |
| HK-4 | Todo path e prefixado por `${CLAUDE_PLUGIN_ROOT}` | Portabilidade (FR-009) |
| HK-5 | `timeout: 5` (paridade com o classico) | Nao alterar comportamento de guarda |

## Artefato 5: `_resolve-root.sh` (helper sourceable)

**Local**: `plugins/cstk/skills/agente-00c-runtime/scripts/_resolve-root.sh`
**Tipo**: POSIX sh sourceable (Constitution II).

### Interface

| Simbolo | Tipo | Contrato |
|---------|------|----------|
| `resolve_runtime_root` | funcao | stdout = path absoluto da raiz de `agente-00c-runtime`; exit 0 |
| — | erro | exit 1 + diagnostico em **stderr** listando os candidatos tentados (FR-012) |

### Ordem de precedencia (normativa) — **duas ordens, por criticidade**

Candidato so e aceito se o diretorio existir **e** conter `scripts/`.

**Ordem A — consumidores gerais** (hooks de metrica, CLIs do runtime):

| Ordem | Candidato | Quando |
|-------|-----------|--------|
| 1 | `${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime` | Sessao com plugin habilitado |
| 2 | `dirname $0`/.. (irmao do script) | DEV / execucao in-place |
| 3 | `$HOME/.claude/skills/agente-00c-runtime` | Instalacao classica |
| 4 | — | erro diagnostico |

**Ordem B — consumidor fail-CLOSED** (`pretooluse-bash-guard.sh`):
**sibling ANTES da variavel de ambiente**.

| Ordem | Candidato | Quando |
|-------|-----------|--------|
| 1 | `dirname $0`/.. (irmao do proprio script) | Sempre que resolver |
| 2 | `${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime` | Fallback |
| 3 | `$HOME/.claude/skills/agente-00c-runtime` | Fallback |
| 4 | — | `MECANISMO_FALHOU` (bloqueia) |

> **Por que a inversao (finding de seguranca F3, severidade MEDIUM)**:
> `pretooluse-bash-guard.sh` carrega o motor de regras (`bash-guard.sh`) por
> essa cascata. Se a raiz vier de uma **variavel de ambiente**, qualquer
> processo pai capaz de exportar `CLAUDE_PLUGIN_ROOT` pode apontar o guard
> para um `bash-guard.sh` permissivo — **neutralizando um guard fail-closed
> sem disparar nenhum erro** (o guard continuaria "funcionando", so que
> aprovando tudo). O proprio script do hook, ao contrario, foi lancado pelo
> harness a partir de um path ja resolvido e confiavel: seu diretorio irmao
> e a ancora mais forte disponivel.
>
> Severidade MEDIUM (nao HIGH) porque o ataque exige controle previo do
> ambiente do processo — quem o tem tambem poderia editar
> `~/.claude/skills/` diretamente. A inversao e adotada mesmo assim por ser
> **custo zero** e eliminar uma classe inteira de shadowing.
>
> A funcao `resolve_runtime_root` MUST aceitar um parametro de modo
> (ex.: `resolve_runtime_root strict`) para selecionar a Ordem B, em vez de
> duplicar a cascata num segundo helper.

### Politica de falha por consumidor (resolve a tensao FR-012 × fail-open)

| Consumidor | Politica atual | Ao NAO resolver |
|------------|----------------|------------------|
| `pretooluse-bash-guard.sh` | fail-CLOSED | Bloqueia com `MECANISMO_FALHOU` (ja e sua politica) |
| `posttooluse-tool-call-tick.sh` | fail-OPEN | Linha de diagnostico no sidecar; **exit 0** |
| `posttooluse-agent-usage.sh` | fail-OPEN | Idem; **exit 0** |
| `posttooluse-loose-usage.sh` | fail-OPEN | Idem; **exit 0** |
| `guard-hooks-status.sh`, `issue.sh` | CLI comum | exit != 0 + stderr |

> **Invariante inegociavel**: a introducao do helper **MUST NOT** alterar a
> polaridade (fail-open/fail-closed) de nenhum consumidor. FR-012 e
> satisfeito pelo canal de diagnostico, nao por mudanca de exit code de
> hook de metrica — inverter isso faria um hook de metrica interferir numa
> tool call, regressao direta do desenho documentado em S7.
