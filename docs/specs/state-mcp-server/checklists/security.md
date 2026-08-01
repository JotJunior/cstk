# Security Checklist: state-mcp-server (capacidade, confinamento, auditoria)

**Purpose**: validar a QUALIDADE dos requisitos de seguranca — token de
capacidade (SEC-H3), confinamento de blast radius (FR-008/FR-016), trilha de
auditoria (FR-005/FR-006), fronteira Node → POSIX (SEC-H1) e perimetro do
container (SEC-H2). NAO valida implementacao (nao ha codigo).
**Created**: 2026-08-01
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [contracts/mcp-session-lifecycle.md](../contracts/mcp-session-lifecycle.md)
**Numeracao**: CHK028–CHK057 (continua de `api.md`)

## Token de capacidade e roteamento (SEC-H3 / bloqueio humano block-001)

- [x] CHK028 - O requisito quantifica a entropia minima e a fonte do token de capacidade, em vez de dizer "token aleatorio"? [Clareza, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — ">= 128 bits de fonte CSPRNG (`/dev/urandom`)", gerado por `cstk mcp start`, por execucao.
- [x] CHK029 - A guarda em disco do token esta especificada com permissao concreta? [Clareza, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — `<state-dir>/mcp-server.json` com `chmod 600`; state-dir ja `chmod 600` no backend sqlite [VERIFICADO: `_state_db_secure_perms`].
- [x] CHK030 - O caminho de entrega do token ao consumidor esta declarado sem ambiguidade? [Clareza, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — o command pai injeta o token no prompt de spawn do orquestrador, pelo mesmo caminho de `state_dir`/`short_name`/modelo da onda (aprovado pelo operador em block-001, dec-021).
- [ ] CHK031 - A alteracao de contrato dos commands pai (`/agente-00c`, `/feature-00c` e resumes) — gerar e injetar o token — aparece como item de trabalho explicito em alguma fase do plano? [Gap, plan.md §Bloqueio humano(1) vs §Fases de implementacao] {auto} — a consequencia esta **declarada** (e aprovada em block-001), mas a tabela de fases so cita "commands pais chamam status/start/stop" na F6; geracao/injecao do token e o toque em arquivos fora desta feature nao constam de nenhuma fase. Deve virar dependencia/task explicita no `create-tasks`.
- [x] CHK032 - O comportamento de rejeicao e fail-closed, sem fallback heuristico para "a execucao mais provavel"? [Clareza, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — token ausente, desconhecido ou de execucao terminal ⇒ `SESSION_MISMATCH`, sem fallback.
- [x] CHK033 - A separacao de papeis entre precedencia (guarda/ambiente) e capacidade (mutacao) esta declarada, evitando duplicacao de logica com o hook? [Consistencia, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — precedencia so vale em `cstk mcp status` sem `--state-dir` (consulta read-only).
- [x] CHK034 - Ha requisito de rotacao/invalidacao do token? [Completude, contracts/mcp-session-lifecycle.md §SEC-H3] {auto} — novo token a cada `cstk mcp start`; `stop` o invalida.
- [ ] CHK035 - Existe requisito sobre validade temporal (TTL) do token numa execucao de longa duracao? [Gap, Spec §FR-010 vs contracts §SEC-H3] {auto} — FR-010 mantem a sessao ativa por dias entre ondas (`Schedule intent`), mas a rotacao esta atrelada apenas a `start`/`stop`; nenhum requisito define expiracao por tempo nem re-emissao periodica.
- [ ] CHK036 - O texto de FR-016 na spec e consistente com o desenho aprovado? [Conflict, Spec §FR-016 vs plan.md §Bloqueio humano(2) + research.md D2] {auto} — FR-016 continua exigindo literalmente "sua propria instancia/**porta** de servidor MCP isolada", enquanto o desenho adotado e `stdio` **sem porta** (isolamento por container + capacidade), releitura aprovada em block-001/dec-021 e marcada [PROPOSAL] em research D2. A spec nao foi atualizada — o texto normativo e a implementacao aprovada divergem.
- [x] CHK037 - O confinamento exigido por FR-008 tem criterio verificavel por cenario, e nao so afirmacao? [Mensurabilidade, Spec §FR-008 + quickstart Scenario 6] {auto} — Scenario 6 exerce duas execucoes concorrentes e exige que nenhuma alcance o state-dir da outra.

## Perimetro do container (SEC-H2 / FR-008 / FR-013)

- [x] CHK038 - A lista de montagens e declarada como sendo O perimetro de blast radius, e nao um detalhe de deploy? [Clareza, contracts/mcp-session-lifecycle.md §Montagens] {auto} — "a lista **e** o perimetro de blast radius — FR-008"; nenhuma outra montagem permitida.
- [x] CHK039 - O requisito distingue montagem de ARQUIVO e de DIRETORIO onde a distincao e o controle de seguranca? [Clareza, contracts/mcp-session-lifecycle.md §SEC-H2] {auto} — bind-mount do arquivo `enforcement-log.jsonl`, nunca do diretorio `.claude` (que contem `hooks/pretooluse-bash-guard.sh` e `settings.json`).
- [x] CHK040 - Ha requisito de assercao ESTATICA das montagens proibidas, e nao apenas a proibicao em prosa? [Mensurabilidade, contracts/mcp-session-lifecycle.md §SEC-H2] {auto} — teste obrigatorio em `tests/cstk/test_mcp-docker.sh`: nenhuma linha de `docker run` pode montar `.claude` como diretorio, `$HOME`, `/`, `/var/run/docker.sock` ou o diretorio do `knowledge.db`.
- [x] CHK041 - A condicao de contorno do bind-mount de arquivo inexistente esta coberta? [Cobertura de edge cases, contracts/mcp-session-lifecycle.md §SEC-H2] {auto} — o arquivo MUST existir (criar vazio com `chmod 600` antes do `docker run`), senao o Docker cria um diretorio no host.
- [x] CHK042 - FR-013 (knowledge.db intocado) esta expresso como ausencia verificavel, e nao so como intencao? [Mensurabilidade, Spec §FR-013 + contracts §Montagens] {auto} — linha explicita "**NAO MONTADO** (FR-013)" na tabela de montagens.

## Fronteira Node → POSIX (SEC-H1 / SEC-M2)

- [x] CHK043 - O requisito trata o texto livre vindo do LLM como entrada hostil em potencial, e nao como texto de humano? [Clareza, contracts/mcp-tools.md §Controles de seguranca da fronteira] {auto} — declarado como injecao indireta (LLM01/ASI01) para `context`, `rationale`, `evidence`, `question`, `title`, `touched_files`.
- [x] CHK044 - As construcoes proibidas estao enumeradas nominalmente, permitindo assercao estatica? [Mensurabilidade, contracts/mcp-tools.md §SEC-H1] {auto} — proibidos `exec()`, `execSync()`, `spawn(..., {shell:true})`, template string montando linha de comando e qualquer `eval`; obrigatorio `execFile`/`spawn` com array de argv e `shell:false`.
- [x] CHK045 - Ha regra que impeca um identificador de ser interpretado como flag na fronteira? [Cobertura de edge cases, contracts/mcp-tools.md §SEC-M2] {auto} — allowlist por regex; nenhum id inicia com `-`.

## Trilha de auditoria (FR-005 / FR-006 / SEC-M3)

- [x] CHK046 - Os campos minimos da entrada de auditoria estao enumerados? [Completude, Spec §FR-005] {auto} — timestamp, ferramenta chamada, sessao/execucao de origem, resultado (aceita/rejeitada + motivo quando rejeitada).
- [x] CHK047 - A cobertura exigida inclui chamadas REJEITADAS, e nao so as aceitas? [Cobertura, Spec §FR-005 + §SC-003] {auto} — "aceita ou rejeitada"; SC-003 exige 100% verificavel sem acesso ao transcript.
- [x] CHK048 - A ordem entre filtragem de segredos e truncamento esta definida como requisito, e nao deixada a implementacao? [Clareza, plan.md §Summary(5) + contracts/mcp-tools.md §SEC-M3] {auto} — ordem obrigatoria `scrub → truncate → serialize`, truncando por code point.
- [x] CHK049 - Ha requisito impedindo forja de entrada de log por texto livre (log injection)? [Cobertura, contracts/mcp-tools.md §SEC-M3] {auto} — serializador JSON real, nunca `printf`/concatenacao (A09).
- [x] CHK050 - A durabilidade da trilha alem do fim do servidor esta exigida explicitamente? [Completude, Spec §Key Entities "Tool Invocation Audit Record" + §US3 cenario 1] {auto} — "sobrevivendo ao encerramento do servidor".
- [x] CHK051 - O limite conhecido de auto-atestacao do log esta declarado, e nao omitido? [Assumption, plan.md §Auto-atestacao do log] {auto} — a linha e escrita pelo mesmo processo que executa a mutacao; declarado como aceitavel no modelo de ameaca e mitigado por SEC-H1/H2.

## Riscos aceitos e N/A justificados

- [x] CHK052 - O N/A de OAuth 2.1/PKCE/RFC 8707/DPoP esta justificado E tem condicao de caducidade declarada? [Assumption, contracts/mcp-session-lifecycle.md §Nota de autenticacao + plan §SEC-I1] {auto} — N/A por `stdio`, zero listener de rede, zero credencial ambiente; **caduca** se o plano B (Streamable HTTP) for acionado.
- [x] CHK053 - O risco de mutar estado fora do alcance do `bash-guard` e sem lock proprio esta declarado com controles compensatorios nomeados? [Assumption, plan.md §SEC-M5 + research D4] {auto} — contrato da tool + `enforcement-log.jsonl`; a onda inteira roda dentro do lock do command pai.
- [x] CHK054 - Os controles de supply chain da primeira arvore Node do repo estao especificados como requisito? [Completude, plan.md §SEC-M4] {auto} — `npm ci --ignore-scripts` (nunca `npm install`), lockfile obrigatorio, base pinada por digest, arvore minima, `npm audit` no CI (F5/F6).
- [x] CHK055 - FR-017 (exclusao mutua entre caminho MCP e caminho Bash) tem mecanismo declarado, e nao so a exigencia? [Clareza, Spec §FR-017 + research D4 + plan §Riscos(4)] {auto} — ambos os caminhos dentro do mesmo lock nao-reentrante do pai; `busy_timeout`/retry/WAL no banco.
- [ ] CHK056 - Aceitar SEC-M5 (mutacao fora do `bash-guard`) e SEC-L1 (sem teto de chamadas por sessao) no MVP e compativel com o apetite de risco do produto? {humano}
- [ ] CHK057 - A auto-atestacao do log (o servidor escreve o proprio rastro) e aceitavel, ou a auditoria exige uma testemunha externa ao processo antes do primeiro uso real? {humano}

## Notes

- Items `{auto}` foram resolvidos contra os artefatos com citacao; `[x]` sem citacao nao vale.
- **CHK031** e **CHK036** materializam os dois pontos aprovados no bloqueio humano block-001 (dec-021): a aprovacao do operador nao dispensa (a) a task explicita para o toque nos commands pai, nem (b) a atualizacao do texto de FR-016 na spec.
- Destino dos abertos: `[Gap]` → `create-tasks`; `[Conflict]` → `clarify`/amendment na spec antes de `execute-task`.
