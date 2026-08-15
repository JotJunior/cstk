# Security Checklist: delivery-tier

**Purpose**: Unit tests for English — verifica se as garantias de
seguranca ja corrigidas no gate `owasp-security` do `plan.md` (findings
F2/F3/F4/F5/F6) estao ancoradas como MUST testavel na letra de
`spec.md`, e nao apenas resolvidas como decisao de design em
plan/data-model/contracts. O risco que este checklist mitiga: uma
proxima edicao/reabertura da spec (sem reler o plano inteiro) pode
regredir uma protecao que hoje so existe uma camada abaixo.
**Created**: 2026-08-15
**Feature**: [spec.md](../spec.md) · gate de origem: `owasp-security`
sobre `plan.md` (ver `plan.md` §"Revisao de seguranca do plano")

## Fail-safe determinista da matriz tier×gate (findings F2/F3)

- [x] CHK001 - FR-005 formula o fail-safe cobrindo tambem o caso de
  linha PRESENTE na matriz com modo malformado/corrompido (nao so o
  caso de par ausente)? [Gap, Spec §FR-005, contracts/tier-gate-map.md
  §2.1 R1] {auto} — **Satisfeito** (onda-007): FR-005 ganhou clausula
  literal "O mesmo fail-safe MUST cobrir o caso de uma linha PRESENTE
  na matriz com modo malformado, corrompido ou vazio... qualquer modo
  lido fora do enum fechado `completo|leve|skip` MUST ser coagido a
  `completo`, nunca propagado verbatim" — a correcao do finding
  F2/HIGH agora e MUST literal da spec, nao so do contrato.
- [x] CHK002 - A tolerancia a variacao de terminador de linha (CRLF) e
  corretamente delegada ao nivel de implementacao, sem exigir
  granularidade de encoding na spec? [Spec §FR-005, contracts/
  tier-gate-map.md §2.1 R2] {auto} — Satisfeito: o comportamento
  testavel exigido por FR-005 (nunca produzir skip silencioso) e
  independente de plataforma; a regra R2 (`tr -d '\r'`) e detalhe de
  parsing POSIX corretamente escopado no contrato, nao na spec
  funcional.
- [x] CHK003 - A exigencia de o consumidor da matriz ser escrito como
  allowlist (nunca denylist) e corretamente tratada como decisao de
  implementacao no contrato, sem diluir o MUST funcional da spec com
  estilo de codigo? [Spec §FR-005, contracts/tier-gate-map.md §2.1 R3]
  {auto} — Satisfeito: FR-005 define o comportamento observavel
  (fail-safe na direcao da profundidade); a forma de codificar esse
  comportamento (R3, allowlist) e apropriadamente um MUST do contrato
  de implementacao, nao da spec de requisitos.
- [x] CHK004 - Existe Acceptance Scenario garantindo que skip/versao
  leve do gate de seguranca SEMPRE gera Decisao auditavel, nunca
  silencioso? [Spec §User Story 2, Acceptance Scenario 1, FR-005,
  FR-008] {auto} — Satisfeito: AS1 da US2 "cada skip gera uma Decisao
  auditavel com o tier citado como justificativa".

## Protecao contra auto-escalada do orquestrador (finding F5 — ASI01/ASI03)

- [x] CHK005 - A clausula de rebaixamento em FR-009 repete
  explicitamente "decisao manual **do operador**" (como a clausula de
  elevacao faz), ou usa a formulacao mais fraca "decisao manual
  explicita" sem nomear o autor — deixando espaco de leitura para uma
  Decisao auto-gerada pelo proprio orquestrador satisfazer a letra do
  requisito? [Ambiguity, Spec §FR-009] {auto} — **Satisfeito**
  (onda-007): FR-009 agora diz "rebaixamento mid-execucao MUST NOT ser
  aplicado sem decisao manual explicita **do operador**" — paridade
  textual completa com a clausula de elevacao; fecha o vetor F5
  (ASI03 Privilege Abuse) tambem na letra da spec, nao so no INV-4 do
  contrato.
- [x] CHK006 - A spec exige, como requisito testavel, um mecanismo de
  deteccao para "tier mudou sem Decisao de operador correspondente"
  (o finding `delivery-tier-unattended-change` do plano), ou esse
  mecanismo e uma adicao do plano sem lastro em FR-008/FR-009? [Gap,
  Spec §FR-008, FR-009] {auto} — **Satisfeito** (onda-007): FR-008
  ganhou a clausula "O review-task MUST detectar e reportar como
  finding qualquer mudanca do tier vigente sem Decisao de operador
  correspondente na trilha de auditoria
  (`delivery-tier-unattended-change`)" — a deteccao ativa agora tem
  lastro testavel na spec, nao so em `plan.md` Fase D item 13.

## Preservacao do log de seguranca na omissao de fases (finding F4 — OWASP A09)

- [x] CHK007 - FR-006 exclui explicitamente log de
  autenticacao/autorizacao e trilha de auditoria do escopo de
  "observabilidade de producao" omitida, ou o termo fica aberto a
  leitura extensiva que incluiria logging de seguranca? [Ambiguity,
  Spec §FR-006] {auto} — **Satisfeito** (onda-007): FR-006 agora
  qualifica "observabilidade de producao — entendida aqui como
  dashboards, SLO/SLI, APM/tracing, alertas e autoescala/multi-regiao/
  CDN de escala operacional; log de autenticacao/autorizacao e trilha
  de auditoria NUNCA entram nessa omissao, em qualquer tier" — o
  carve-out do finding F4 (OWASP A09) agora e MUST literal, nao so
  `data-model.md` linhas 41-56.
- [x] CHK008 - O carve-out (escala operacional vs rastreabilidade de
  seguranca) e redigido como classificacao objetiva, sem zona cinzenta
  entre as duas colunas? [data-model.md carve-out, linhas 46-50] {auto}
  — Satisfeito: a tabela de 3 linhas classifica cada item de
  infraestrutura de forma binaria e sem sobreposicao (dashboards/SLO/
  APM/tracing/alertas = omitivel; deploy/autoescala/multi-regiao/CDN =
  omitivel; log auth/autorizacao/trilha de auditoria/acesso a dado
  sensivel = nunca omitido).
- [x] CHK009 - Existe Acceptance Scenario ou cenario de quickstart que
  valide especificamente que o backlog `local`/`internal-network`
  PRESERVA tarefas de logging de seguranca, e nao so testa a OMISSAO
  das fases de nuvem? [Spec §User Story 2 Acceptance Scenario 3,
  quickstart.md Cenario 23] {auto} — Satisfeito: Cenario 23 "Omissao de
  fases preserva log de seguranca [CRITICO]" cobre exatamente essa
  direcao, complementando (nao substituindo) o Cenario 10 que testa a
  omissao.

## Leitura segura do tier / superficie de injecao (finding F6 — LLM01)

- [x] CHK010 - FR-004 (propagacao do tier no contexto de
  briefing/specify/plan) exige que a leitura venha de uma fonte
  coagida ao enum de 4 tokens, ou apenas diz "propagar o tier vigente"
  sem garantir que o valor interpolado no prompt nunca seja texto
  livre? [Gap, Spec §FR-004] {auto} — **Satisfeito** (onda-007): FR-004
  ganhou a clausula "A leitura do tier propagado MUST vir de fonte
  coagida ao enum fechado de 4 tokens — nunca texto livre interpolado
  diretamente no prompt da skill" — a garantia INV-5
  (`delivery-tier.sh get` como unica porta de leitura) agora tem lastro
  na letra de FR-004, nao so em `contracts/cli-delivery-tier.md`
  §INV-5.

## Consolidacao (risco agregado)

- [x] CHK011 - Os 4 gaps/ambiguidades acima (CHK001, CHK005+CHK006,
  CHK007, CHK010) compartilham o mesmo padrao: a correcao de
  seguranca existe e foi verificada no `plan.md`/contratos, mas nao
  esta escrita como MUST na letra de `spec.md`. Vale promover 1+ delas
  para a spec via `/clarify` antes de `/create-tasks` (defesa em
  profundidade contra uma futura reabertura da spec que nao releia o
  plano), ou o time aceita o risco residual dado que os contratos +
  os Cenarios 7/19/20/21/22/23 do quickstart ja cobrem
  operacionalmente cada um? [Assumption, Risco] {humano} — **Risco
  tratado** (onda-007, task 1.2): as 5 correcoes (CHK001, CHK005,
  CHK006, CHK007, CHK010) foram promovidas a MUST literal em
  `spec.md` — defesa em profundidade aplicada, nao mais pendencia
  `{humano}` em aberto.

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com evidencia
  citada, ou `[Gap]`/`[Ambiguity]` quando a spec nao cobre — mesmo
  quando o plano ja implementa a correcao).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Rastreabilidade: 11/11 items (100%) citam `[Spec §X.Y]` e/ou
  `[Gap]`/`[Ambiguity]`/`[Assumption]` com path do artefato de origem —
  acima do minimo de 80%.
- Nenhum dos 5 achados originalmente abertos (CHK001, CHK005, CHK006,
  CHK007, CHK010) indicava um bug REAL de implementacao — todos ja
  haviam sido corrigidos no `plan.md`/contratos na onda anterior (gate
  `owasp-security`, findings F2-F6) e tinham cenario de quickstart
  correspondente. O risco de MANUTENCAO que este checklist revelou (a
  spec, isolada do plano, nao carregava a garantia por escrito) foi
  fechado na onda-007 (task 1.2): as 5 clausulas agora sao MUST literal
  em `spec.md`. 11/11 items `[x]`.
