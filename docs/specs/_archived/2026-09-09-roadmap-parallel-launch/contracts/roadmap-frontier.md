# Contrato: `roadmap-frontier.sh`

**Feature**: `roadmap-parallel-launch`
**Arquivo**: `plugins/cstk/skills/review-features/scripts/roadmap-frontier.sh`
**Status**: `[PROPOSTA — a validar na implementacao]`

> **Todo este documento e PROPOSTA.** Nenhuma flag, exit code ou campo abaixo
> existe hoje no repo. O que E real e citado explicitamente como
> "ja existente" com a fonte. Ao implementar, divergencias encontradas MUST
> atualizar este contrato — nao o contrario.

---

## 1. Proposito

Derivar a **fronteira de elegibilidade** do roadmap (FR-001): entradas
`nao-iniciada` cujas dependencias declaradas estao TODAS `concluida`.

Nao lanca nada, nao interage com o operador, nao escreve arquivo algum —
computacao pura sobre a saida de um helper ja existente.

---

## 2. Dependencia real (ja existente, nao proposta)

`plugins/cstk/skills/review-features/scripts/roadmap-status.sh --json`, script
irmao no MESMO diretorio. Contrato REAL dele (lido em
`roadmap-status.sh:16-24` e `:200-201`):

- Flags: `--roadmap PATH` (default `docs/roadmap.md`), `--specs-dir DIR`
  (default `docs/specs`), `--json`.
- Saida `--json`: JSON-lines, uma linha por entrada, no formato literal
  `{"ordem":N,"short_name":"...","status":"...","depende_de":[...]}`.
- Exit codes: `0` sucesso (inclusive 0 entradas), `1` roadmap AUSENTE,
  `2` uso incorreto, `3` roadmap presente mas invalido (sem header
  `# Roadmap`).
- Enum de `status` (`roadmap-mode/contracts/roadmap-artifact.md` §5):
  `nao-iniciada` | `em-andamento` | `concluida`.

`roadmap-frontier.sh` **MUST NOT** reimplementar leitura de `docs/roadmap.md`
para status; a unica excecao e a leitura do bloco de prosa para o aviso de
sobreposicao (§6), que nao e status.

---

## 3. Uso proposto

```
roadmap-frontier.sh [--roadmap PATH] [--specs-dir DIR] [--json]
                    [--exclude-active-from-repo PATH]
roadmap-frontier.sh -h | --help
```

| Flag | Semantica |
|---|---|
| `--roadmap PATH` | repassado tal-e-qual a `roadmap-status.sh` |
| `--specs-dir DIR` | repassado tal-e-qual a `roadmap-status.sh` |
| `--json` | emite JSON-lines (default: tabela markdown legivel) |
| `--exclude-active-from-repo PATH` | remove da fronteira os short-names que ja tem worktree ativa no repo indicado (FR-011 — ver §5) |

### 3.1 Validacao de paths (finding LOW — A05)

`--roadmap`, `--specs-dir` e `--exclude-active-from-repo` recebem caminhos.
`git -C <PATH>` num repositorio hostil pode executar codigo via
`.git/config` (ex.: `core.fsmonitor`). Portanto:

- todo path MUST ser resolvido e **rejeitado** (exit `2`) se contiver
  componente `..` ou se resolver para fora do repo coordenador;
- a premissa de confianca ("o repo coordenador e o roadmap sao do proprio
  operador") MUST estar declarada no `--help` do script.

---

## 4. Regra de elegibilidade (FR-001, FR-010)

Uma entrada `E` entra na fronteira se e somente se:

1. `E.status == "nao-iniciada"`; **E**
2. para todo `d` em `E.depende_de`: existe entrada `D` no mesmo roadmap com
   `D.short_name == d` **e** `D.status == "concluida"`.

Consequencias normativas:

- `depende_de` vazio (`-` literal no artefato, §3.3 do contrato de roadmap)
  => condicao 2 vacuamente verdadeira => elegivel se `nao-iniciada`.
- `D.status` em `em-andamento` **ou** `D` inexistente => `E` NAO elegivel.
  Isto e o que satisfaz **FR-010**: termino nao-concluido (abortado, ou
  bloqueio humano pendente) mantem `tasks.md` com linha pendente, logo
  `em-andamento`, logo nao libera dependentes.
- Entrada ja `em-andamento` ou `concluida` nunca entra na fronteira.

Nao ha deteccao de ciclo aqui: a §3.3 do contrato de roadmap ja exige grafo
aciclico compativel com `ordem`, e a regra acima e um filtro de um unico nivel
(nao percorre transitivamente), logo termina sempre.

---

## 5. Guarda anti-duplicidade (FR-011)

Com `--exclude-active-from-repo PATH`, o helper executa
`git -C PATH worktree list --porcelain` e descarta da fronteira todo
short-name para o qual exista linha `branch refs/heads/<short-name>`.

Formato `--porcelain` e o mesmo ja consumido por `cli/lib/session.sh:261-283`
(`/^branch refs\/heads\//`) — line-oriented, sem `jq` (Principio II).

Ausencia de `git`, path invalido ou repo sem worktrees => **nenhuma exclusao**
+ aviso em stderr; NUNCA erro fatal (a guarda e defesa em profundidade;
`cstk session start` ainda falharia com exit `6` se houvesse colisao real).

**Recuperacao apos sessao-filha morta (FR-016)**: esta mesma guarda e o
mecanismo de recuperacao. Enquanto a worktree existir, a linha
`branch refs/heads/<short-name>` continua presente em `--porcelain` e a
feature permanece excluida da fronteira — mesmo que a sessao-filha
tenha travado ou sido encerrada abruptamente sem notificar. Nao ha
logica adicional de "expiracao": o operador MUST rodar
`cstk session end <SHORT>` (contrato `parallel-launch.md` §8.bis) para
remover a worktree; a proxima chamada a este helper ja nao vera mais a
linha correspondente e a feature volta a ser elegivel, sujeita as
demais condicoes de §4.

---

## 6. Aviso de sobreposicao de artefatos (FR-014, US4)

Emitido apenas como **indicio**, nunca como afirmacao de conflito
(Principio VI — heuristica textual nao comprova sobreposicao).

Fonte: bloco de prosa de cada entrada de `docs/roadmap.md` (§3.4 do contrato
de roadmap) — unica documentacao existente para candidata `nao-iniciada`,
cujo diretorio `docs/specs/<short>/` por definicao nao existe.

Regra proposta: para cada par de candidatas da fronteira, extrair tokens que
pareçam caminho de artefato (contendo `/` ou terminados em extensao conhecida)
e reportar a intersecao nao-vazia. Redacao obrigatoria da saida: forma
"as entradas X e Y mencionam ambas <token>" — proibido redigir como
"X e Y vao conflitar".

Intersecao vazia ou prosa ausente => nenhum aviso (AC2 da US4: segue
oferecendo sem bloquear).

**Truncamento (finding HIGH — LLM01/ASI01, mitigacao 2/4 do plan.md task
4.4)**: cada token extraido do bloco de prosa MUST ser truncado a, no
maximo, 128 caracteres antes de aparecer em qualquer saida (markdown ou
JSON) — mesmo teto de tamanho ja usado por `<CHILD_NAME>` em
`contracts/parallel-launch.md` §4.1 (`^cstk-coord/[A-Za-z0-9._-]{1,64}$`,
dobrado para acomodar path completo em vez de so nome-do-repo). Um bloco
de prosa deliberadamente longo, ou contendo texto de instrucao embutido,
nunca e refletido integralmente na saida do helper.

**Rotulo de nao-confiavel (finding HIGH — LLM01/ASI01, mitigacao 4/4 do
plan.md task 4.4)**: toda linha de aviso de sobreposicao (`--json`: objeto
`warning`; markdown: secao `### Avisos`) MUST incluir um campo/rotulo
explicito marcando a origem como texto livre nao-confiavel — em `--json`,
`"source":"roadmap-prose-untrusted"`; em markdown, o sufixo
"(oriundo de texto livre nao-confiavel do roadmap, nao verificado)" ao
final de cada linha de aviso. Mesmo tratamento dado pelo command pai a
notificacoes de conclusao (`contracts/parallel-launch.md` §6, "gatilho
opaco") — nenhum consumidor downstream (humano ou agente) deve tratar o
token de prosa como fato verificado.

---

## 7. Saida

### 7.1 `--json` (JSON-lines)

Uma linha por candidata elegivel, superset do formato ja emitido por
`roadmap-status.sh`:

```
{"ordem":N,"short_name":"...","depende_de":[...],"eligible":true}
```

**Escaping obrigatorio (finding MEDIUM — LLM05, output handling)**: todo
campo derivado de prosa MUST passar pelas mesmas funcoes de escape ja usadas
por `roadmap-status.sh` (`json_escape` para `--json`, `md_escape` para a
tabela). Sem isso, um token com aspa quebra o JSON-lines e permite forjar
campos no consumidor.

Avisos de sobreposicao (§6) vao em linhas separadas, com o rotulo de
nao-confiavel e o token ja truncado a 128 chars (§6):

```
{"warning":"artifact_overlap","pair":["X","Y"],"tokens":[...],"source":"roadmap-prose-untrusted"}
```

### 7.2 Default (markdown)

Tabela `| ordem | short-name | depende-de |` seguida, quando houver, de uma
secao `### Avisos` com uma linha por par.

### 7.3 Fronteira vazia

Exit `0` + aviso em stderr ("nenhuma feature elegivel"), stdout vazio (ou `[]`
sem linhas em `--json`). Fronteira vazia **nao** e erro — e um dos edge cases
declarados na spec.

---

## 8. Exit codes propostos

| Code | Significado |
|---|---|
| `0` | sucesso (inclusive fronteira vazia) |
| `1` | `roadmap-status.sh` retornou `1` (roadmap AUSENTE) — propagado |
| `2` | uso incorreto |
| `3` | `roadmap-status.sh` retornou `3` (roadmap invalido) — propagado |
| `4` | `roadmap-status.sh` nao encontrado no diretorio irmao |

Propagar `1` e `3` preserva o edge case "roadmap ausente ou mal formado: nao
oferecer paralelismo nem falhar de forma confusa" com a MESMA semantica do
helper ja existente, em vez de inventar codigos paralelos.

---

## 9. Invariantes

- **INV-1**: read-only. Nenhuma escrita em disco, em nenhum caminho.
- **INV-2**: POSIX sh puro, sem `jq` (Principio II) — paridade com
  `roadmap-status.sh` e `aggregate.sh`, no mesmo diretorio.
- **INV-3**: status NUNCA e derivado por leitura propria; sempre por
  `roadmap-status.sh` (fonte unica — SC-004).
- **INV-4**: nenhum token vindo de `docs/roadmap.md` e emitido bruto.
  `short_name` e `depende_de` sao validados a montante pelo fail-closed de
  `roadmap-status.sh`; os tokens do bloco de prosa (§6) — unica leitura direta
  do artefato, e por isso **fora** daquele filtro — sao validados pela
  allowlist propria de §6, **truncados a 128 chars** e emitidos com **rotulo
  de nao-confiavel** (`"source":"roadmap-prose-untrusted"` / sufixo em
  markdown — §6) antes de escapados conforme §7.1. Nenhum caminho emite
  texto do roadmap sem passar por essa cadeia completa.
- **INV-5**: todo campo derivado de prosa e escapado antes de compor JSON ou
  markdown (§7.1) — o helper nao pode emitir JSON-lines malformado.
- **INV-6**: paths recebidos por flag sao validados antes de qualquer uso
  (§3.1); `git -C` nunca aponta para repo fora do escopo declarado.
