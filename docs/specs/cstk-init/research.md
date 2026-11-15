# Research: cstk-init

Documento do Phase 0 do `/plan`. Technical Context sem `NEEDS CLARIFICATION`: a stack e
herdada do toolkit (skill do catalogo, SKILL.md + scripts POSIX sh; dec-006). Nenhum eixo
estrutural fica aberto: linguagem/runtime, arquitetura e persistencia ja estao fixados
pela constitution do toolkit (Principios II e III) e pela clarificacao dec-006 (skill, sem
subcomando do binario). As decisoes abaixo sao operacionais (desenho interno da skill).

Fontes lidas para este documento (todas no repositorio):
`plugins/cstk/skills/{briefing,constitution,specify,checklist,plan,reconcile-docs,review-features,presentation,converge,agente-00c-runtime}/`,
`scripts/profiles.txt.in`, `tests/test_doc-counts.sh`, `tests/lib/harness.sh`,
`tests/trigger-eval/gen-eval-cases.sh`, `README.md`, `docs/constitution.md` 1.3.0,
`docs/specs/code-reconciliation/` (precedente de skill com scripts + fixtures).

## Decision 1: Composicao com as skills existentes — templates e regras por referencia, nao invocacao das entrevistas

**Decision**: `cstk-init` preenche os documentos lendo, em tempo de execucao, os templates
das skills irmas resolvidas na MESMA raiz de catalogo da propria skill (projeto → plugin →
global, mesma ordem dos hooks):

| Documento | Template lido (por referencia) | Regras aplicadas por referencia |
|-----------|-------------------------------|---------------------------------|
| `docs/briefing.md` | `briefing/templates/briefing.md` | `briefing/references/discovery-guide.md` (redacao das perguntas); tabela `## Itens a Definir` com coluna `Impacto` |
| `docs/constitution.md` | `constitution/templates/constitution.md` | `constitution/SKILL.md`: principio obrigatorio "Veracidade de Dados — Zero Fabricacao", formato `**MUST:**` em linha propria (gate `converge/scripts/extract-must.sh`), SemVer + Sync Impact Report em emendas |
| `docs/specs/<short>/spec.md` | `specify/templates/feature-spec.md` | short-name kebab-case de 2-4 palavras (`specify/SKILL.md`), gate `checklist/scripts/requirement-coverage.sh` |
| `checklists/<dominio>.md` | — | invocacao da skill `checklist` (tool `Skill`) sobre a spec reconstituida |
| `data-model.md` | `plan/templates/data-model.md` | origem rastreavel por entidade (FR-017) |

`cstk-init` NAO invoca as skills `briefing` e `constitution` pela tool `Skill`.

**Rationale**: as duas skills conduzem entrevista propria (briefing: ate 10 perguntas,
uma por vez, aprovacao no fim — `briefing/SKILL.md` 115-117 e 204-226; constitution:
entrevista de principios). A spec exige o inverso: inventario primeiro, pergunta so o que
nao tem fonte (FR-002, FR-005) e citacao de origem por fato (FR-007), que o briefing nao
faz (ele marca `[inferido]`/`[fornecido]`, sem caminho de origem). Invocar a skill
produziria entrevista dupla. Ler o template da irma mantem um unico formato canonico
(sem copia em `cstk-init/templates/`), entao o "padrao vigente" muda junto com a irma.
`checklist` e diferente: ela parte de uma spec existente, que e exatamente o insumo
disponivel, entao a invocacao direta nao duplica nada.

**Alternatives considered**: (a) invocar `Skill(briefing)`/`Skill(constitution)` com o
inventario como argumento — rejeitado por entrevista dupla e sem citacao de origem;
(b) copiar os templates para `cstk-init/templates/` — rejeitado: duas fontes do mesmo
formato divergem na primeira mudanca da irma (justamente o que o modo de revisao detecta).

## Decision 2: Perfil de instalacao `sdd` e dependencia de irmas so dentro do perfil

**Decision**: registrar `sdd:cstk-init` em `scripts/profiles.txt.in`. Todas as irmas cujo
template, script ou skill `cstk-init` consome estao no perfil `sdd` (`briefing`,
`constitution`, `specify`, `checklist`, `plan`, `review-features` e `agente-00c-runtime`,
linhas 14-52 de `profiles.txt.in`). Nenhum script de skill do perfil `complementary`
(`presentation`, `reconcile-docs`) e chamado. Se uma irma exigida faltar na raiz de
catalogo resolvida, a skill encerra antes de escrever, citando o caminho ausente e a
instrucao `cstk install` (perfil `sdd`).

**Rationale**: `cstk-init` e a porta de entrada da pipeline SDD; o precedente
`reconcile-docs` registrou que chamadas cruzadas de script entre perfis diferentes quebram
em instalacao parcial (plan.md de `code-reconciliation`, "Relacao com converge").

**Alternatives considered**: perfil `complementary` — rejeitado: dependeria de irmas do
`sdd` sem garantia de instalacao conjunta. Os dois perfis — rejeitado: sem ganho, e mais
uma contagem de README para manter.

## Decision 3: Scripts proprios em vez de reusar `scan-project-docs.sh` e `pipeline.sh`

**Decision**: seis scripts POSIX novos sob `plugins/cstk/skills/cstk-init/scripts/`, de
responsabilidade unica, com prefixo `init-` (sem colisao com `tests/test_*.sh` existentes,
verificado por `ls tests/`):

| Script | Responsabilidade |
|--------|------------------|
| `init-probe.sh` | pre-condicoes (raiz, escrita, VCS), estado dos artefatos cstk, versao do cstk instalada |
| `init-inventory.sh` | inventario deterministico de artefatos do projeto (caminho + tipo, nunca conteudo) |
| `init-conformance.sh` | divergencias estruturais entre artefatos existentes e os templates vigentes |
| `init-candidates.sh` | sinais de evidencia para features candidatas + validacao/colisao de short-name |
| `init-guard.sh` | guarda de escrita (confinamento, create-only, allowlist) + varredura de segredo |
| `init-provenance.sh` | lint de marcadores de origem/pendencia num documento gerado |

**Rationale**: `presentation/scripts/scan-project-docs.sh` (`_sp_inventory`, linha 154)
e `agente-00c-runtime/scripts/pipeline.sh` (`_pl_cmd_detect_completion`, linha 505) ja
localizam briefing canonico/legado e constitution, mas: o primeiro esta no perfil
`complementary` (Decision 2) e inventaria so `docs/`; o segundo e runtime interno dos
orquestradores com contrato de etapa da pipeline, nao de adocao (nao reporta coexistencia
canonico+legado como estado proprio, exigido pelo edge case "Briefing legado e canonico
coexistem"). A deteccao repetida e pequena (tres testes de existencia) e fica coberta
por teste proprio.

**Alternatives considered**: estender `scan-project-docs.sh` — rejeitado por fronteira de
perfil; chamar `pipeline.sh detect-completion` — rejeitado por acoplar a skill de usuario
ao contrato interno dos orquestradores.

## Decision 4: Modo por artefato, nao global

**Decision**: `init-probe.sh artifacts` classifica cada artefato: briefing
`absent | canonical | legacy | both`; constitution `absent | present`; cada spec ativa
(`docs/specs/<dir>/spec.md`, excluindo `_archived/` e `current/`). Artefato ausente segue o
fluxo de criacao; artefato presente segue o fluxo de revisao. Um projeto pode estar nos
dois modos ao mesmo tempo (ex.: constitution presente, briefing ausente). `both` nunca e
resolvido sozinho: apresenta os dois caminhos e pede decisao (edge case da spec).

**Rationale**: FR-003/FR-004 condicionam a criacao a ausencia de cada documento e FR-008
proibe sobrescrever o que existe; um modo global "criacao" ou "revisao" erraria nos
projetos parcialmente adotados. A ordem de busca do briefing replica a da skill `briefing`
(`docs/briefing.md`, depois `docs/01-briefing-discovery/briefing.md`; `briefing/SKILL.md`
73-89).

**Alternatives considered**: modo global decidido pela presenca de qualquer artefato —
rejeitado (nao cria o documento faltante em projeto parcial).

## Decision 5: "Padrao vigente" = templates instalados + catalogo de regras; versao lida do manifesto

**Decision**: a referencia de conformidade (FR-009, dec-007) tem duas camadas:
(1) **regras de cabecalho derivadas dos templates instalados** — os titulos `##` de
`briefing/templates/briefing.md` e `specify/templates/feature-spec.md`, e os titulos fixos
(sem placeholder `[...]`) de `constitution/templates/constitution.md`; titulo do template
ausente no artefato = divergencia `missing-section`; (2) **regras nomeadas** em
`references/conformance-rules.md` (IDs `CR-NNN`), ex.: briefing so no caminho legado,
rodape de versao da constitution fora do formato
`**Version**: X | **Ratified**: Y | **Last Amended**: Z`, principio "Veracidade de Dados"
ausente, spec sem `## Delta Requirements`.
A versao declarada no relatorio vem de `init-probe.sh version`, nesta ordem:
`<raiz-do-plugin>/.claude-plugin/plugin.json` (campo `version`, instalacao por plugin),
`.cstk-manifest` do diretorio de skills da raiz resolvida (coluna 2 da linha `cstk-init`,
schema `<skill>\t<toolkit-version>\t<sha256>\t<installed-at>` observado em
`~/.claude/skills/.cstk-manifest`), e por fim `unknown` (declarado como tal, nunca
estimado). Sem rede (FR-012).

**Rationale**: derivar dos templates garante que a regra acompanha a versao instalada sem
tabela duplicada; as regras nomeadas cobrem o que nao e cabecalho. Ler o JSON por
`grep`/`sed` de uma unica chave mantem o script sem `jq` (Principio II).

**Alternatives considered**: tabela fixa de secoes dentro do script — rejeitado
(desatualiza a cada mudanca de template); comparar com a release publicada — proibido por
dec-007 e Principio IV.

## Decision 6: Politica de escrita — create-only por padrao, emenda so com confirmacao

**Decision**: toda escrita passa por `init-guard.sh check` antes da tool Write/Edit:
caminho resolvido (`cd -P` + `pwd -P`, sem `realpath`) dentro da raiz do projeto, sem
symlink que escape, na allowlist (`docs/briefing.md`, `docs/constitution.md`,
`docs/specs/<short>/spec.md`, `docs/specs/<short>/data-model.md`,
`docs/specs/<short>/checklists/<dominio>.md`; mais o caminho legado do briefing apenas como
origem de migracao confirmada). `--op create` nega arquivo existente (FR-008, FR-016);
`--op amend` exige `--confirmed` (FR-010). Emenda de constitution segue as regras da skill
`constitution` (bump SemVer MINOR para secao/principio acrescentado, Sync Impact Report no
topo, `Last Amended` atualizado, texto ratificado intacto).

**Rationale**: o guarda fail-closed segue o precedente `reconcile-docs/scripts/doc-guard.sh`;
"create-only" torna a nao-sobrescrita verificavel por script, nao por disciplina do modelo.

**Imposicao do guarda (dec-026 D1=c, FR-026)**: nesta feature o guarda e PROCEDIMENTAL: `init-guard.sh check` e invocado pelo proprio modelo antes de cada Write/Edit e nenhuma ferramenta bloqueia um Write/Edit feito sem ele; sob injecao indireta a protecao depende de o modelo cumprir o fluxo. Risco residual declarado no SKILL.md (Gotchas) e no plan (Riscos). Hook `PreToolUse` `Write|Edit` restrito a execucao do `cstk-init` fica para feature futura; custo conhecido dele: hook novo + teste 1:1 + registro em `plugins/cstk/hooks/hooks.json` (hoje so `Bash|PowerShell`) + provisionamento, e o `cstk-init` nao tem arquivo de estado (Decision 10, FR-011), entao detectar "execucao ativa" exigiria marcador novo ou heuristica, com risco de falso positivo bloqueando Write/Edit na sessao manual.

**Alternatives considered**: confiar na prosa do SKILL.md — rejeitado (FR-010 e SC-004 sao
MUST verificaveis).

## Decision 7: Git opcional, confinado em `init-probe.sh`, com aviso em vez de recusa

**Decision**: `git` e dependencia opcional (carve-out 1.1.0), invocada SO em
`init-probe.sh preflight` (`git -c core.fsmonitor=false status --porcelain`, com
`GIT_OPTIONAL_LOCKS=0`). Saida `VCS\tgit-clean | git-dirty | none`. `git-dirty` ou `none`
→ aviso e confirmacao antes da primeira escrita (FR-022). Sem confirmacao (inclusive em
modo nao-interativo) → nenhuma escrita; relatorio apenas.

**Rationale**: diferente de `reconcile-docs` (que recusa escrever sem git, dec-035 daquela
feature), aqui a spec pede aviso + confirmacao. Sem git o fallback e correto: o aviso
continua sendo emitido (`none`) e a escrita depende da confirmacao.

**Alternatives considered**: recusar sem git — contraria FR-022; ignorar VCS — contraria
FR-022.

## Decision 8: Segredos — inventario nunca le valores; varredura pos-escrita reusa `secrets-filter.sh check`

**Decision**: `init-inventory.sh` classifica como `secret-bearing` (so caminho) arquivos
`.env*`, `*.pem`, `*.key`, `id_rsa*`, `*.p12`, `credentials*`; o SKILL.md proibe ler o
conteudo deles. Cada documento gerado passa por `init-guard.sh scan --file F`, que delega a
`agente-00c-runtime/scripts/secrets-filter.sh check` (mesma raiz de catalogo; perfil `sdd`;
`check` e POSIX sh, sem `jq` — o `jq` do arquivo fica so no subcomando `for-backup`).
Deteccao → o valor e redigido por Edit (o campo vira `[PENDENTE: ...]`), o documento e reescaneado e, se o `scan` ainda detectar, o operador e informado com o arquivo mantido; NAO ha remocao automatica de arquivo (o SKILL.md nao tem tool de remocao, nao ha ledger do que foi criado na execucao — Decision 10 — e FR-010/FR-034c vedam apagar sem confirmacao; decisao do orquestrador da onda 007, score 2, fecha requirements CHK043). Script ausente → FAIL-CLOSED (dec-026 D2, FR-027): `init-guard.sh scan --probe` roda antes da primeira escrita e, se `unavailable` (exit 4), nenhum documento e gravado; so relatorio com `secrets-scan-unavailable` e `cstk install` (perfil `sdd`). O `scan` descarta o stderr do `secrets-filter.sh check`, que contem os matches (FR-024). Criterio de "aparentar segredo" e piso de deteccao: FR-027 (a lista de padroes vem do cabecalho de `secrets-filter.sh`, issue #169). Segredo digitado pelo operador numa resposta e coberto por FR-019/FR-027: nao e gravado nem ecoado, o campo vira pendente. Momento de deteccao: ANTES da escrita por julgamento do modelo (regra do SKILL.md) e DEPOIS por `scan` (unica verificacao mecanica, limitada ao piso declarado em FR-027); o que escapa dos dois e o risco residual ja aceito na arquitetura de duas camadas (security CHK018, dec-018).

**Rationale**: FR-019 e SC-007. O proprio `secrets-filter.sh` documenta que sua cobertura e
um PISO (issue #169), por isso a defesa principal e a montante (nao ler valores); a
varredura e a segunda camada.

**Alternatives considered**: regex propria — rejeitado (duplicaria o filtro mantido no
runtime); confiar so na prosa — rejeitado (SC-007 exige verificacao).

## Decision 9: Modo nao-interativo explicito

**Decision**: argumento `--non-interactive`, ativado tambem quando `AGENTE_00C_STATE_DIR`
esta definido (execucao sob orquestrador). Nele: nenhuma pergunta; nenhum arquivo
existente alterado; criacao so de documentos ausentes com conteudo de fonte rastreavel e
campos `[PENDENTE: ...]`; registro de features nao e oferecido (FR-013 exige resposta
afirmativa, que nao existe); VCS `git-dirty`/`none` → zero escritas. Pergunta sem resposta
no modo interativo tem o mesmo tratamento: pendencia, nunca default. Como cada principio da
constitution exige confirmacao do operador (FR-004, dec-018 CHK029, dec-023), o modo
nao-interativo nao cria constitution com principios; o briefing recebe so conteudo com fonte
mais `[PENDENTE: ...]`.

**Rationale**: a skill nao tem como detectar com seguranca a ausencia do operador; uma
flag explicita e verificavel (FR-018, SC-006).

**Alternatives considered**: inferir pela ausencia de `AskUserQuestion` — rejeitado
(`briefing/SKILL.md` 158 mostra que sem a tool as perguntas viram texto, entao a ausencia
da tool nao implica ausencia de operador).

## Decision 10: Retomada pelo proprio sistema de arquivos, sem arquivo de progresso

**Decision**: nao ha ledger de execucao. A retomada (FR-021) e uma nova execucao: o que ja
existe cai no fluxo de revisao (create-only impede duplicar), o que falta e oferecido de
novo. Candidatas descartadas numa execucao anterior podem ser reapresentadas — limitacao
documentada em Gotchas.

**Rationale**: FR-011/SC-003 exigem que a segunda execucao sobre projeto em conformidade
nao crie nem altere arquivo algum; um ledger seria ele proprio uma escrita.

**Alternatives considered**: ledger em `.claude/cstk-init/` — rejeitado por FR-011.

## Decision 11: Features candidatas — sinais por script, agrupamento pelo modelo, decisao do operador

**Decision**: `init-candidates.sh evidence` emite sinais deterministicos (diretorios de
codigo de 1o e 2o nivel, agrupamentos de testes, paginas de documentacao, workspaces
declarados em manifestos). O modelo agrupa os sinais em capacidades coesas (dec-008),
cada candidata com nome sugerido e lista de evidencias citaveis; o operador confirma,
renomeia, mescla/divide ou descarta, em lotes de ate 5 candidatas (padrao de politica de
UX, nao dado factual). `init-candidates.sh name --root R --name N` valida kebab-case e
detecta colisao com `docs/specs/<N>/` e `docs/specs/_archived/*<N>` (FR-016).

**Rationale**: a definicao de feature e semantica (dec-008), entao o script fornece so
evidencia; nome e colisao sao deterministicos.

**Alternatives considered**: um candidato por diretorio — rejeitado por dec-008
(diretorio e sinal, nao definicao).

## Decision 12: Spec reconstituida — observado com evidencia, inferido sem palavra normativa

**Decision**: a spec segue `specify/templates/feature-spec.md` com tres adicoes
(contrato em `contracts/markers.md`): cabecalho de origem + marcador de maquina
`<!-- cstk-init:reconstructed -->`; requisitos observados como `FR-NNN` com
`(fonte: <caminho>[:<linha>])`; comportamento inferido numa subsecao propria
`### Inferido (nao confirmado)` com IDs `INF-NNN` e sem `MUST`/`SHOULD`. `## Delta
Requirements` = `**Skip**` com motivo (comportamento ja existente). Antes de concluir,
roda `checklist/scripts/requirement-coverage.sh` (mesmo gate usado por `specify`).

**Origem de User Scenarios, Success Criteria e prioridades (dec-026 D3, FR-028)**: o template de `specify` exige Acceptance Scenarios e SC com metas, que nao sao "comportamento observado"; inventa-los violaria o Principio VI. Regra: cenario de aceite so e derivado de teste existente do projeto, citando `(fonte: <caminho-do-teste>[:<linha>])`; sem teste, `[PENDENTE: ...]`; Success Criterion com meta numerica exige fonte, senao `[PENDENTE: ...]`; prioridade sem fonte, `[PENDENTE: ...]`. Risco aceito: specs reconstituidas com muitos `[PENDENTE: ...]`. O addendum `templates/reconstructed-spec-addendum.md` (tarefa 5.5) reflete a regra.

**Rationale**: FR-015 proibe apresentar inferencia como decisao original; sem palavra
normativa, o inferido nao vira obrigacao para `converge`/`requirement-coverage.sh`
(que casa `- **FR-NNN**:`, linha 139 do script).

**Alternatives considered**: marcar inferidos com `[inferido]` dentro dos FRs — rejeitado
(continuariam contando como requisito normativo).

## Decision 13: Testes — scripts com teste 1:1 e fixtures; comportamento do modelo por quickstart + trigger eval

**Decision**: `tests/test_init-{probe,inventory,conformance,candidates,guard,provenance}.sh`
sobre fixtures em `tests/fixtures/cstk-init/` (`bare`, `legacy`, `conformant`,
`three-features`, `secrets`, `both-briefings`) carregadas pelo helper `fixture` de
`tests/lib/harness.sh` (linha 223). O fluxo conversacional e validado pelos cenarios de
`quickstart.md` e por `evals/triggers.jsonl` (gerador `tests/trigger-eval/gen-eval-cases.sh`).

**Rationale**: regra de cobertura do repo (`./tests/run.sh --check-coverage`) e
precedente `code-reconciliation`.

**Alternatives considered**: testar o fluxo do modelo em CI — fora do alcance do harness
POSIX; fica nas camadas nao-gateantes.

## Decision 14: Politicas de pendencia, limiares, lote, migracao, idioma e contorno (dec-026 D4-D6)

**Decision** (resposta do operador "aceito todas as recomendações", block-001/dec-026; redacao do orquestrador):

- **Pendencia entre execucoes (D4, FR-029)**: artefato com `[PENDENTE: ...]` entra em modo de revisao; reconsulta so os campos pendentes; preencher = `amend` confirmado (guard + scan + lint). Valido = `lint` `ok`/`pending` e `init-conformance.sh check` `STATUS conformant`. Registro de features oferecido mesmo com pendencias ou correcoes recusadas, desde que nenhum lint seja `invalid`. FR-011/SC-003 ficam restritos a projeto em conformidade e sem pendencias (a Decision 10 permanece: sem ledger; o proprio marcador `[PENDENTE: ...]` no arquivo e o estado).
- **Limiares (D5, FR-030)**: teto default do inventario 1000 itens (valor de design, SEM medicao empirica; ajustavel por `--max-items`), `TRUNCATED` obriga aviso explicito e proibe afirmar completude; ate 5 perguntas por rodada (igual ao teto do clarify) e candidatas em lotes de 5; "projeto grande" = teto atingido ou mais de 5 candidatas; "inventario insuficiente" = zero `readme`/`doc`/`manifest`; "quase sem codigo" = zero `source-dir` e zero `test`; "fato concreto" definido em FR-030e. `init-provenance.sh lint` so verifica marcadores presentes, entao a completude de marcadores em SC-002 e verificada por tabela de fatos da fixture (revisao [conversa]).
- **Lote declarado (D6, FR-031)**: lista explicita caminho+operacao; confirmacao generica vedada; o guarda valida por caminho (uma invocacao de `check` por caminho; `--confirmed` so apos confirmacao nominal).
- **Migracao do briefing legado (D6, FR-032)**: MOVE para `docs/briefing.md`, so com confirmacao explicita por caminho; executado por `init-guard.sh migrate` (unico subcomando que altera o sistema de arquivos alem de Write/Edit, porque o SKILL.md nao tem tool de remocao e o Bash e restrito aos scripts `init-*.sh`); recusado se o destino existe (estado `both` nao migra). Sem VCS nao ha como desfazer: o aviso de FR-022 diz isso. Alternativas apresentadas ao operador e nao escolhidas: copiar (gera estado `both` e reabre a pergunta), manter e atualizar o legado no lugar.
- **Idioma (D6, FR-033)**: idioma predominante do README, confirmado ao operador; titulos de secao seguem os templates (consequencia de redacao do orquestrador, para `missing-section` de FR-009). Alternativas nao escolhidas: sempre pt-BR; sempre ingles.
- **Contorno (D6, FR-034)**: zero candidatas informa e encerra a etapa sem spec; irma ausente na criacao encerra antes de escrever; `lint` `invalid` apos gravar mantem o arquivo, reporta e oferece corrigir.

**Rationale**: fecha SC-001/SC-003 sem ambiguidade e remove invencao de limiares sem fonte (Principio VI): o unico numero sem medicao (1000) e declarado como valor de design.

**Alternatives considered**: pendencia intocada ate edicao manual (preserva FR-011 estrito mas nunca fecha pela skill) — nao escolhida; teto 500 ou 2000 — nao escolhidos.

