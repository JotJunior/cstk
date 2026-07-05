# Data Model: enforced-guards

Nenhuma entidade aqui e uma tabela de banco de dados — todas sao registros em
arquivo (JSON/JSONL/texto), no mesmo espirito ja usado pelo runtime
`agente-00c` (`state.json`, whitelist por-execucao). Campos e tipos abaixo sao
desenho tecnico desta feature ([PROPOSTA] onde indicado); nenhum reflete um
contrato externo ja existente fora do controle deste toolkit.

## Entity: GuardHookRegistration

Representa a configuracao de interceptacao provisionada num projeto-alvo (ou
globalmente) — o registro vive dentro do `settings.json` do harness (nao um
arquivo proprio desta feature), sob a chave `"hooks"."PreToolUse"` (contrato
externo, ver `contracts/pretooluse-hook.md`). Modelado aqui como a VIEW logica
que o `cstk install`/`cstk update` provisiona.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| matcher | string | fixo `"Bash"` | so intercepta a tool Bash (FR-001); nao Edit/Write |
| hook_type | enum | `"command"` | unico tipo usado; suportado pelo harness |
| command_path | string | resolvido via `$CLAUDE_PROJECT_DIR` | path para `pretooluse-bash-guard.sh` provisionado em `.claude/hooks/` do projeto-alvo |
| timeout | int (segundos) | `[PROPOSTA] 5` | evita travar a sessao se o hook penderar; falha por timeout cai no mesmo tratamento de FR-007 (mecanismo falhou) do lado do harness |
| provisioned_by | enum | `install` \| `update` | proveniencia (Decision 9), nao persistida no settings.json em si — usada so para relato de instalacao |
| scope | enum | `project` | `global` sempre omitido (Decision 9) |

### Relationships

- `GuardHookRegistration` 1:N `EnforcementDecisionLog` — cada comando Bash
  interceptado por um hook registrado gera zero ou uma entrada de log
  (zero quando fora do escopo de execucao ativa, FR-006/Decision 3).

### State Transitions

N/A — e configuracao estatica escrita uma vez por instalacao/atualizacao,
sem ciclo de vida proprio (sobrescrita idempotente a cada `install`/`update`,
via `merge_settings`, target vence em conflito).

---

## Entity: EnforcementDecisionLog

Registro auditavel (FR-016) de UM comando Bash processado pela camada enforced
(US1), permitido ou bloqueado — distinguivel das invocacoes advisory (que nao
escrevem aqui; advisory continua so no `state.json`/decisions do orquestrador).
Persistencia: JSONL append-only, `<projeto-alvo>/.claude/enforcement-log.jsonl`
(Decision 5). Uma linha = um JSON compacto.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| timestamp | string (ISO 8601 UTC) | NOT NULL | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| outcome | enum | `blocked-by-rule` \| `blocked-mechanism-failure` \| `allowed` | `allowed` so e logado quando houve execucao ativa detectada (Decision 3) — fora desse escopo o hook nem escreve linha (evita volume irrelevante de sessoes interativas comuns) |
| command | string | **ordem OBRIGATORIA**: `secrets-filter.sh scrub` PRIMEIRO, truncagem a 500 chars DEPOIS (CHK020 [Ambiguity], task 1.4) — nunca o inverso, truncar antes cortaria um token no meio e deixaria o fragmento restante fora do alcance do regex de scrub | o `.tool_input.command` interceptado, ja filtrado (Decision 10 de `research.md`, achado do gate `owasp-security` — MUST, nao mais adiavel); pipeline: `scrub \| cut -c1-500`; caso adversarial obrigatorio em `contract/enforcement-log.md` (token atravessando a posicao 500) |
| reason | string | NOT NULL quando outcome != `allowed` | equivalente a `permissionDecisionReason` emitido ao harness |
| category | string \| null | ex: `git-push`, `rm-recursive`, `network-not-whitelisted`, `mechanism-error` | mesma taxonomia de categoria ja emitida por `bash-guard.sh` (`_bg_emit_block`) |
| detected_execution | enum | `agente-00c` \| `feature-00c` | qual state.json disparou a deteccao de "execucao ativa" (Decision 3) |
| detected_execution_path | string | path resolvido | `<cwd>/.claude/agente-00c-state/state.json` ou o `feature-00c-state/<short>/state.json` casado |

### Precedencia deterministica quando ha MAIS DE UMA execucao ativa (CHK007 [Gap], task 1.3)

Cenario: `cwd` tem simultaneamente `.claude/agente-00c-state/state.json` COM
`.execution.status = "em_andamento"` E um ou mais
`.claude/feature-00c-state/<short>/state.json` tambem `em_andamento` (ex:
`cstk session` legitimamente roda multiplas features em paralelo, cada uma
em sua propria worktree — ver CLAUDE.md §Sessoes paralelas). O hook precisa
de UMA regra deterministica para preencher `detected_execution`/
`detected_execution_path` — nao pode depender de ordem de leitura do
filesystem (mtime/inode variam por SO e nao sao reproduziveis em teste).

**Regra (ordem de checagem, primeira que casar vence)**:

1. `agente-00c-state/state.json` com status `em_andamento` (ou
   `aguardando_humano`) — SE presente, `detected_execution = "agente-00c"`,
   `detected_execution_path` = esse arquivo. Precedencia sobre qualquer
   feature-00c: agente-00c orquestra o projeto inteiro (escopo maior) e os
   proprios orquestradores ja tratam essa combinacao como preferencial —
   `feature-00c` MUST abortar ao detectar `agente-00c` ativo no seu proprio
   pre-flight (FR-026 de `agente-00c-feature-orchestrator.md`), entao um
   `agente-00c` ativo e o sinal mais forte de "execucao autonoma em curso"
   quando ambos aparecem (janela de corrida entre o pre-flight de um
   orquestrador e a escrita do outro, nao eliminada por aquele guard).
2. Caso contrario, entre os `feature-00c-state/<short>/state.json` com
   status `em_andamento`, ordenar por **ordem lexicografica (byte-wise,
   `C` locale) do `<short>`** e escolher o PRIMEIRO. Lexicografico (nao
   mtime/ordem de `glob`) porque e 100% deterministico e testavel com uma
   fixture fixa (duas pastas `<short>` quaisquer sempre produzem o mesmo
   vencedor, independente de SO/timing de criacao).
3. Nenhum dos dois presente/ativo -> fora de escopo (Decision 3),
   `exit 0` sem decisao.

Esta regra so decide QUAL execucao e citada no log quando mais de uma esta
ativa — nao muda a decisao de bloqueio em si (`bash-guard.sh check` roda
igual, independente de qual execucao foi detectada); o campo existe apenas
para auditoria/rastreabilidade (FR-016), respondendo "qual execucao estava
em curso quando este comando foi avaliado".

### Relationships

- N:1 com `GuardHookRegistration` (todo log vem de uma invocacao do hook
  registrado).

### State Transitions

N/A — append-only, sem update/delete de linhas existentes (auditoria
imutavel, mesmo espirito de `state-history/` do runtime agente-00c).

---

## Entity: IntegrityVerificationOutcome

Resultado de uma tentativa de confirmar integridade de um pacote baixado pelo
painel web (US2). Persistido em duas formas: (a) efeito imediato (bloqueia ou
prossegue a instalacao do painel, `serve.sh`); (b) quando ha bypass explicito,
uma entrada auditavel no MESMO arquivo JSONL de `EnforcementDecisionLog`
(Decision 6) — reuso do arquivo, discriminado pelo campo `source`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| timestamp | string (ISO 8601 UTC) | NOT NULL | |
| source | string | fixo `"serve-integrity"` | discrimina de entradas de US1 no mesmo arquivo |
| outcome | enum | `verified` \| `unverifiable-blocked` \| `unverifiable-bypassed` \| `mismatch-blocked` | `verified` = `.sha256` obtido e confere (comportamento ja existente, preservado); `mismatch-blocked` = ja existente hoje (preservado, FR-010); os dois `unverifiable-*` sao o comportamento NOVO desta feature (substituem o antigo "so aviso e prossegue") |
| package_url | string | | URL do tarball do cstk-panel avaliado |
| expected_sha256 | string \| null | | null quando `.sha256` nao pode ser obtido |
| actual_sha256 | string \| null | | sha256 calculado localmente do tarball baixado |
| bypass_method | enum \| null | `flag` \| `env` \| null | `flag` = `--allow-unverified`; `env` = `CSTK_SERVE_ALLOW_UNVERIFIED=1`; null quando outcome != `unverifiable-bypassed` |

### Relationships

- Nenhuma FK — entidade standalone, ligada apenas por convencao de arquivo
  compartilhado com `EnforcementDecisionLog`.

### State Transitions

```
download-iniciado → (sha256 obtido?)
  sim → confere? → verified
               → nao confere → mismatch-blocked (ja existente, preservado)
  nao → operador optou por --allow-unverified/env?
               → sim → unverifiable-bypassed
               → nao → unverifiable-blocked (NOVO — default desta feature)
```

---

## Entity: TrustedHostAllowlist

Conjunto ESTATICO (nivel-toolkit, nao por-execucao) de hosts aceitos como
origem de artefatos de release para `install`/`self-update`/`serve`
(Decision 7). Distinto do `agente-00c-whitelist`/`.agente-00c-whitelist.txt`
por-execucao (Decision 8), que continua existindo sem mudanca.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| host | string | dominio exato, sem wildcard | os 4 valores: `github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `api.github.com` — fonte: `cli/lib/serve.sh:31`, ja em producao |
| applies_to | enum[] | subconjunto de `{install, self-update, serve}` | v1 desta feature: todos os 4 hosts aplicam-se aos 3 consumidores igualmente (nenhuma diferenciacao por-consumidor identificada nas fontes) |

### Relationships

- Nenhuma — lista estatica embutida em `[PROPOSTA] cli/lib/trusted-hosts.sh`
  (Decision 7), sem persistencia em arquivo separado no projeto-alvo (ao
  contrario de `agente-00c-whitelist`, que e por-projeto/por-execucao).

### State Transitions

N/A — constante versionada no proprio toolkit; muda apenas via release nova
do cstk (nao em runtime).
