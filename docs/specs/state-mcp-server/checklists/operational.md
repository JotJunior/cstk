# Operational Checklist: state-mcp-server (ciclo de vida, fallback, premissas)

**Purpose**: validar a QUALIDADE dos requisitos operacionais — fronteira de
sessao e health check (FR-010/FR-011/FR-015), degradacao graciosa (FR-007/
FR-012/US4), carve-out da dep `docker` (Principio II), integridade da camada de
estado (FR-013/FR-014/FR-017) e as premissas nao verificadas (spikes S1..S5).
NAO valida implementacao (nao ha codigo).
**Created**: 2026-08-01
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [research.md](../research.md)
**Numeracao**: CHK058–CHK085 (continua de `security.md`)

## Fronteira de sessao e ciclo de vida (FR-010 / FR-011 / FR-015)

- [x] CHK058 - A fronteira de sessao do servidor esta definida sem ambiguidade (coextensiva com o que, exatamente)? [Clareza, Spec §FR-010 + §Clarifications] {auto} — coextensiva com a **execucao autonoma inteira** (inicio ate estado terminal), NAO com cada onda.
- [x] CHK059 - O comportamento durante pausa longa entre ondas esta especificado como requisito, e nao deixado ao operador? [Completude, Spec §FR-010 + quickstart Scenario 8] {auto} — o servidor permanece ativo; o command pai apenas verifica saude a cada `-resume`, sem parar/reiniciar.
- [x] CHK060 - A condicao de encerramento esta enumerada exaustivamente e sem passo manual? [Clareza, Spec §FR-010 + §US2 cenario 2] {auto} — encerrado somente em estado terminal (`concluida` ou `abortada`), sem exigir acao do operador.
- [x] CHK061 - O tempo limite do health check esta quantificado, e nao apenas exigido? [Assumption, Spec §FR-011 + contracts/mcp-session-lifecycle.md §Health check] {auto} — `Timeout | 30s`, com estouro ⇒ `unavailable:health-timeout`; o valor esta rotulado **[PROPOSAL — a calibrar no spike]**, entao segue como premissa a confirmar, nao como fato.
- [x] CHK062 - Os motivos de indisponibilidade sao um conjunto enumerado, permitindo diagnostico acionavel? [Clareza, contracts/mcp-session-lifecycle.md §cstk mcp status] {auto} — `image-build-failed`, `health-timeout`, `no-active-execution`.
- [x] CHK063 - FR-015/SC-005 sao mensuraveis (o operador determina o status em quantas consultas, sem inspecionar Docker)? [Mensurabilidade, Spec §FR-015 + §SC-005] {auto} — "numa unica consulta", via `cstk mcp status`.
- [x] CHK064 - Existe requisito para container remanescente quando o command pai termina SEM chamar `stop` (crash, `kill -9`, sessao encerrada)? [Gap, Spec §US2 vs contracts §Ciclo de vida] {auto} — resolvido na task 5.4: `cstk mcp gc [--dry-run]` (`cli/lib/mcp.sh::_mcp_cmd_gc`) detecta containers gerenciados cujo state-dir dono esta terminal/ausente e os remove, fail-safe para container sem label; documentado em `contracts/mcp-session-lifecycle.md` §Limpeza de containers orfaos.
- [x] CHK065 - A condicao de contorno "abort com chamada em voo" esta coberta nos requisitos? [Cobertura de edge cases, Spec §Edge Cases] {auto} — "ou ela completa, ou e revertida por inteiro"; sem corrupcao de mutacao em voo.
- [x] CHK066 - A colisao de identidade entre duas execucoes concorrentes esta tratada como requisito, sem coordenacao manual? [Cobertura de edge cases, Spec §Edge Cases + contracts §SEC-H3] {auto} — identidade e o token de capacidade por execucao (>=128 bits CSPRNG), nao uma porta/slot disputado.

## Degradacao graciosa (FR-007 / FR-012 / US4 / SC-004)

- [x] CHK067 - As condicoes que acionam o fallback estao enumeradas, e nao descritas como "quando o servidor falhar"? [Clareza, Spec §FR-007] {auto} — falha de inicializacao, ambiente sem Docker, execucao headless/cron.
- [x] CHK068 - A decisao de NAO ter modo Node-local intermediario esta registrada com justificativa rastreavel? [Rastreabilidade, Spec §FR-012 + §Clarifications] {auto} — bloqueia direto para o fallback Bash; um segundo caminho multiplicaria superficie de auditoria/health-check/isolamento sem ser exigido.
- [x] CHK069 - "Sem regressao funcional" (SC-004) esta ancorado em criterio comparavel, e nao em adjetivo? [Mensurabilidade, Spec §SC-004 + quickstart Scenario 7] {auto} — Scenario 7 exige "mesmas invariantes finais do Scenario 1".
- [x] CHK070 - A queda do servidor NO MEIO de uma onda tem requisito de estado resultante? [Cobertura, Spec §US4 cenario 2] {auto} — o estado nao pode ficar pior que uma onda interrompida no caminho Bash; a rede de reconciliacao (equivalente ao `reconcile-wave`) continua aplicavel na retomada.
- [x] CHK071 - Ha requisito definindo COMO o orquestrador detecta a indisponibilidade no meio da onda e comuta para o caminho Bash? [Gap, Spec §FR-007 vs §US4 cenario 2] {auto} — resolvido na task 5.5: gatilho (erro de transporte MCP) + tentativas (zero retries + 1 confirmacao via `status --live`) + ponto de comutacao (resto da onda, mutacao nunca reemitida via MCP) documentados em `contracts/mcp-session-lifecycle.md` §Deteccao de queda mid-onda; US4 cenario 2 ja coberto por `close_wave` (compensacao por pre-imagem) + `reconcile-wave` pre-existentes.

## Carve-out da dep `docker` e Principio II

- [x] CHK072 - As tres condicoes cumulativas do carve-out 1.1.0 estao enderecadas item a item, e nao invocadas em bloco? [Rastreabilidade, plan.md §Analise do Principio II] {auto} — (a) fallback graceful verificavel (FR-007/FR-012 + Scenario 7); (b) codigo confinado em `cli/lib/mcp-docker.sh`; (c) declarada na feature.
- [ ] CHK073 - A leitura da condicao (b) do carve-out ("um unico arquivo identificavel") esta resolvida para o caso em que `docker` passa a ser referenciada em DOIS arquivos (`serve-docker.sh` + `mcp-docker.sh`)? [Conflict, plan.md §Complexity Tracking + §Re-check de Constitution] {humano} — o plano oferece a leitura "um arquivo por **feature**" (precedente: `cstk serve`) e alerta que, se a leitura correta for "um arquivo por **dep** no repo inteiro", a conformidade exige **amendment MINOR antes da F5** — nao ha opt-out tacito de MUST. Decisao do operador em block-001 (dec-021): **avaliar na F5**; se necessario, o amendment vira task antes da F5.
- [x] CHK074 - O carve-out 1.3.0 (`jq`/`sqlite3` dentro do container) esta declarado com as quatro condicoes, e sem estender o escopo ja vigente? [Rastreabilidade, plan.md §Analise do Principio II] {auto} — mesmas deps que os helpers ja exigem hoje, apenas rodando dentro do container.
- [x] CHK075 - A ausencia de meta de performance esta justificada, e nao omitida? [Assumption, plan.md §Technical Context] {auto} — N/A porque o gargalo da onda e a inferencia do LLM, nao o `fork+exec` do helper (dezenas de ms).

## Integridade da camada de estado (FR-013 / FR-014 / FR-017)

- [x] CHK076 - FR-014 (nao enfraquecer garantias) tem mecanismo estrutural, e nao apenas a promessa de nao enfraquecer? [Clareza, plan.md §Summary(1)] {auto} — nenhuma regra de estado e reimplementada em JS; cada tool delega ao helper POSIX correspondente, evitando duas fontes de verdade.
- [x] CHK077 - O re-check de constitution confirma ausencia de estruturas novas que ampliariam a superficie? [Consistencia, plan.md §Re-check de Constitution] {auto} — zero tabela nova, zero regra duplicada, zero lock novo, zero porta de rede.
- [x] CHK078 - Ha exigencia de paridade entre os dois backends de estado (`state.db` e `state.json`)? [Cobertura, plan.md §Convencoes de Borda + quickstart Scenario 9] {auto} — Scenario 9 compara campo a campo nos **dois** backends.
- [x] CHK079 - A decisao de o servidor NAO adquirir lock esta justificada com evidencia, e nao por conveniencia? [Rastreabilidade, research.md D4 + plan §Summary(4)] {auto} — o command pai ja detem o mutex nao-reentrante durante toda a onda; um `acquire` do servidor daria `exit 3` sempre.

## Dependencias e premissas — spikes F0 (todos [NAO-VERIFICADO])

- [x] CHK080 - O spike S1 (subagente consegue chamar tool MCP?) tem criterio de escalada definido e posicao de gate declarada? [Assumption, research.md §S1 + plan §Fases F0 + §Riscos(1)] {auto} — falha ⇒ **BLOQUEIO HUMANO**, a feature nao prossegue; e o **primeiro** item de trabalho, antes de qualquer codigo. A premissa em si permanece [NAO-VERIFICADO] — vira task de spike no `create-tasks` (quickstart Scenario 0.1).
- [x] CHK081 - O spike S2 (nome exato da tool na allowlist do subagente) tem criterio de escalada definido? [Assumption, research.md §S2 + quickstart Scenario 0.2] {auto} — sem o nome, o subagente nao consegue restringir/usar a tool ⇒ **escala junto de S1**. Padrao presumido `mcp__<server>__<tool>` segue [NAO-VERIFICADO].
- [x] CHK082 - O spike S3 (`.mcp.json` novo passa a valer na sessao corrente?) esta declarado como nao-bloqueante, com a mitigacao ja embutida no desenho? [Assumption, research.md §S3 + plan §Riscos(2)] {auto} — desenho ja imune por entrada **estatica** + resolucao lazy (D2); o spike apenas confirma.
- [x] CHK083 - O spike S5 (helpers POSIX sob busybox/alpine) tem escape hatch declarado com custo conhecido? [Assumption, research.md §S5 + plan §Riscos(3) + quickstart Scenario 0.3] {auto} — trocar a base para `node:22-slim` (Debian): custo de tamanho de imagem, nao de desenho.
- [ ] CHK084 - Iniciar a F1 (fundacao POSIX, sem dependencia do SDK) em paralelo a F0, ou serializar todo o trabalho apos o resultado de S1? {humano} — o plano trata F0 como gate bloqueante da feature inteira; a decisao de paralelizar a parte independente e de apetite de risco.
- [ ] CHK085 - Se S1 falhar, a feature e abandonada ou reduzida (ex.: so CLI/POSIX, sem consumidor subagente)? {humano} — o plano define o gatilho (bloqueio humano) mas nao a alternativa a ser oferecida ao operador nesse momento.

## Notes

- Items `{auto}` foram resolvidos contra os artefatos com citacao; `[x]` sem citacao nao vale.
- Os spikes (CHK080–CHK083) estao `[x]` porque a QUALIDADE do requisito (criterio de aprovacao/escalada declarado) esta satisfeita — o **fato** subjacente segue [NAO-VERIFICADO] e por isso cada um carrega `[Assumption]` e vira task na fase F0 do `create-tasks`.
- Destino dos abertos: `[Gap]` (CHK064, CHK071) → `create-tasks`; `[Conflict]` (CHK073) → decisao do operador / amendment MINOR antes da F5; `{humano}` (CHK084, CHK085) → antes de `execute-task`.
