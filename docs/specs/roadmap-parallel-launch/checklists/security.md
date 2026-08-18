# Security Checklist: Lançamento Paralelo de Features do Roadmap

**Purpose**: validar a QUALIDADE dos **requisitos de segurança** desta feature —
se as mitigações levantadas pelo gate `owasp-security` (2 findings HIGH, ratificados
em block-004) estão especificadas com precisão suficiente para serem implementadas e
verificadas. Não é um teste de código.
**Created**: 2026-08-17
**Feature**: [spec.md](../spec.md)

## Cobertura no nivel de requisito (spec.md)

- [x] CHK101 - As mitigações de segurança ratificadas têm contrapartida como **requisito** (FR/SC) na `spec.md`, ou existem apenas como decisão de design em plan/contracts? [Completude, Spec §FR-017 (sintetiza as 4 mitigações, cada uma citando a seção do contrato que a implementa)] {auto}
- [x] CHK102 - Os findings do gate estão registrados com o desfecho da decisão humana, e não apenas resolvidos em silêncio? [Rastreabilidade, state.json — block-004 respondido `ratificar`, Decisão dec-027] {auto}
- [x] CHK103 - Existe requisito que proíba apresentar o paralelismo ao operador como sandbox/isolamento de segurança? [Completude, Spec §FR-018 + contracts/parallel-launch.md §3 passo 4 (critério verificável: declaração ocorre na mesma interação da oferta) + §8.bis] {auto}

## Canal de notificacao nao-confiavel (finding HIGH — ASI07)

- [x] CHK104 - A regra de validação da mensagem recebida está especificada literalmente (ancorada e com conjunto fechado), em vez de "validar o formato"? [Clareza, contracts/parallel-launch.md §6 item 1 — regex ancorada `^\[cstk-parallel\] feature=([a-z][a-z0-9-]{0,63}) outcome=(concluida|abortada|aguardando_humano) repo=([A-Za-z0-9._-]{1,64})$`] {auto}
- [x] CHK105 - O tratamento de conteúdo excedente está definido de forma fail-closed? [Clareza, contracts/parallel-launch.md §6 item 1 — "qualquer sobra de texto na mensagem e **descartada**, nunca lida"] {auto}
- [x] CHK106 - Está especificado que a mensagem é gatilho **opaco**, sem derivar ação, comando ou caminho do seu conteúdo? [Completude, contracts/parallel-launch.md §6 item 2 + INV-8] {auto}
- [x] CHK107 - O pior caso de uma notificação forjada está declarado e limitado a um efeito benigno? [Mensurabilidade, contracts/parallel-launch.md §6 item 3 — "no pior caso, provoca um recalculo redundante — nunca um lancamento fora da fronteira"] {auto}
- [x] CHK108 - O requisito de best-effort (FR-015) está redigido de modo que falha de entrega não altere o ciclo de vida da filha? [Consistência, Spec §FR-015 + contracts/parallel-launch.md §6 "Regras duras" + INV-5] {auto}
- [x] CHK109 - Existe cenário de teste adversarial associado à notificação forjada? [Cobertura, plan.md §Cenários (linha transversal do gate) — `quickstart.md` C7b] {auto}

## Prosa do roadmap como conteudo nao-confiavel (finding HIGH — LLM01/ASI01)

- [x] CHK110 - A fonte da heurística está declarada como conteúdo não-confiável que chega ao ponto onde há execução de shell? [Completude, plan.md §Riscos conhecidos — "Prosa de `docs/roadmap.md` é conteúdo não-confiável ... (LLM01/ASI01)"] {auto}
- [x] CHK111 - As quatro mitigações atribuídas a esse risco (allowlist de token, **truncamento**, escaping, **rótulo de não-confiável**) estão todas especificadas no contrato citado como fonte? [Completude, contracts/roadmap-frontier.md §6 (truncamento a 128 chars + rótulo `roadmap-prose-untrusted`) + §7.1 (exemplo JSON com `source`) + §9 INV-4 atualizado] {auto}
- [x] CHK112 - O escaping obrigatório está atrelado a funções já existentes, em vez de "escapar adequadamente"? [Clareza, contracts/roadmap-frontier.md §7.1 — `json_escape` para `--json`, `md_escape` para markdown, com justificativa de que aspa quebraria o JSON-lines] {auto}
- [x] CHK113 - A redação da saída do aviso está normatizada como indício, com forma proibida explicitada? [Clareza, contracts/roadmap-frontier.md §6 — obrigatório "as entradas X e Y mencionam ambas <token>"; proibido "X e Y vao conflitar"] {auto}
- [x] CHK114 - Existe invariante que impeça qualquer caminho de emitir token bruto do roadmap? [Completude, contracts/roadmap-frontier.md INV-4 e INV-5] {auto}

## Injecao em linha de comando (finding MEDIUM — camada unica / argument injection)

- [x] CHK115 - As allowlists dos identificadores interpolados estão especificadas com o padrão literal e o ponto de aplicação? [Clareza, contracts/parallel-launch.md §4.1 — `^cstk-feature/[a-z][a-z0-9-]*$` e `^cstk-coord/[A-Za-z0-9._-]{1,64}$`] {auto}
- [x] CHK116 - Está especificada a revalidação no ponto de uso (defesa em profundidade), com exit code definido, em vez de confiar só na validação a montante? [Completude, contracts/parallel-launch.md §4.2 — `emit` revalida `--feature` contra `^[a-z][a-z0-9-]*$` (<= 64) e recusa com exit `2`] {auto}
- [x] CHK117 - O requisito de quoting cobre o valor que **não** passa pela allowlist (nome do repo)? [Cobertura, contracts/parallel-launch.md §4.1 — `<WORKTREE>` deriva do nome do repo, que "NAO passa pelo filtro" e por isso MUST ser emitido entre aspas duplas; forma argv múltiplo em vez de string única] {auto}
- [x] CHK118 - A validação de paths recebidos por flag está especificada com o vetor concreto que a justifica? [Clareza, contracts/roadmap-frontier.md §3.1 — rejeitar componente `..` ou resolução fora do repo (exit `2`), motivado por `git -C` em repo hostil via `core.fsmonitor`; premissa de confiança declarada no `--help`] {auto}
- [x] CHK119 - A janela TOCTOU entre a guarda anti-duplicidade e o lançamento está tratada com recomputação e backstop? [Cobertura de Edge Cases, contracts/parallel-launch.md §4.2 — recomputar imediatamente antes de executar; backstop exit `6` de `cstk session start`] {auto}
- [x] CHK120 - Existe cenário adversarial associado (nome de repo com espaço/aspa, short-name malicioso, path com `..`)? [Cobertura, plan.md task 1.5b] {auto}

## Limite de isolamento e blast radius (finding MEDIUM — ASI03/ASI08)

- [x] CHK121 - O que é compartilhado entre sessões está enumerado explicitamente, em vez de afirmar isolamento genérico? [Clareza, contracts/parallel-launch.md §8.bis — `.git` common-dir (logo `hooks/` e `config`), `$HOME`, `~/.claude`, `knowledge.db` global, credenciais do operador] {auto}
- [x] CHK122 - O teto de concorrência está declarado também como limite de blast radius, e não só de rate-limit? [Consistência, contracts/parallel-launch.md §8.bis] {auto}
- [x] CHK123 - O kill switch está especificado com comandos verificáveis e local de documentação? [Completude, contracts/parallel-launch.md §8.bis — `tmux kill-window -t <pane_id>` + `cstk session end <SHORT>`, documentados junto da via manual §7] {auto}
- [x] CHK124 - A inatividade da guarda de Bash no instante do lançamento (status já `concluida`) está declarada e mitigada, em vez de omitida? [Completude, contracts/parallel-launch.md §2 — short-name MUST vir da saída fail-closed de `roadmap-status.sh`, nunca de texto livre] {auto}
- [x] CHK125 - O registro de auditoria do lançamento está especificado além do campo `source`? [Completude, contracts/parallel-launch.md §4.2 "Schema da linha (CHK125)" — 6 campos + exigência de `secrets-filter.sh scrub` no campo `command` antes de qualquer truncamento, mesma disciplina de `pretooluse-bash-guard.sh`] {auto}

## Decisoes do dono do produto (aguardando)

- [x] CHK126 - Aceita-se operar o paralelismo sabendo que worktree não é fronteira de segurança (filha comprometida alcança coordenadora, `$HOME` e credenciais)? [Risco, contracts/parallel-launch.md §8.bis] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): aceito -->
- [x] CHK127 - Aceita-se um canal de notificação sem autenticação de remetente, com o risco residual limitado a recálculo redundante? [Risco, contracts/parallel-launch.md §6] {humano} <!-- decidido pelo operador 2026-08-17 (dec-035): aceito -->

## Notes

- Items `{auto}` vêm resolvidos com citação; `[ ]` + `[Gap]` = lacuna de requisito verificada empiricamente nesta onda.
- CHK101, CHK103, CHK111 e CHK125 (os 4 gaps originais) foram fechados na
  task 1.2 (`docs/specs/roadmap-parallel-launch/tasks.md`): FR-017/FR-018
  em `spec.md`, truncamento+rótulo em `contracts/roadmap-frontier.md` §6,
  schema de auditoria em `contracts/parallel-launch.md` §4.2.
