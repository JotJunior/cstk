# Catalogo MVP de sinais — `model-selector`

Catalogo de **15 sinais** (5 por faixa) usado pelo classificador
`scripts/classify.sh` para mapear input textual em faixa de
complexidade (`rasa` | `media` | `profunda`) e sugerir um rotulo
abstrato de modelo (`haiku` | `sonnet` | `opus` | `manter-atual`).

Referencias: FR-003, FR-004, FR-005, dec-004 (`spec.md`); Decision 1
(`research.md`); Entity `SinalDeClassificacao` (`data-model.md`).

---

## Formato

Tabela markdown POSIX-friendly com 3 colunas — **sem HTML, sem code
fence aninhado, sem celulas multi-linha**. Cada linha de dados representa
um sinal unico globalmente (case-insensitive) no catalogo.

Colunas (ordem fixa):

1. `termo` — string lowercase, sem espacos internos. NOT NULL, min 1 char.
2. `faixa` — enum literal `rasa`, `media` ou `profunda`. NOT NULL.
3. `peso` — inteiro >=1, default 1. NOT NULL.

O classificador parseia este arquivo via `awk` em modo streaming
(Decision 1 do `research.md`), ignorando header e separator. Linhas
de dados sao matched literalmente (`grep -Fxq`) contra cada token do
input ja normalizado (lowercase + strip non-alnum).

O arquivo MUST conter exatamente UMA tabela markdown (a do Catalogo
abaixo). Tabelas adicionais quebrariam o awk de validacao em 1.3.5
(`/^\|/ && !/-+/` conta linhas de pipe sem hyphens — qualquer outra
tabela inflaria a contagem).

---

## Catalogo

| termo | faixa | peso |
|---|---|---|
| rode | rasa | 1 |
| liste | rasa | 1 |
| conte | rasa | 1 |
| grep | rasa | 1 |
| formate | rasa | 1 |
| explique | media | 1 |
| documente | media | 1 |
| resuma | media | 1 |
| traduza | media | 1 |
| compare | media | 1 |
| projete | profunda | 1 |
| refatore | profunda | 1 |
| arquitete | profunda | 1 |
| debate | profunda | 1 |
| escolha | profunda | 1 |

---

## Validacao do catalogo

```sh
# Esperado: 16 (1 header + 15 data rows; separator excluido pelo filtro -+)
awk '/^\|/ && !/-+/ {c++} END {print c}' references/sinais.md
```

Se o output for diferente de 16, o catalogo esta corrompido (linhas
faltando, separator removido, ou data row excluida).

Conferencia rapida por faixa:

```sh
awk -F'|' '/^\|/ && !/-+/ && NR>1 {gsub(/ /,"",$3); print $3}' \
  references/sinais.md | sort | uniq -c
# Esperado: 5 rasa, 5 media, 5 profunda
```

---

## Extensibilidade (FR-004)

Operadores podem **estender o catalogo localmente sem patch** —
basta editar este arquivo diretamente, acrescentando linhas no mesmo
formato `| termo | faixa | peso |`. Mecanismo cravado em CHK041: nao
ha overlay, env-var de busca extra, nem mecanismo de patch
hierarquico — a fonte unica e este arquivo.

### Como estender (passo a passo)

1. Abra `global/skills/model-selector/references/sinais.md` em
   qualquer editor de texto. NAO ha rebuild, recompilacao, restart
   do harness, regeneracao de indice ou cache invalidation — o
   classificador (`scripts/classify.sh`) le este arquivo a cada
   invocacao via `awk` streaming (Decision 1 do `research.md`).
2. Localize a tabela `## Catalogo` (linhas que comecam com `|`).
3. Acrescente UMA linha de dados imediatamente apos a ultima linha
   existente, no formato literal:
   ```
   | <verbo-lowercase> | <faixa> | <peso> |
   ```
   - `<verbo-lowercase>` — string ASCII unica (case-insensitive) no
     catalogo, sem espacos internos.
   - `<faixa>` — UM literal de `{rasa, media, profunda}`. Faixas
     fora desse enum quebram o parser (`awk` filtra silenciosamente
     linhas com faixa invalida).
   - `<peso>` — inteiro `>=1`. No MVP, **peso=1 e o unico valor
     observado** em todos os 15 sinais shipados. Pesos `>1`
     funcionam (o classificador soma), mas alteram o tie-break
     ponderado por contagem e nao por presenca; documentacao de
     edge cases para pesos heterogeneos ficou fora do MVP — use
     `peso=1` salvo justificativa empirica.
4. Salve. Rode `sh global/skills/model-selector/scripts/classify.sh
   "<input que cite o verbo novo>"` para validar que o sinal e
   detectado. Output deve listar o termo novo na linha `sinais
   detectados:` da `## Justificativa`.
5. Opcional: rode tambem o sanity-check do catalogo:
   ```sh
   awk '/^\|/ && !/-+/ {c++} END {print c}' \
     global/skills/model-selector/references/sinais.md
   # Esperado: 17 (1 header + 16 data rows = 15 originais + 1 novo)
   ```

### Catalogo lido dinamicamente — zero rebuild

- O classificador resolve o path do catalogo via
  `${0%/*}/../references/sinais.md` (relativo ao proprio script —
  ver `tasks.md` 2.1.4). NAO ha hardcode absoluto, NAO ha cache
  persistido em disco, NAO ha snapshot binario.
- Cada invocacao re-le o arquivo do disco. Edicao + invocacao
  imediata reflete o sinal novo sem nenhum passo intermediario.
- Por consequencia: rollback de uma extensao = `git checkout
  references/sinais.md` (ou desfazer a edicao manualmente). Nao ha
  estado a invalidar.

### Faixas validas e peso no MVP

Faixas aceitas (enum literal, case-sensitive) — outras quebram o
parser silenciosamente (linhas com faixa fora desse conjunto sao
filtradas pelo `awk` de validacao em `tasks.md` 2.3.1):

- `rasa` — peso aceito no MVP: `1`.
- `media` — peso aceito no MVP: `1`.
- `profunda` — peso aceito no MVP: `1`.

Pesos fracionarios sao explicitamente proibidos (regra 3 da secao
"Regras ao customizar" abaixo) — o classificador e POSIX puro,
inteiro, deterministico. Tabelas markdown adicionais nesta secao
sao PROIBIDAS por invariante de parsing — o arquivo deve conter
**exatamente UMA** tabela `|`-pipe (a do `## Catalogo`).

Regras ao customizar:

1. **Termo unico** globalmente (case-insensitive). Dois registros
   para o mesmo termo (ex: `rode` em `rasa` e `profunda`) violam o
   invariante do `data-model.md` — comportamento indefinido. O
   operador e responsavel pela consistencia.
2. **Faixa literal** em `{rasa, media, profunda}`. Adicionar uma 4a
   faixa exige amendment da spec (FR-003 cita 3 faixas explicitamente).
3. **Peso inteiro >=1**. Sem fracoes — o classificador e
   deterministico e portavel; tie-break entre faixas e resolvido por
   `FR-005` (regra conservadora — vence a mais profunda), nao por
   peso fracionario.
4. **Lowercase obrigatorio** no termo. Variacoes como `Rode` ou
   `RODE` sao normalizadas pelo classificador via `tolower($2)` antes
   da comparacao com tokens do input, mas mantemos o catalogo
   lowercase para que `grep -Fxq` na fonte casse literalmente.
5. **POSIX-friendly**. Sem HTML inline (`<br>`, `<sub>`), sem code
   fence aninhado dentro da tabela, sem celulas multi-linha. O parser
   `awk` espera tabela markdown chata.

### Colisao de sinais

Se um operador acrescentar um termo que tambem aparece como
substring de outro (ex: novo `lista` colidindo com `liste`), o
classificador NAO usa substring matching: ele usa `grep -Fxq`
(fixed-string, exact-line) contra cada token. Portanto colisao
substring nao causa falsos positivos; apenas colisao **exata**
(mesma string em duas faixas) viola o invariante.

Para sinais ambiguos por intencao (ex: `compare` que tanto pode ser
faixa media simples quanto pegar contexto de uma analise profunda),
mantenha-o na faixa **menos profunda** que descreve o caso comum — a
regra conservadora `FR-005` ja eleva quando sinais profundos
co-ocorrem no input.

---

## Origem dos 15 sinais MVP

Os verbos abaixo foram escolhidos por refletirem o eixo "esforco
cognitivo + ambiguidade detectada" descrito em FR-003. Decisao
cravada em dec-004 (clarify) — 15 sinais MVP / 5 por faixa.

- **Rasa** — verbos deterministicos, output curto, contexto pequeno,
  ZERO ambiguidade. Ex: rodar comando, listar arquivos, contar
  linhas, fazer grep, formatar trecho.
- **Media** — raciocinio simples, contexto medio, output narrativo
  curto, SEM decisao arquitetural. Ex: explicar codigo, documentar
  funcao, resumir texto, traduzir snippet, comparar dois arquivos.
- **Profunda** — verbo de design ou decisao, multi-arquivo provavel,
  consequencia em contrato/security/breaking change, ambiguidade nao
  resolvida no input. Ex: projetar API, refatorar modulo, arquitetar
  componente, debater abordagens, escolher entre alternativas.
