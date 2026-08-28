# Contribuindo para o cstk-panel

Este documento descreve como rodar testes, verificar invariantes constitucionais e manter a paridade de tipos ao contribuir.

## Pre-requisitos

- Node.js >= 20 LTS
- npm >= 10
- `~/.claude/cstk/knowledge.db` (para testes de integracao com base real)

```bash
npm install
```

**Hooks e MCP nao vem no clone.** O `.claude/settings.json` e versionado (ele
declara QUAIS hooks o projeto usa), mas os scripts em `.claude/hooks/` e o
`.mcp.json` sao artefatos INSTALADOS e ficam fora do git — versionar copia
instalada e o que faz a copia local divergir do catalogo em silencio. Para
popular:

```bash
cstk hooks install     # popula .claude/hooks/
cstk mcp install       # gera .mcp.json (contem path absoluto da sua maquina)
```

Sem isso, os hooks declarados em `settings.json` apontam para scripts
ausentes.

## Como rodar os testes

```bash
# Suite completa (shared-types + server integração)
npm test

# Apenas testes do servidor (requer base fixture em apps/server/test/)
cd apps/server && npx vitest run

# Apenas testes de tipos compartilhados
cd packages/shared-types && npx vitest run

# Em modo watch (desenvolvimento)
npx vitest
```

## Como checar read-only absoluto (Invariante I)

O invariante mais critico: **zero mutacao no banco**.

```bash
# scripts/readonly-check.sh — falha (exit 1) se um verbo SQL de mutacao
# aparecer em CODIGO sob apps/server/src/ (INSERT, UPDATE, DELETE, CREATE,
# DROP, ALTER).
npm run lint:readonly-check
```

A saida **declara a cobertura**, nao so o veredito:

```
OK: 0 verbos de mutacao em 58 arquivos sob apps/server/src
```

Isso e proposital. Um gate que responde apenas `OK` nao distingue "varri tudo
e nao achei" de "nao varri nada" — e a segunda hipotese passa despercebida por
tempo indeterminado.

Ocorrencia em **linha de comentario** e reportada e ignorada (comentario nao
executa SQL). Comentario no **fim** da linha, apos codigo, continua reprovando:
na duvida, o gate reprova. Se voce esbarrar nisso, mova o comentario para
linha propria em vez de reescrever o codigo.

Adicionalmente, a abertura do banco em `apps/server/src/db/open.ts` usa:
- `{ readonly: true, fileMustExist: false }` — modo read-only do better-sqlite3
- `db.pragma('query_only = 1')` — barreira runtime: qualquer tentativa de mutacao lanca excecao

Para confirmar a barreira runtime no codigo:

```bash
grep -n 'readonly.*true\|query_only' apps/server/src/db/open.ts
```

## Como verificar paridade de tipos (Invariante shared-types)

Todos os DTOs devem viver exclusivamente em `packages/shared-types/src/`. Nenhum tipo de dominio deve ser redefinido localmente em `apps/server/src/` ou `apps/web/src/`.

```bash
# Verificar ausencia de pasta types/ em web/src
ls apps/web/src/types/ 2>/dev/null && echo "FALHA: pasta types/ existe" || echo "OK: sem tipos locais"

# Rodar testes de paridade round-trip (payload real -> schema Zod)
cd packages/shared-types && npx vitest run
```

Ao adicionar um novo campo a um DTO:
1. Edite `packages/shared-types/src/entities.ts` (tipo TypeScript)
2. Edite `packages/shared-types/src/schemas/entities.ts` (schema Zod correspondente)
3. Atualize os fixtures nos testes de paridade
4. Confirme que `safeParse(payload_real).success === true` para o novo campo

## Como verificar conteudo UNTRUSTED (Invariante V)

Campos provenientes de agentes (contexto, justificativa, evidencia, body FTS) sao UNTRUSTED e devem ser renderizados via `<TextRaw>`, nunca via `dangerouslySetInnerHTML`.

```bash
# Confirmar ausencia de dangerouslySetInnerHTML= em codigo JSX/TSX
grep -rn 'dangerouslySetInnerHTML\s*=' apps/web/src/ || echo "OK"

# Confirmar uso de TextRaw nos campos UNTRUSTED
grep -rn 'TextRaw' apps/web/src/ | grep -v import
```

## Como verificar honestidade de metrica (Invariante III)

Custo deve ser exibido apenas como `tool calls` (proxy), nunca como `$`/USD/tokens.

```bash
# Verificar ausencia de rotulos monetarios em codigo fonte
grep -rni '\bUSD\b\|\$[0-9]' apps/server/src/ apps/web/src/ || echo "OK"
```

## Estrutura de testes

```
apps/server/test/
├── lib/
│   ├── server-health.test.ts   # Saude e headers de seguranca
│   ├── open.test.ts            # Abertura do DB e 4 motivos de degradacao
│   ├── freshness.test.ts       # Frescor de snapshot e ETag
│   ├── roundtrip.test.ts       # Payload real ponta-a-ponta
│   ├── routes.test.ts          # 29 endpoints GET
│   ├── degradation.test.ts     # 3 cenarios de degradacao x 5 endpoints
│   ├── readonly.test.ts        # Mutacao zero + payload hostil FTS5
│   └── fts.test.ts             # Sanitizacao FTS5
├── mappers/
│   └── mappers.test.ts         # Conversao snake_case->camelCase, lintOk, score
└── knowledge-fixture.db        # Fixture real read-only (nao modificar)

packages/shared-types/src/__tests__/
├── envelope.test.ts            # Schemas Zod do envelope padrao
├── parity.test.ts              # DTOs com payloads sinteticos
└── parity-real.test.ts         # DTOs com payloads reais da API
```

## Build de producao

```bash
# Ordem obrigatoria: shared-types -> server -> web
npm run build

# Verificar artefatos
ls apps/server/dist/   # JS compilado do servidor
ls apps/web/dist/      # SPA bundlada pelo Vite
```

## Invariantes que NAO podem ser violados

| # | Invariante | Verificacao |
|---|------------|-------------|
| I | Read-Only Absoluto | `npm run lint:readonly-check` + `grep readonly.*true open.ts` |
| II | Degradar Nunca Quebrar | Nenhum `throw` em `open.ts`; todos os caminhos retornam `{ok: false}` |
| III | Honestidade de Metrica | `grep '\bUSD\b\|\$[0-9]' apps/` retorna 0 resultados em src/ |
| IV | Nao Reimplementar | `grep '\.post\|\.put\|\.delete\|\.patch' apps/server/src/` retorna 0 |
| V | Conteudo UNTRUSTED | `grep 'dangerouslySetInnerHTML=' apps/web/src/` retorna 0 |
| VI | Snapshot que Muda | `freshness.ts` + `etag.ts` devem existir e ser usados em todas as rotas |
