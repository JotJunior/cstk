# Contract: `tier-gate-map.txt` (formato da matriz tier x gate)

**Status**: `[PROPOSTA — a validar na implementacao]`. O arquivo
`plugins/cstk/skills/agente-00c-runtime/references/tier-gate-map.txt`
**nao existe** hoje. O formato aqui especificado e uma copia deliberada
do unico precedente real de tabela versionada POSIX-pura do repo,
`references/phase-model-map.txt`, que **foi lido integralmente** e esta
citado abaixo.

---

## 1. Por que copiar `phase-model-map.txt`

FR-005 exige *"matriz tier x gate versionada no toolkit"*. O repo ja tem
exatamente uma tabela desse tipo e ela ja resolveu os problemas que a
nova enfrentaria. Convencoes herdadas, todas verificadas no arquivo real:

| Convencao | Como aparece no precedente |
|---|---|
| Versao na 1a linha, como comentario | `# phase-model-map v1` |
| Separador de campos | `\|` |
| `#` e linha vazia ignorados | regra declarada no cabecalho e implementada no parser |
| Chave nao listada **nunca** e erro | *"Fase NAO listada (ou linha desconhecida) -> resultado '\|manter-atual' (exit 0)"* |
| Cabecalho documenta formato + regras + enum | ~28 linhas de comentario antes dos dados |
| Consumido sem `jq` | *"POSIX-puro, sem jq"* |

A versao (`v1`) e **convencao documental**, nao lida por codigo — mesmo
status que no precedente. Bump manual quando a semantica das colunas
mudar.

---

## 2. Formato

Cada linha de dados tem **3 campos**:

```
tier|gate|modo
  tier  : local | internal-network | cloud-internal | cloud-public
  gate  : nome do quality gate complementar
  modo  : completo | leve | skip
```

Regras de lookup:

- Linhas iniciadas por `#` e linhas vazias sao ignoradas.
- Chave de busca e o **par** `(tier, gate)`.
- Par NAO listado ⇒ resultado `completo`, exit 0.
- Arquivo ausente, ilegivel ou com linha malformada ⇒ `completo`, exit 0.
- Primeira linha declara a versao do mapa (`v1`).
- **Primeiro match vence** e o laco para (`break`). Linha duplicada para o
  mesmo par nao e erro — a primeira ocorrencia decide. Coberto por teste.

**Fail-safe assimetrico e deliberado**: toda degradacao aponta para
`completo`. **Nao existe** entrada, ausencia ou erro que produza `skip`.
Isto e literal em FR-005: *"gate ausente da matriz para um tier MUST
rodar completo (fail-safe na direcao da profundidade)"*.

### 2.1 Saneamento obrigatorio do valor lido (fail-open fechado)

> Origem: gate `owasp-security` sobre este plano, findings **F2 (HIGH)** e
> **F3 (MEDIUM)**. Sem estas duas regras o fail-safe declarado acima e
> **falso** — o lookup e seguro, mas o valor entregue ao consumidor nao.

**R1 — Coercao ao enum fechado (MUST)**. O terceiro campo lido do arquivo
**NAO PODE** ser ecoado verbatim. `gate-mode` valida o valor contra o
conjunto fechado `completo | leve | skip` e **coage qualquer outra coisa
para `completo`**. Sem isso, uma linha malformada (`...|skipp`,
`...|SKIP`, campo vazio, 4o campo colado) produziria uma string arbitraria
que o consumidor interpretaria — e um consumidor escrito como denylist
("pular a menos que seja `completo`") **pularia o gate de seguranca**.

**R2 — Remocao de CR (MUST)**. Os tres campos tem `\r` removido antes de
qualquer comparacao. O ultimo campo da linha e o que retem o `\r` quando o
arquivo e checkout com CRLF (Windows/`core.autocrlf`), fazendo
`completo\r` falhar a igualdade com `completo`. **Esta classe de bug ja
ocorreu neste repo** e foi corrigida em `next-id` (linha v7.5.1,
"next-id imune a CRLF"); o gotcha registrado la e que `$( )` **nao**
remove `\r`. R1 sozinho ja fecha o risco (o valor com `\r` cai fora do
enum e vira `completo`), mas R2 evita degradar silenciosamente todo o
arquivo em plataforma Windows.

**R3 — Consumidor e allowlist, nunca denylist (MUST)**. A prosa do
orquestrador MUST agir como:

```
se modo == "skip"      -> nao invocar (exige Decisao)
senao se modo == "leve" -> invocar com escopo reduzido (exige Decisao)
senao                   -> invocar COMPLETO
```

e **nunca** como "invocar completo apenas se modo == completo, senao
pular". A primeira forma degrada para o gate rodando; a segunda degrada
para o gate desligado. Esta e a mesma disciplina fail-closed do
`bash-guard.sh` (falha do mecanismo bloqueia, nao libera).

---

## 3. Conteudo v1 (proposto)

```
# tier-gate-map v1
#
# Matriz tier x gate: resolve o modo de execucao de um quality gate
# complementar em funcao do tier de entrega declarado (FR-005).
# Consumido por `delivery-tier.sh gate-mode --tier <t> --gate <g>`
# (POSIX-puro, sem jq).
#
# Formato de cada linha de dados (3 campos, separador '|'):
#   tier|gate|modo
#     tier  : local | internal-network | cloud-internal | cloud-public
#     gate  : nome do quality gate complementar
#     modo  : completo | leve | skip
#
# Regras de lookup (fail-safe na direcao da profundidade):
#   - Linhas iniciadas por '#' e linhas vazias sao ignoradas.
#   - Par (tier, gate) NAO listado -> 'completo' (exit 0). Nenhuma
#     degradacao produz 'skip' — errar sempre para MAIS rigor.
#   - Arquivo ausente/ilegivel -> 'completo' (exit 0).
#   - Versionamento: a primeira linha declara a versao do mapa ('v1').
#
# ESCOPO DELIBERADO (decisao do operador, clarify 2026-08-15 / dec-012):
# esta matriz cobre EXCLUSIVAMENTE o gate `owasp-security`. Os demais
# gates complementares (checklist, validate-documentation,
# validate-docs-rendered, analyze) NAO tem linha aqui de proposito —
# rodam completos nos 4 tiers por consequencia do fail-safe acima.
# Adicionar linha para outro gate e mudanca de politica: exige spec.
#
# Modo 'leve' de owasp-security = checagens essenciais apenas:
# auth, secrets, input (literal de FR-005).
local|owasp-security|skip
internal-network|owasp-security|leve
cloud-internal|owasp-security|completo
cloud-public|owasp-security|completo
```

**4 linhas de dados. Nenhuma outra.** A ausencia dos demais gates e a
implementacao de dec-012 — uma propriedade estrutural verificavel por
`grep -c '|' tier-gate-map.txt` (deve casar 4 linhas de dados), nao uma
promessa em prosa.

---

## 4. Como uma politica nova entra

Adicionar linha a esta tabela **muda politica de seguranca** e por isso
nao e edicao livre:

1. Cobrir outro gate (ex.: `local|analyze|skip`) ⇒ contraria dec-012;
   exige spec propria + bump de versao do mapa.
2. Mudar o modo de um par existente (ex.: `internal-network` de `leve`
   para `skip`) ⇒ reduz rigor; exige spec + registro de decisao.
3. Adicionar tier novo ⇒ muda o enum de DeliveryTier; exige spec.

O que **nao** exige spec: correcao tipografica em comentario.

---

## 5. Verificacoes automatizaveis

Assercoes sugeridas para `tests/test_delivery-tier.sh` (o arquivo de
dados nao tem teste proprio — quem o testa e o consumidor, mesmo padrao
de `phase-model-map.txt`, coberto por `tests/test_model-routing.sh`):

| Assercao | Garante |
|---|---|
| os 4 tiers x `owasp-security` devolvem `skip\|leve\|completo\|completo` | conteudo v1 |
| `--gate checklist` em qualquer tier ⇒ `completo` | dec-012 estrutural |
| `--gate validate-documentation` ⇒ `completo` | dec-012 estrutural |
| tabela renomeada/ausente ⇒ `completo`, exit 0 | fail-safe |
| linha malformada (2 campos) nao quebra o parser | tolerancia |
| tier fora do enum ⇒ `completo` | fail-safe |
| nenhum caminho produz `skip` sem linha explicita | INV-2 |
| modo fora do enum no arquivo (`skipp`, `SKIP`, vazio) ⇒ `completo` | **R1** (F2) |
| arquivo com terminadores CRLF ⇒ modos continuam corretos | **R2** (F3) |
| linha duplicada para o mesmo par ⇒ primeira vence, deterministico | §2 |
| stdout de `gate-mode` esta SEMPRE no enum de 3 valores | R1 |
