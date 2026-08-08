# Proposta de desenho — cobertura de testes por metadados explícitos

> **Status:** proposta de desenho (P2.1 do backlog). **NÃO implementar antes de
> aprovação.** Pede-se aqui apenas: formato do metadado, como o runner consome,
> plano de migração e trade-offs.

## 1. Problema

A convenção de cobertura atual (`tests/run.sh`, FR-009) infere o par
script↔teste **pelo nome**:

```
plugins/cstk/skills/<X>/scripts/<n>.sh  ->  tests/test_<n>.sh
cli/lib/<n>.sh                    ->  tests/cstk/test_<n>.sh
```

Quando um teste tem nome **descritivo** (não-1:1) — porque cobre um aspecto, ou
porque um script é coberto por vários testes granulares — a inferência falha e
gera **falso órfão**. A solução atual são duas allowlists manuais espelhadas em
`run.sh`:

- `_is_internal_test` — testes sem script 1:1 (lado dos testes).
- `_is_covered_by_named_test` — scripts cobertos sob nome divergente (lado dos
  scripts).

Hoje já há **~15 exceções** (model-selector granulares, `report_*`,
`runtime-log-redaction`→`_log.sh`, `secrets-filter-backup`,
`skills-cache-protocol`→`state-cache.sh`, `state-dir-parametrization`,
`update-extra-kinds`, `doc-counts`, e os internos `e2e`/`quickstart`/`bootstrap`...).
Cada teste de nome descritivo novo exige editar `run.sh` em um ou dois pontos.
**Não escala.**

## 2. Solução proposta: metadado `# covers:` no cabeçalho do teste

Cada `test_*.sh` declara, num comentário de cabeçalho, qual(is) script(s) cobre:

```sh
#!/bin/sh
# test_runtime-log-redaction.sh
# covers: plugins/cstk/skills/agente-00c-runtime/scripts/_log.sh
```

Regras do formato:

- **Sintaxe:** linha de comentário `# covers: <path>` (paths relativos ao
  REPO_ROOT). Um path por linha; múltiplas linhas `# covers:` permitidas (um
  teste cobrindo N scripts).
- **Sentinela de "interno":** `# covers: none` declara explicitamente um teste
  sem script 1:1 (harness self-tests, e2e, integration, invariantes de doc).
  Substitui a entrada manual em `_is_internal_test`.
- **Posição:** dentro das primeiras ~15 linhas do arquivo (cabeçalho), para o
  parser ler barato sem varrer o arquivo todo.
- **Retrocompat:** se um teste **não** declara `# covers:`, cai na convenção 1:1
  atual (`test_<n>.sh` ⇒ script de mesmo `<n>`). Nada quebra de imediato.

### 2.1 Anti-ponto-cego (preservar a garantia atual)

A allowlist atual **exige que o script cobridor exista em disco** (se some, o
teste volta a ser órfão real). O metadado deve preservar isso: ao ler
`# covers: <path>`, o runner **valida que `<path>` existe**. Se o path declarado
não existe ⇒ erro de cobertura (exit 1), nunca isenção silenciosa. Isso é
*mais forte* que hoje, porque a relação fica explícita e verificável, não
embutida em `case` patterns.

## 3. Como o runner consome

`_compute_orphans` passa a montar o mapa `script→teste` em duas fontes,
nesta ordem:

1. **Metadados:** varre `grep -lE '^# covers:'` em todos os `test_*.sh`; para
   cada um, extrai os paths declarados → marca esses scripts como cobertos e
   esse teste como não-órfão. `# covers: none` ⇒ teste interno (não-órfão), não
   cobre script.
2. **Fallback 1:1:** para testes sem `# covers:`, aplica a regra de nome atual.

Pseudo-lógica:

```sh
# Para cada test_*.sh:
#   se tem '# covers:' -> registra pares declarados (valida existência do path)
#   senão              -> aplica convenção 1:1 (comportamento legado)
# Órfão de SCRIPT  = script sem nenhum teste apontando p/ ele (por metadado OU 1:1)
# Órfão de TESTE   = teste sem '# covers:' E sem script 1:1 correspondente
#                    (um '# covers: none' nunca é órfão)
```

As funções `_is_internal_test` e `_is_covered_by_named_test` **deixam de crescer**:
viram, no limite, fallback vazio (ou são removidas após migração completa).

## 4. Plano de migração (faseado, sem big-bang)

**Fase 0 — Implementar o parser, modo aditivo.** O runner passa a ler
`# covers:` *em adição* às allowlists. Comportamento idêntico ao atual enquanto
nenhum teste tem metadado. Adicionar `tests/test_*` de cobertura do próprio
parser. Suite verde.

**Fase 1 — Migrar os casos descritivos.** Adicionar `# covers:` aos ~15 testes
hoje na allowlist; remover a entrada correspondente de `_is_internal_test` /
`_is_covered_by_named_test` à medida que cada um migra. `--check-coverage`
continua zero-órfãos a cada passo (gate de regressão).

**Fase 2 — Esvaziar as allowlists.** Quando todas as exceções migraram, as duas
funções ficam só com o fallback 1:1 (ou são removidas). A convenção 1:1 segue
válida para os testes "bem-comportados" (maioria) — eles não precisam de
metadado.

**Fase 3 — Documentar.** Atualizar `CLAUDE.md` ("Como testar scripts shell") e
`tests/README.md` ("Adicionar teste para script novo") para: *teste 1:1 →
nenhum metadado necessário; teste de nome descritivo → declare `# covers:`*.

## 5. Trade-offs

| | A favor | Contra |
|--|---------|--------|
| **Manutenção** | Cobertura fica junto do teste; zero edição em `run.sh` ao adicionar teste descritivo. | Mais uma convenção para o autor lembrar (mitigado: 1:1 segue sem metadado). |
| **Robustez** | Relação explícita e validada (path tem de existir); some o `case` espelhado e propenso a drift. | Parser novo = nova superfície de bug (mitigado por testes do parser na Fase 0). |
| **Legibilidade** | `# covers:` é auto-documentante; lê-se o alvo no topo do teste. | Risco de metadado mentir (declarar cobertura que não exerce) — não detectável estaticamente. |
| **Migração** | Aditiva, reversível, gate verde a cada passo. | Trabalho manual nos ~15 casos atuais. |

### Limite reconhecido
O metadado garante o **mapa de cobertura**, não a **qualidade** dela: um
`# covers: X` pode existir num teste que mal exercita X. Isso já é verdade hoje
(a allowlist também não mede qualidade). Fora de escopo desta proposta.

## 6. Alternativas consideradas

- **Manter allowlist (status quo):** sem custo de implementação, mas a dívida de
  exceções manuais cresce linearmente com testes descritivos. É o problema.
- **Diretório/convenção por aspecto** (ex.: `tests/aspects/<script>/…`): força
  estrutura de pasta, mais invasivo que um comentário, e ainda precisa de mapa.
- **Frontmatter YAML nos testes:** mais pesado para shell puro; `# covers:` é
  POSIX-friendly e grep-ável (Princípio II — zero Bash-isms / deps mínimas).

## 7. Decisão pendente

- [ ] Aprovar o formato `# covers:` + `# covers: none` e seguir para Fase 0.
- [ ] Ajustar formato antes de implementar (ex.: outra palavra-chave).
- [ ] Recusar (manter allowlist).

> Nenhuma mudança em `run.sh` foi feita. Aguarda aprovação para implementar a
> Fase 0.
