# Contracts: Skill Converge — Interfaces

> **[PROPOSTA — a validar na implementação]**: TODAS as assinaturas abaixo
> descrevem scripts e uma skill que **ainda não existem** neste repositório
> (verificado nesta onda: `global/skills/converge/` ausente). São contratos de
> **design projetados do zero**, não interfaces reais afirmadas. Cada
> assinatura MUST ser reconfirmada/ajustada em `/execute-task`. Nenhum valor,
> flag ou caminho abaixo é dado factual observado — é proposta de arquitetura
> (Constitution VI: distinção explícita entre "projetado" e "afirmado como
> real"). Onde um contrato reusa algo **existente**, está marcado `[REAL]` com
> o path verificado.

Convenção de estilo: nomes de scripts, flags, subcomandos e mensagens de
diagnóstico em inglês onde forem sintaxe; texto de UI/erro pode ser pt-br
(regra global de idioma). POSIX sh puro, sem dep externa obrigatória
(Constitution II).

---

## 1. Invocação da skill `converge` (interface de topo)

### Modo standalone (FR-014)

```
Skill(converge) com argumento = <caminho do diretório da feature>
  ex.: docs/specs/skill-converge
```

**Pré-requisitos** (FR-017): `spec.md` E `tasks.md` presentes no diretório.
Ausência de qualquer um ⇒ abortar com mensagem indicando o artefato faltante
e o comando que o gera (`/specify` ou `/create-tasks`) — MUST NOT inferir
conteúdo.

**Saída**: `ConvergenceReport` (stdout, formato estruturado — ver §5) +
eventual append no `tasks.md` (§4). Sem `state.json` a escrever (SC-006).

### Modo autônomo (FR-015, via orquestrador)

Invocada pelo orquestrador na fronteira `execute-task → review-task`,
incondicional (sem flag). Além do report, registra Decisão auditável (§6).

---

## 2. `scripts/extract-intent.sh` — extração determinística de paths [PROPOSTA]

Parseia `tasks.md` (primário) e `plan.md` (secundário, se presente) para os
paths de arquivo declarados + sua origem (task/FR). Determinístico (FR-011).

```
extract-intent.sh --tasks <tasks.md> [--plan <plan.md>]
```

**Saída (stdout)**: uma linha por path declarado, TSV:

| Coluna | Descrição |
|--------|-----------|
| `path` | path relativo ao projeto-alvo, como declarado |
| `origin` | heading `### N.M` ou `FR-NNN` mais próximo que declarou o path |

**Exit codes**: `0` sucesso (≥0 linhas); `1` arquivo `tasks.md` ausente;
`2` erro de uso.

**Determinismo**: mesma entrada ⇒ mesma saída, mesma ordem (ordenação estável).

---

## 3. `scripts/extract-must.sh` — princípios MUST da constitution [PROPOSTA]

Extrai princípios marcados `MUST`/`NON-NEGOTIABLE` de `constitution.md`.

```
extract-must.sh --constitution <constitution.md>
```

**Saída (stdout)**: uma linha por princípio `MUST`/`NON-NEGOTIABLE`:
identificador + título curto (ex.: `II\tScripts POSIX sh Puros`).

**Exit codes**: `0` sucesso; `1` constitution ausente (⇒ escalada `CRITICAL`
por violação de `MUST` fica indisponível, Edge Case — demais severidades
seguem); `2` erro de uso.

---

## 4. `scripts/converge-tasks.sh` — mecânica do `tasks.md` [PROPOSTA]

Agrupa as operações determinísticas sobre o `tasks.md` (espelha o padrão de
`create-tasks/scripts/next-task-id.sh` `[REAL]`). Subcomandos:

### `next-phase`

```
converge-tasks.sh next-phase --tasks <tasks.md>
```
Imprime `max(FASE N) + 1`. (Distinto de `next-task-id.sh` `[REAL]`, que calcula
a próxima **tarefa dentro de** uma fase, não a próxima fase.) Exit `0`.

### `existing-keys`

```
converge-tasks.sh existing-keys --tasks <tasks.md>
```
Imprime as `converge-key` já presentes (parseando `<!-- converge-key: ... -->`
de fases de convergência anteriores). Base do dedup (FR-012). Exit `0`
(imprime nada se não houver — feature nunca convergida).

### `append-phase`

```
converge-tasks.sh append-phase --tasks <tasks.md> --phase-file <novaFase.md>
```
Anexa `<novaFase.md>` ao **final** de `tasks.md` (append-only, FR-009). MUST
falhar (exit `1`, sem escrever) se `<novaFase.md>` estiver vazio (guarda
FR-010). Idempotência (FR-011): chamador só invoca quando há gaps novos; se
nada muda, este subcomando não é chamado ⇒ `tasks.md` byte-idêntico.

**Exit codes** (todos os subcomandos): `0` ok; `1` erro de I/O / entrada
inválida; `2` erro de uso.

---

## 5. `scripts/severity.sh` — função pura de severidade [PROPOSTA]

```
severity.sh --type <missing|partial|contradicts|unrequested> \
            --priority <P1|P2|P3|none> --must-violated <true|false>
```

Imprime `CRITICAL|HIGH|MEDIUM|LOW` conforme a tabela de research §Decision 3.
Pura e determinística (mesma entrada ⇒ mesma saída, sem I/O de arquivo).
Exit `0` sucesso; `2` argumento inválido.

---

## 6. `scripts/path-contains.sh` — contenção de blast radius (FR-018) [PROPOSTA]

```
path-contains.sh --root <dir-projeto-alvo> --path <path-declarado>
```

Resolve `--path` (via `realpath` com fallback POSIX `cd`+`pwd -P`) e verifica
se está **dentro** de `--root`. Exit `0` = contido (seguro ler); exit `1` =
fora do projeto-alvo (⇒ achado `missing`/inconclusivo, arquivo NÃO é lido);
exit `2` erro de uso. Standalone (não depende de state-dir do orquestrador —
research §Decision 6).

---

## 7. Formato do `ConvergenceReport` (stdout, FR-016)

```
## Convergence Report — <feature>

### Achados (N)
| # | tipo | severidade | path | origem |
|---|------|------------|------|--------|
| 1 | missing | HIGH | scripts/foo.sh | FR-003 / task 2.1 |
| ... |

### Resumo por tipo
missing: N | partial: N | contradicts: N | unrequested: N

### Resumo por severidade
CRITICAL: N | HIGH: N | MEDIUM: N | LOW: N

### Ação
Fase de convergência apendada: FASE <N>  (ou: "nenhuma — feature convergida")
```

Todo achado cita ≥1 path concreto + origem (FR-007, SC-004). Sem achado sem
localização rastreável.

---

## 8. Registro como Decisão auditável (FR-019, execução autônoma) [REAL]

Reusa o runtime existente (verificado): `state-decisions.sh register` +
`state-ondas.sh record-skill` em
`global/skills/agente-00c-runtime/scripts/` `[REAL]`.

```
state-decisions.sh register --state-dir <SD> \
  --agente "<orquestrador>" --etapa "converge" \
  --contexto "Gate converge: <resumo quantitativo>" \
  --opcoes '["aceitar","escalar-para-humano"]' \
  --escolha "<aceitar|escalar-para-humano>" \
  --justificativa "<...>" --score <0|2|3>

state-ondas.sh record-skill --state-dir <SD> --skill converge --decisao-id <dec-NNN>
```

Mesmo two-step atômico-lógico dos gates `validate-documentation`/
`owasp-security`. CRITICAL ⇒ candidato a `bloqueios.sh register` (decisão do
orquestrador, não da skill — FR-019).
