# Security Checklist: panel-docker

**Purpose**: Validar a qualidade dos requisitos de seguranca do modo Docker do `cstk
serve` — mount read-only do knowledge.db (incluindo o RISCO #1 de leitura WAL),
hardening do container, exposicao de rede, supply chain da imagem e confinamento
contra push a registry — antes de decompor em tarefas.
**Created**: 2026-07-11
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [research.md](../research.md)

## Leitura Read-Only do Knowledge DB (RISCO #1 — WAL sem `immutable=1`)

- [x] CHK001 - O requisito de acesso read-only ao knowledge.db exige verificacao
  empirica explicita antes de ser considerado atendido, em vez de presumir sucesso?
  [Mensurabilidade, Spec §FR-008/FR-009; research.md §Decision 3 linha 142] {auto}
- [x] CHK002 - Existe um cenario de teste que exercita a leitura do knowledge.db em
  modo WAL com dado REAL (sem mock/fixture), comparando modo Docker vs modo nativo?
  [Cobertura de Cenarios, quickstart.md §Scenario 4] {auto}
- [x] CHK003 - O comportamento esperado SE a verificacao empirica do RISCO #1 falhar
  (`SQLITE_CANTOPEN`/torn read) esta definido, em vez de deixar a falha sem tratamento?
  [Completude, research.md §Decision 3 linha 142-155; quickstart.md §Scenario 4 passo 6]
  {auto}
- [x] CHK004 - As alternativas de mitigacao para o RISCO #1 estao ordenadas por
  preferencia, com justificativa de rejeicao para as descartadas (ex.: checkpoint do
  WAL no host)? [Completude, research.md §Decision 3 "Alternatives considered"] {auto}
- [x] CHK005 - O campo `wal_readonly_verified` (data-model) esta vinculado a um
  criterio MUST-verificar antes de fechar FR-008/US2, e nao apenas anotado como nota de
  risco solta? [Rastreabilidade/Mensurabilidade, data-model.md §Knowledge DB Mount linha
  94] {auto}

## Hardening do Container

- [x] CHK006 - O conjunto de flags de hardening (non-root, `--cap-drop`,
  `no-new-privileges`, rootfs read-only) esta especificado como DEFAULT do sistema, e
  nao como algo "a avaliar"? [Clareza/Mensurabilidade, research.md §Decision 7 linha
  272-276] {auto}
- [x] CHK007 - Existe requisito de validacao empirica de que o runtime do painel
  (Fastify + relay) continua funcional sob o conjunto completo de hardening, antes de
  ser considerado pronto? [Verificabilidade, research.md §Decision 7 linha 275-276,
  310-312] {auto}
- [x] CHK008 - A ausencia de `CAP_NET_ADMIN` esta justificada em relacao a alternativa
  de design que ela elimina (encaminhador via `iptables`/DNAT)? [Clareza/Consistencia,
  research.md §Decision 2 "Alternatives considered" linha 100-101; §Decision 7 linha
  277] {auto}
- [x] CHK009 - O requisito de hardening se mantem explicitamente apos um rebuild de
  imagem via `--update`/`--reinstall` (nao so na primeira construcao), ou o plano e
  omisso sobre se o conjunto de flags de `docker run` e reafirmado apos cada gatilho de
  rebuild? [Consistencia, contracts/cli-docker-mode.md §Sequencia passo 5 vs
  §Invariantes de seguranca; research.md §Decision 5 tabela de flags] **[Gap resolvido —
  tasks.md 3.1.3/3.1.5, dec-049: `docker run` e uma UNICA invocacao incondicional em
  `_serve_docker_main` (mesmo conjunto de flags independente do gatilho), agora coberto
  por `_assert_hardening_flags_in_run_line` nos 3 gatilhos (imagem ausente/--update
  rebuild/--reinstall) + reuso sem rebuild em tests/cstk/test_serve-docker.sh]** {auto}
- [x] CHK010 - O resultado do gate `owasp-security` (contagem de findings por
  severidade, decisao de aceite) esta registrado de forma auditavel, permitindo
  confirmar que o gate nao foi pulado silenciosamente? [Rastreabilidade/Auditabilidade,
  plan.md §Constitution Check linha 56; state.json dec-015 (onda de plan, score 3)]
  {auto}

## Exposicao de Rede (Loopback por Default)

- [x] CHK011 - O bind em loopback (`127.0.0.1`) para a porta publicada esta
  especificado como comportamento MUST por default, e nao apenas implicito? [Clareza/
  Mensurabilidade, research.md §Decision 4 linha 179-182; contracts/cli-docker-mode.md
  §Invariantes linha 93] {auto}
- [x] CHK012 - O comportamento para `--host` nao-loopback (aviso vs bloqueio) esta
  definido explicitamente, evitando ambiguidade entre "aviso" (paridade nativa) e algo
  mais restritivo? [Clareza, research.md §Decision 4 linha 183-185;
  contracts/cli-docker-mode.md linha 20] {auto}

## Supply Chain da Imagem

- [x] CHK013 - A fixacao da imagem base por digest (`@sha256:...`, nao tag flutuante)
  tem um mecanismo de verificacao objetivo definido (ex.: teste/lint), analogo ao ja
  exigido para a ausencia de `docker push`? [Mensurabilidade, research.md §Decision 7
  linha 281-285 (MUST fixar por digest, sem teste associado) vs linha 293-296 (teste
  exigido para no-push)] **[Gap resolvido — tasks.md 3.2.2/3.2.3:
  `scenario_dockerfile_pins_base_by_digest_not_floating_tag` (regex `@sha256:` 64-hex
  nos dois estagios, tests/cstk/test_serve-docker.sh) + processo de atualizacao do
  digest documentado em cli/lib/serve-docker.sh junto a `_SD_BASE_IMAGE`]** {auto}
- [x] CHK014 - O uso de `npm ci` (vs `npm install`) no build da imagem tem um
  comportamento definido para o caso em que `package-lock.json` esteja ausente em uma
  release futura do painel, ou o requisito assume incondicionalmente que o lockfile
  sempre existira? [Consistencia/Edge Case, research.md §Decision 1 linha 67 ("decidir
  conforme a presenca de package-lock.json" — condicional) **contradiz** §Decision 7
  linha 283-285 ("MUST usar npm ci... em vez de npm install" — incondicional, aterrado
  apenas na v0.12.1 atual)] **[Conflict resolvido — tasks.md 3.3, dec-050: fail-closed
  explicito (`RUN test -f package-lock.json || { mensagem acionavel; exit 1; }` antes de
  `RUN npm ci` em `_serve_docker_write_dockerfile`), nunca degrada para `npm install`;
  guard extraido e exercitado hermeticamente (sem/com lockfile) em
  tests/cstk/test_serve-docker.sh]** {auto}
- [x] CHK015 - O download+verificacao de integridade do painel no modo Docker reusa o
  MESMO code path do modo nativo (sem segundo mecanismo de download/verificacao)?
  [Consistencia, Spec §FR-007; research.md §Decision 1 linha 39-43, §Decision 7 linha
  286-289] {auto}
- [x] CHK016 - FR-013 (nunca `docker push`) tem um mecanismo de verificacao objetivo
  (teste automatizado) definido no plano, em vez de depender so de disciplina do
  implementador? [Mensurabilidade, research.md §Decision 7 linha 293-296] {auto}

## Escopo do Mount vs FR-009

- [x] CHK017 - A tensao entre "montar o diretorio `~/.claude/cstk/` inteiro `:ro`"
  (necessario pelo WAL) e o requisito de escopo mais estreito possivel (FR-009) tem um
  criterio de decisao explicito (ordem de preferencia condicionada ao resultado do
  RISCO #1), em vez de ficar como ambiguidade aberta sem criterio? [Ambiguidade,
  research.md §Decision 7 linha 299-303] {auto}
- [ ] CHK018 - O apetite de risco para aceitar a exposicao read-only dos arquivos
  irmaos `knowledge.db.bak-*` (em vez de investir esforco extra isolando um diretorio
  dedicado) reflete a prioridade real do produto para este incremento? [Risco/
  Priorizacao de negocio, research.md §Decision 7 linha 299-303] {humano}

## Auditoria do Proprio Gate (Governanca)

- [x] CHK019 - O plano documenta o resultado do gate `owasp-security` (severidade,
  decisao) de forma rastreavel a uma decisao auditavel do orquestrador? [Rastreabilidade,
  plan.md §Constitution Check linha 56; state.json dec-015] {auto}
- [ ] CHK020 - A classificacao de severidade dos 4 achados MEDIUM do gate owasp (todos
  rebaixados a "defaults de hardening" em vez de bloqueios formais) reflete o julgamento
  de risco correto para uma ferramenta local de uso pessoal (nao multi-tenant, nao
  exposta a internet), ou merece confirmacao humana antes do primeiro release do modo
  Docker? [Risco/Julgamento, research.md §Decision 7; state.json dec-015] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/
  `[Conflict]`). Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Nenhum valor concreto foi inventado: onde a fonte marca `[a fixar]`/`[detalhe de
  execute-task]`, o item cobra que a decisao seja tomada E validada empiricamente, nunca
  presume o valor.

### Follow-up obrigatorio (gap → acao)

| Item | Marcador | Destino |
|------|----------|---------|
| CHK009 | `[Gap]` | `/create-tasks` — tarefa: assegurar (teste/assercao) que as flags de hardening do `docker run` (cap-drop ALL, no-new-privileges, read-only rootfs, USER node) sao aplicadas identicamente apos QUALQUER gatilho de (re)build (ausente / `--update` / `--reinstall`), nao so na primeira construcao. |
| CHK013 | `[Gap]` | `/create-tasks` — tarefa: adicionar teste/lint que confirma que o Dockerfile fixa a imagem base por digest (`@sha256:...`), espelhando o teste ja exigido para ausencia de `docker push` (research.md Decision 7). |
| CHK014 | `[Conflict]` | Nao reabrir `/clarify` (pipeline autonoma ja avancou de etapa; risco de baixo raio de acao). Rotear para `/create-tasks`: tarefa explicita "build da imagem MUST falhar fail-closed com mensagem acionavel se `package-lock.json` estiver ausente na arvore extraida, em vez de degradar silenciosamente para `npm install`" — preserva a garantia de reproducibilidade de Decision 7 sem presumir lockfile eterno. Decisao de roteamento registrada como Decisao auditavel pelo orquestrador (ver state.json). |
| CHK018 | `{humano}` | Decisao do dono do produto antes de `/execute-task`: aceitar exposicao read-only dos `.bak-*` siblings, ou investir em mount de escopo mais estreito. |
| CHK020 | `{humano}` | Confirmacao humana antes do primeiro release do modo Docker: validar que os 4 MEDIUM do gate owasp, rebaixados a defaults de hardening, sao apetite de risco aceitavel. |
