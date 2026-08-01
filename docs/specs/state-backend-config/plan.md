# Implementation Plan: Configuração de Backend do state.db (Cutover Fase 2)

**Feature**: `state-backend-config` | **Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)

## Summary

A Fase 1 (`state-db-foundation`, linha v6) entregou o backend SQLite completo —
schema, primitivas dual-backend, migração explícita — mas o backend só é
selecionado pela **presença** de um `state.db` no diretório de estado
(`_state-rw-db.sh:41-48`), e `state-rw.sh init` **nunca** cria esse arquivo
(`state-rw.sh:390-395`). Consequência: hoje só se chega ao SQLite migrando um
projeto já existente; nenhuma execução **nova** nasce em SQLite.

Esta feature fecha esse cutover introduzindo uma configuração global
por-usuário (`~/.claude/cstk/config`, texto plano `key=value`), um comando
explícito de ativação com fail-fast (`cstk state enable-sqlite`) e um diagnóstico
de dependências utilizável como gate de CI (`cstk doctor --deps`).

A decisão técnica central é a **fonte única de leitura** (research.md Decision 2):
a config é interpretada por um só script do runtime, e o binário `cstk` **delega**
a ele em vez de reimplementar — o mesmo padrão de delegação que `cli/lib/state.sh`
já usa com `state-db-migrate.sh`. É isso que torna SC-004 (0% de divergência entre
o caminho do binário e o caminho do runtime) verdadeiro **por construção**, não por
disciplina.

## Technical Context

**Language/Version**: POSIX `sh` puro (sem bash-isms) — Princípio II da constitution
**Primary Dependencies**: `sqlite3` ≥ 3.45.1; `jq`. Ambas são deps **obrigatórias
confinadas à camada de estado transacional**, autorizadas pelo carve-out do
amendment 1.3.0 da constitution — que autoriza a obrigatoriedade mas **não fixa
versão**. O piso numérico `3.45.1` vem da Fase 1
(`docs/specs/state-db-foundation/research.md:320-336`, menor versão real entre
macOS local e o runner de CI). **O leitor da config não depende de nenhuma das
duas** — ver Constitution Check
**Storage**: arquivo de texto plano `key=value` em `$HOME/.claude/cstk/config`
(diretório já existente — abriga `knowledge.db`)
**Testing**: harness POSIX do repositório (`./tests/run.sh`); convenção de
mapeamento: `cli/lib/<n>.sh` → `tests/cstk/test_<n>.sh`,
`global/skills/<X>/scripts/<n>.sh` → `tests/test_<n>.sh`
(`./tests/run.sh --check-coverage` gateia órfãos)
**Target Platform**: macOS e Linux (dev em macOS/zsh; CI em Ubuntu) — sem GNU-only
**Project Type**: CLI tool + runtime de scripts
**Performance Goals**: N/A — leitura de um arquivo de poucas linhas, uma vez por
inicialização
**Constraints**: nenhuma escrita na config antes de todas as pré-condições passarem
(FR-004); config ausente/inválida nunca falha inicialização nem diagnóstico (FR-008)
**Scale/Scope**: um arquivo de config por usuário do SO; 42 scripts no runtime
`agente-00c-runtime` hoje

**NEEDS CLARIFICATION restantes**: 0

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (NON-NEGOTIABLE) | PASS | A feature é ela própria conduzida pelo pipeline SDD: `spec.md` ratificada e clarificada (3/3 respostas integradas) antes deste plano; `checklist` e `create-tasks` seguem |
| II. POSIX sh puro, zero dependência externa (NON-NEGOTIABLE) | PASS (com carve-out declarado) | Ver análise dedicada abaixo |
| III. Formato canônico de skill | N/A | A feature não cria nem altera nenhuma skill. Toca `cli/lib/` e os scripts do runtime `agente-00c-runtime` (que é runtime interno, não skill user-invocável) |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Tudo é local: um arquivo em `$HOME` e invocações de binários locais. Nenhuma rede, nenhuma telemetria |
| V. Profundidade e redução de retrabalho acima de métricas de adoção | PASS | A checagem ativa de capability (FR-004A) existe exclusivamente para evitar o retrabalho de diagnosticar "ativei e não funcionou" — custo pago no comando, não pelo operador |
| VI. Veracidade de dados — zero fabricação (NON-NEGOTIABLE) | PASS | Toda afirmação sobre código existente nos artefatos cita arquivo + linha verificados; toda superfície ainda inexistente está marcada `[PROPOSTA — a validar na implementação]`. Nenhum caminho, flag ou assinatura foi suposto |

### Princípio II — análise detalhada

O bloco MUST do Princípio II proíbe dependências obrigatórias. Esta feature opera
sob o **carve-out do amendment 1.3.0** (*Mandatory dependency carve-out:
transactional state layer*), cujas quatro condições cumulativas são verificadas
abaixo:

| Condição do carve-out | Status | Como esta feature satisfaz |
|-----------------------|--------|----------------------------|
| (a) Confinamento de camada | PASS | A obrigatoriedade de `sqlite3` permanece restrita ao `state.db` e às primitivas de acesso. Esta feature **não** amplia o alcance: ela adiciona um *gate* que verifica a dependência antes de permitir optar pelo backend. Nenhuma skill de documentação, o CLI de catálogo ou os hooks passam a exigir `sqlite3` |
| (b) Fail-fast diagnóstico | PASS | É literalmente o objeto de FR-004: ausência ou versão insuficiente produz erro imediato citando versão exigida × detectada, mais instrução. Coberto pelos Scenarios 2 e 3 do quickstart |
| (c) Consumidores derivados degradam gracioso | PASS | Nada muda para `knowledge.db`/`recall`, painel ou relatórios. Além disso, **o próprio leitor da config não depende de `jq` nem de `sqlite3`** (research.md Decision 1): formato `key=value` justamente para poder rodar e reportar quando essas ferramentas faltam |
| (d) Declaração explícita na feature | PASS | Esta seção, mais `spec.md` FR-003/FR-004 e research.md Decisions 1 e 4 |

**Ponto de atenção deliberado**: a escolha do formato `key=value` (em vez de JSON
via `jq`) não é preferência estética — é o que permite ao diagnóstico FR-007
reportar a **ausência de `jq`** como anomalia. Um leitor de config que dependesse
de `jq` seria incapaz de rodar exatamente no cenário que precisa diagnosticar.

## Project Structure

### Documentation (this feature)

```
docs/specs/state-backend-config/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/       # Phase 1 output
    ├── cli-surface.md
    └── state-backend-runtime.md
```

### Source Code (repository root)

Árvore real do repositório, com os pontos de toque desta feature marcados:

```
cstk/
├── cli/
│   ├── cstk                          # binário; dispatch de subcomandos  [ALTERAR]
│   └── lib/
│       ├── state.sh                  # `cstk state` — só `migrate` hoje  [ALTERAR]
│       ├── doctor.sh                 # `cstk doctor` — `--fix`/`--scope` [ALTERAR]
│       ├── config.sh                 # leitor/delegador da config global [NOVO]
│       ├── common.sh
│       └── ... (23 libs no total)
├── global/
│   └── skills/
│       └── agente-00c-runtime/
│           └── scripts/              # 42 scripts POSIX
│               ├── state-backend.sh  # fonte ÚNICA da config            [NOVO]
│               ├── state-rw.sh       # `init` passa a honrar a config   [ALTERAR]
│               ├── _state-rw-db.sh   # `_sr_backend` (presença)  — intacto
│               ├── state-db-schema.sh# `create --db`  — reusado, intacto
│               └── state-db-migrate.sh# migração       — intacto
├── tests/
│   ├── test_state-backend.sh         # cobre state-backend.sh           [NOVO]
│   ├── test_state-rw.sh              # extensão: init honra config      [ALTERAR]
│   └── cstk/
│       ├── test_config.sh            # cobre cli/lib/config.sh          [NOVO]
│       ├── test_state.sh             # extensão: enable-sqlite          [ALTERAR]
│       └── test_doctor.sh            # extensão: --deps                 [ALTERAR]
└── docs/
    ├── constitution.md               # v1.3.0 — não requer amendment
    └── specs/state-backend-config/
```

**Structure Decision**: a lógica vive no **runtime** (`state-backend.sh`), não no
CLI. `cli/lib/config.sh` é uma camada fina de delegação, seguindo o padrão já
estabelecido por `cli/lib/state.sh` → `state-db-migrate.sh`. Três razões:

1. **SC-004 por construção** — uma única implementação não pode divergir de si mesma.
2. **Direção correta da dependência** — quem precisa da config é o runtime (é
   `state-rw.sh init` que cria o estado). O inverso obrigaria o runtime a depender
   de `cli/lib/`, que **não é instalado junto com as skills**: `cstk install`/`update`
   tocam só o catálogo; o runtime do CLI vai por `cstk self-update` (GOTCHA
   registrado no `CLAUDE.md`).
3. **Testabilidade** — o harness POSIX do runtime já cobre esse tipo de script, e
   a convenção de mapeamento de testes gateia a cobertura automaticamente.

## Convenções de Borda

A feature **não** é single-layer: existe uma borda real, e é exatamente onde mora
o risco que SC-004 mede — **binário `cstk` ↔ runtime dos orquestradores**. Duas
implementações do mesmo parser driftariam silenciosamente, e o sintoma
(inicializações usando o backend errado) apareceria longe da causa.

| Camada | Formato / convenção | Validação | Fonte da verdade |
|--------|---------------------|-----------|------------------|
| Arquivo de config (disco) | `key=value`, uma linha por par; `#` = comentário; `snake_case` nas chaves | Parse tolerante: chave desconhecida ignorada; formato inválido ⇒ fallback (FR-008) | `$HOME/.claude/cstk/config` |
| Leitura da config | subcomando `resolve` | Contrato de não-falha: sempre exit 0 | `global/skills/agente-00c-runtime/scripts/state-backend.sh` **[PROPOSTA]** |
| Superfície de operador (`cstk`) | subcomandos e flags em `kebab-case` (`enable-sqlite`, `--deps`) | Delegação pura; exit code repassado verbatim | `cli/lib/config.sh` → delega ao script acima |
| Consumo na inicialização | resultado de `resolve` | Guardas L390-395 / L397-400 preservadas | `global/skills/agente-00c-runtime/scripts/state-rw.sh` (`init`) |
| Resolução de caminho do script | 3 camadas: `PATH` → repo via `CSTK_LIB` → `~/.claude` | A camada de repo é obrigatória (CI fresh-checkout) | padrão de `_state_migrate_script_path`, `cli/lib/state.sh:44-66` |

**Mapper layer**: N/A — não há transformação de formato entre camadas. O valor
(`sqlite` \| `json`) atravessa todas as camadas **literalmente**, sem tradução de
case nem de nome. Essa ausência de mapeamento é deliberada: é o que elimina a
classe de bug que a seção de Convenções de Borda existe para prevenir.

**Validação de schema**: N/A — não há Zod/JSON Schema. A validação é a checagem de
domínio do enum (`sqlite` \| `json`), feita num único ponto (`resolve`).

## Riscos e mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Binário novo + catálogo antigo: ativação "sucede" mas `init` ignora a config | Alto — falha **silenciosa**, viola SC-001 sem erro visível | FR-004A: checagem **ativa** de capability antes de escrever. Ausência do script já é o sinal (research.md Decision 5) |
| Reintrodução de um parser paralelo no CLI "por conveniência" | Alto — reabre a divergência que SC-004 mede | Quickstart Scenario 9 compara empiricamente os dois caminhos nas 6 combinações; sem ele a unicidade é convenção, com ele é contrato |
| Comparação de versão lexicográfica (`"3.9.0" > "3.45.1"`) | Alto — permitiria ativar com versão insuficiente, **silenciosamente** | research.md Decision 4: comparação numérica campo-a-campo, sem `sort -V` (não-POSIX) |
| Teste de "dependência ausente" via stub de `PATH` | Médio — passa local, quebra no CI (ou vice-versa) | GOTCHA no Scenario 3: stub de `PATH` não esconde binário em `/usr/bin`; desacoplar o lookup do SUT |
| Teste vazando para o `HOME` real do operador | Médio — ativaria o backend na máquina do operador | Nota de isolamento no topo do quickstart: `HOME` temporário obrigatório |
| `set -e` + `x=$(cmd); rc=$?` matando o shell | Médio — falha de captura mascarada | research.md Decision 8: forma `if x=$(cmd); then` obrigatória em toda captura |

## Superfície de segurança

Revisão de design (gate `owasp-security`) sobre a arquitetura proposta. A feature
não tem autenticação, rede, nem dados sensíveis — o modelo de ameaça relevante é
**execução local**: um arquivo de configuração e um script executável, ambos
consumidos automaticamente por um orquestrador autônomo a cada nova inicialização
de execução. Os controles abaixo são **vinculantes para a implementação**, não
sugestões.

| ID | Risco | OWASP / CWE | Sev. | Controle obrigatório |
|----|-------|-------------|------|----------------------|
| SEC-01 | Parsing da config por `.` (source) ou `eval` | A05 Injection / CWE-78 | **Alta** (pré-mitigação) | O leitor **MUST NOT** usar `.`/`source`/`eval` sobre o arquivo. Parse linha a linha, split no **primeiro** `=`, sem executar nada |
| SEC-02 | Valor da config usado sem validação de domínio | A05 / CWE-20 | Média | O valor **MUST** ser validado contra a allowlist `sqlite`\|`json` **antes** de qualquer uso. Valor fora do domínio ⇒ tratado como config inválida ⇒ fallback `json` (FR-008), nunca repassado adiante |
| SEC-03 | Capability validada num runtime ≠ do que executará | A08 Integrity | Média | Ver análise dedicada abaixo |
| SEC-04 | Resolução do script via `PATH` (`command -v`) | A03 Supply Chain / CWE-426 | Baixa | Risco herdado do padrão existente; aceito com o modelo de ameaça declarado abaixo |
| SEC-05 | Config com permissão de escrita para outros | A02 Misconfiguration | Baixa | Diretório criado com `700` e arquivo com `600`, coerente com `_state_db_secure_perms` (`_state-db.sh:147-152`), que já aplica `600` ao `state.db` |
| SEC-06 | Escrita não-atômica / TOCTOU | CWE-367 / CWE-59 | Baixa | `mktemp` no **mesmo diretório** + `mv` (Decision 7). `mv` substitui o alvo sem seguir symlink, o que também neutraliza troca de link |

### SEC-01 — por que é o item mais importante desta feature

Um arquivo `key=value` é sintaticamente **shell válido**, o que torna
`. "$CONFIG"` o atalho mais tentador — e o mais perigoso. Uma linha como
`state_backend=$(comando)` seria **executada** no momento da leitura.

O agravante é o consumidor: a config é lida por `state-rw.sh init`, ou seja, em
**toda nova inicialização de execução 00c**, dentro de um orquestrador autônomo.
Isso transforma uma edição de arquivo em execução de código no contexto do agente
(ASI02 Tool Misuse / ASI05 Code Execution do OWASP Agentic 2026).

Verificado que **hoje nenhum script do repositório faz source de arquivo de dados**
(`grep` por `. "$…CONFIG"` em `cli/lib/` e nos 42 scripts do runtime: nenhum
resultado) e que **não existe precedente de parser `key=value`** no toolkit. Esta
feature escreve o primeiro — motivo pelo qual o controle precisa estar fixado no
plano, e não descoberto na revisão de código.

### SEC-03 — catálogo instalado × árvore do repo

A checagem de capability (FR-004A) só tem valor se validar **o mesmo runtime que
de fato executará** a inicialização. O resolvedor de três camadas pode divergir:
rodando da árvore do repo, a camada `CSTK_LIB` resolve para
`global/skills/agente-00c-runtime/scripts/`, enquanto uma execução 00c real
consome o catálogo instalado em `~/.claude/skills/`. Validar um e executar o outro
produz exatamente o falso "sucesso" que FR-004A existe para impedir.

**Controle**: `enable-sqlite` MUST reportar **qual caminho** foi validado. Como a
config é global por-usuário e serve às execuções 00c (que usam o catálogo
instalado), a checagem de capability MUST priorizar o catálogo instalado quando
ambos existirem — divergindo deliberadamente da ordem de `_state_migrate_script_path`,
cuja prioridade em `PATH`/repo serve a testes e CI, não a esta decisão.

### SEC-04 — modelo de ameaça aceito

A camada 1 do resolvedor usa `command -v`, isto é, confia no `PATH`. Um `PATH`
contendo diretório gravável por terceiros permitiria sequestrar a resolução. O
risco é aceito porque: (a) é o padrão **já vigente** para `state-db-migrate.sh` —
esta feature não amplia a superfície, apenas a reutiliza; (b) o atacante precisa
já controlar o `PATH` do usuário, posição da qual pode executar código
diretamente, sem passar por este vetor. Registrado explicitamente para não ser
redescoberto como novidade numa auditoria futura.

### Avaliação positiva — fail-safe direcionalmente correto

FR-008 (config ausente/inválida ⇒ fallback `json`) degrada para o
**comportamento legado já vigente**, não para o caminho novo e mais privilegiado.
Um arquivo corrompido nunca promove uma execução a SQLite silenciosamente — a
promoção exige ativação explícita com as três pré-condições satisfeitas. Isso é
fail-closed em relação à mudança de comportamento, que é a direção certa.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa

**Nenhuma violação.** O Constitution Check passou em todos os princípios aplicáveis.
O uso de `sqlite3` como dependência obrigatória não é violação: opera dentro do
carve-out do amendment 1.3.0, cujas quatro condições estão verificadas na seção
Princípio II acima. Nenhuma emenda à constitution é necessária para esta feature.

## Re-check pós-Phase 1

Revalidação após o design (data-model, contratos e quickstart concluídos):

| Verificação | Resultado |
|-------------|-----------|
| O design introduziu complexidade não justificada? | Não. Dois arquivos novos (`state-backend.sh`, `cli/lib/config.sh`), sendo o segundo uma camada fina de delegação. Nenhuma abstração especulativa |
| Princípios MUST continuam respeitados? | Sim. II opera sob carve-out declarado e verificado; IV e VI inalterados pelo design |
| O design ampliou o alcance da dep obrigatória? | Não. `sqlite3` continua confinado à camada de estado transacional; o leitor da config roda sem ele e sem `jq` |
| Alguma superfície foi afirmada como existente sem verificação? | Não. `cli-surface.md` e `state-backend-runtime.md` abrem com bloco `[PROPOSTA]` explícito e citam os greps que confirmam a inexistência atual |
| Restou algum `NEEDS CLARIFICATION`? | Não — 0 |

**Constitution Check pós-design: PASS.**

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/state-backend-config/plan.md | Criado |
| docs/specs/state-backend-config/research.md | Criado |
| docs/specs/state-backend-config/data-model.md | Criado |
| docs/specs/state-backend-config/contracts/cli-surface.md | Criado |
| docs/specs/state-backend-config/contracts/state-backend-runtime.md | Criado |
| docs/specs/state-backend-config/quickstart.md | Criado |

## Próximos Passos

1. `/checklist` — gerar quality gate antes de implementar
2. `/create-tasks` — decompor o plano em backlog executável
3. `/analyze` — após ter tasks, validar consistência cross-artifact
