# Requirements Checklist: cstk-setup

**Purpose**: Validar qualidade (completude, clareza, consistencia, mensurabilidade)
dos requisitos de `spec.md`, apos o endurecimento pos-`owasp-security`
(achados SEC-01/SEC-02/SEC-03) aplicado a `plan.md`/`data-model.md`/
`contracts/cli-setup.md`/`quickstart.md` nesta mesma onda.
**Created**: 2026-08-07
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Sao os quatro dominios de configuracao e sua ordem fixa de apresentacao definidos sem ambiguidade? [Completude, Spec §FR-001] {auto}
  - Evidencia: FR-001 enumera explicitamente hooks (com loose-usage aninhado), state backend, MCP, telemetria, "in a fixed order".
- [x] CHK002 - E definida, para cada area, a fonte de deteccao read-only e a proibicao de reimplementa-la em `setup.sh`? [Completude, Spec §FR-002] {auto}
  - Evidencia: `plan.md` Summary ("setup.sh e uma camada de orquestracao pura... nenhuma deteccao nem escrita propria") + `data-model.md` tabela "Fonte de status por area" (4 linhas, uma por area).
- [x] CHK003 - Os 3 achados de seguranca que alteravam contrato/data-model (SEC-01/02/03) ficaram integralmente refletidos em FR-016 apos o hardening desta onda? [Completude, Spec §FR-016] {auto}
  - Evidencia: `contracts/cli-setup.md` §2.3 (token `"command"` exigido — SEC-01), `data-model.md` invariante I5 (`indeterminate` → `unavailable` — SEC-02), `data-model.md` tabela de fontes linha `hooks` (3 chamadas separadas — SEC-03).
- [ ] CHK004 - Os 4 achados de seguranca restantes (SEC-04..SEC-07, sem impacto em contrato/data-model) tem destino explicito para nao virarem debito silencioso? [Completude] {auto} [Gap]
  - Nao totalmente satisfeito: estao registrados em `plan.md` §Re-check de Constitution com o que cada um exige, mas **ainda nao existem como tarefas** em `tasks.md` (arquivo nem existe — `create-tasks` e a proxima etapa). Destino: `/create-tasks` MUST consumir os 4 achados como tarefas explicitas (nao apenas herdar a prosa do plan.md).

## Clareza de Requisitos

- [ ] CHK005 - E "default recomendado" (FR-005) quantificado numa unica fonte rastreavel, cobrindo as 4 areas e a escolha aninhada de loose-usage? [Clareza, Spec §FR-005] {auto} [Gap]
  - Nao consolidado: o default de cada area esta espalhado em 4 locais distintos — `data-model.md` (`loose_usage_choice` default=`skip`), `plan.md` §Analise Principio IV ("unica area cujo default recomendado e 'nao'"), FR-015 (MCP aplica mesmo sem Docker) e `data-model.md` `applicable=false` para telemetria. Nenhum artefato tem uma tabela unica "area → default em `--yes`". Recomendado como tarefa de consolidacao documental no `create-tasks` (baixo risco, custo de manutencao).
- [x] CHK006 - FR-018 ("nao expor override de catalogo") e formulado de forma objetivamente testavel? [Clareza, Spec §FR-018] {auto}
  - Evidencia: `contracts/cli-setup.md` §2.4 nota FR-018 (tabela dos dois knobs de catalogo + por que nenhum e exposto) + `quickstart.md` Scenario 16 (`--catalog` → exit 2, `CSTK_HOOKS_CATALOG_DIR` → area anuncia referencia nao-padrao).
- [x] CHK007 - A regra de decisao pos-hardening SEC-01 ("linha canonica") esta redigida sem termo vago, com o residual aceito declarado explicitamente (nao verificado textualmente)? [Clareza, Spec §FR-016] {auto}
  - Evidencia: `contracts/cli-setup.md` §2.3, bloco "Correcao pos-gate (achado SEC-01, MEDIUM)" declara literalmente o limite ("nao verifica posicionamento estrutural").

## Consistencia de Requisitos

- [x] CHK008 - FR-005 ("aplica o default para toda area nao configurada") e FR-012 ("telemetria NUNCA escreve fora do projeto") sao consistentes entre si? [Consistencia, Spec §FR-005, §FR-012] {auto}
  - Evidencia: `data-model.md` `ConfigurationArea.applicable=false` para `telemetry` resolve a tensao — a area e sempre diagnosticada, nunca "aplicada" no sentido de escrita, mesmo sob `--yes`.
- [x] CHK009 - FR-009 (falha isolada por area, nunca crash do wizard inteiro) permanece consistente apos a introducao do status `unavailable` para `hooks` via 5a coluna `indeterminate` (SEC-02)? [Consistencia, Spec §FR-009] {auto}
  - Evidencia: `quickstart.md` Scenario 15 variante 4, texto explicito: "nao uma excecao/crash da area (FR-009 segue intacto: a area reporta um status valido do enum fechado, o wizard nao aborta)".
- [x] CHK010 - A tabela de fontes de `data-model.md` (hooks: 3 chamadas separadas, SEC-03) permanece consistente com o Scenario 10 pre-existente (loose-usage ja era chamada separada)? [Consistencia, Spec §FR-009] {auto}
  - Evidencia: Scenario 10 (pre-existente) ja isolava `--include-loose-usage`; o fix SEC-03 estende a mesma disciplina para `--verify-registration`, que ate entao estava descrita como combinada com a baseline — sem conflito entre os dois scenarios apos o fix (`quickstart.md` Scenario 18 novo).

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK011 - SC-002 ("zero configuration changes" no 2o run) e mensuravel objetivamente, com metodo definido? [Mensurabilidade, Spec §SC-002] {auto}
  - Evidencia: `quickstart.md` Scenario 2 define o metodo exato (assinatura de `.claude/settings.json`, `.mcp.json`, `$HOME/.claude/cstk/config`, `.claude/hooks/` antes/depois, comparando conteudo e nao so mtime).
- [x] CHK012 - SC-006 ("100% divergent / 0% already-configured" para registro redirecionado) tem cenarios de teste que cobrem tanto o caso obvio quanto o caso de decoy textual (SEC-01)? [Mensurabilidade, Spec §SC-006] {auto}
  - Evidencia: Scenario 13 (comando redirecionado obvio) + Scenario 17 novo (linha-isca decorativa, SEC-01) + Scenario 14 (MCP).

## Cobertura de Cenarios

- [x] CHK013 - O gate deterministico `requirement-coverage.sh` encontrou algum FR de `spec.md` sem cenario de Acceptance/Edge Case associado? [Cobertura] {auto}
  - Evidencia: `global/skills/checklist/scripts/requirement-coverage.sh docs/specs/cstk-setup/spec.md` rodado nesta onda → `RESULT|...|requirements=18|covered=18|errors=0`, exit 0. Zero FR orfao.
- [x] CHK014 - Existe cenario cobrindo runtime instalado desatualizado que rejeita `--include-loose-usage` **e**, separadamente, `--verify-registration`? [Cobertura, Spec §FR-009] {auto}
  - Evidencia: Scenario 10 (loose-usage) + Scenario 18 novo (verify-registration, SEC-03) — os dois testados isoladamente, nao combinados.
- [ ] CHK015 - US2 AC3 ("backend deliberadamente diferente nao e migrado a forca") tem seu comportamento `--yes` totalmente especificado, incluindo os valores possiveis de `reason=` do `state-backend.sh resolve`? [Cobertura, Spec §US2 AC3] {auto} [Gap]
  - Nao satisfeito: `plan.md` §Riscos item 1 e `research.md` Decision 10 registram explicitamente que os valores de `reason=` nao estao enumerados e que a decisao do default de `--yes` para esta area foi **adiada para `create-tasks`** (investigacao empirica antes de codificar). Gap pre-existente (nao introduzido nesta onda), reafirmado aqui para garantir que `create-tasks` de fato o consuma.

## Dependencias e Premissas

- [x] CHK016 - A premissa de FR-011 (".git como marcador de onboarding, nao fronteira de confianca") declara sua limitacao conhecida, em vez de a esconder? [Premissas, Spec §FR-011] {auto}
  - Evidencia: `contracts/cli-setup.md` linhas 80-90, bloco explicito: "`.git` e marcador de onboarding, NAO fronteira de confianca... nao atesta procedencia".
- [x] CHK017 - A dependencia entre FR-016 e a semantica de merge "target vence" de `hooks install`/`mcp install` esta documentada de forma que a remediacao publicada seja de fato efetiva (nao uma instrucao que nao surte efeito)? [Dependencias, Spec §FR-016] {auto}
  - Evidencia: `research.md` Decision 11 + `data-model.md` "Por que `divergent` → `failed`, e nao `applied` apos 'corrigir'" — remediacao de duas etapas justificada contra o comportamento real do merge.

## Risco (decisao do dono do produto)

- [ ] CHK018 - A prioridade relativa entre fechar SEC-04..SEC-07 versus avancar as tarefas de US1-US4 no `create-tasks` reflete o apetite de risco do time para este projeto? [Risco] {humano}
- [ ] CHK019 - O residual aceito do fix SEC-01 (posicionamento estrutural sob `PreToolUse`/`matcher` nao verificado textualmente) e aceitavel para o perfil de ameaca deste projeto, ou justifica investir em parse real (`jq`) numa iteracao futura? [Risco, Spec §FR-016] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Gaps abertos (CHK004, CHK005, CHK015) tem destino: `/create-tasks` deve consumi-los como tarefas explicitas de documentacao/investigacao, nao apenas herdar a prosa do `plan.md`.
