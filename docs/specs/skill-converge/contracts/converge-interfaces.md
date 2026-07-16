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

**Resolução de `--root`** (fecha CHK017, tarefa 1.2): antes da primeira
chamada a `path-contains.sh` (§6), a skill resolve automaticamente o
diretório-raiz do projeto-alvo (flag explícita → `.git/` ascendente →
`docs/constitution.md` ascendente → abort) — ver §6 para a regra completa.
Essa resolução acontece **uma vez**, de forma transparente, **sem exigir
input adicional do usuário**: quem invoca `Skill(converge)` em modo
standalone não precisa saber ou informar a raiz do projeto manualmente, a
menos que queira sobrepor a detecção automática via `--root`.

**Saída**: `ConvergenceReport` (stdout, formato estruturado — ver §7) +
eventual append no `tasks.md` (§4). Sem `state.json` a escrever (SC-006).

### Modo autônomo (FR-015, via orquestrador)

Invocada pelo orquestrador na fronteira `execute-task → review-task`,
incondicional (sem flag). Além do report, registra Decisão auditável (§8).

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

### Nota de implementação — heading sem numeral fixo (fechado na tarefa 2.3)

O exemplo `II\t...` acima **não** implica que todo `constitution.md` numera
principios em algarismo romano: o template genérico da skill `constitution`
(`global/skills/constitution/templates/constitution.md`) usa placeholders
sem numeração (`### [PRINCIPLE_1_NAME]`), e o próprio princípio-base
obrigatório que essa skill semeia em toda constituição gerada
(`SKILL.md` ETAPA 3.2) também não tem numeral: `### Veracidade de Dados —
Zero Fabricacao (NON-NEGOTIABLE)`. A numeração romana é uma escolha
estilística que **este repositório** fez para a própria
`docs/constitution.md` — não é garantida em `constitution.md` de outros
projetos-alvo.

`extract-must.sh` por isso aceita heading `### <texto>` **com ou sem**
prefixo curto de identificador (romano `I.`/`II.` ou arábico `1.`/`2.`);
quando ausente, usa o próprio título (limpo) como identificador — nunca
fabrica uma numeração que a fonte não declara (Constitution VI). Um
princípio é emitido se **pelo menos um** dos dois sinais, ambos puramente
textuais, estiver presente: (a) o heading termina literalmente em
`(NON-NEGOTIABLE)`; ou (b) o corpo do princípio (até o próximo `### ` ou
EOF) contém uma linha `**MUST:**`. Isso cobre também o caso de um
princípio com regras `MUST` reais cujo heading não leva o sufixo — ex.:
o Princípio III desta própria constituição (`Formato Canônico de Skill`)
tem bloco `**MUST:**` mas não carrega `(NON-NEGOTIABLE)` no heading, e
mesmo assim é corretamente capturado por essa segunda condição.

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

### `gap-key`

```
converge-tasks.sh gap-key --path <p> --type <t> --origin <o>
```
Calcula e imprime **uma** `gap_key` nova: `sha256-12(normalize(path) + " " +
type + " " + normalize(origin))`, onde `normalize()` segue a definição
fechada em `data-model.md` §Entity Gap "Definição de `normalize()`" (tarefa
1.1, CHK011). Responsabilidade distinta de `existing-keys`: este subcomando
**calcula** uma chave a partir de um Gap recém-classificado pelo agente;
`existing-keys` só **lê** marcadores `<!-- converge-key: ... -->` já
gravados em execuções anteriores — os dois nunca se sobrepõem. `--type` MUST
estar em `{missing, partial, contradicts, unrequested}` (mesmo enum de
`severity.sh` §5); valor fora do enum ⇒ exit `2`. Determinístico (mesma
tripla `path`/`type`/`origin` ⇒ sempre a mesma `gap_key`, FR-012).

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

### Resolução automática de `--root` em modo standalone (fecha CHK017, tarefa 1.2)

Em modo autônomo, `--root` é sempre passado explicitamente pelo orquestrador
(`target_project_path` do `state.json`). Em modo **standalone** (FR-014), não
há `state.json`; quando a flag não é fornecida, `--root` é resolvido pela
seguinte ordem de precedência, aplicada **uma única vez** por invocação da
skill (não por chamada individual do script) e reusada em todas as chamadas
subsequentes de `path-contains.sh` dentro da mesma execução:

1. **flag `--root` explícita**, se fornecida — vence sempre, sem busca;
2. senão, **busca ascendente a partir do CWD por `.git/`** (raiz do
   repositório — sinal mais confiável de "raiz de projeto" no ambiente do
   toolkit);
3. senão, **fallback: busca ascendente por `docs/constitution.md`** (raiz do
   projeto-alvo pela convenção já em uso no restante do toolkit — ver
   `agente-00c-runtime`);
4. a busca ascendente tem **teto de 20 níveis** (evita loop em symlink
   circular ou filesystem malformado);
5. **nenhum marcador encontrado** dentro do teto ⇒ `path-contains.sh` (e a
   skill que o invoca) MUST abortar com mensagem indicando que `--root` deve
   ser passado explicitamente — fail-closed, nunca assume o CWD cego (mesmo
   padrão de FR-017). Exit `2` (erro de uso — mesma família de "invocação
   incompleta" já usada pelos demais subcomandos deste contrato; distinto de
   exit `1`, que significa "root foi determinado, mas o path avaliado está
   fora dele").

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

> **Nota — enum de `--escolha` com 2 valores, divergência intencional do
> padrão genérico (resolve CHK025, tarefa 1.5)**: os demais quality gates do
> toolkit (`validate-documentation`, `owasp-security`) usam um enum de 3
> valores (`corrigir-agora` incluso). Este contrato mantém **2** valores
> deliberadamente — `corrigir-agora` não tem correspondente semântico na
> arquitetura do `converge`: **todo** achado acionável vira tarefa residual
> apendada em `tasks.md` (FR-008/FR-013, data-model.md `ConvergencePhase`),
> nunca correção inline durante o próprio gate (distinto de
> `validate-documentation`/`owasp-security`, cujos findings podem ser
> corrigidos no artefato imediatamente). Decisão registrada e auditada em
> `dec-027`/`dec-028` (onda `onda-005`, etapa `create-tasks`) —
> `dec-028` corrige um erro clerical de `dec-027` (citava CHK011 em vez de
> CHK025 no campo `--contexto`; escolha/justificativa/score de `dec-027`
> permanecem corretos). **Reversibilidade explícita**: se o dono do produto
> discordar após revisão, a troca é puramente textual — expandir o enum de
> 2 para 3 valores (`--opcoes '["aceitar","corrigir-agora",
> "escalar-para-humano"]'` neste contrato + no `SKILL.md`, tarefa 3.1.9) —
> sem qualquer refatoração de código ou de scripts.

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
