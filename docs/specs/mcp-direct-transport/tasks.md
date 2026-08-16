# Tarefas mcp-direct-transport - Transporte MCP direto (sem container, resolucao por chamada)

Escopo: eliminar o container Docker do caminho critico do servidor MCP de
estado, invertendo o ponto de resolucao — o servidor passa a registrar todas
as tools na inicializacao e a resolver/validar a sessao a cada chamada. Cobre
as 15 Functional Requirements de `spec.md`, as 7 fases de `plan.md` (F1-F7,
cutover isolado em F5) e os gaps de requisito levantados em
`checklists/requirements.md` (CHK001, CHK002, CHK003, CHK015).

**Legenda de status:**
- `[ ]` Pendente
- `[~]` Em andamento
- `[x]` Concluido
- `[!]` Bloqueado

**Legenda de criticidade:**
- `[C]` Critico - Impacto financeiro direto ou bloqueante
- `[A]` Alto - Funcionalidade essencial
- `[M]` Medio - Necessario mas sem urgencia imediata

**Restricao de sequenciamento (dec-035, plan.md "Invariante de
sequenciamento")**: as FASES 1 a 4 NAO MUST mudar comportamento observado
pelo operador — nenhuma delas pode, isoladamente, deixar o sistema no estado
proibido em que `/mcp` lista as 7 tools mas toda chamada morre em
`SESSION_MISMATCH`. FASE 5 e o UNICO ponto de corte que torna a mudanca
visivel (cutover). Executar fora desta ordem viola a garantia que a propria
feature existe para restaurar.

---

## FASE 1 - Servidor: registro incondicional de tools + resolucao por chamada

### 1.1 Bootstrap sem resolucao de sessao previa `[C]`

Ref: spec.md FR-001, FR-002, FR-004; contracts/server-session-resolution.md §1 (C-1..C-4)

- [x] 1.1.1 Remover a chamada a `resolveActiveSession` de `bootstrap()` (`mcp/state-server/src/index.ts:124`) — as 7 tools passam a ser registradas incondicionalmente, independentemente de existir token
- [x] 1.1.2 Remover/ajustar o `try/catch` de `SessionMismatchError` em `main()` (`index.ts:274-280`) que hoje aborta o processo com `exitCode=1` quando a sessao nao resolve no boot — ausencia de token deixa de impedir o processo de subir
- [x] 1.1.3 Atualizar o comentario fail-closed de `index.ts:120-123` ("sem sessao resolvida, o servidor nao registra NENHUMA tool") para refletir que o fail-closed passa a ser por-chamada, nao mais de boot — comentario desatualizado aqui mentiria sobre o invariante
- [x] 1.1.4 Teste: cobrir em `index.test.ts` que `bootstrap()` sem `MCP_SESSION_TOKEN` registra as 7 tools e nao lanca `SessionMismatchError`

### 1.2 Cache `token -> state_dir` com revalidacao integral por chamada `[C]`

Ref: spec.md FR-002, FR-003, FR-011; contracts/server-session-resolution.md §2 (fluxo, A-1..A-6), §2.3 (K-1..K-5); data-model.md Entity "Cache de resolucao"

- [x] 1.2.1 Criar estrutura em memoria (`session_id -> state_dir`), escopada ao processo, sem TTL (K-1, K-3, K-4)
- [x] 1.2.2 Implementar a resolucao por chamada: hit de cache invoca `mcp-session.sh resolve --state-dir <cached>` (modo direto, revalida do disco); miss invoca `mcp-session.sh resolve --project-path <PP>` (tree-walk) e, em caso de sucesso, popula o cache (fluxo §2.1 do contrato)
- [x] 1.2.3 Garantir que o cache NUNCA armazena `stopped_at`, o descritor inteiro, ou qualquer veredito de autorizacao — apenas o par `session_id -> state_dir` (K-2, invariante de seguranca: cachear o descritor abriria janela de autorizacao para sessao terminal)
- [x] 1.2.4 Confirmar que a rejeicao Zod de `session_id` ausente/vazio antes de qualquer I/O nao regride (A-1) e que a mensagem literal `"session_id nao corresponde ao token de capacidade desta sessao"` e preservada (A-2)
- [x] 1.2.5 Chamar a resolucao por chamada nos 7 handlers de tool (`mcp/state-server/src/tools/*.ts`), substituindo a dependencia da sessao resolvida no boot
- [x] 1.2.6 Confirmar que a resolucao usa exclusivamente o `session_id` apresentado na propria chamada, nunca "a sessao ativa mais provavel", mesmo com multiplas execucoes ativas (A-4, FR-011)
- [x] 1.2.7 Teste: popular o cache com um hit, marcar `stopped_at` no descritor em disco, e confirmar que a chamada seguinte com o MESMO token e rejeitada — prova de que a revalidacao e integral, nao apenas o cache (research Decision 2)

### 1.3 Atualizar semantica de `maxToolCalls` `[A]`

Ref: contracts/server-session-resolution.md §5 (T-1, T-2); data-model.md §Relacionamentos

- [x] 1.3.1 Atualizar o comentario `index.ts:128-131` ("sessao == processo, um container por execucao") para refletir a nova cardinalidade 1 processo : N sessoes — teto passa a ser por processo/sessao do harness, nao mais por execucao autonoma
- [x] 1.3.2 Confirmar que o texto de rejeicao `TOOL_CALL_LIMIT_EXCEEDED` (`index.ts:146`, instrui comutar para o caminho Bash) permanece acionavel sem alteracao de comportamento (T-2)

### 1.4 Gate de aceite da fase `[A]`

Ref: plan.md §Fases de Implementacao (gate obrigatorio por fase, R2); quickstart.md Cenario 0

- [x] 1.4.1 `cd mcp/state-server && npm ci && npm test` — os 15 `*.test.ts` compilam e passam
- [x] 1.4.2 `LC_ALL=C ./tests/run.sh --check-coverage` — exit 0 (nenhum arquivo removido/orfanado nesta fase)

---

## FASE 2 - Build lazy: resolucao de `dist/` + mitigacao de supply chain (R8)

### 2.1 Resolucao de `dist/` + preflight de Node herdado de `serve.sh` `[A]`

Ref: spec.md FR-004; contracts/server-session-resolution.md §4.2 (L-3, L-4, L-6); data-model.md Entity "Cache de build do servidor"

- [ ] 2.1.1 No launcher, resolver o entrypoint `dist/src/index.js` sob `~/.claude/mcp/state-server/` (mesmo diretorio ja usado pelo catalogo, `cli/lib/install.sh:769-784`)
- [ ] 2.1.2 Se `dist/` nao existir, disparar o build lazy (task 2.2) antes de tentar o `exec` do processo node
- [ ] 2.1.3 Reusar o preflight de major de Node ja em producao: `cli/lib/serve.sh:127` (`_SERVE_SUPPORTED_NODE_MAJORS`) e `:160` (`_serve_node_preflight`) — nao duplicar a logica de deteccao de major
- [ ] 2.1.4 Teste: cenario cobrindo resolucao com `dist/` presente vs ausente

### 2.2 Instalacao de dependencias do build lazy com mitigacao de supply chain `[C]`

Ref: checklists/requirements.md CHK001, CHK015; plan.md Risco R8 (severidade HIGH, dec-041/dec-042 — a UNICA ocorrencia real hoje da flag de protecao no repo, `cli/lib/mcp-docker.sh:169`, sai junto com a FASE 3); contracts/server-session-resolution.md §4.2 (L-4)

- [ ] 2.2.1 **CHK002** — Auditar a arvore resolvida de `mcp/state-server/package-lock.json` por dependencias (diretas ou transitivas) com `scripts.install`/`scripts.postinstall` que compilem binario nativo (ex.: via `node-gyp`/`prebuild-install`). Esta e uma VERIFICACAO real sobre o lockfile, nao uma suposicao — o comentario existente em `cli/lib/mcp-docker.sh:165-168` ("as deps desta arvore sao JS puro") e premissa NAO validada, nao fato estabelecido. Registrar a evidencia (pacotes inspecionados + resultado) no relatorio de execucao desta task
- [ ] 2.2.2 Se a auditoria (2.2.1) encontrar dependencia com build nativo, tratar o caso explicitamente (allowlist pontual documentada ou alternativa de empacotamento) ANTES de aplicar a flag da subtask seguinte cegamente — MUST, nao pode ser ignorado silenciosamente
- [ ] 2.2.3 **CHK001** — No build lazy, instalar as dependencias com o comando que ignora scripts de ciclo de vida (mesma flag ja usada no Dockerfile removido na FASE 3, `cli/lib/mcp-docker.sh:169` — a UNICA ocorrencia real hoje no repo dessa protecao) — o build lazy no host executa com os privilegios do usuario (sem o confinamento que o `docker build` dava antes), logo nunca instalar sem essa flag
- [ ] 2.2.4 **CHK015** — Fixar a instalacao pelo `package-lock.json` ja versionado — o comando escolhido em 2.2.3 exige lockfile presente e sincronizado por natureza (nao usar o comando alternativo que ignora o lock); segunda metade da mitigacao de R8
- [ ] 2.2.5 Cachear o resultado do build (`node_modules/` + `dist/`) em `~/.claude/mcp/state-server/`, fora do repositorio, gerado em runtime
- [ ] 2.2.6 Teste: gate manual documentado no Cenario 0 do quickstart (nao ha CI para `mcp/`, ver FASE 6 R2); confirmar no relatorio da fase que a evidencia da auditoria 2.2.1 foi registrada

### 2.3 Degradacao para idle quando o build lazy nao e possivel (contrato L-5) `[C]`

Ref: spec.md FR-004; contracts/server-session-resolution.md §4.2 (L-5); quickstart.md Cenario 9

- [ ] 2.3.1 Sem `npm` no PATH, sem rede, ou Node fora da faixa suportada, o launcher MUST degradar para idle com motivo explicito — NUNCA falhar a sessao do harness (guard-rail contra regredir ao sintoma da US1)
- [ ] 2.3.2 Teste: simular indisponibilidade (`npm` fora do PATH) e confirmar idle com motivo diagnosticavel, nunca erro opaco (Cenario 9 do quickstart)

### 2.4 Gate de aceite da fase `[A]`

- [ ] 2.4.1 `npm test` local + `LC_ALL=C ./tests/run.sh --check-coverage`
- [ ] 2.4.2 Executar manualmente o Cenario 9 do quickstart completo (build lazy ausente -> idle -> `npm` restaurado -> `dist/src/index.js` existe -> tools listadas)

---

## FASE 3 - CLI: `start` sem Docker + remocao de `cli/lib/mcp-docker.sh`

### 3.1 Validar o recorte "codigo que `gc` usa" vs "codigo que so `start` usava" (R6) `[C]`

Ref: checklists/requirements.md CHK003; contracts/cli-mcp-lifecycle.md §5.1; plan.md Risco R6

**MUST ser concluida antes da task 3.3 (remocao)** — e a decisao de fronteira mais delicada da implementacao e nao foi verificada linha a linha nas fases anteriores.

- [ ] 3.1.1 Ler `cli/lib/mcp-docker.sh` e `cli/lib/mcp.sh` e listar as funcoes/blocos que `_mcp_cmd_gc` de fato invoca (preflight Docker + listagem/remocao de containers pelo padrao de nome `cstk-mcp-state-*`)
- [ ] 3.1.2 Listar separadamente o codigo usado SOMENTE por `_mcp_cmd_start` (build de imagem, `docker run` com montagens, healthcheck) — candidato a remocao total
- [ ] 3.1.3 Documentar o recorte resultante (no commit da task 3.3) substituindo o rotulo `[PROPOSTA — a validar na implementacao]` de `contracts/cli-mcp-lifecycle.md §5.1` pelo recorte real verificado

### 3.2 `cstk mcp start` sem motor de containers `[C]`

Ref: spec.md FR-006, FR-010, FR-014; contracts/cli-mcp-lifecycle.md §2.2 (S-1..S-5), §2.3 (S-6, S-7)

- [ ] 3.2.1 Substituir o fluxo `preflight docker -> build imagem -> docker run -> healthcheck` por `resolver state-dir -> gerar/reusar token -> gravar descritor mode=direct -> exit 0`
- [ ] 3.2.2 Gravar o descritor sem `mode=docker` nem `container_name` preenchido, reusando o schema existente de `_mcp_write_descriptor` (`cli/lib/mcp.sh:446-469`) com `container_name: null`
- [ ] 3.2.3 Preservar idempotencia: chamada repetida para execucao com sessao ja ativa reusa o `session_id` existente, nunca duplica processo nem invalida a sessao em curso (S-3, FR-010)
- [ ] 3.2.4 Detectar descritor legado `mode=docker`, emitir aviso explicito em stderr e sobrescrever com o novo formato — nunca falhar nem recusar por causa de estado legado (S-4, FR-014, clarify dec-015)
- [ ] 3.2.5 Confirmar que `start` NAO inicia processo algum — nenhum `docker run`/spawn de processo sobra no caminho novo; quem cria o processo do servidor e o harness, ao conectar o `.mcp.json` (S-5, FR-012)
- [ ] 3.2.6 Preservar integralmente o contrato de exit code (0/1/2/3) e os motivos de fallback NAO especificos de Docker (S-6, S-7)
- [ ] 3.2.7 Teste: cenario de idempotencia (chamar `start` duas vezes, confirmar `session_id` identico) e cenario de descritor legado sobrescrito com aviso em stderr (Cenarios 4 e 5 do quickstart)

### 3.3 Remover `cli/lib/mcp-docker.sh` e seu teste no MESMO commit `[C]`

Ref: plan.md Risco R1 (dec-033); quickstart.md Cenario 0 passo 3

**Depende de**: task 3.1 concluida (recorte validado) e task 3.4 preservando o que `gc` precisa.

- [ ] 3.3.1 Remover `cli/lib/mcp-docker.sh`, preservando em `cli/lib/mcp.sh` apenas o minimo identificado em 3.1.1
- [ ] 3.3.2 Remover `tests/cstk/test_mcp-docker.sh` no MESMO commit da 3.3.1 — NUNCA via allowlist de "internos" em `_is_internal_test` (mentiria sobre a natureza do arquivo e corromperia o sinal do `--check-coverage`)
- [ ] 3.3.3 `LC_ALL=C ./tests/run.sh --check-coverage` MUST sair 0 apos a remocao — gate obrigatorio antes do commit

### 3.4 `cstk mcp gc` continua recolhendo o passivo Docker legado `[C]`

Ref: spec.md FR-015; contracts/cli-mcp-lifecycle.md §5 (G-1..G-3); quickstart.md Cenario 6

- [ ] 3.4.1 Confirmar que `_mcp_cmd_gc` continua detectando e removendo containers `cstk-mcp-state-*` apos a remocao da task 3.3 (usa exclusivamente o codigo preservado em 3.1.1/3.3.1) — `gc` NAO vira no-op, apenas deixa de ter containers NOVOS para gerenciar
- [ ] 3.4.2 Confirmar que a degradacao com `summary=docker-indisponivel examined:0 removed:0 kept:0 skipped:0` + exit 0 (`cli/lib/mcp.sh:806`) permanece intacta quando Docker esta ausente da maquina
- [ ] 3.4.3 Teste: `cstk mcp gc --dry-run` lista candidatos sem remover; `cstk mcp gc` remove e reporta contagem; `cstk mcp gc` sem Docker degrada com exit 0 (Cenario 6 do quickstart)

### 3.5 Gate de aceite da fase `[A]`

- [ ] 3.5.1 `npm test` + `LC_ALL=C ./tests/run.sh --check-coverage` + `LC_ALL=C ./tests/run.sh mcp`

---

## FASE 4 - Commands: generalizar a injecao do token (FR-013)

### 4.1 Remover a condicao `mode == "docker"` em `/agente-00c` `[C]`

Ref: spec.md FR-013; contracts/cli-mcp-lifecycle.md §7 (P-1, P-2); plan.md Project Structure (`plugins/cstk/commands/agente-00c.md:487`)

- [ ] 4.1.1 Em `plugins/cstk/commands/agente-00c.md`, remover/generalizar o bloco `if [ "$_mcp_mode" = "docker" ]; then` (em torno da linha 487) — injetar o token sempre que o descritor existir e tiver `session_id` valido, independentemente do valor de `mode`
- [ ] 4.1.2 Teste: estender `tests/test_command-spawn-mcp-lifecycle.sh` (ou adicionar cenario) cobrindo injecao do token com `mode=direct`

### 4.2 Remover a condicao `mode == "docker"` em `/feature-00c` `[C]`

Ref: spec.md FR-013; contracts/cli-mcp-lifecycle.md §7 (P-1, P-2, P-3); plan.md Project Structure (`plugins/cstk/commands/feature-00c.md:728`)

**MESMO commit da task 4.1** — deixar um dos dois commands desatualizado gera assimetria silenciosa entre `/agente-00c` e `/feature-00c` (P-3).

- [ ] 4.2.1 Em `plugins/cstk/commands/feature-00c.md`, remover/generalizar o bloco equivalente (em torno da linha 728)
- [ ] 4.2.2 Teste: cenario equivalente ao de 4.1.2, para o command `/feature-00c`

---

## FASE 5 - CUTOVER: launcher `exec` direto, sem exigir token

### 5.1 Launcher: `exec` no processo node real `[C]`

Ref: spec.md FR-004, FR-005, FR-012; contracts/server-session-resolution.md §4.2 (L-1, L-2, L-7); clarify dec-010

**Este e o UNICO passo que torna a mudanca visivel ao operador (research Decision 13). Depende de FASE 1, 2, 3 e 4 concluidas.**

- [ ] 5.1.1 Substituir o caminho idle-quando-sem-token (`plugins/cstk/skills/agente-00c-runtime/scripts/mcp-launch.sh:128-130`) por `exec` incondicional no processo `node` real, repassando `MCP_SESSION_TOKEN`/`CSTK_MCP_PROJECT_PATH` quando existirem — elimina o stub em shell (clarify dec-010)
- [ ] 5.1.2 Confirmar que o launcher nao depende de motor de containers em nenhum ponto do caminho novo (L-2, FR-005)
- [ ] 5.1.3 Usar `exec` (nao fork em background) — o processo MUST morrer junto com a sessao do Claude Code que o hospeda (L-7, FR-012)
- [ ] 5.1.4 Teste: encerrar a sessao do harness com o servidor conectado e confirmar ausencia de processo orfao (Cenario 10 do quickstart)

### 5.2 Confirmar invariante de sequenciamento (dec-035) `[C]`

Ref: plan.md §Fases de Implementacao ("Invariante de sequenciamento"); research.md Decision 13

- [ ] 5.2.1 Revisar o diff acumulado das FASEs 1-4 e confirmar que nenhuma delas alterou comportamento observado pelo operador antes deste ponto — esta e a UNICA fase em que `/mcp` passa a listar as 7 tools **e** as chamadas passam a ser aceitas simultaneamente (nunca um estado intermediario com tools listadas e `SESSION_MISMATCH` universal)

### 5.3 Gate de aceite completo (Cenarios 0-6, 8-10) `[C]`

Ref: quickstart.md Cenarios 0-6, 8-10 (Cenario 7 fica para a FASE 6, apos sincronizar runtime+catalogo)

- [ ] 5.3.1 Rodar manualmente os Cenarios 1 a 6 e 8 a 10 do quickstart numa maquina de desenvolvimento local

---

## FASE 6 - Testes: reescrita de contrato + validacao end-to-end

### 6.1 Reescrever os 2 cenarios que afirmam sobrevivencia do processo a pausa `[C]`

Ref: plan.md §Mudanca de contrato (BREAKING); `tests/test_command-spawn-mcp-lifecycle.sh:121,125`

Os 2 cenarios de `tests/test_command-spawn-mcp-lifecycle.sh:121,125` que afirmam sobrevivencia a pausa passam a MENTIR apos a FASE 5 — sem reescreve-los, a mudanca de contrato fica sem teste que a proteja.

- [ ] 6.1.1 Reescrever `scenario_resume_agente_instrui_mcp_stop_terminal` (`tests/test_command-spawn-mcp-lifecycle.sh:121`) e o cenario irmao de `feature-00c` (`:125`) para o contrato novo: o PROCESSO do servidor e coextensivo com a sessao do harness (FR-012), mas a SESSAO MCP (descritor + token) continua sobrevivendo a pausas entre ondas — nao confundir os dois (data-model.md §State transitions)
- [ ] 6.1.2 Adicionar cobertura, no mesmo arquivo ou em `tests/test_mcp-launch.sh`/`tests/test_mcp-session.sh`, do fluxo de resolucao por chamada (cache hit + miss) no nivel de comando/orquestrador

### 6.2 Cobertura de multi-sessao (FR-011) `[C]`

Ref: quickstart.md Cenario 7 passo 5; data-model.md §Relacionamentos

- [ ] 6.2.1 Adicionar/estender teste cobrindo duas execucoes ativas simultaneas (`agente-00c` + `feature-00c`) com tokens distintos, confirmando que cada chamada muta exclusivamente o state-dir da sessao cujo token foi apresentado — nenhum cross-talk (mudanca de cardinalidade 1 processo : N sessoes)

### 6.3 Sincronizar runtime + catalogo ANTES de qualquer validacao end-to-end `[C]`

Ref: CLAUDE.md §"Installed vs Source Drift" (GOTCHA documentado); plan.md Risco R4

A feature toca as DUAS metades da instalacao: runtime (`cli/lib/mcp.sh`, remocao de `cli/lib/mcp-docker.sh` -> `cstk self-update`) e catalogo (`mcp-launch.sh`, `mcp-session.sh`, `mcp/state-server/`, os 2 commands -> `cstk install`). Rodar so uma reproduz o sintoma "fix funciona no repo mas nao na sessao".

- [ ] 6.3.1 Buildar o tarball local da linha de desenvolvimento (`./scripts/build-release.sh X.Y.Z-dev`) apos as FASEs 1-5 concluidas
- [ ] 6.3.2 Atualizar o RUNTIME via `cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"` — sem isso, `cstk mcp start` continua executando o binario/lib antigos mesmo com o repo corrigido
- [ ] 6.3.3 Atualizar o CATALOGO via `cstk install --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"` — sem isso, o launcher/commands instalados em `~/.claude` continuam sendo os antigos
- [ ] 6.3.4 `cstk doctor` MUST confirmar catalogo sem drift antes de prosseguir para a task 6.4

### 6.4 Validacao manual end-to-end completa (Cenario 7 do quickstart) `[C]`

Ref: quickstart.md Cenario 7 (FR-002, FR-011, FR-013)

**Depende de**: task 6.3 concluida (runtime + catalogo sincronizados) — sem isso a validacao mede a copia velha.

- [ ] 6.4.1 Executar o Cenario 7 completo: `/feature-00c` real, confirmar que o token e injetado sem depender de `mode == "docker"`, tool de mutacao real e aceita, e o estado gravado bate campo a campo com a fonte de verdade (`state-rw.sh read --state-dir <SD> | jq '.decisions[-1]'`)
- [ ] 6.4.2 Repetir o passo 5 do Cenario 7 com **duas** execucoes ativas simultaneas (`agente-00c` + `feature-00c`), cada uma chamando tools com o proprio token — o unico passo que exercita de fato a cardinalidade 1 processo : N sessoes; sem ele a regressao mais grave possivel (chamada mutando o state-dir errado) passaria despercebida

### 6.5 Gate final de aceite `[A]`

Ref: plan.md Risco R2 (CI nao roda os testes do servidor — este e o unico gate)

- [ ] 6.5.1 `npm test` (dentro de `mcp/state-server/`) + `LC_ALL=C ./tests/run.sh --check-coverage` + `LC_ALL=C ./tests/run.sh mcp` + `LC_ALL=C ./tests/run.sh` (suite POSIX completa) todos verdes

---

## FASE 7 - Documentacao: CHANGELOG BREAKING + `CLAUDE.md`

### 7.1 CHANGELOG com nota de BREAKING `[A]`

Ref: plan.md §Mudanca de contrato (BREAKING); Constitution Principio I (SDD recursivo — mudanca de contrato exige nota de BREAKING)

- [ ] 7.1.1 Adicionar entrada no `CHANGELOG.md` documentando a mudanca de contrato: FR-012 (processo coextensivo com a sessao do harness) revoga FR-010 da feature-base `state-mcp-server` (processo coextensivo com a execucao, sobrevivendo a pausas)
- [ ] 7.1.2 Conferir que a nova versao tem a entrada correspondente no bloco de link references no rodape do `CHANGELOG.md` (regra do repo — numero de versao sem link e sintoma de esquecimento; usar o comando `comm` documentado em `CLAUDE.md`)

### 7.2 Atualizar `CLAUDE.md` §"Servidor MCP de estado (`cstk mcp`)" `[A]`

Ref: CLAUDE.md §"Servidor MCP de estado (`cstk mcp`)"; plan.md §Postura de Seguranca

- [ ] 7.2.1 Atualizar a secao para refletir: sem container Docker no caminho critico, resolucao por chamada (nao mais no boot), cardinalidade 1 processo : N sessoes, e a regressao declarada de confinamento por filesystem (SEC-H2) — sem alegar paridade com o comportamento anterior
- [ ] 7.2.2 Registrar, se ainda nao coberta explicitamente para este fluxo, a nota GOTCHA de sincronizacao dupla (runtime + catalogo) usada na task 6.3

---

## Matriz de Dependencias

```mermaid
flowchart TD
    F1[FASE 1 - Servidor: resolucao por chamada]
    F2[FASE 2 - Build lazy + mitigacao R8]
    F3[FASE 3 - CLI: start sem Docker + remocao mcp-docker.sh]
    F4[FASE 4 - Commands: generalizar injecao do token]
    F5[FASE 5 - CUTOVER: launcher exec node]
    F6[FASE 6 - Testes + sync + E2E]
    F7[FASE 7 - Documentacao]

    F1 --> F5
    F2 --> F5
    F3 --> F5
    F4 --> F5
    F5 --> F6
    F6 --> F7
```

**Nenhuma fase antes de F5 muda o comportamento observado pelo operador**
(dec-035). F1-F4 sao paralelizaveis entre si (sem dependencia direta umas
das outras), mas TODAS MUST concluir antes de F5.

## Resumo Quantitativo

| Fase | Tarefas | Subtarefas | Criticidade |
|------|---------|------------|-------------|
| 1 - Servidor: resolucao por chamada | 4 | 14 | C |
| 2 - Build lazy + mitigacao R8 | 4 | 14 | C |
| 3 - CLI: start sem Docker + remocao mcp-docker.sh | 5 | 17 | C |
| 4 - Commands: generalizar injecao do token | 2 | 4 | C |
| 5 - CUTOVER: launcher exec node | 3 | 6 | C |
| 6 - Testes + sync + E2E | 5 | 9 | C |
| 7 - Documentacao | 2 | 4 | A |
| **Total** | **25** | **68** | - |

## Escopo Coberto

| Item | Descricao | Fase |
|------|-----------|------|
| FR-001 | Tools registradas no boot independentemente de token | 1 |
| FR-002 | Resolucao/validacao de sessao a cada chamada | 1 |
| FR-003 | Rejeicao fail-closed preservada (ausente/invalida/terminal) | 1 |
| FR-004 | Launcher sobe sem exigir token previo | 2, 5 |
| FR-005 | Transporte deixa de depender de motor de containers | 2, 3, 5 |
| FR-006 | `cstk mcp start` sem motor de containers | 3 |
| FR-007 | `cstk mcp status` sem inspecionar container (no-change funcional) | 3 |
| FR-008 | `cstk mcp stop` idempotente sem depender de container | 3 |
| FR-009 | Token nunca em identificador observavel (consequencia da remocao do container) | 3, 5 |
| FR-010 | `cstk mcp start` idempotente | 3 |
| FR-011 | Resolucao exclusiva pelo `session_id` da chamada | 1, 6 |
| FR-012 | Processo encerra junto com a sessao do harness | 5 |
| FR-013 | Injecao do token generalizada nos 2 commands | 4 |
| FR-014 | Descritor legado `mode=docker` detectado, avisado, sobrescrito | 3 |
| FR-015 | `gc` continua removendo containers `cstk-mcp-state-*` orfaos | 3 |
| CHK001 | Mitigacao de R8 (flag que ignora scripts de ciclo de vida) | 2 |
| CHK002 | Verificacao real de ausencia de build nativo nas deps | 2 |
| CHK003 | Recorte gc-vs-start validado linha a linha antes da remocao (R6) | 3 |
| CHK015 | Instalacao fixada por `package-lock.json` | 2 |

## Escopo Excluido

| Item | Descricao | Motivo |
|------|-----------|--------|
| CHK008 | Declarar a regressao SEC-H2 em `spec.md` com o mesmo peso que em `plan.md` | `{humano}` — decisao de apetite de risco/produto, nao decomponivel em tarefa tecnica (checklists/requirements.md) |
| R2 | Adicionar gate de CI para os 15 `*.test.ts` do servidor | Fora de escopo desta feature (acoplaria o release POSIX-puro a toolchain Node por um componente opcional); registrado como candidato a feature propria (plan.md Risco R2) |
| R5 | Corrigir `cli/lib/mcp.sh` para nao chamar `jq` diretamente (viola o proprio carve-out) | Divergencia pre-existente, nao introduzida por esta feature; correcao sem FR que a exija (plan.md Risco R5, dec-036) |
| U-1 | Cabear `appendAuditRecord` (trilha de auditoria do servidor) | Gap pre-existente da feature-base, ja desligado antes desta feature (contracts/server-session-resolution.md §6, research.md Decision 4) |
| T-3 | Estender o teto `maxToolCalls` para ser por-sessao (nao por-processo) | Nenhum FR o pede; DoS cross-sessao (R10) fica como degradacao documentada, nao falha (research Decision 1) |
| SEC-H2 (mitigacao equivalente) | Recriar o confinamento de filesystem que o `docker run` dava (montagens `/data/state`, scripts `:ro`) | Regressao DECLARADA sem alegacao de paridade (Constitution VI); nao ha mecanismo equivalente a implementar sem reintroduzir o container que a feature elimina |
| R9 (descritor deslocado) | Conferir na revalidacao que `state_dir` de dentro do descritor bate com o diretorio de leitura | Risco MEDIUM proposto em plan.md, sem FR ancorando um MUST — mesmo padrao que gerou CHK001/CHK002/CHK015 para R8, mas nao sinalizado pelo checklist desta onda; candidato a checklist/tarefa futura se priorizado |
| R10 (DoS cross-sessao) | Contador de `maxToolCalls` por sessao em vez de por processo | Ver T-3 acima — mesma exclusao, mesma justificativa (degradacao com fallback documentado, nao falha) |
