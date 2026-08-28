# API Checklist: cstk-panel — Dashboard de Observabilidade Read-Only

**Purpose**: Validar a qualidade, completude e clareza dos requisitos de API
dos 29 endpoints `GET /api/v1/*` — incluindo envelope, degradação, cache,
paginação e controle de acesso. Não testa implementação; testa se os
**requisitos escritos** são suficientemente precisos para guiar a implementação.

**Created**: 2026-05-24
**Feature**: [`../spec.md`](../spec.md)
**Contratos**: [`../contracts/api-read.md`](../contracts/api-read.md),
[`../contracts/envelope.md`](../contracts/envelope.md)

---

## Contratos de Superfície e Cobertura de Endpoints

- [ ] CHK001 - Os 29 endpoints listados em `api-read.md` têm shape de `data` descrito
  para **todos** os campos de nível superior — ou a spec permite omissão implícita?
  [Completude, Contrato §api-read.md]

- [ ] CHK002 - O endpoint `/health` é o único obrigado a responder `200` mesmo
  com `dbReachable=false`? Está claro que os demais endpoints também devem
  responder `200` (não `503`) em degradação, ou isso só é implícito pela
  leitura cruzada de Princípio II + FR-005? [Clareza, Spec §FR-005]

- [ ] CHK003 - O contrato define o shape de **erro de validação** (`400`) de forma
  consistente com o envelope padrão `{data, meta}`? Há um exemplo de payload
  de erro 400 especificado? [Completude, Contrato §envelope.md]

- [ ] CHK004 - Os endpoints de sub-recursos de execução (waves, decisions, tasks,
  events, alerts, bloqueios, skills) especificam comportamento quando
  `execucaoId` não existe — `404` ou `data:[]` com `meta.degraded`?
  [Clareza, Spec §FR-005, Contrato §api-read.md]

- [ ] CHK005 - Estão especificados os tipos dos path params (`execucaoId`,
  `project`, `feature`) — string UUID, string slug, sem restrição? Isso é
  necessário para validação de entrada e prevenção de path traversal.
  [Clareza, Spec §FR-018]

- [ ] CHK006 - O endpoint `/overview` retorna `kpis` com campos
  nomeados explicitamente na spec ou contrato? Ou `kpis: {...}` é
  apenas um placeholder sem detalhamento dos campos que o compõem?
  [Completude, Contrato §api-read.md]

---

## Envelope Padrão e Degradação

- [ ] CHK007 - O campo `meta.pagination` é obrigatório apenas em `decisions` e
  `search`, ou em **todas** as listas retornadas? A spec/contrato não é
  unívoca: `api-read.md` diz "demais listas paginadas" sem enumerar quais.
  [Ambiguity, Contrato §envelope.md]

- [ ] CHK008 - O contrato especifica o que `data` contém para **cada** `meta.reason`
  de degradação? (`db-missing` → `[]` para lista, `null` para detalhe — mas
  isso está documentado para todos os 29 endpoints ou apenas implícito?)
  [Completude, Contrato §envelope.md]

- [ ] CHK009 - O campo `meta.approximate` é especificado como aplicável apenas a
  métricas, ou pode aparecer em outros recursos? Está claro que `false` é o
  default e que apenas `clarify-resolution` (e potencialmente `severidade
  derivada`) recebe `true`? [Clareza, Spec §FR-009, Contrato §envelope.md]

- [ ] CHK010 - A spec define comportamento quando `schema_version` da base é **maior**
  que `"2"` (base mais nova que o painel espera) — `schema-mismatch` também
  nesse caso, ou só quando menor? [Cobertura de Edge Cases, Spec §FR-007]

- [ ] CHK011 - Estão especificados os requisitos de **consistência do `meta.freshness`**
  entre chamadas em sequência rápida enquanto a base é reescrita? A spec menciona
  que o painel "não assume imutabilidade", mas não define se `mtime` pode
  regredir entre duas requisições subsequentes. [Clareza, Spec §FR-015]

---

## Cache, ETag e 304

- [ ] CHK012 - O cálculo do `ETag` é especificado com suficiente precisão para
  ser determinístico? (`W/"<mtime_epoch>-<maxIngestedAt>"` — mas `maxIngestedAt`
  é de qual tabela quando o endpoint agrega múltiplas entidades?)
  [Clareza, Contrato §envelope.md]

- [ ] CHK013 - A spec define o comportamento de `304` quando a base foi reescrita
  mas os dados do **recurso específico** não mudaram (ETag de recurso vs. ETag
  global da base)? Há granularidade por recurso ou é um ETag único por arquivo?
  [Ambiguity, Spec §FR-016, Contrato §envelope.md]

- [ ] CHK014 - O requisito `FR-016` usa "SHOULD" (não MUST) para ETag/304. Há
  critério definido para quando esse comportamento é aceitável **não** estar
  implementado no MVP? Sem critério, "SHOULD" é ambíguo para acceptance testing.
  [Clareza, Spec §FR-016]

- [ ] CHK015 - O `Cache-Control: no-cache` especificado força revalidação a cada
  requisição. Isso é intencional dado que a base pode ser reescrita? Está
  documentado o trade-off entre frescor e latência? [Consistencia,
  Spec §FR-014, Contrato §envelope.md]

---

## Paginação e Filtros

- [ ] CHK016 - O teto de `limit=200` especificado em `envelope.md` está alinhado
  com o constraint de performance (p95 < 50ms para base ~3MB)? Há requisito
  de tamanho máximo de payload de resposta? [Consistencia, Spec §SC-008,
  Plan §Technical Context]

- [ ] CHK017 - Os filtros globais (`project`, `feature`, `status`, `period`)
  são especificados como case-sensitive ou case-insensitive? Isso afeta
  comportamento quando nomes de projeto têm variações de capitalização.
  [Clareza, Contrato §api-read.md]

- [ ] CHK018 - O comportamento de `total` no `meta.pagination` está especificado
  para o caso degradado? (`total: 0` ou `total: null` quando `meta.degraded=true`?)
  [Completude, Contrato §envelope.md]

- [ ] CHK019 - Estão especificados os requisitos de **ordenação default** para
  cada lista? (`decisions` por onda/score/data? `waves` por ordem cronológica?)
  Sem ordenação default definida, implementações divergirão. [Gap,
  Contrato §api-read.md]

- [ ] CHK020 - O endpoint `/metrics/cost-over-time` retorna série diária (`by day`),
  mas o filtro `period=all` pode retornar anos de dados. Há requisito de
  granularidade adaptativa (dia/semana/mês conforme período) ou agregação
  máxima de pontos? [Gap, Contrato §api-read.md]

---

## Segurança de Superfície de API

- [ ] CHK021 - O requisito de bind em `127.0.0.1` (não `0.0.0.0`) está quantificado
  para o cenário de deploy em container/VM onde `localhost` pode ter significado
  diferente? Ou a spec pressupõe uso exclusivamente em desktop pessoal?
  [Clareza, Spec §FR-017]

- [ ] CHK022 - A lista de origens CORS permitidas é configurável (apenas
  `http://localhost:5173`) ou hardcoded? Se configurável, há requisito de
  validação do valor (ex: rejeitar wildcard)? [Completude, Spec §FR-017,
  Contrato §envelope.md]

- [ ] CHK023 - O requisito de `X-Content-Type-Options: nosniff` está definido
  para **todas** as rotas incluindo `/health` e rotas de erro 400/404? Ou apenas
  para rotas com payload JSON sensível? [Completude, Spec §FR-019]

- [ ] CHK024 - O requisito de canonicalização do path do banco (`config >
  $CSTK_KNOWLEDGE_DB > default`) especifica o que ocorre quando o caminho
  resultante não existe em tempo de execução vs. em tempo de inicialização?
  [Clareza, Spec §FR-018, Contrato §envelope.md]

---

## Rate-Limit e Busca FTS5

- [ ] CHK025 - O "rate-limit leve na busca FTS5" (FR-020) é quantificado em algum
  lugar? Sem threshold (ex: `N req/min por IP`) o requisito é inverificável.
  [Clareza, Spec §FR-020]

- [ ] CHK026 - O comportamento do rate-limit é especificado: `429 Too Many Requests`
  com `Retry-After` header, ou degradação silenciosa (`meta.degraded=true`)?
  Um viola Princípio II (não é condição de dado), o outro pode ocultar abuse.
  [Ambiguity, Spec §FR-020, FR-005]

- [ ] CHK027 - O tamanho máximo de `q` (200 chars, mencionado em `envelope.md`)
  está alinhado com os limites práticos do FTS5 (queries muito longas podem
  causar degradação de performance)? Há testes de performance para `q` próximo
  ao limite? [Consistencia, Spec §FR-012, Contrato §envelope.md]

---

## Invariantes de Read-Only (Auditabilidade)

- [ ] CHK028 - O requisito SC-003 ("zero operações de mutação — auditável por
  inspeção") tem critério de verificação definido? A spec menciona "grep" mas
  não especifica o padrão exato, a ferramenta ou quando esse audit deve rodar
  (CI? pre-commit?). [Clareza, Spec §SC-003]

- [ ] CHK029 - O `PRAGMA query_only=1` é especificado como obrigatório além do
  `mode=ro&immutable=1` no DSN? Ambos são camadas diferentes de proteção —
  a spec (plan.md §Constitution Check) menciona ambos, mas a spec funcional
  (spec.md §FR-002) menciona apenas `mode=ro&immutable=1`. [Consistencia,
  Spec §FR-002, Plan §Constitution Check]

- [ ] CHK030 - Há requisito explícito sobre o comportamento quando o arquivo da
  base é substituído **em disco** enquanto há requisições em andamento? (race
  condition entre reindex externo e leitura — mencionado em Edge Cases da spec
  mas sem requisito formal de tratamento.) [Gap, Spec §Edge Cases, §FR-015]

---

## Consistência entre Contratos e Spec

- [ ] CHK031 - O contrato `api-read.md` lista `/metrics/clarify-resolution` com
  `meta.approximate: true`. A spec funcional (FR-009) exige que métricas
  derivadas sejam **rotuladas** — mas não especifica se a rotulagem é apenas no
  `meta.approximate` ou também em campo de texto na UI. Há alinhamento entre
  spec e contrato nesse ponto? [Consistencia, Spec §FR-009,
  Contrato §api-read.md]

- [ ] CHK032 - O endpoint `/alerts` cross-execução retorna `AlertSignal[]` com
  "drill-down refs". Esses refs estão especificados no shape de `AlertSignal`
  em `data-model.md` ou `api-read.md`? Sem definição, a UI não sabe como
  construir o link de drill-down. [Completude, Contrato §api-read.md]

- [ ] CHK033 - O modelo `Bloqueio` (bloqueios humanos) tem campos `pergunta` e
  `resposta` marcados como UNTRUSTED na spec. O contrato de API reflete esse
  marcador em algum campo de `meta` ou anotação no DTO, ou é apenas um
  requisito implícito de implementação (renderizar como texto puro)?
  [Consistencia, Spec §FR-011, Contrato §api-read.md]

---

## Observabilidade e Operação

- [ ] CHK034 - A spec define requisitos de logging do servidor (nível, formato,
  campos obrigatórios por requisição)? Sem isso, troubleshooting em produção
  depende do que cada desenvolvedor decidir logar. [Gap, Spec geral]

- [ ] CHK035 - Há requisito de métricas de performance do servidor (latência p95
  por endpoint, taxa de erro)? O target `< 50ms p95` aparece no plan.md mas
  não é um requisito funcional mensurável na spec (não há SC correspondente).
  [Gap, Plan §Technical Context, Spec §SC geral]

---

## Notes

- Marcar items concluídos com `[x]`
- Items numerados sequencialmente para referência futura
- Rastreabilidade: 35/35 items têm referência a spec/contrato (100% — acima
  do mínimo de 80%)
- **CHK002, CHK004, CHK013** são os de maior risco — ambiguidades que podem
  causar comportamento divergente entre BE e FE em cenários degradados
- **CHK025, CHK026** são bloqueadores potenciais de acceptance testing (FR-020
  inverificável sem threshold)
