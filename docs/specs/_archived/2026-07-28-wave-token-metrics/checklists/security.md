# Security Checklist: wave-token-metrics

**Purpose**: validar qualidade dos requisitos de seguranca (nao a
implementacao — inexistente ainda) do hook `PostToolUse`/matcher `Agent` que
captura telemetria de uso por spawn de subagente, e da cadeia
sidecar->state.json->knowledge.db que a persiste/expoe. Adaptado ao
dominio real da feature (CLI local, sem rede/auth/PII) — os items de
authN/RBAC/TLS/LGPD do catalogo generico de `security.md` nao se aplicam
aqui e sao marcados N/A com justificativa, nao copiados as cegas.
**Created**: 2026-07-25
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) ·
[contracts/hook-posttooluse-agent-usage.md](../contracts/hook-posttooluse-agent-usage.md)

## Vazamento de Dados / Protecao de Segredos

- [x] CHK001 - O requisito de nao-vazamento de texto livre (prompt/resposta do subagente) no sidecar esta explicito e nao apenas implicito? [Protecao de Dados, Contract §2 "Restricoes duras da linha"] {auto}
  - Satisfeito: `contracts/hook-posttooluse-agent-usage.md` §2, item 1 — "MUST NOT conter `content`, `prompt` ou `description` — texto livre e proibido (tamanho + vazamento de segredo)"; §1.3 tabela marca `prompt`/`description` explicitamente "NAO" consumidos.
- [x] CHK002 - Ha teste de cenario dedicado que garante essa restricao anti-vazamento na pratica (nao so na intencao do requisito)? [Cobertura, Contract §6 cenario 11] {auto}
  - Satisfeito: Contract §6, cenario #11 — "anti-vazamento: `content`/`prompt` presentes na entrada nunca aparecem na linha".
- [x] CHK003 - O requisito de nao-fabricacao de dado (FR-009/FR-012) tambem previne o risco inverso — um `null` real sendo mascarado como `0` (o que poderia esconder uma falha de captura)? [Clareza, Spec §FR-009, Plan §Constitution Check Principio VI] {auto}
  - Satisfeito: Plan detalha isso como o risco #2 do Principio VI — "um `0` no lugar de um `null` transforma 'nao medi' em 'medi e deu zero'" — tratado como invariante replicada em todas as camadas (sidecar -> state.json -> SQLite -> relatorio).
- [x] CHK004 - O canal de persistencia (knowledge.db) usa o mesmo helper de nulos ja auditado em vez de logica nova sujeita a regressao? [Consistencia, Plan §Principio VI] {auto}
  - Satisfeito: Plan cita reuso do helper existente `recall_int_or_null` para propagar `NULL` no SQLite, em vez de introduzir tratamento de nulo paralelo.

## Least Privilege / Superficie de Acesso (ASI02 — Tool Misuse)

- [x] CHK005 - O hook consome apenas os campos estritamente necessarios do payload do harness (nao um dump irrestrito de `tool_response`)? [ASI02 Tool Misuse — "validar todos os inputs/outputs de tool", Contract §1.4] {auto}
  - Satisfeito: Contract §1.3/§1.4 listam campo-a-campo o que e consumido (`SIM`) vs explicitamente descartado (`NAO`) — `prompt`, `description`, `content` marcados NAO; apenas 11 campos numericos/identificadores curtos sao lidos.
- [x] CHK006 - O acesso do hook ao sistema de arquivos e de escrita confinada (append-only, um unico arquivo por state-dir), sem escrita arbitraria fora do escopo da execucao? [ASI02 Least Privilege, Research §Decision 5] {auto}
  - Satisfeito: Decision 5 — hook escreve "UMA linha JSON por spawn em `<state-dir>/wave-agent-usage.jsonl`, append-only" e "nunca toca `state.json`"; nenhum outro caminho de escrita e requisitado.
- [x] CHK007 - Todo campo lido do payload do harness tem tratamento de ausencia/malformacao explicito (validacao de input), em vez de assumir presenca? [ASI02 "Validate all tool inputs and outputs", Contract §3] {auto}
  - Satisfeito: Contract §3 tabela "Politica de falha" cobre `jq` ausente, stdin vazio/invalido, `cwd` vazio, `tool_name != Agent`, `tool_response` malformado — cada condicao com comportamento definido (`exit 0` ou `status=indisponivel`), nunca um crash ou leitura nao validada.
- [x] CHK008 - A deteccao de "execucao ativa" (decidir para qual state-dir a metrica vai) reusa um algoritmo ja auditado, em vez de introduzir logica nova de resolucao de escopo? [ASI02 Escopo/Privilegio, Contract §4] {auto}
  - Satisfeito: Contract §4 exige algoritmo "**identico** ao de `posttooluse-tool-call-tick.sh:68-100`" com regra dura "MUST NOT divergir desse algoritmo" — reuso deliberado em vez de reimplementacao paralela, reduzindo superficie nova de erro/escopo incorreto.

## Disponibilidade / Fail-Open como Vetor (nao-funcional de seguranca)

- [x] CHK009 - O requisito de fail-open esta especificado por condicao, nao como principio generico vago? [Clareza, Contract §3] {auto}
  - Satisfeito: Contract §3 enumera 7 condicoes de falha distintas com o comportamento exato para cada uma (nao um "deve falhar graciosamente" generico).
- [x] CHK010 - Existe restricao dura contra o hook usar `set -e` ou escrever em stdout (vetores que fariam o harness expor stderr/ruido ao operador ou interromper o fluxo)? [Clareza, Contract §3] {auto}
  - Satisfeito: Contract §3 — "MUST NOT usar `set -e`... MUST NOT escrever em stdout... MUST NOT bloquear, atrasar ou reprovar a tool call".
- [x] CHK011 - O crescimento do sidecar (potencial vetor de esgotamento de disco sob spawns repetidos) tem limite de ciclo de vida definido? [Cobertura, Research §Decision 5 "Ciclo de vida"] {auto}
  - Satisfeito: Decision 5 — "reset em `start` e em `end`... Janela de contagem = start->end" — o sidecar nao acumula indefinidamente entre ondas, limitando o vetor a uma unica onda.
- [x] CHK012 - O tamanho maximo de linha do sidecar (relevante para atomicidade E para limitar o que pode ser escrito) esta quantificado, nao apenas qualificado como "curto"? [Clareza, Contract §2 item 2] {auto}
  - Satisfeito: Contract §2 — "MUST caber em uma linha curta (< PIPE_BUF)"; Research §Decision 5 reforca que a restricao de tamanho e "load-bearing" tanto para atomicidade do append quanto para banir campos de texto livre.

## Auditoria / Rastreabilidade de Uso

- [x] CHK013 - Cada metrica de spawn capturada carrega proveniencia suficiente para auditoria (execucao, onda, feature/projeto, modelo)? [ASI02 "Log all tool invocations for audit", Spec §FR-003] {auto}
  - Satisfeito: FR-003 MUST — associa a metrica "a onda, ao identificador de execucao, a feature/projeto e ao modelo que foi roteado para aquele spawn", com o campo de modelo sempre presente (nunca omitido).
- [x] CHK014 - A auditoria de custo x modelo roteado (FR-007/US2) tem requisito de qualidade equivalente ao dos demais tipos de registro auditavel do toolkit (Decisoes, bloqueios)? [Consistencia, Spec §FR-007] {auto}
  - Satisfeito: FR-007 explicitamente reusa "auditoria de custo x roteamento ja existente no toolkit" em vez de propor um mecanismo de auditoria paralelo — consistente com o padrao ja estabelecido para `model-routing-report.sh`.

## Zero Coleta Remota (Principio IV — escopo de confianca)

- [x] CHK015 - A spec/plan garantem explicitamente que nenhum dado de uso (potencialmente sensivel a nivel de padrao de consumo) sai do disco local? [ASI04-adjacente / Principio IV, Plan §Constitution Check] {auto}
  - Satisfeito: Plan §Constitution Check, linha IV — "todo dado permanece local... Nenhum egress, nenhum endpoint, nenhum identificador enviado a lugar algum. O hook nao faz rede." — marcado "Ponto de maior atencao desta feature", nao tratado como obvio.
- [x] CHK016 - Os 3 destinos de persistencia (sidecar, state.json, knowledge.db) sao todos explicitamente locais, sem introduzir um servico/API novo? [Completude, Plan §Storage] {auto}
  - Satisfeito: Plan §Technical Context "Storage" — `state.json` por execucao + sidecar JSONL por onda + `~/.claude/cstk/knowledge.db` (SQLite local) — os 3 sao arquivo-em-disco, nenhum servidor.

## Achados do Gate owasp-security (dec-035)

- [ ] CHK020 - Ha um teto explicito de numero de linhas/spawns por onda no sidecar, para o caso de um loop anomalo gerar muitos spawns ANTES do proximo `end` resetar o arquivo? [Cobertura, Research §Decision 5 "Ciclo de vida"] {auto} [Gap]
  - Nao satisfeito: o desenho limita o vetor pelo ciclo de vida (reset em `start`/`end`, janela = 1 onda) e pelo `Scale/Scope` do plan ("poucos spawns por onda, ordem de unidades"), mas nenhum artefato define um teto explicito de linhas dentro de uma unica onda antes do reset — diferente de `budget.sh`, que ja vigia `state_size_threshold_bytes` para o `state.json`, o sidecar `wave-agent-usage.jsonl` em si nao e observado por nenhum threshold dedicado. Risco residual classificado INFO/LOW pelo gate `owasp-security` (dec-035): nao bloqueia, mas fica registrado para `/create-tasks` avaliar um contador leve (ex.: `wc -l` best-effort em `state-ondas.sh end` antes do reset, so para log/aviso, sem bloquear).

## Gaps / Itens Nao Cobertos

- [ ] CHK017 - Ha requisito explicito de permissoes de arquivo (umask/chmod) para o sidecar `wave-agent-usage.jsonl` e para `~/.claude/cstk/knowledge.db`, dado que ambos passam a conter contagens de tokens/duracao por feature (sinal de padrao de uso, ainda que nao PII)? [Protecao de Dados] {auto} [Gap]
  - Nao satisfeito: nenhum artefato (spec/plan/research/contracts) especifica permissoes de arquivo para o sidecar ou para o knowledge.db. **Contexto atenuante, nao dispensa o Gap**: o hook irmao pre-existente (`posttooluse-tool-call-tick.sh`) e o `~/.claude/cstk/knowledge.db` ja em producao tambem nao tem requisito de permissao documentado — ou seja, este e um gap **herdado do padrao ja estabelecido no toolkit**, nao introduzido de novo por esta feature. Ainda assim, como esta feature adiciona dado novo (consumo por feature/projeto) ao mesmo arquivo compartilhado, vale registrar o gap para consumo por `/create-tasks` em vez de ignora-lo.
- [ ] CHK018 - A superficie de ameaca ASI05 (Unexpected Code Execution) se aplica a este hook — ha algum caminho em que dado do `tool_response` e interpretado/executado (nao apenas lido como valor)? [ASI05, Contract §1] {auto}
  - Satisfeito (N/A justificado, nao Gap): revisado campo-a-campo no Contract §1.4 — todos os 11 campos consumidos sao valores escalares (string/number) lidos via `jq` e gravados verbatim; nenhum e usado como comando, template ou caminho de `eval`. ASI05 nao se aplica a este componente por desenho (metrica pura, sem execucao de conteudo dinamico).
- [ ] CHK019 - Os requisitos generico-catalogo de authN/RBAC/TLS/LGPD-PCI-HIPAA se aplicam a esta feature? [Compliance] {auto}
  - Nao aplicavel, justificado: feature e um mecanismo local de telemetria de uso dentro de um CLI de execucao autonoma single-user, sem superficie de rede, sem conta de usuario, sem dado de terceiro/PII — os mesmos motivos ja documentados no Constitution Check Principio IV. Item generico do catalogo `references/security.md` descartado deliberadamente (nao copiado as cegas), conforme instrucao da propria skill checklist §3.3.

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- **{auto} resolvidos**: 18 (15 satisfeitos + 2 N/A justificados: CHK018/CHK019 — nao sao Gap, sao aplicabilidade descartada com evidencia; CHK020 conta como item auto-resolvido que revelou Gap)
- **{humano} aguardando decisao**: 0
- **Gaps abertos**: 2 (CHK017 — permissoes de arquivo do sidecar/knowledge.db, herdado do padrao pre-existente do toolkit, nao introduzido por esta feature; CHK020 — sem teto explicito de linhas/spawns por onda no sidecar antes do reset, achado do gate `owasp-security`)
- Gate `owasp-security` (dec-035): 0 findings `critical`/`high` (nenhum bloqueio humano obrigatorio); 3 findings INFO/LOW registrados (CHK017, CHK020, e nota defensiva sobre renderizacao futura em painel — esta ultima sem acao, ja mitigada porque knowledge.db v10 so recebe colunas INTEGER agregadas, nenhum campo string novo).
