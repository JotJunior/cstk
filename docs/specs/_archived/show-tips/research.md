# Research: Show Tips

**Feature**: `show-tips` | **Date**: 2026-05-27 | **Phase**: 0 (Outline & Research)

Objetivo do Phase 0: resolver todos os NEEDS CLARIFICATION tecnicos antes do
design (Phase 1). As ambiguidades de produto ja foram resolvidas em `/clarify`
(spec §Clarifications, sessao 2026-05-26). Este documento resolve as decisoes
TECNICAS, com enfase na conformidade com a Constitution (Principio II — POSIX
sh puro, NON-NEGOTIABLE).

---

## Decision 1: Mecanismo de selecao pseudoaleatoria POSIX

**NEEDS CLARIFICATION origem**: spec FR-003 + clarificacao dec-008 escolheram
`$RANDOM % N`. Porem `$RANDOM` e um **bash-ism**, nao POSIX.

**Decision**: usar `/dev/urandom` como fonte de entropia, lido via
`od -An -N4 -tu4 /dev/urandom`, alimentando `awk 'BEGIN{srand(SEED); ...}'`
para produzir um indice `0..N-1`. Fallback quando `/dev/urandom` indisponivel:
`awk 'BEGIN{srand(); print int(rand()*N)}'` (srand sem argumento usa time-of-day;
aceitavel para degradacao).

**Rationale**:
- Constitution Principio II e **NON-NEGOTIABLE** e proibe explicitamente
  bash-isms ("nenhum `$'...'`", "nenhum array", e por extensao construcoes
  nao-POSIX). `$RANDOM` nao e definido em POSIX sh.
- Evidencia empirica (sonda Phase 0):
  - `dash -c 'echo $RANDOM'` retorna string **vazia** (CI roda em ubuntu com
    `dash` como `/bin/sh`).
  - `shellcheck -s sh` sobre `x=$((RANDOM % 5))` emite **SC3028 (warning):
    In POSIX sh, RANDOM is undefined** — viola o Quality Standard "Scripts sao
    POSIX — detectados por shellcheck com dialeto sh; zero warnings e meta".
  - `od -An -N4 -tu4 /dev/urandom | awk srand`: 5 picks consecutivas distintas
    (`0 6 8 5 2`), satisfazendo FR-003 (variacao entre execucoes).
- `od` e `awk` sao ferramentas POSIX canonicas (Principio II lista `awk` entre
  as permitidas; `od` faz parte do POSIX base utilities).
- `/dev/urandom` existe em todo ambiente POSIX moderno; quando ausente, o
  fallback `srand()` mantem a feature funcional (FR-006 fail-silent nunca e
  acionado por causa de RNG).

**Alternatives considered**:
- `$RANDOM % N` (spec original): REJEITADO — bash-ism, viola Principio II e
  falha em `dash`/CI (retorna vazio → divisao por contexto vazio).
- `awk 'BEGIN{srand(); ...}'` SEM seed externo: REJEITADO como mecanismo
  primario — `srand()` sem argumento usa segundos-desde-epoch; chamadas dentro
  do mesmo segundo retornam o MESMO valor (sonda confirmou: `9 9 9` em loop
  apertado). Mantido apenas como fallback (frequencia de invocacao real, 1x por
  onda, torna a colisao improvavel).
- `head -c4 /dev/urandom | cksum`: REJEITADO — `cksum` e POSIX mas o pipe
  adiciona um processo extra sem ganho sobre `od`.

> **Atualizacao da spec necessaria**: FR-003 cita `$RANDOM % N` literalmente.
> A intencao (selecao pseudoaleatoria sem estado persistente) permanece; apenas
> o mecanismo muda para POSIX-compliant. Registrado como Decisao auditavel
> dec-012 (score 3, com evidencia empirica). FR-003 deve ser lido como
> "selecao pseudoaleatoria POSIX (`/dev/urandom` + `awk`)".

---

## Decision 2: Formato e parsing do catalogo

**NEEDS CLARIFICATION origem**: resolvido em `/clarify` dec-007 (Markdown +
frontmatter YAML, arquivo unico `tips/catalog.md`). Este Phase 0 detalha o
parsing POSIX.

**Decision**: cada entrada e um bloco delimitado por linha `---` isolada,
contendo um frontmatter YAML minimo (`skill:`, `category:`, `text:`) seguido
do corpo Markdown (exemplos). Parsing via `awk` com maquina de estados que
detecta os delimitadores `---` e extrai os campos `chave: valor`.

**Rationale**:
- O YAML usado e um subconjunto plano (apenas `chave: valor` escalar de uma
  linha) — nao requer parser YAML completo. `awk` resolve com regex simples
  `^skill:` / `^category:` / `^text:`.
- Legivel por humano sem ferramenta especial (SC-005 — mantenedor adiciona
  dica editando o arquivo).
- Sem dependencia externa (Principio II). `awk`/`grep` bastam.

**Alternatives considered**:
- JSON com `jq`: REJEITADO — `jq` e dep nao-POSIX banida no bloco MUST do
  Principio II (so permitida sob carve-out 1.1.0, que exige fallback; aqui o
  catalogo NAO precisa de jq, entao introduzi-lo seria gratuito).
- Arquivos separados por skill (`tips/<skill>.md`): REJEITADO — dec-007 fixou
  arquivo unico; multiplos arquivos complicariam a contagem de cobertura
  (SC-001/SC-004) e o `find`/scan.
- TSV (`skill\tcategory\ttext\texample`): REJEITADO — menos legivel para humano,
  exemplos multilinhas com backticks (edge case da spec) ficariam ilegiveis.

**Convencao de delimitacao** (resolvendo ambiguidade do edge case "exemplos com
backticks/asteriscos"): o separador de entradas e uma linha contendo
EXATAMENTE `---` (3 hifens, nada mais). Frontmatter e o bloco entre o `---` de
abertura e um proximo `---`; corpo e o que segue ate o proximo separador de
entrada. O `awk` reconhece o estado (fora / frontmatter / corpo) para nao
confundir um `---` no corpo de um exemplo. **Mitigacao**: exemplos no corpo
NAO devem usar linha isolada `---`; usar fence de codigo (``` ``` ```) para
blocos, que o parser ignora como corpo.

---

## Decision 3: Integracao com o ponto de exibicao (inicio de onda)

**NEEDS CLARIFICATION origem**: spec US1/US4 — como o orquestrador invoca e
onde o gatilho dispara.

**Decision**: o script `cli/lib/show-tip.sh` e despachado por `cli/cstk` como
`cstk show-tip [skill] [--phase FASE]`, seguindo EXATAMENTE o mesmo padrao de
`cstk recall` (resolve `cli/lib/<cmd>.sh`, source, chama `<cmd>_main`). A
exibicao no inicio de onda e responsabilidade do ORQUESTRADOR (documentada como
ponto de integracao opcional), nao um hook automatico do runtime nesta feature
— evita acoplar o pipeline 00c a uma dependencia nova. O contrato e: orquestrador
chama `cstk show-tip --phase <fase>`, recebe um bloco formatado em stdout (ou
string vazia), e o exibe.

**Rationale**:
- `cstk recall` ja estabeleceu o padrao de despacho (`_dispatch` case list +
  `<cmd>_main`). Reusar = menor superficie de mudanca e familiaridade do
  mantenedor (paralelismo explicitado na spec dec-009).
- FR-006 exige fail-silent: o script SEMPRE retorna exit 0 e, em qualquer erro
  de leitura, emite string vazia em stdout. O orquestrador exibe o que vier —
  vazio significa "sem dica", nunca erro.
- Manter o gatilho como invocacao explicita (nao hook) respeita Principio IV
  (zero coleta remota — N/A aqui, mas o principio de nao-acoplamento se aplica)
  e evita modificar o contrato dos orquestradores 00c nesta feature. A
  integracao automatica por onda fica como uso documentado (US4), nao alteracao
  de runtime.

**Alternatives considered**:
- Hook em `cli/lib/hooks.sh` disparado automaticamente: REJEITADO neste escopo —
  acoplaria show-tips ao ciclo de vida do hook system; aumentaria blast radius.
  Pode ser feature futura.
- Novo binario standalone fora de `cstk`: REJEITADO — dec-009 fixou
  `cli/lib/show-tip.sh` paralelo a `recall.sh`, dentro do `cstk`.

---

## Decision 4: Cobertura do catalogo (quais skills, quantas dicas)

**NEEDS CLARIFICATION origem**: spec SC-001 — "100% das skills (global +
language-related)".

**Decision**: o universo de skills e derivado de `global/skills/*/` (23 skills)
+ `language-related/{go,dotnet}/skills/*/` (15 skills) = 38 skills. Cada uma
recebe >= 2 dicas (categorias minimas `uso` e `gotcha`). Um script de auditoria
(`cstk show-tip --audit` ou test dedicado) percorre `tips/catalog.md`, conta
entradas por skill, e compara contra o universo listado por `find`.

**Rationale**:
- `find global/skills -maxdepth 1 -type d` + `find language-related -name
  SKILL.md` da a lista canonica sem hardcode.
- SC-004 exige auditoria com exit 0/1 — implementavel em `awk` contando
  `skill:` por valor e cruzando com o universo.

**Alternatives considered**:
- Hardcode da lista de skills no catalogo: REJEITADO — quebra quando skill e
  adicionada (FR-008 extensibilidade); auditoria deve descobrir o universo
  dinamicamente.

---

## Decision 5: Bloco visual de destaque (FR-004)

**Decision**: o bloco de saida usa delimitadores ASCII/Markdown puros: uma linha
de borda (`========` ou box-drawing simples), o nome da skill, a categoria, o
texto da dica e os exemplos identados. Saida em stdout, sem cores ANSI por
default (portabilidade; cores opcionais so se TTY e `ui.sh` ja prover helper).

**Rationale**: FR-004 pede destaque visual claro; o toolkit ja tem `cli/lib/ui.sh`
com helpers de apresentacao — reusar quando rodando em TTY, degradar para texto
puro quando pipe/redirect (o caso do orquestrador capturando stdout).

**Alternatives considered**:
- Cores ANSI sempre: REJEITADO — polui stdout quando capturado por orquestrador.
- HTML/markdown rico: REJEITADO — saida e terminal, nao renderer.

---

## Unknowns restantes

Nenhum. Todos os NEEDS CLARIFICATION tecnicos resolvidos. Pronto para Phase 1.
