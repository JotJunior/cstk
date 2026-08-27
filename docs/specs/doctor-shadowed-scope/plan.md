# Implementation Plan: Doctor Shadowed Scope

**Feature**: `doctor-shadowed-scope` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md)

## Summary

`cstk doctor` hoje afirma saude sobre definicoes de escopo de projeto que
nunca comparou contra o catalogo corrente. Esta feature (a) adiciona uma
secao **Shadowed Scope** que compara o **conteudo** das copias de projeto
(`./.claude/agents/`, `./.claude/commands/`) contra o **conteudo** do
catalogo global instalado, e (b) entrega uma **declaracao de cobertura**
que declara fontes, mede quantos registros o arquivo contem e quantos
foram de fato interpretados — com denominador e numerador nascendo de
caminhos de granularidade diferente, para que a cobertura nao possa
reportar 100% por construcao.

A abordagem tecnica e aditiva: uma lib nova (`cli/lib/manifest-coverage.sh`)
com o validador de registro e o contador independente, mais uma secao nova
em `cli/lib/doctor.sh` modelada na forma de `_doctor_distribution_paths`
(condicional, read-only, sem `--fix`, retorno 0/1 lido via `$?`).
`cli/lib/manifest.sh` fica **intocado** — endurecer seu leitor mudaria o
comportamento de `install`/`update`, fora de escopo.

> **Nota de veracidade (Constitution VI)**: neste plano, tudo afirmado
> como EXISTENTE foi lido de `cli/lib/doctor.sh`, `cli/lib/manifest.sh`,
> `cli/lib/hash.sh`, `guard-hooks-status.sh` ou medido em execucao.
> Todo desenho novo esta marcado `[PROPOSTA — a validar na implementacao]`.
> Detalhamento e evidencias literais em [research.md](./research.md).

## Technical Context

**Language/Version**: POSIX sh puro (Constitution Principio II — NON-NEGOTIABLE)
**Primary Dependencies**: nenhuma nova. Reusa `cli/lib/manifest.sh`, `cli/lib/hash.sh`, `cli/lib/common.sh`, ja sourceadas por `doctor.sh`. Ferramentas: `awk`, `printf`, `[`, `case`. **Sem `jq`** (confinado a `plugin-detect.sh` por amendment 1.1.0), **sem GNU-only**
**Storage**: N/A — leitura de arquivo texto, zero persistencia
**Testing**: harness POSIX do repo (`./tests/run.sh`); `tests/cstk/test_doctor.sh` (existente, estendido) + `tests/cstk/test_manifest-coverage.sh` `[PROPOSTA]` (novo, obrigatorio por `--check-coverage`)
**Target Platform**: CLI local. Fonte: `CLAUDE.md` §"Como testar scripts shell" (harness POSIX local) + `.github/workflows/shellcheck.yml` e `release.yml` (CI Linux); ambiente de desenvolvimento macOS/zsh e o do operador desta execucao
**Project Type**: cli — runtime do binario `cstk` (`cli/lib/`)
**Performance Goals**: N/A — 2 arquivos texto e alguns `hash_file` por invocacao
**Constraints**: saida classica do `cstk doctor` inalterada byte-a-byte; nenhuma flag nova; `.claude/` e gitignored, logo o desenho nao pode depender de git
**Scale/Scope**: ~2 fontes, ordem de dezenas de registros (MEDIDO: 7 linhas de dados em cada manifesto global desta maquina)

**NEEDS CLARIFICATION restantes**: 0. Os 6 eixos estruturais estao fixados
pelo repositorio (POSIX sh; o proprio cstk; helper de lib + subcomando
existente; sem persistencia; CLI local; tier N/A) — nao ha eixo estrutural
em aberto, logo o gate de decisao estrutural em modo autonomo nao se
aplica a este plano.

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1 (secao Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | feature tem spec ratificada + clarify; este plano fecha o Phase 0/1 antes de qualquer codigo |
| II. POSIX sh puro, zero dep externa (MUST) | PASS | so `awk`/`printf`/builtins; sem `jq`, sem GNU-only, sem dependencia nova |
| III. Formato canonico de skill | N/A | feature nao toca skills — alvo e `cli/lib/` (runtime do binario) |
| IV. Zero coleta remota (MUST) | PASS | leitura estritamente local (`./.claude/`, `$HOME/.claude/`); nenhuma rede |
| V. Profundidade sobre adocao (SHOULD) | PASS | escopo deliberadamente estreito (sem retrofit, sem `--json`), mas a lib nova e projetada para reuso — que e o pedido de FR-006 |
| VI. Veracidade — zero fabricacao (MUST) | PASS | ver abaixo |

**Principio VI, aplicacao concreta nesta feature** (e o principio que a
feature *implementa*, nao so respeita):

- O plano rotula `[PROPOSTA]` tudo o que e desenho novo; o que e afirmado
  como existente tem fonte citada.
- A saida MUST NOT afirmar qual lado esta desatualizado — nao ha fonte
  para isso (mtime nao e evidencia). Mesma postura ja escrita no
  cabecalho de `_doctor_distribution_paths`.
- `unmanaged-upstream` existe justamente para nao afirmar uma divergencia
  que nao foi medida quando falta uma das pontas.
- `indeterminate`/`unreadable` existem para dizer "nao consegui" em vez de
  emitir um veredito sem base.
- A guarda `inconsistent` (numerador > denominador) proibe o contador de
  se auto-corrigir para caber na narrativa.
- Apos o gate `owasp-security`, a proibicao ganhou dente adicional: o
  texto do relatorio MUST ser sanitizado, porque um campo untrusted com
  bytes de controle podia **forjar visualmente** a linha de saude — uma
  fabricacao de dado induzida por terceiro, nao pelo agente, mas com o
  mesmo efeito sobre quem le.

## Project Structure

### Documentation (this feature)

```
docs/specs/doctor-shadowed-scope/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 — 11 decisoes com evidencia
├── data-model.md    # Phase 1 — 5 entidades
├── quickstart.md    # Phase 1 — 14 cenarios (inclui adversariais + release-wave)
└── contracts/
    └── doctor-shadowed-scope-output.md
```

### Source Code (repository root — arvore real)

```
cli/
├── cstk                      # binario (dispatch; nao muda)
└── lib/
    ├── doctor.sh             # ALTERADO: + _doctor_shadowed_scope, wiring em doctor_main
    ├── manifest.sh           # INTOCADO (esta no caminho de escrita de install/update)
    ├── hash.sh               # reusado (hash_file)
    ├── common.sh             # reusado
    ├── config.sh             # nao usado por esta feature
    ├── plugin-detect.sh      # nao usado por esta feature
    └── manifest-coverage.sh  # NOVO [PROPOSTA]

tests/
└── cstk/
    ├── test_doctor.sh            # ESTENDIDO (cenarios novos; os existentes intactos)
    └── test_manifest-coverage.sh # NOVO [PROPOSTA] — obrigatorio por --check-coverage
```

**Structure Decision**: dividir em lib nova + secao no `doctor.sh`, em vez
de concentrar tudo em `doctor.sh` (que ja tem 674 linhas), porque FR-006
pede que a declaracao de cobertura seja **padrao de referencia
reutilizavel** por outros mecanismos de saude — codigo enterrado em
funcoes `_doctor_*` acopladas as globais `_doctor_count_*` nao e
reutilizavel por construcao. Consequencia aceita e planejada: o test file
novo e obrigatorio (`./tests/run.sh --check-coverage` sai com exit 1 em
orfao). `manifest.sh` nao e estendido de proposito — endurecer
`read_manifest` mudaria o comportamento de install/update/plugin-detect,
que estao fora do escopo desta feature.

## Desenho — as duas metades

### Metade 1: o fix (US1/US2, FR-001..FR-005, FR-010)

O defeito, precisado por leitura (dec-014, score 3): `doctor_main` **ja**
itera os 3 kinds e `_doctor_walk_kind` **ja** sabe resolver o escopo de
projeto (`project) _doctor_scope_dir="./.claude/$_dwk_kind"`). O que nao
existe e comparacao **cross-scope**: `_doctor_classify_entry` compara o
hash do artefato contra o sha gravado no manifesto do **mesmo** escopo,
e nada mais. Como o manifesto de projeto nunca muda sozinho, a copia de
projeto reporta `OK` para sempre. Soma-se o default `--scope global`, que
faz o escopo de projeto sequer ser visitado sem a flag.

Encaixe sem quebrar o existente:

- A comparacao intra-escopo (`OK`/`EDITED`/`MISSING`/`ORPHAN`) **nao e
  tocada**. Nenhuma linha, contagem ou rotulo muda.
- A comparacao cross-scope vive numa **secao separada**, emitida depois do
  sumario classico e antes de `Distribution Paths`, com estados de nome
  proprio: `shadowed`, `shadow-current`, `unmanaged-upstream`,
  `indeterminate` (research.md D3).
- Verdade da comparacao = **conteudo** (`hash_file` das duas pontas), nao
  o sha registrado no manifesto global (research.md D2; precedente
  literal: `guard-hooks-status.sh:354` compara byte-a-byte com `cmp -s`,
  e sem `cmp` no PATH devolve `unknown`, nunca `stale`).
- Roda **sempre**, independente de `--scope`/`--fix` (research.md D4).
  Fosse opt-in, o operador que roda `cstk doctor` puro — o caso
  majoritario — continuaria vendo o falso OK.
- **FR-004/FR-005 sao garantidos estruturalmente**: a secao itera o
  **manifesto**, nunca o diretorio. Copia local sem registro e
  inalcancavel por este codigo, e nao depende de nenhum `if` que um
  refactor possa inverter. Caso de teste nomeado: `.claude/skills/release-wave`
  (quickstart Cenario 4). **Precisao**: dizer que essa copia "continua
  sendo listada como ORPHAN" so vale sob `--scope project`; no
  `cstk doctor` puro (default `global`) `./.claude/` nem e varrido, e ela
  nao recebe rotulo nenhum. A afirmacao que a feature sustenta e a mais
  fraca e suficiente: **a secao nova nao lhe atribui problema em nenhum
  modo de invocacao**.
- **FR-010**: nome no manifesto de projeto sem artefato correspondente no
  catalogo ⇒ `unmanaged-upstream` — distinto de `shadowed` (nao houve
  comparacao) e distinto de saudavel. **Nao gateia o exit**, pelo mesmo
  argumento ja registrado no codigo para de-gatear ORPHAN (rename upstream
  nao da acao obrigatoria ao operador).

### Metade 2: a declaracao de cobertura (US3, FR-006..FR-009)

Criterio de aceite duro: a cobertura e medida contra o que o **arquivo
contem**, nunca contra o que o **parser reconhece**.

- **Denominador** — `manifest_count_data_lines <path>` `[PROPOSTA]`:
  criterio puramente de **linha** (nao vazia, nao inicia com `#`). Nao
  conhece TAB, nao conhece campo, nao conhece o schema, nao chama
  `read_manifest`.
- **Numerador** — contado **por uso**: incrementado como efeito colateral
  do laco que de fato classifica. Um registro so conta quando foi
  decomposto em `(name, version, sha)` validos **e** produziu um veredito.

Por que nao colapsam:

1. Granularidade diferente (linha vs registro decomposto em campos).
2. `read_manifest` **nao pode** servir de numerador: seu filtro
   (`awk '/^[[:space:]]*$/ {next} /^#/ {next} {print}'`) imprime toda
   linha nao-comentario nao-vazia **sem olhar campo nenhum**. Um numerador
   construido sobre ele daria numerador == denominador sempre — 100% de
   cobertura por construcao, exatamente o contador auto-congratulatorio
   que a spec proibe. Logo o discriminador "reconhecido vs nao
   interpretado" precisa nascer de um **validador de registro novo**, que
   hoje nao existe em lugar nenhum do repo.
3. Contar por uso (e nao por uma segunda passada de validacao) faz a
   metrica acusar sozinha quando o classificador mudar: o numerador cai
   sem o denominador se mexer.

Regras de relato:

- `data_lines > records_used` ⇒ `partial`, exit 1 (FR-008). Para um gate
  de CI (`cstk doctor || exit 1`), **exit 0 e a apresentacao de sucesso**.
- Fonte ininterpretavel (header desconhecido — `detect_schema_version` ja
  retorna 1 nesse caso) ⇒ `unreadable` **explicito**, exit 1 (FR-009).
  Nunca omitir a fonte, nunca confundir com `absent`.
- `records_used > data_lines` ⇒ `inconsistent`, exit 1, numeros brutos
  exibidos. Proibido normalizar/arredondar/silenciar (research.md D7).
- A declaracao sai em **toda** execucao, inclusive com 0 fontes
  encontradas (FR-006/SC-003).
- `[OK]` MUST NOT ser impresso se qualquer fonte estiver `partial`,
  `unreadable` ou `inconsistent`, **mesmo com zero divergencias**: "nao
  encontrei divergencia" e "li tudo e nao ha divergencia" sao afirmacoes
  diferentes.

**Armadilha medida, ja evitada no desenho**: o denominador "obvio"
(`grep -cv -e '^[[:space:]]*$' -e '^#'`) retorna **0** num arquivo cujo
ultimo registro nao termina em `\n`, enquanto o `awk` do parser ve **1** —
produzindo numerador > denominador, isto e, **mais de 100% de cobertura**:
o mecanismo de honestidade mentindo a favor da ferramenta. Por isso o
denominador MUST ser robusto a newline final ausente, e por isso a guarda
`inconsistent` existe. Detalhe e transcricao da medicao em research.md D6;
cenario de regressao em quickstart Cenario 9.

## Convencoes de Borda

**N/A — single-layer.** A feature e um CLI local que le arquivos texto no
proprio host; nao ha borda backend↔frontend, DB↔backend nem broker↔consumer.
Nao ha DTO, nao ha payload, nao ha mapper.

A unica convencao de formato relevante ja existe e nao e criada aqui: o
TSV do `.cstk-manifest` schema v1, cuja fonte da verdade e
`cli/lib/manifest.sh` (constantes `_CSTK_MANIFEST_HEADER_V1` /
`_CSTK_MANIFEST_SCHEMA_V1`). Identificadores em ingles; mensagens ao
operador em pt-br, seguindo o padrao ja vigente em `doctor.sh`.

## GOTCHA de sincronizacao — `self-update`, nunca `install`

`cli/lib/doctor.sh` e `cli/lib/manifest-coverage.sh` sao **runtime do
binario**, nao catalogo.

| O que foi editado | Comando que sincroniza | O que atualiza |
|---|---|---|
| `cli/lib/*.sh`, binario `cli/cstk` | `cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"` | `~/.local` |
| `plugins/cstk/skills/`, `commands/`, `agents/` | `cstk install --from ...` / `cstk update` | `~/.claude` |

Rodar `cstk install`/`cstk update` apos editar esta feature reporta
"updated" e **nao toca a lib** — o codigo antigo continua rodando,
reproduzindo o sintoma classico "o fix funciona no repo mas nao na
sessao". Fluxo de dev correto:

```sh
./scripts/build-release.sh X.Y.Z-dev
cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"
```

Como esta feature **nao** toca catalogo (nenhuma skill/command/agent),
`cstk install`/`cstk update` nao sao necessarios para ela.

## Riscos e mitigacoes

| Risco | Mitigacao |
|---|---|
| A propria feature virar a proxima instancia da classe que mata (contador que so conta o que entendeu) | denominador de granularidade de linha + numerador por uso + guarda `inconsistent`; cenarios adversariais 6-10 no quickstart, montados por sessao irma sem alinhamento previo |
| Regressao na saida classica | nenhuma linha/contagem/rotulo existente e alterado; quickstart Cenario 11 roda a suite existente sem edicao |
| Falso positivo sobre copia local legitima (`release-wave`) | garantia estrutural (itera manifesto, nao diretorio) + caso de teste nomeado no Cenario 4 |
| **Manifesto de projeto e entrada NAO CONFIAVEL** (repo de terceiro pode versionar `.claude/agents/.cstk-manifest`; o operador clona e roda `cstk doctor` dentro) | contrato §7, regras normativas R1..R6: forma do `name` validada antes de compor path, symlink recusado, texto untrusted sanitizado + `printf '%s'`, `set -f` no laco, teto de consumo, hash so para path validado. Achados do gate `owasp-security`, detalhe em research.md D12 |
| Traversal via campo `name` (o unico usado para compor path) | `manifest_name_is_safe` como gate obrigatorio; reprovado vira `unrecognized` — entra no denominador, e a cobertura ja o expoe |
| Relato humano forjavel por bytes de controle no manifesto (ESC/`\r` apagam `[DRIFT]` e forjam `[OK]`) | `manifest_scrub_text` + `printf '%s'` normativos. Exit code nunca foi forjavel — so o texto |
| Dependencia de CWD (`./.claude/...`) surpreender o operador | declarada no contrato §2 e visivel na saida: fora da raiz, `fontes encontradas: 0 de 2` em vez de silencio. Nao ha descoberta de raiz por git — `.claude/` e gitignored |
| Ruido de exit em `unmanaged-upstream` | nao gateia, pelo precedente ja registrado no codigo para ORPHAN |
| Lib nova sem teste quebrar o gate | `tests/cstk/test_manifest-coverage.sh` previsto no plano; Cenario 14 valida `--check-coverage` |
| CRLF corromper campo | `\r` terminal removido antes de validar (medido: `awk -F'\t'` mantem `\r` no ultimo campo) |

## Re-check de Constitution (pos-Phase 1)

Design introduziu 1 arquivo novo em `cli/lib/` e 1 secao em `doctor.sh`.

| Principio | Status pos-design | Nota |
|---|---|---|
| I | PASS | artefatos de spec/plan/research/data-model/contracts/quickstart completos antes de codigo |
| II | PASS | o design fechou em `awk` + builtins; nenhuma dependencia nova entrou no Phase 1 |
| IV | PASS | nenhuma rede foi introduzida pelo design |
| V | PASS | a lib nova e justificada por FR-006 (reuso), nao por generalizacao especulativa; escopo permanece estreito (sem retrofit, sem `--json`) |
| VI | PASS | contrato inteiro rotulado `[PROPOSTA]`; proibicoes de afirmacao-sem-fonte escritas como normativas no contrato §3.2 e §3.4 |

**Complexity Tracking**: N/A — nenhuma violacao de constitution a
justificar.

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor este plano em backlog
3. `/analyze` — consistencia cross-artifact apos as tasks
