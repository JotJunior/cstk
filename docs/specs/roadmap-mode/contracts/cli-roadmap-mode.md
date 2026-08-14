# Contrato: superficie CLI do modo roadmap

**Status**: `[PROPOSTA — a validar na implementacao]`
**Feature**: `roadmap-mode` (FR-001, FR-002, FR-004, FR-006)

Contrato das mudancas de interface nos helpers POSIX do runtime e nos
scripts de skill. Todas sao **aditivas**: omitir as novas flags reproduz
o comportamento atual byte-a-byte (SC-003).

> **Nota de veracidade (Constitution VI)**: as assinaturas *existentes*
> citadas abaixo (`state-rw.sh init`, `pipeline.sh`, `state-ondas.sh`,
> `commit-mode.sh`) foram lidas do codigo-fonte, com path e linha. As
> assinaturas *novas* estao marcadas `[NOVO]` e sao propostas desta
> feature, nao descricoes de algo que ja exista.

---

## 1. `state-rw.sh init --roadmap-mode` `[NOVO]`

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh`
(`_sr_cmd_init`, arg loop existente)

| Flag | Valores | Default | Comportamento |
|---|---|---|---|
| `--roadmap-mode` | `true` \| `false` | `false` | grava `.roadmap_mode_enabled` no estado inicial |

Espelha exatamente o precedente `--atomic-commit` (mesma validacao,
mesmo default seguro, mesmo exit code): valor fora de `true|false` ⇒
**exit 2** (uso incorreto), sem escrever estado.

**Persistencia**: campo top-level `.roadmap_mode_enabled`. Sob backend
SQLite pousa na coluna catch-all `execution.extra_fields` — **sem
migracao de schema** (verificado empiricamente, research.md Decision 1).

**Doc**: o header do script deve passar a listar `--roadmap-mode` (e,
na mesma passagem, `--atomic-commit`, hoje ausente do header).

---

## 2. `roadmap-mode.sh is-enabled` `[NOVO]`

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/roadmap-mode.sh`

```
roadmap-mode.sh is-enabled --state-dir DIR
```

| Aspecto | Contrato |
|---|---|
| stdout | `true` ou `false`, exatamente |
| exit | **0 sempre** — inclusive quando o campo esta ausente |
| campo ausente | ⇒ `false` (default seguro) |
| valor nao-booleano | ⇒ `false` (defensivo) |
| estado ausente/ilegivel | ⇒ `false`, exit 0 |

Espelha `commit-mode.sh is-enabled` (mesmo contrato de exit-0-sempre e
mesma leitura defensiva via `state-rw.sh get`). O "exit 0 sempre" e
essencial: o consumidor e um `if` na prosa do orquestrador, e um exit
nao-zero abortaria a onda sob `set -e`.

```
roadmap-mode.sh set-enabled --state-dir DIR --value true|false
```

| exit | Significado |
|---|---|
| 0 | gravado |
| 1 | falha de escrita no estado |
| 2 | uso incorreto (valor fora de `true\|false`) |
| 2 | **mudanca de modo apos a execucao ter passado de `constitution`** |

`set-enabled` existe por paridade e para testabilidade; o caminho normal
grava o flag no `init` (§1), nao por mutacao posterior.

**O flag e efetivamente write-once (MUST)**. `set-enabled` MUST recusar
(exit 2, sem escrever) quando ja existir onda registrada em fase
posterior a `constitution`. Motivo de seguranca: sem essa trava, ligar o
modo no meio de uma execucao **trunca a pipeline restante** — pula
`checklist`, `analyze` e `review-task` — e a execucao entao se
autodeclara `concluida`. Como quem invoca os helpers e o proprio
orquestrador (um modelo, sujeito a injecao via artefato lido), a
capacidade de encurtar a propria supervisao nao pode ficar disponivel
mid-execucao.

Trocar de modo depois de iniciada a execucao e decisao do operador, e o
caminho para isso e abortar e reabrir — nao mutar o flag em voo.

---

## 3. `pipeline.sh --mode` `[NOVO]`

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh`

Nova flag opcional aceita por `stages`, `next-stage`, `prev-stage`:

| Valor de `--mode` | Lista de etapas efetiva |
|---|---|
| omitido, ou `default` | `briefing constitution specify clarify plan checklist create-tasks execute-task review-task review-features` (inalterada) |
| `roadmap` | `briefing constitution roadmap` |
| qualquer outro | exit 2 (uso incorreto) |

**Invariante dura**: `_PL_STAGES_LIST` **nao muda**. A assercao existente
de que `stages` (sem `--mode`) retorna exatamente as 10 etapas, na ordem,
continua verdadeira — e e a rede de seguranca contra regressao de SC-003.

**Terminalidade**: `next-stage --mode roadmap --current roadmap` produz
**stdout vazio + exit 0**, identico ao comportamento ja contratado para
a ultima etapa do modo default.

### 3.1 `detect-completion --stage roadmap` `[NOVO]`

Novo arm no `case` existente:

- localiza `<projeto-alvo>/docs/roadmap.md` (via `--projeto-alvo-path`,
  mesmo padrao de fallback PAP ja usado por `briefing` e `constitution`,
  que sao igualmente artefatos project-level);
- aplica a validacao estrutural de `contracts/roadmap-artifact.md` §6;
- exit 0 = etapa concluida; exit 1 = incompleta, com diagnostico em
  stderr apontando qual regra falhou.

Nao ha fallback de path legado (o artefato e novo — nao existe legado a
suportar).

**A validacao de etapa vira `--mode`-aware, NAO globalmente permissiva
(MUST)**: hoje `detect-completion` valida o `--stage` recebido contra a
lista global de etapas e sai com exit 2 para etapa desconhecida — logo
`--stage roadmap` e **rejeitado** no estado atual (fail-closed, correto).
A correcao MUST ser tornar a validacao ciente do modo, e **nao** alargar
a lista global: alargar faria `roadmap` virar etapa valida tambem no
modo default, reintroduzindo pela porta dos fundos exatamente a mudanca
de pipeline que a Decision 2 do research rejeitou.

Assercao de regressao obrigatoria: `--stage roadmap` **sem**
`--mode roadmap` continua invalido.

### 3.2 Reuso de briefing e constitution ja ratificados (FR-002, Edge Case 1)

O modo roadmap **nao** re-entrevista um projeto que ja tem os artefatos
foundation. O comportamento e emergente do mecanismo ja existente, e nao
exige logica nova: `detect-completion --stage briefing` e
`--stage constitution` ja resolvem os paths project-level
(`docs/briefing.md`, com fallback para o caminho legado, e
`docs/constitution.md`) e ja aplicam validacao estrutural. Se o artefato
existe e passa na validacao, a etapa esta concluida e o orquestrador
avanca sem invocar a skill.

Consequencia contratada: num projeto que ja passou por
briefing+constitution, uma execucao em modo roadmap avanca direto para a
etapa `roadmap`. Nenhum flag novo e necessario; o que **seria** erro e
supor que o modo precisa forcar re-execucao dessas etapas.

---

## 4. `state-ondas.sh end --advance --mode` `[NOVO]`

**Arquivo**: `plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh`

Passthrough opcional repassado a `pipeline.sh next-stage`:

```
state-ondas.sh end --state-dir DIR --motivo-termino etapa_concluida_avancando \
  --advance --mode roadmap
```

Sem `--mode`, o comportamento e o atual. Com `--mode roadmap`, a
resolucao da proxima fase usa a lista escopada — necessario porque, do
contrario, fechar a onda de `constitution` gravaria `specify` como
proxima fase no mesmo write atomico do fechamento, reintroduzindo a
pipeline que o modo existe para evitar.

`--mode` sem `--advance` ⇒ **exit 2**, mesma politica ja aplicada a
`--terminal-phase` e `--advance-from`.

### 4.1 O que NAO muda: `--terminal-phase` continua fail-closed

`end --advance --terminal-phase roadmap` **continua morrendo** com erro
de uso quando a fase corrente ja e `roadmap`. Isso e comportamento
correto e preservado: `--terminal-phase` impede o ponteiro de passar do
fim; nao executa o fim. O encerramento com sucesso e o §5.

---

## 5. Encerramento terminal do modo (FR-004)

Sequencia contratada ao concluir a etapa `roadmap`:

1. `state-ondas.sh end --state-dir DIR --motivo-termino concluido`
   (valor da ONDA — enum fixo do helper, identico ao usado pela pipeline
   completa; nao distingue o modo)
2. promocao explicita de **5 campos**, no mesmo lote de escrita:
   - `.execution.status` = `concluida`
   - `.execution.termination_reason` = `concluido_roadmap` (valor da
     EXECUCAO — ver §5.2; **distinto** do `--motivo-termino` da onda)
   - `.execution.finished_at` = timestamp ISO 8601 UTC
   - `.current_stage` = `concluida`
   - `.next_instruction` = texto de execucao encerrada

Multi-campo num unico write e obrigatorio sob backend SQLite: status
terminal exige `finished_at` no mesmo envelope transacional; um write
parcial e rejeitado com o estado intacto.

> **Os 5 campos sao obrigatorios — 3 nao bastam.** Promover apenas
> `status`/`termination_reason`/`finished_at` deixaria `.current_stage`
> em `roadmap` com `.next_instruction` stale, que e exatamente a classe
> de **meio-avanco** que a feature `wave-close-advance` existe para
> eliminar: ponteiro incoerente, invisivel ao `reconcile-wave` (que e
> no-op em onda ja fechada). O precedente aplica os 5 numa unica
> transacao — o proprio comentario do codigo declara "`write` aplica as
> 5 mudancas na mesma transacao (C4), backend-agnostico".

**Precedente seguido**: o branch terminal do `reconcile-wave`, que ja faz
exatamente `end --motivo-termino concluido` + promocao de status. O modo
roadmap difere apenas na fase terminal (`roadmap` em vez de
`review-features`).

**Consequencia no orquestrador**: status `concluida` ⇒
`Schedule intent: none; motivo=concluido` — a execucao para, sem
reagendamento. Isso ja e a regra vigente da tabela de decisao do
orquestrador; nenhuma mudanca e necessaria ali.

### 5.1 Ordem obrigatoria: `finalize` ANTES da promocao terminal (MUST)

Sob modo atomic-commit, o hook de finalize (push + PR) MUST rodar
**antes** da promocao de status terminal, nunca depois.

Motivo — e um risco de seguranca, nao de estetica: o hook `PreToolUse`
de guarda de Bash so age quando ha **execucao ativa**; uma execucao com
status terminal e tratada como inativa e o guard sai sem decidir. Se o
`finalize` (que executa `git push`) rodar **apos** a promocao para
`concluida`, ele executa com a guarda enforced ja desligada — perdendo
justamente a protecao que confina o comando nessa borda.

Sequencia correta:

```
1. detect-completion --stage roadmap   (artefato valido)
2. commit-mode.sh finalize             (push + PR — guarda ATIVA)
3. state-ondas.sh end --motivo-termino concluido
4. promocao dos 5 campos terminais     (guarda passa a inativa)
```

Coberto por cenario dedicado no quickstart.

### 5.2 `termination_reason` distingue o modo

O encerramento do modo roadmap MUST ser distinguivel de uma conclusao de
pipeline completa. Duas execucoes que terminam com
`status=concluida` + `termination_reason=concluido` sao indistinguiveis
para os consumidores derivados (painel, `knowledge.db`, `recall`), o que
tornaria impossivel medir SC-001 ("conclui em menos ondas que a pipeline
completa") — nao ha como saber qual execucao foi qual.

O modo roadmap grava `.execution.termination_reason` = `concluido_roadmap`
— valor **normativo** (enum fechado), nao exemplificativo: todo
consumidor derivado (painel, `knowledge.db`, `recall`) que precisa
distinguir uma execucao em modo roadmap de uma pipeline completa DEVE
casar essa string exata. `status` permanece `concluida` — e conclusao
real, com sucesso, e nenhum consumidor que checa apenas `status` deve
precisar conhecer o modo.

> **Nota de escopo**: este `termination_reason` normativo e o do campo
> **`.execution`** (nivel da execucao), promovido no passo 2 de §5 —
> distinto do `--motivo-termino` passado a `state-ondas.sh end` no
> passo 1 (nivel da **onda**), cujo enum (`etapa_concluida_avancando`,
> `threshold_proxy_atingido`, `bloqueio_humano`, `aborto`, `concluido`)
> e fixo no helper e compartilhado com a pipeline completa — o modo
> roadmap nao introduz um valor novo nesse enum de onda.

---

## 6. `roadmap-status.sh` — cruzamento de portfolio `[NOVO]`

**Arquivo**: `plugins/cstk/skills/review-features/scripts/roadmap-status.sh`
**POSIX puro, sem `jq`** (Principio II; paridade com `aggregate.sh`, que
e jq-free).

```
roadmap-status.sh [--roadmap PATH] [--specs-dir DIR] [--json]
```

| Flag | Default | Papel |
|---|---|---|
| `--roadmap` | `docs/roadmap.md` | artefato a cruzar |
| `--specs-dir` | `docs/specs` | portfolio a inspecionar |
| `--json` | — | emite JSON-lines em vez de tabela markdown |

**Saida default** (tabela markdown), uma linha por entrada, na ordem do
roadmap:

| Coluna | Origem |
|---|---|
| `ordem` | heading da entrada |
| `short_name` | heading da entrada |
| `status` | derivado (contrato do artefato §5) |
| `depende_de` | metadado da entrada |

**Saida `--json`**: uma linha JSON por entrada, montada sem `jq` — mesmo
padrao ja usado por `aggregate.sh`.

**Escape e obrigatorio, nao implicito (MUST)**: "montar JSON sem `jq`"
so e seguro com o escape que o precedente aplica. O script MUST:

- escapar `"` e `\` em todo campo string emitido em JSON (mesma funcao
  de escape do precedente);
- sanitizar `|` nas colunas da tabela markdown (o precedente troca por
  `/`), senao um valor com `|` quebra ou injeta colunas.

Sem isso, um `depende-de` malformado corrompe **os dois** formatos de
saida.

**Validacao fail-closed na leitura**: o script MUST re-aplicar as regras
de `contracts/roadmap-artifact.md` §9.2 — descartar entrada com
`short-name` fora de `^[a-z][a-z0-9-]*$` ou acima de 64 chars, e
descartar token de `depende-de` invalido apos remover crases. Nunca
emitir valor bruto nao validado. O gate de conclusao roda so dentro de
uma execucao em modo roadmap; este script le **qualquer**
`docs/roadmap.md`, inclusive um jamais gateado.

| exit | Significado |
|---|---|
| 0 | sucesso (inclusive roadmap com 0 entradas — aviso em stderr) |
| 1 | roadmap **ausente** |
| 3 | roadmap **presente mas invalido/ilegivel** |
| 2 | uso incorreto |

Exit 1 e exit 3 sao distintos de proposito: o `review-features` chama
best-effort e omite a secao em ambos, mas um roadmap **corrompido** deve
gerar aviso visivel em vez de sumir em silencio do relatorio — ausencia
e um fato normal, corrupcao nao e.

**Ausencia de roadmap nao e erro do relatorio**: o `review-features`
chama este script de forma best-effort — projeto sem `docs/roadmap.md`
segue produzindo o relatorio atual, sem secao de roadmap e sem falhar.
Isso preserva zero regressao para todos os projetos existentes.

---

## 7. Prompt de opt-in no `/agente-00c` (FR-001)

Prosa do command, espelhando o bloco de opt-in do atomic-commit:

- **Posicao**: antes de inicializar o estado — mesma janela em que o
  opt-in de atomic-commit ja e perguntado.
- **Default seguro**: qualquer resposta que nao seja afirmativa,
  **inclusive Enter**, ⇒ `false` (pipeline completa atual).
- **Afirmativas aceitas**: o mesmo conjunto ja usado pelo opt-in
  existente (`s`, `S`, `y`, `Y`, `sim`, `yes`).
- **Nao-interativo**: cai no default sem bloquear — requisito explicito
  de FR-001; nenhuma execucao pode travar esperando resposta.
- **Retomada**: `/agente-00c-resume` **nunca** re-pergunta; le
  `.roadmap_mode_enabled` do estado (paridade com atomic-commit).

O valor coletado e repassado ao `init` como `--roadmap-mode "$_roadmap"`.

---

## 8. Matriz de compatibilidade

| Cenario | Resultado |
|---|---|
| Execucao existente sem `.roadmap_mode_enabled` | lido como `false` ⇒ pipeline atual |
| Comandos do runtime sem `--mode` | comportamento atual, byte-identico |
| Projeto sem `docs/roadmap.md` | `review-features` inalterado |
| `--mode roadmap` com valor invalido | exit 2, sem escrita |
| Backend JSON e backend SQLite | mesmo contrato; sem migracao em nenhum dos dois |
