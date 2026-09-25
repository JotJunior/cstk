# Security Checklist: cstk-jira

**Purpose**: validar a qualidade dos requisitos de seguranca (SEC-1..SEC-5
do gate `owasp-security`, FR-012, FR-015, FR-016) antes de `create-tasks`.
**Created**: 2026-09-24
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) (secao "Requisitos de seguranca derivados do gate owasp-security") | [contracts/hooks.md](../contracts/hooks.md) | [contracts/rovo-mcp.md](../contracts/rovo-mcp.md)

## Input Validation (SEC-1, SEC-3)

- [x] CHK001 - E' o charset allowlist de segmentos de path (`[A-Za-z0-9_-]`) e a lista de bytes proibidos (`..`, `//`, `\`, `@`, `#`, espaco, CR/LF, controle) suficientemente especifica para virar teste automatizado, sem ambiguidade de interpretacao? [Mensurabilidade, Plan.md SEC-1] {auto}
- [x] CHK002 - Esta explicito QUAIS variaveis (`jira_id`/`jira_key` do `jira-map.tsv` versionado, `project_key`) passam pela validacao SEC-1 antes de qualquer interpolacao em PATH ou JQL, cobrindo TODOS os pontos de interpolacao (R1-R11 + busca JQL de SEC-3)? [Completude, Plan.md SEC-1/SEC-3] {auto}
- [x] CHK003 - E' explicito que nenhum texto livre (titulo/descricao) entra em JQL montada pelo plugin — so valores que ja passaram pela allowlist de SEC-1? [Clareza, Plan.md SEC-3] {auto}

## Dados Nao-Confiaveis / Prompt Injection (SEC-2)

- [x] CHK004 - E' explicito que texto livre do Jira (titulo, descricao, nomes de status, comentarios, respostas de tools Rovo) NUNCA pode disparar uma decisao de sync (transicao/sobrescrita/resolucao de conflito) — e que toda decisao de sync vem so de ids/keys/status mapeados ou de escolha humana? [Consistencia/Seguranca, Plan.md SEC-2 + data-model.md ConflictRecord] {auto}
- [ ] CHK005 - As skills interativas tem um requisito explicito de ROTULAR conteudo lido do Jira como externo/nao-confiavel antes de apresenta-lo ao operador (mesma disciplina do read-back loop do proprio toolkit — "UNTRUSTED"), em vez de so mencionar isso como principio geral no plan? [Gap, Plan.md SEC-2 nao especifica o MECANISMO de rotulagem nas 3 skills] {auto} — **[Gap]**: SEC-2 declara a regra ("apresenta-lo rotulado como conteudo externo nao-confiavel") mas nenhuma skill (`jira-setup`/`jira-convert`/`jira-sync`) ainda existe para implementar o rotulo concretamente — as skills so serao escritas em `create-tasks`/`execute-task`. Destino: `/create-tasks` MUST gerar tarefa explicita "rotular texto do Jira como UNTRUSTED nas 3 skills interativas, citando SEC-2" (nao ha o que editar em spec/plan agora — o requisito ja existe, falta so a tarefa de implementacao).

## Credencial e Transporte (SEC-4, SEC-5)

- [x] CHK006 - E' verificavel objetivamente que o arquivo de credencial temporario e criado com `umask 077`, em diretorio privado, e removido por `trap` em EXIT/INT/TERM — com teste dedicado citado na Test Strategy? [Mensurabilidade, Plan.md SEC-4 + Test Strategy "Hooks"/"Mutation"] {auto}
- [x] CHK007 - Esta definido o comportamento de limpeza do arquivo de credencial temporario para TODOS os casos (sucesso, sinal recebido, crash do processo), nao so o caso feliz (EXIT normal)? [Cobertura de Edge Case, Plan.md SEC-4 "trap em EXIT/INT/TERM"] {auto}
- [x] CHK008 - E' explicito que o cliente HTTP nunca segue redirect e sempre verifica TLS, com comportamento EXATO para resposta 3xx (erro sem nova requisicao, nao retry silencioso)? [Clareza, Plan.md SEC-5] {auto}
- [x] CHK009 - Existe algum requisito ou flag de configuracao que permita desligar a verificacao TLS (mesmo para debug/teste)? Se existisse, contradiria SEC-5. [Conflito potencial, Plan.md SEC-5 "proibido desligar verificacao de certificado"] {auto} — Nao existe tal flag em nenhum artefato (`data-model.md` ProjectConfig nao lista opcao de TLS); requisito protegido de regressao futura por redacao MUST explicita.

## Deny-list de Exclusao e Defesa em Profundidade (FR-012)

- [x] CHK010 - E' o deny-list de exclusao (`deleteJiraIssue`/`executeDestructive`) enforced em DOIS lugares independentes (hook `PreToolUse` regex + ausencia de metodo `DELETE` em `jira-io.sh`), reduzindo o risco de bypass por um unico ponto de falha? [Completude/Defesa em profundidade, Plan.md ponto 2 da tabela onda-003 + Contracts rovo-mcp.md deny-list] {auto}
- [ ] CHK011 - A guarda `PreToolUse` de delecao fica INATIVA quando o plugin nao esta configurado (no-op, FR-017/SC-006) — esse trade-off (permitir `deleteJiraIssue` sobre issues NAO relacionadas ao plugin quando desconfigurado) esta documentado como decisao aceita em `contracts/hooks.md`, mas NAO esta refletido na spec (FR-012 nao menciona a condicao "so quando configurado")? [Ambiguity, spec.md FR-012 vs contracts/hooks.md ultima secao] {humano} — FR-012 le como proibicao absoluta ("MUST NOT apagar automaticamente"); o escopo real (guarda so ativa com config presente) e coerente com FR-017/SC-006 mas e uma nuance de ESCOPO que um mantenedor lendo so a spec nao veria. Decisao de produto (aceitar a nuance documentada so no contrato, ou elevar a spec) cabe ao dono do produto — nao e uma correcao textual mecanica como CHK006/CHK009 do dominio api.
- [x] CHK012 - E' o requisito de host unico (FR-015) verificavel objetivamente — existe definicao precisa de "mesmo dominio" (igualdade exata de string, nao subdominios/wildcards) evitando ambiguidade de implementacao? [Mensurabilidade, Plan.md ponto 3 da tabela onda-003: "host unico por igualdade exata"] {auto}

## Nao-Exfiltracao e Fail-Open dos Hooks

- [x] CHK013 - Esta coberto o cenario "hook recebe `tool_input` com `session_id` (token de capacidade) e NAO deve exfiltra-lo" com um teste dedicado, nao so uma frase de intencao? [Mensurabilidade, Contracts hooks.md item 7 "Nao-exfiltracao" + Test Strategy "Hooks": "nunca imprime/grava session_id"] {auto}
- [x] CHK014 - Credenciais expiradas/revogadas (FR-016) tem criterio de aceite que distingue claramente `auth_failed` (401, suspende) de `permission_denied` (403 em R1/R2, nao suspende drain inteiro) e de `deferred` (429/rede, adia), evitando que os 3 cenarios colidam no mesmo tratamento? [Clareza/Consistencia, data-model.md OutboxEvent transitions + correcao desta onda no dominio api CHK009] {auto} — Referencia cruzada: a distincao `auth_failed`/`permission_denied` foi introduzida nesta mesma onda (ver `checklists/api.md` CHK009, dec-038); `data-model.md` ConflictRecord ainda lista so `auth_failed` no enum `reason` — sem gap adicional porque `permission_denied` nao e um CONFLITO de sync (e falha de escrita), tratamento fica no motor/OutboxEvent, nao no ConflictRecord.
- [x] CHK015 - Existe requisito explicito de que o hook de sync NUNCA bloqueia/atrasa a tool do orquestrador (fail-open absoluto), com criterio verificavel (`async: true` sem timeout aplicado, ou timeout maximo definido)? [Mensurabilidade, Contracts hooks.md item 6 "Fail-open absoluto" + hooks.json `async: true`] {auto}

## Notes

- Items `{auto}` resolvidos pelo agente (`[x]` com citacao) ou marcados `[Gap]` com destino explicito.
- CHK005 (`[Gap]`) -> `/create-tasks`: tarefa "rotular texto do Jira como UNTRUSTED nas skills interativas".
- CHK011 (`{humano}`) -> decisao do dono do produto: elevar a nuance de escopo de FR-012 para a spec, ou aceitar que ela fica documentada so no contrato de hooks. Nao resolvido nesta onda (nao e correcao mecanica).
- 2 items em aberto de 15 totais (13 resolvidos {auto}, 1 `[Gap]` com destino, 1 `{humano}` aguardando decisao do produto).
