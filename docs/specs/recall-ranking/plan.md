# Implementation Plan: Ranking Composto no cstk recall

**Feature**: `recall-ranking` | **Date**: 2026-08-20 | **Spec**: [spec.md](./spec.md)

## Summary

Hoje o `cstk recall` ordena por relevancia textual pura
(`ORDER BY bm25(knowledge_fts)`), em dois pontos de `cli/lib/recall.sh`:
o modo busca (linha 3067) e o modo `--context` (linha 3216). O efeito e que
uma invocacao de skill mecanica pode ficar a frente de uma decisao
arquitetural ratificada, e que um achado de um ano atras compete de igual
para igual com um de ontem.

A feature substitui essa clausula por um **score composto de tres
componentes** — relevancia textual (`bm25`), reforco de autoridade por tipo
e desconto de recencia — computado **inteiramente como expressao SQL na
propria consulta**, sem coluna nova, sem migracao e sem reindex. Adiciona
ainda uma flag `--explain` (somente no modo busca) que expoe os tres
componentes por resultado.

Abordagem tecnica, derivada do Phase 0:

- **Score aditivo por subtracao**: `score = bm25 - bonus_autoridade -
  bonus_recencia`, ordenado ASC. Como `bm25()` e negativo e a ordem ja e
  ASC, subtrair um bonus positivo promove o resultado sem inverter a
  clausula existente (research.md D3).
- **Calibracao medida, nao arbitrada**: os pesos derivam da dispersao real
  de `bm25()` no indice de producao (gap tipico entre vizinhos 0.042-0.495;
  amplitude do top-20 0.805-3.958). Autoridade com spread de `0.30`
  reordena resultados comparaveis sem nunca vencer uma diferenca textual
  grande (research.md M3, D4).
- **Nao-dominacao demonstravel**: o teto de recencia (`0.10`) e
  estritamente menor que o menor degrau de autoridade (`0.15`), tornando
  aritmeticamente impossivel que recencia inverta tiers de autoridade
  (research.md D7).
- **Sem dependencia matematica nova**: o decaimento de recencia usa forma
  hiperbolica (`R_MAX * H / (H + idade)`), que entrega semantica de
  meia-vida **no ponto `H`** (em `idade = H` o bonus e exatamente `R_MAX/2`;
  a curva nao e exponencial fora dele) usando apenas `+` e `/` — evitando
  `exp()`/`ln()`, que dependem de flag de compilacao do SQLite. A idade e
  **clampada** em `max(0.0, ...)`, sem o que `source_ts` no futuro
  estouraria o teto do bonus em ordens de grandeza (research.md D6).
- **Determinismo**: instante de referencia resolvido uma unica vez no shell
  e interpolado como literal (nunca `julianday('now')` inline), mais
  desempate total `source_ts DESC, type ASC, source_id ASC` (research.md D8).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`), conforme
Constitution II. Nenhuma linguagem nova.
**Primary Dependencies**: `sqlite3` (>= 3.45.1, piso ja vigente do projeto;
medido em 3.51.0 na maquina de desenvolvimento) — **dependencia existente,
nenhuma nova**. Confinada a `cli/lib/recall.sh` sob o carve-out 1.1.0.
**Storage**: `~/.claude/cstk/knowledge.db` (SQLite + FTS5), **somente
leitura** nesta feature. `RECALL_SCHEMA_VERSION` permanece `15`.
**Testing**: harness POSIX proprio — `./tests/run.sh`, cenarios novos em
`tests/cstk/test_recall.sh` (arquivo ja existente, 4987 linhas).
**Target Platform**: macOS e Linux — herdado do projeto, nao decidido por
esta feature (fonte: `docs/constitution.md` Principio II, "rodam em qualquer
ambiente POSIX sem setup"; `CLAUDE.md` §"Shell & edicoes", "Ambiente e
macOS/zsh: nao dependa de GNU-only").
**Project Type**: CLI tool (single-layer).
**Performance Goals**: sem regressao mensuravel. A ordenacao continua
resolvida integralmente pelo SQLite com `LIMIT` aplicado no motor; a
mudanca adiciona apenas aritmetica escalar por linha casada.
**Constraints**:
- `knowledge_fts` e tabela virtual FTS5 — nao aceita `ADD COLUMN`; o indice
  e derivado/reconstruivel e nao pode virar fonte de verdade (C-004).
- `bm25()` so resolve no nivel de SELECT que contem o `MATCH` (restricao do
  motor, verificada empiricamente — research.md D2).
- Degradacao graciosa e invariante: todo caminho de falha de infraestrutura
  retorna `exit 0` com aviso. A feature nao pode introduzir caminho de erro
  novo.
- Formato de saida do modo `--context` e contrato congelado (rotulo
  UNTRUSTED, teto `--max-bytes`, frase `Aprendizado recuperado (read-back
  loop)`): so a ordem pode mudar.
**Scale/Scope**: indice real medido em 8699 linhas de `knowledge_fts`
(decision 6870, skill 1467, block 248, suggestion 112, retro 2, memory 0);
faixa etaria de 0 a 100.9 dias. Blast radius de codigo: **1 arquivo de
producao** (`cli/lib/recall.sh`) + **1 arquivo de teste**
(`tests/cstk/test_recall.sh`).

**NEEDS CLARIFICATION restantes**: 0. Nenhum eixo estrutural
(linguagem/runtime, stack, arquitetura, persistencia, ambiente-alvo, tier de
entrega) e decidido por esta feature — todos herdados do projeto e
inalterados.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (secao "Re-check").*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente | PASS | A feature tem `spec.md` ratificada (clarify concluido, FR-010 resolvido), este `plan.md`, `research.md`, `data-model.md`, `contracts/` e `quickstart.md`. O backlog sera gerado por `/create-tasks`. |
| II. POSIX sh puro, zero dep externa | PASS | Nenhum script novo. Nenhuma dep nova. `sqlite3` permanece dep **opcional** confinada a `cli/lib/recall.sh`, com fallback graceful ja coberto por teste — as 3 condicoes cumulativas do carve-out 1.1.0 seguem satisfeitas (research.md D12). A escolha da forma hiperbolica em vez de exponencial existe justamente para **nao** adicionar dependencia de extensao matematica do SQLite (D6). Sem Bash-isms. |
| III. Formato canonico de skill | N/A | A feature nao cria nem altera skill alguma. Toca runtime do binario (`cli/lib/`), nao catalogo (`plugins/cstk/skills/`). |
| IV. Zero coleta remota | PASS | Toda computacao e local, sobre um indice local, em processo. Nenhuma rede, nenhuma telemetria, nenhum envio. A feature nao adiciona nem um byte de I/O externo. |
| V. Profundidade acima de metricas de adocao | PASS | O objetivo e reduzir retrabalho: hoje o read-back loop dos orquestradores (`--context`) pode injetar achados de baixa autoridade no lugar de decisoes ratificadas. Melhorar a ordem melhora a qualidade da decisao seguinte — nao e feature de vitrine. |
| VI. Veracidade de dados — zero fabricacao | PASS | Toda calibracao vem de medicao reproduzivel contra o indice real, com as consultas publicadas em `quickstart.md` Scenario 8 para reexecucao independente. Nenhum peso foi arbitrado. O contrato marca explicitamente **[ATUAL]** (extraido do codigo) vs **[PROPOSTA]** (a validar na implementacao). O tratamento de `source_ts` ausente rejeita usar `ingested_at` como proxy justamente por ser dado substituto inventado (research.md D9). |

**Resultado do gate**: PASS em todos os MUST (I, II, IV, VI). Nenhuma
violacao a justificar.

## Project Structure

### Documentation (this feature)

```
docs/specs/recall-ranking/
├── spec.md                              # ratificada (clarify concluido)
├── plan.md                              # este arquivo
├── research.md                          # Phase 0 — 12 decisoes + 4 medicoes
├── data-model.md                        # Phase 1 — N/A persistido, justificado
├── quickstart.md                        # Phase 1 — 11 cenarios
└── contracts/
    └── cstk-recall-ranking.md           # Phase 1 — contrato CLI
```

### Source Code (repository root)

Arvore real, limitada ao que a feature toca ou consulta:

```
cli/
├── cstk                                 # dispatch — encaminha argv p/ recall_main; NAO muda
└── lib/
    └── recall.sh                        # UNICO arquivo de producao alterado
        ├── recall_usage()          L183   # + documentar --explain
        ├── RECALL_TYPE_ENUM        L164   # lido (nao alterado)
        ├── RECALL_SCHEMA_VERSION   L161   # permanece 15
        ├── recall_schema_ddl()     L448   # knowledge_fts DDL L700-708 — NAO alterado
        ├── recall_mode_search()    L2977  # + parse --explain, + score, + render explicacao
        │     └── ORDER BY          L3067  # ponto de mudanca 1
        └── recall_mode_context()   L3106  # + score (ordem apenas; formato congelado)
              └── ORDER BY          L3216  # ponto de mudanca 2

tests/cstk/
└── test_recall.sh                       # + cenarios do quickstart.md
      └── scenario_04_limite_e_bm25 L143 # assere CONTAGEM, nao ordem — nao quebra

docs/specs/_archived/
├── cstk-knowledge-db/contracts/cstk-recall.md          # contrato base preservado
└── recall-autoconsume/contracts/cstk-recall-context.md # contrato --context preservado
```

**Structure Decision**: mudanca confinada a um unico arquivo de producao.
A expressao de score aparece em dois pontos do mesmo arquivo e **nao** e
extraida para helper proprio: extrair espalharia referencia a `sqlite3`
para um segundo arquivo, quebrando a condicao (b) do carve-out 1.1.0
(dep confinada a um unico arquivo identificavel por grep) e acionando a
regra de ouro do projeto — todo `.sh` novo exige `tests/<n>.sh`
correspondente, gateado por `./tests/run.sh --check-coverage` — sem ganho
algum para uma unica expressao SQL (research.md D12). A duplicacao
controlada em dois pontos do mesmo arquivo e o custo aceito; a divergencia
entre os dois pontos e coberta pelos cenarios 1 e 11 do `quickstart.md`,
que asseguram que a mesma ordem de autoridade vale nos dois modos.

## Convencoes de Borda

**N/A — single-layer.** A feature nao atravessa nenhuma fronteira de
serializacao: e um CLI POSIX lendo um SQLite local e escrevendo texto em
stdout. Nao ha DB<->backend, backend<->frontend, broker<->consumer, DTO,
JSON de API, ORM ou schema compartilhado envolvidos.

As unicas convencoes de borda relevantes ja existem, sao **congeladas** por
esta feature e estao declaradas no contrato:

| Borda | Convencao | Fonte da verdade |
|-------|-----------|------------------|
| stdout do modo busca (default) | 2 linhas por achado, formato inalterado byte-a-byte | `cli/lib/recall.sh` render de `recall_mode_search()`; contrato §1.3 |
| stdout do modo busca (`--explain`) | +1 linha aditiva por achado, indentada, nunca iniciando com `[` | contrato §1.4 (**[PROPOSTA]**) |
| stdout do modo `--context` | bloco markdown com cabecalho UNTRUSTED + teto `--max-bytes` | `docs/specs/_archived/recall-autoconsume/contracts/cstk-recall-context.md`; contrato §2.2 |
| separador interno de colunas | `\|@\|` (unit separator textual) entre colunas do `.mode list` | `cli/lib/recall.sh`, inalterado |
| formato de `source_ts` | ISO 8601 UTC `YYYY-MM-DDTHH:MM:SSZ` | produzido na ingestao; medido em 8698/8699 linhas do indice real |

## Riscos e mitigacoes

| Risco | Mitigacao |
|-------|-----------|
| Refatoracao futura mover a consulta para subquery e quebrar `bm25()` em runtime | Registrado como restricao explicita (research.md D2, contrato I-6); cenario 8 do quickstart executa a expressao completa contra o indice real |
| Calibracao envelhecer conforme o indice cresce e a dispersao de `bm25()` mudar | Quickstart Scenario 8 publica as consultas de medicao; a regra e **remedir**, nunca rechutar os pesos |
| Divergencia entre os dois pontos de `ORDER BY` (busca e `--context`) | Cenarios 1 e 11 asseguram a mesma ordem de autoridade nos dois modos |
| Validacao manual passar em codigo velho por sync incompleto | GOTCHA destacado no topo do quickstart: `cli/lib/` exige `cstk self-update --from`, nunca `cstk install` |
| `--explain` quebrar a contagem de blocos de teste existente | Contrato C-2 exige que a linha nao comece com `[`; cenario 7 assere `grep -c '^\['` igual com e sem a flag |
| **`source_ts` no futuro estourar o teto do bonus de recencia** (gate security F2, HIGH) | Clamp normativo `max(0.0, ...)` na idade (contrato §1.2, research.md D6). Sem ele, `-89.99d` produz bonus `~900` e fixa o achado em 1o lugar em qualquer consulta. `source_ts` nao e validado na ingestao, e clock skew basta para materializar |
| **Injecao SQL pelo override de relogio** (gate security F1, HIGH) | Item **bloqueado** aguardando ratificacao humana (contrato §3, research.md D13). O caminho de leitura abre o DB em read-write, entao injecao aqui e escrita, nao leitura |
| **Falha de SQL indistinguivel de "nenhum resultado"** (gate security F7) | Invariante I-10 do contrato: checar exit do `sqlite3` separadamente e emitir `log_warn`. Sem isso, o read-back loop pode sumir em silencio e a pipeline decide sem memoria achando que nao havia o que recuperar |
| **`body` com `\|@\|` falsificar a linha `score=`** (gate security F5) | Contrato §1.2.bis: colunas de score **antes** de `body` no SELECT, mantendo `body` como ultima coluna |
| **Bonus de autoridade amplificar memory poisoning** (gate security F6) — **RISCO ACEITO** | O `type` e escolhivel por quem escreve o `state.json`, e `+0.30` promove justamente o tipo mais facil de forjar, num canal com `--limit 4` que alimenta prompt de agente autonomo. E **amplificacao de um vetor preexistente**, nao vetor novo: o achado ja era elegivel. Controles compensatorios reais: rotulo UNTRUSTED emitido em **nivel de codigo** (nao so instrucao ao LLM) e `body` ja passado por `secrets-filter` na ingestao. **Limite honesto desses controles**: o rotulo sinaliza, mas nao impede a selecao. Mitigacao mais forte (condicionar o tier alto a proveniencia, e nao ao `type` sozinho) fica **fora do escopo** desta feature e registrada para avaliacao futura |

## Resultado dos Quality Gates da fase `plan`

Ambos os gates rodaram sobre os 5 artefatos deste plano, com verificacao
empirica (leitura do codigo real + reexecucao das consultas contra o indice).

| Gate | Veredito | critical | high | medium | low |
|------|----------|----------|------|--------|-----|
| doc-quality (`validate-documentation`, plan-profile) | PASS_COM_RESSALVAS | 0 | 1 | 4 | 5 |
| security (`owasp-security`) | PASS_COM_RESSALVAS (condicionado) | 0 | 2 | 5 | 2 |

**Zero findings CRITICAL nos dois gates.** Nenhuma citacao de codigo
divergente, nenhuma divergencia numerica entre artefatos, nenhum erro
aritmetico — o gate documental reproduziu M1-M4 linha a linha, confirmou os
9 numeros de linha citados de `cli/lib/recall.sh` e confirmou que
`scenario_04_limite_e_bm25` de fato assere contagem e nao ordem.

**Findings HIGH — todos enderecados nesta revisao do plano:**

| # | Gate | Finding | Tratamento |
|---|------|---------|------------|
| F1 | security | Env var de relogio interpolada na SQL com validacao subespecificada; DB aberto read-write torna a injecao **escrita**, nao leitura | **Bloqueio humano** — contrato §3 reescrito com 2 opcoes; research.md D13 |
| F2 | security | `source_ts` futuro torna o bonus de recencia **ilimitado** (medido: `~900`), quebrando I-1/I-2 | Clamp `max(0.0, ...)` normativo; I-1 reescrita para valer no dominio inteiro |
| F3-doc | doc-quality | A variavel test-only **nunca era nomeada** em nenhum artefato — 3 cenarios dependiam dela | Resolvido junto de F1: nomeacao explicita virou clausula normativa da Opcao A |

**Findings MEDIUM/LOW aplicados**: intervalo do bonus corrigido para
`[0, 0.10]` com diferenca maxima **atingivel** (D7); mediana da amostra
corrigida de `~0.13` para `0.143` com a distincao entre gaps medios e
individuais (M3); I-9 reescrita por ser factualmente falsa (ordenacao **muda**
quais achados entram sob `LIMIT`); ordem das colunas fixada (§1.2.bis);
sinal em stderr para falha de query (I-10); `Target Platform` com fonte;
linha de instrucao de template removida; redacao de meia-vida qualificada.

**Findings LOW nao aplicados, com motivo**: o canal lateral de inferencia de
IDF via `bm25()` (F8) foi avaliado pelo proprio gate como **nao
materializavel** num `knowledge.db` local mono-usuario — registrado, nao
acionado. O custo de query (F9) foi **medido** (`EXPLAIN QUERY PLAN`
identico entre as duas formas) e nao constitui regressao.

## Complexity Tracking

**Nao aplicavel** — Constitution Check retornou PASS em todos os principios
MUST (I, II, IV, VI) e N/A justificado em III. Nenhuma violacao, nenhuma
excecao temporaria, nenhuma dependencia nova, nenhum arquivo novo. A feature
adiciona zero superficie arquitetural: altera duas clausulas `ORDER BY` e
adiciona uma flag booleana, tudo dentro de um arquivo que ja existia.

## Re-check pos-Phase 1

Revalidacao apos o design (data-model + contratos + quickstart):

- **Design introduziu complexidade nao justificada?** Nao. O Phase 1
  confirmou que nao ha entidade persistida nova (`data-model.md`), nenhum
  arquivo novo e nenhuma camada nova. A unica superficie publica adicionada
  e uma flag booleana.
- **Principios MUST continuam respeitados?** Sim. II segue PASS e **ficou
  mais forte** apos o design: a escolha da forma hiperbolica (D6) foi feita
  precisamente para evitar dependencia de extensao matematica do SQLite que
  o design exponencial teria introduzido.
- **Superficie test-only introduzida?** Sim, uma variavel de ambiente para
  fixar o relogio (contrato §3), necessaria para asserção deterministica de
  recencia. Declarada explicitamente como test-only, fora do `--help`, sem
  garantia de estabilidade, e incapaz de alterar formato, exit code ou
  conteudo (invariante I-9). Nao constitui contrato publico nem viola
  principio algum.
- **Veracidade (VI) apos design?** Reforcada: o contrato separa
  **[ATUAL]** de **[PROPOSTA]** item a item, e o quickstart publica as
  consultas de medicao para que a calibracao seja reproduzivel por terceiros
  em vez de aceita por autoridade.

**Resultado**: PASS. Nenhuma mudanca na tabela de Constitution Check.

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/recall-ranking/plan.md` | Criado |
| `docs/specs/recall-ranking/research.md` | Criado |
| `docs/specs/recall-ranking/data-model.md` | Criado |
| `docs/specs/recall-ranking/contracts/cstk-recall-ranking.md` | Criado |
| `docs/specs/recall-ranking/quickstart.md` | Criado |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor este plano em backlog executavel
3. `/analyze` — validar consistencia cross-artifact apos as tasks
