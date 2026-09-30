# Research: Code Reconciliation (`reconcile-docs`)

Documento produzido no Phase 0 do `/plan`. Nenhum `NEEDS CLARIFICATION` restou no
Technical Context: linguagem, stack e ambiente sao herdados da constitution do
toolkit (Principios II e III) e da skill vizinha `converge`, nao decididos aqui.

Fontes consultadas (todas existentes no repositorio no momento do plan):
`docs/constitution.md` (v1.3.0), `plugins/cstk/skills/converge/` (SKILL.md +
6 scripts), `plugins/cstk/skills/presentation/` (skill complementar mais recente),
`docs/specs/presentation/plan.md`, `scripts/profiles.txt.in`,
`tests/test_doc-counts.sh`, `tests/trigger-eval/gen-eval-cases.sh`,
`tests/trigger-eval/negatives.jsonl`, listagem de `docs/specs/` e
`docs/specs/_archived/`.

## Decision 1: Stack e formato da entrega

**Decision**: skill do catalogo em `plugins/cstk/skills/reconcile-docs/`
(SKILL.md + `templates/` + `references/` + `scripts/` POSIX + `evals/triggers.jsonl`),
mesmo formato de `converge` e `presentation`.
**Rationale**: Principio II (scripts `#!/bin/sh` + `set -eu`, sem `jq`) e Principio III
(progressive disclosure, `## Gotchas`, description-como-trigger) ja fixam linguagem,
runtime e anatomia; nao ha eixo estrutural em aberto. A leitura semantica do codigo e
feita pelo LLM que executa a skill; os scripts cobrem so o que e deterministico.
**Alternatives considered**: (a) subcomando novo do `cstk` CLI — rejeitado: a
comparacao doc-vs-codigo e semantica (spec, Assumptions) e o CLI nao tem LLM; (b) flag
`--reverse` dentro da skill `converge` — rejeitado: `converge` e etapa obrigatoria da
pipeline autonoma, tem contrato de escrita append-only em `tasks.md` e gate MUST
fail-closed; misturar o sentido inverso quebraria esse contrato (Principio I exige spec
para mudar contrato de skill).

## Decision 2: Divisao deterministico (script) vs semantico (LLM)

**Decision**: seis scripts de responsabilidade unica — `locate-feature.sh`,
`extract-anchors.sh`, `doc-guard.sh`, `markers.sh`, `reconciliation-log.sh`,
`git-probe.sh` — e o SKILL.md orquestra. Tudo que decide "o codigo faz X?" fica no LLM,
com evidencia obrigatoria.
**Rationale**: resolucao de nome (FR-002/FR-014/FR-015), lista do portfolio (FR-003),
guarda de escrita (FR-006/FR-017), proximo FR-NNN (FR-009), sintaxe de marcadores
(FR-009/FR-012) e append do registro (FR-018) sao regras mecanicas; em LLM elas falham
por contagem errada ou esquecimento (mesmo motivo do pre-gate
`validate-tasks-template.sh` do orquestrador). `converge` segue o mesmo corte
(`extract-intent.sh`, `path-contains.sh`, `converge-tasks.sh`).
**Alternatives considered**: um unico script com muitos subcomandos — rejeitado pelo
mesmo motivo registrado em `docs/specs/presentation/plan.md` §Structure Decision
(cada script testavel isolado; `tests/run.sh --check-coverage` exige teste 1:1).

## Decision 3: Resolucao do nome da feature

**Decision**: casamento EXATO. Ativa: basename de `docs/specs/<dir>/` igual ao nome,
excluidos `_archived` e `current`. Arquivada: basename de `docs/specs/_archived/<dir>/`
igual ao nome OU igual ao nome apos remover o prefixo `AAAA-MM-DD-`. Sem casamento
exato: nada e escolhido; candidatos por substring sao listados (FR-014). Mais de um
casamento exato na mesma classe (ex.: a mesma feature arquivada em duas datas, sem
versao ativa): ambiguo, encerra sem alterar nada. Ativa + arquivada: reconcilia a ativa
e informa a arquivada (FR-015).
**Rationale**: o spec proibe escolha sozinha em nome ambiguo (Edge Case "Nome ambiguo");
prefixo parcial resolvendo automaticamente seria escolha implicita. Os dois formatos de
arquivo existem hoje: na listagem de `docs/specs/_archived/` 23 dos 57 diretorios nao
tem prefixo de data (legados) — ambos precisam casar (spec, Assumptions "Identidade
da feature").
**Alternatives considered**: casamento por prefixo quando unico — rejeitado (mesmo
risco de escolha silenciosa); fuzzy/Levenshtein — rejeitado (so para sugestao; ordem
por substring basta e e POSIX).

## Decision 4: Tokens dos marcadores inline (delegado ao plan por FR-009)

**Decision**: marcador visivel, entre colchetes, anexado ao FIM da linha/celula
afetada, sintaxe em ingles:

```
[reconciled:<kind> <YYYY-MM-DD> evidence=<ref>]
kind ∈ removed | updated | added
ref  = <repo-relative-path>:<line>   (codigo presente)
     | absent:<repo-relative-path>   (codigo removido)
```

`removed` preserva o texto e o identificador FR-NNN originais (nada e apagado);
`added` acompanha um FR-NNN NOVO sequencial (max existente + 1); `updated` acompanha
trecho reescrito por FR-005. Possivel regressao e nao verificavel NAO geram marcador no
documento — so no relatorio (FR-007/FR-008). Contrato completo em
[contracts/markers.md](./contracts/markers.md).
**Rationale**: (a) visivel no Markdown renderizado — quem le a spec ve que o trecho
foi confrontado com o codigo; comentario HTML ficaria invisivel; (b) prefixo
`reconciled:` nao colide com nada no repositorio (busca por `reconciled:` so encontra
este spec); (c) regex fixa permite `markers.sh lint/list` deterministico, que sustenta a
idempotencia (FR-012): marcador existente sobre trecho coerente nunca e reescrito;
(d) sintaxe em ingles cumpre a regra global de identificadores; o texto livre ao redor
segue em portugues.
**Alternatives considered**: comentario HTML `<!-- reconciled ... -->` — rejeitado
(invisivel, contraria o objetivo de rastro para o leitor); tachado `~~texto~~` para
removidos — rejeitado (altera o texto original que FR-005/FR-009 mandam preservar e
quebra `grep` do FR-NNN em algumas ferramentas); marcador so em `reconciliation.md` —
rejeitado (spec, clarify Q4, exige marcador inline).

## Decision 5: Garantia "so documentacao" (FR-006/FR-017, SC-001)

**Decision**: duas camadas. (1) Antes de CADA escrita, `doc-guard.sh check` valida o
caminho real (resolvido com `cd -P`/`pwd -P`, sem seguir simlink para fora) contra a
allowlist: dentro do diretorio da feature resolvida, e arquivo em
{`spec.md`, `plan.md`, `data-model.md`, `quickstart.md`, `reconciliation.md`,
`contracts/*.md`}; qualquer caminho sob `docs/specs/current/` e negado mesmo que o
nome case. Negado => a escrita nao acontece e o ponto vai ao relatorio.
(2) Auditoria pos-execucao via `git-probe.sh status` (snapshot antes/depois): toda
entrada nova fora da allowlist vira erro visivel no relatorio. Sem git, a camada (2) e
pulada com aviso; a camada (1) segue obrigatoria.
**Rationale**: FR-006 exige proibicao "por regra da skill, nao apenas por convencao";
um script que o SKILL.md manda chamar antes de toda escrita e deterministico e testavel.
A auditoria pega escrita que escapou da regra (defesa em profundidade), sem depender
dela. `research.md`, `checklists/` e `tasks.md` ficam fora da allowlist conforme
Assumptions ("Escopo de documentos").
**Alternatives considered**: snapshot por `cksum` de todo o repositorio — rejeitado
(custo linear no tamanho do repo, inclui `node_modules/` do `panel/`); confiar so na
instrucao do SKILL.md — rejeitado por FR-006.

## Decision 6: Uso de `git` (FR-016) — dep opcional confinada

**Decision**: `git` e dependencia OPCIONAL sob o carve-out 1.1.0 do Principio II,
confinada a `scripts/git-probe.sh` (unico arquivo que invoca `git`). Subcomandos:
`changed-since` (arquivos alterados desde a ultima edicao dos documentos da feature —
atalho de priorizacao) e `status` (snapshot para a auditoria da Decision 5). Sem `git`
no PATH ou fora de repositorio: exit 0 sem linhas de dados, so a linha `STATUS\tno-git` —
nunca erro; a reconciliacao segue lendo o codigo atual.
**Rationale**: condicoes (a) fallback testado (`tests/test_git-probe.sh` cobre
`no-git`), (b) confinamento em um arquivo (grep por `git ` nos scripts da skill so
acha `git-probe.sh`), (c) declaracao neste research e no plan. Precedentes de `git`
opcional: `docs/specs/_archived/atomic-commit-pr/plan.md` (commit-mode.sh) e
`docs/specs/cstk-jira/plan.md` (resolve-path).
**Alternatives considered**: mandar o LLM rodar `git log` direto — rejeitado
(espalha a dep pela prosa, sem fallback testado); nao usar git — rejeitado (perde a
priorizacao que FR-016 permite e a auditoria da Decision 5).

**Adendo (dec-035, execute-task 1.5)**: sem git a skill RECUSA gravar (so `--dry-run`
forcado). A recusa e deterministica no subcomando `can-write` do mesmo `git-probe.sh`
(`rev-parse` apenas, leitura): `WRITE\tallowed` exit 0 com git; `WRITE\tdenied-no-git`
exit 3 sem git; o chamador trata exit != 0 (inclusive script ausente) como recusa. Nenhum
script novo e nenhuma nova chamada de `git` fora de `git-probe.sh`.

## Decision 7: Escopo de busca no codigo (FR-004, clarify Q2)

**Decision**: `extract-anchors.sh` extrai dos documentos da feature os tokens entre
crases que parecem caminhos (contem `/` ou extensao de arquivo), flags (`--x`),
comandos (`/x`) e identificadores FR/SC, com `doc:linha`, e marca para caminhos
`present|absent` relativo a raiz. O LLM parte dessas ancoras (e dos arquivos que elas
referenciam) para ler o codigo; comportamento sem ancora nao e buscado e, quando
relevante, sai como `unverifiable`.
**Rationale**: clarify Q2 fixou o escopo ancorado; a extracao deterministica garante
que "codigo removido" (ancora `absent`) seja detectado sempre (Edge Case "Codigo de
referencia removido"), independente do julgamento do LLM. Padrao analogo a
`converge/scripts/extract-intent.sh`, que extrai paths de `tasks.md`.
**Alternatives considered**: reusar `converge/scripts/extract-intent.sh` — rejeitado:
ele so varre `tasks.md`/`plan.md` estruturados e a skill `converge` pode nao estar
instalada junto (perfis diferentes); busca livre no repo inteiro — rejeitado por Q2.

## Decision 8: Registro `reconciliation.md` (FR-018, clarify Q1)

**Decision**: `reconciliation-log.sh append` cria o arquivo com cabecalho na primeira
vez e anexa uma entrada `## <YYYY-MM-DD>` com o resumo (contagem por tipo + documentos
tocados). So e chamado quando ao menos um documento foi alterado; em `--dry-run` e em
execucao sem divergencia nunca e chamado. Append-only: o script recusa reescrever
entradas existentes.
**Rationale**: clarify Q1; append deterministico evita que o LLM reescreva o historico.
**Alternatives considered**: registro dentro de `spec.md` — rejeitado por Q1.

## Decision 9: Relatorio e modo `--all`

**Decision**: relatorio e saida da conversa (nao arquivo), no formato de
`templates/report.md`: uma secao por feature + tabela consolidada. Em `--all`, as
features sao processadas uma a uma na ordem de `locate-feature.sh --all` (ativas, depois
arquivadas); falha de uma feature vira linha `error` e o lote segue (FR-013). O SKILL.md
recomenda delegar cada feature a um subagente quando a tool estiver disponivel,
retendo so a linha-resumo, e recomenda `--all --dry-run` antes do `--all` gravando.
Duplicata ativa+arquivada em `--all`: a arquivada vira `skipped` com motivo
`shadowed-by-active` (FR-015, Edge Case "Feature presente em dois locais").
**Rationale**: spec, Assumptions "Modo standalone" (como `converge`, sem estado de
orquestrador); o portfolio deste repositorio tem 7 features ativas + 57 arquivadas, o
que torna o contexto o recurso escasso do `--all`.
**Alternatives considered**: gravar o relatorio em arquivo — rejeitado (FR-006/SC-001
limitam escrita a documentos de feature; o relatorio nao pertence a nenhuma feature).

## Decision 10: Registro no catalogo

**Decision**: perfil `complementary` (nao `sdd`): linha
`complementary:reconcile-docs` em `scripts/profiles.txt.in`. Atualizar contagens do
README/README.pt-BR (hoje 22 global / 11 complementary / 29 all → +1 cada), help do
`cli/lib/install.sh`, `docs-site/manual/profiles.md`, triggers + negativos e regenerar
os casos com `tests/trigger-eval/gen-eval-cases.sh`. CHANGELOG com bump MINOR.
**Rationale**: a skill nao e etapa da pipeline autonoma (spec, Assumptions "Modo
standalone"); `presentation` seguiu exatamente esse caminho (commit `673ed32`).
`tests/test_doc-counts.sh` falha se a contagem do README divergir das pastas reais.
**Alternatives considered**: perfil `sdd` — rejeitado: aumentaria a instalacao
default com skill que nenhuma etapa da pipeline invoca.
