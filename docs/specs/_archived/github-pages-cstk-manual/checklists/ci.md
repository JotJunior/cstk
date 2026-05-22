# CI Checklist: GitHub Pages — Manual do cstk

**Purpose**: Validar a QUALIDADE dos requisitos de Continuous Integration
— triggers de build, gates de PR, idempotencia, performance, deploy
mechanism (`actions/deploy-pages@v4`) e resiliencia. Items validam se
os REQUISITOS estao bem-escritos e auditaveis — nao a implementacao do
workflow.

**Created**: 2026-05-19
**Feature**: [spec.md](../spec.md)
**Domain**: ci
**Aderente a**: Constitution-delta D-III (Automated-Publishing);
FR-007, FR-008, FR-009, FR-018, FR-022;
FR-025-INFRA-SCHED, FR-026-INFRA-IDEMP;
SC-001, SC-002, SC-009, SC-011.

---

## 1. Triggers de Build (FR-007, FR-025-INFRA-SCHED)

- [ ] CHK001 - O conjunto de paths que disparam build em FR-007 esta
  consistente com a estrutura real do repositorio (`docs/`,
  `README.md`, `global/skills/**/SKILL.md`, `global/agents/*.md`,
  `global/commands/*.md`, `language-related/**/SKILL.md`, config do
  gerador)? [Completude, Spec §FR-007]
- [ ] CHK002 - A clausula "na configuracao do gerador" (FR-007) tem
  paths explicitos enumerados (`mkdocs.yml`, `docs-site/**`,
  `.github/workflows/*.yml`)? [Clareza, Spec §FR-007]
- [ ] CHK003 - O requisito de "branch principal" (FR-007) declara
  qual e o nome real da branch (`main`, `master`, `github-pages`)?
  [Ambiguity, Spec §FR-007]
- [ ] CHK004 - FR-025-INFRA-SCHED declara `autoSchedule: 'event-driven'`
  sem cron — esta consistente com a ausencia de qualquer trigger
  `schedule:` em FR-007? [Consistencia, Spec §FR-007,
  §FR-025-INFRA-SCHED]
- [ ] CHK005 - O comportamento esperado quando push toca multiplos
  paths simultaneamente (concorrencia de runs, cancel-in-progress)
  esta definido? [Gap, Spec §FR-007]
- [ ] CHK006 - O comportamento esperado para push em tag (vs branch)
  esta definido — tags disparam ou nao? [Gap, Spec §FR-007]

## 2. Gate de Pull Request (FR-008, SC-009)

- [ ] CHK007 - O requisito "build-only sem publicar" em FR-008
  define quais steps especificos sao EXCLUIDOS do workflow de PR
  (apenas `deploy-pages`? Tambem upload-artifact?)? [Clareza, Spec
  §FR-008]
- [ ] CHK008 - O status check obrigatorio em FR-008 esta consistente
  com SC-009 (status check vermelho bloqueia merge sem override)?
  [Consistencia, Spec §FR-008, §SC-009]
- [ ] CHK009 - O conjunto de "regressao bloqueante" em SC-009 (build
  falha, link interno quebrado, queda de Lighthouse abaixo do
  threshold) esta exaustivo — falha de teste de a11y na CI esta
  incluida? [Completude, Spec §SC-009]
- [ ] CHK010 - O mecanismo de "override explicito" em SC-009 esta
  definido (quem pode, como, registro)? [Gap, Spec §SC-009]
- [ ] CHK011 - O PR de fork (contribuidor externo sem permissoes
  `pages: write`) tem comportamento definido — workflow roda em
  modo read-only? [Edge Case, Gap]
- [ ] CHK012 - O comportamento esperado para PR-against-non-main-branch
  (ex: PR para branch experimental) esta definido? [Gap, Spec
  §FR-008]

## 3. Re-publicacao Manual (FR-009)

- [ ] CHK013 - O `workflow_dispatch` em FR-009 tem input definido
  (ex: campo "razao" para auditoria) ou e parameter-less?
  [Gap, Spec §FR-009]
- [ ] CHK014 - O caso de uso "rollback" mencionado em FR-009 esta
  definido — rollback para qual commit (workflow_dispatch permite
  selecionar SHA arbitrario)? [Ambiguity, Spec §FR-009]
- [ ] CHK015 - O uso de `workflow_dispatch` esta consistente com
  FR-025-INFRA-SCHED ("workflow_dispatch cobre republicar sem
  mudanca") — semantica de "republicar mesmo commit" vs
  "republicar commit antigo" esta definida? [Clareza, Spec
  §FR-009, §FR-025-INFRA-SCHED]
- [ ] CHK016 - Existe requisito de autorizacao para
  `workflow_dispatch` (qualquer collaborator? apenas owner?)?
  [Gap, Spec §FR-009]

## 4. Mecanismo de Deploy (FR-022)

- [ ] CHK017 - O requisito FR-022 referencia versoes especificas
  (`upload-pages-artifact@v3`, `deploy-pages@v4`) — existe regra
  para tratamento de major version bump dessas actions (renovate
  automatico vs pin)? [Gap, Spec §FR-022]
- [ ] CHK018 - As permissions exigidas (`pages: write`,
  `id-token: write`) estao consistentes com FR-015 (sem servico
  externo em runtime do navegador — `id-token` e oidc, nao runtime
  do site)? [Consistencia, Spec §FR-022, §FR-015]
- [ ] CHK019 - O ambiente `github-pages` esta nomeado consistentemente
  com a configuracao padrao do GitHub Pages environment? [Clareza,
  Spec §FR-022]
- [ ] CHK020 - O comportamento esperado quando GitHub Pages
  environment esta com protection rules (required reviewers) esta
  definido? [Gap, Spec §FR-022]
- [ ] CHK021 - Existe requisito de retencao do artifact apos publish
  (default GitHub e 90 dias) — relevante para SC-011 (sobrevivencia
  30 dias)? [Gap, Spec §FR-022, §SC-011]

## 5. Idempotencia e Reprodutibilidade (FR-026-INFRA-IDEMP)

- [ ] CHK022 - O criterio "binario-equivalente modulo timestamps
  embutidos pela stack" (FR-026-INFRA-IDEMP) tem definicao de
  quais timestamps sao considerados aceitaveis (build date no HTML?
  sitemap.xml? meta tags)? [Clareza, Spec §FR-026-INFRA-IDEMP]
- [ ] CHK023 - O requisito de idempotencia tem criterio mensuravel
  (ex: hash do output de 2 builds do mesmo commit difere apenas em
  timestamps conhecidos)? [Mensurabilidade, Spec §FR-026-INFRA-IDEMP]
- [ ] CHK024 - O pin da versao da stack (`TODO(MKDOCS_VERSION_PIN)`
  mencionado em FR-021) esta declarado como REQUISITO em algum FR
  ou esta apenas como TODO informativo? [Gap, Spec §FR-021,
  §FR-026-INFRA-IDEMP]
- [ ] CHK025 - Versoes das dependencias transitivas (plugins
  `awesome-pages`, `gen-files`, `meta`) tem requisito de pin? [Gap,
  Spec §FR-021]
- [ ] CHK026 - O requisito "re-publicar mesma versao nao invalida
  cache do navegador alem do TTL padrao" esta consistente com a
  realidade do GitHub Pages (que adiciona cache-control padrao
  sem permitir override no MVP per Assumptions)? [Consistencia,
  Spec §FR-026-INFRA-IDEMP, §Assumptions]

## 6. Performance de Build (FR-018, SC-001, SC-002)

- [ ] CHK027 - O limite "build local <=60s em hardware do mantenedor"
  (FR-018) define qual hardware ("M1 Pro? Intel x86 4-core?") ou
  e relativo? [Mensurabilidade, Spec §FR-018, §SC-002]
- [ ] CHK028 - O limite "workflow CI <=5min" inclui tempo de fila
  do GitHub Actions ou apenas wallclock do run? [Clareza, Spec
  §FR-018, §SC-002]
- [ ] CHK029 - O limite "push to publish <=10min" em SC-001 esta
  consistente com "CI <=5min" em SC-002 (deixa <=5min de buffer
  para Pages CDN propagar)? [Consistencia, Spec §SC-001, §SC-002]
- [ ] CHK030 - O criterio "condicoes normais" em SC-001 esta
  definido (GitHub status: operational? Sem outage de Pages CDN?)?
  [Ambiguity, Spec §SC-001]
- [ ] CHK031 - A medicao "comparando timestamp do commit com
  Last-Modified do HTML publicado" (SC-001) cobre o caso do CDN
  servir versao em cache (Last-Modified pode ser anterior ao push)?
  [Edge Case, Spec §SC-001]
- [ ] CHK032 - O limite de tempo de build escala com inventario —
  quando o numero de paginas dobrar (de 43 para 86), o limite de 60s
  ainda se aplica? [Edge Case, Gap]

## 7. Resiliencia (SC-011, Edge Cases)

- [ ] CHK033 - O criterio SC-011 ("site sobrevive 30 dias")
  reconhece que e propriedade do GitHub Pages — existe requisito
  proprio (ex: nao publicar artefato vazio em caso de falha
  parcial)? [Clareza, Spec §SC-011]
- [ ] CHK034 - O Edge Case "Build falha em CI" descreve continuidade
  da ultima publicacao — existe requisito de NOTIFICACAO ao
  mantenedor (email, slack) ou apenas o status check vermelho?
  [Gap, Spec §Edge Cases]
- [ ] CHK035 - O Edge Case "Repositorio offline / GitHub down"
  cobre comportamento da BUSCA client-side (indice e asset estatico,
  segue funcionando) — esta consistente com FR-006? [Consistencia,
  Spec §Edge Cases, §FR-006]
- [ ] CHK036 - Existe requisito sobre rollback automatico em
  caso de deploy bem-sucedido mas que viola gate posterior
  (ex: Lighthouse cai apos publish)? [Gap]

## 8. Consistencia e Gaps Globais

- [ ] CHK037 - O termo "branch principal" (FR-007) e "branch de
  deploy" (FR-022 nao usa esse termo, deploy-pages e via
  environment) sao termos consistentes ou ha confusao conceitual?
  [Clareza, Spec §FR-007, §FR-022]
- [ ] CHK038 - O conjunto de gates do PR (FR-008 + SC-009) esta
  alinhado entre si — todos os gates listados em SC-009 (build,
  link, Lighthouse) tem requisito de RODAR no workflow de PR
  (FR-008 fala apenas "build-only")? [Conflict, Spec §FR-008,
  §SC-009]
- [ ] CHK039 - Existe requisito sobre observabilidade do workflow
  (logs structured, artifact com build report) ou esta delegado
  ao default do GitHub Actions? [Gap]
- [ ] CHK040 - A constitution-delta D-III ("Automated-Publishing")
  exige algo mais alem dos 3 FRs (007, 008, 009) — ex: notificacao
  de falha, retry automatico, escalation? [Completude, Spec
  §D-III]

---

## Notes

- Marcar items concluidos com `[x]`.
- Items `[Gap]` indicam ausencia de requisito; entrada para
  `/clarify` adicional ou decisao em `plan.md`/`tasks.md`.
- Item CHK038 e o conflito mais relevante: FR-008 diz "build-only"
  mas SC-009 implica que Lighthouse e link-check tambem rodem no PR.
  Precisa alinhamento.
- Item CHK029 confirma consistencia entre dois SCs — bom indicador.
- Rastreabilidade: 39/40 items (~97%) com `[Spec §X.Y]` ou marcador.
