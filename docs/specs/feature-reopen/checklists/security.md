# Security Checklist: feature-reopen

**Purpose**: Validar requisitos de seguranca/governanca — exclusao mutua,
integridade do estado terminal, veracidade das afirmacoes da sonda de
trabalho pendente (Principio VI) e o desvio constitucional pre-existente ja
resolvido pelo operador. Este checklist **nao reabre** as decisoes de
`dec-022` (desvio do `gh`; escopo do `--backend`) — apenas confirma que a
spec/plan as refletem corretamente.
**Created**: 2026-08-11
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [research.md](../research.md)

## Exclusao Mutua e Concorrencia

- [x] CHK001 - A rotacao (mover round + iniciar execucao nova) MUST estar
      integralmente coberta pelo lock, sem janela onde outra sessao possa
      intervir? [Spec §FR-012] {auto}
      Evidencia: `contracts/reopen-flow.md` ordem de execucao — lock
      adquirido no passo 7 e "permanece detido continuamente do passo 7 ate
      o Cleanup" (T-31), cobrindo `recover`/`rotate`/restauracao de spec/
      `init`/gravacao do `.previous_round`.
- [x] CHK002 - Ha teste dedicado para o TOCTOU entre a checagem de
      pre-condicao (passo 6.a, antes do lock) e o `acquire` (passo 7)? [Spec
      §FR-012, Edge Case "outra sessao"] {auto}
      Evidencia: `contracts/reopen-flow.md` passo "7.a re-verificacao
      pos-lock (fecha TOCTOU)"; `plan.md` §Riscos lista a janela residual
      como Baixa e documentada; T-32 cobre "segunda sessao concorrente ⇒
      exit 3, sem tocar a rotacao em curso".
- [x] CHK003 - A segunda sessao concorrente recebe um exit code distinto do
      das recusas de pre-condicao (FR-002/FR-003), para nao confundir "sem
      execucao anterior" com "outra sessao ja reabrindo"? [Clareza, Spec
      §FR-012] {auto}
      Evidencia: exit `4` (sem execucao anterior, FR-002), exit `5`
      (execucao viva, FR-003) e exit `3` (lock contention, T-32) sao tres
      codigos distintos — sem colisao.

## Integridade do Estado Preservado

- [x] CHK004 - O round preservado MUST ser imutavel apos a rotacao — existe
      mecanismo que TORNARIA visivel uma alteracao acidental, nao so a
      promessa de que "nao sera alterado"? [Spec §FR-007] {auto}
      Evidencia: SC-002 exige verificacao byte a byte (`cmp`) apos qualquer
      numero de reaberturas; T-04/T-05 (`plan.md`) sao testes de regressao
      dedicados a essa invariante nos dois backends.
- [x] CHK005 - A rotacao e observavelmente tudo-ou-nada — uma interrupcao no
      meio nunca deixa o operador em estado que exija edicao manual de
      arquivo? [Spec §FR-011] {auto}
      Evidencia: `state-rounds.sh recover`/journal (`data-model.md` Entity
      RotateJournal, campos J1-J7, allowlist de chaves, parser
      linha-a-linha proprio — nunca `.`/`source`/`eval`); T-36 cobre
      journal invalido ⇒ sai por exit `6`, nunca editado a mao.
- [x] CHK006 - Os arquivos que NAO fazem parte do estado transacional (ex.:
      `enforcement-log.jsonl`) MUST permanecer no lugar e continuar sendo
      escritos pela execucao nova — isso esta testado, nao so declarado?
      [Spec §FR-007] {auto}
      Evidencia: `data-model.md` "Composicao do round por backend" lista
      explicitamente o que fica ("`state-history/`, `backups/`,
      `feature-00c-report.md`, `.lock/`, `.gitignore`" para json; mais
      "`commit-baseline.txt`, `mcp-server.json`, `tool-call-ticks.log`,
      `wave-agent-usage.jsonl`, `enforcement-log.jsonl`" para sqlite) —
      lista exaustiva, nao "et cetera".

## Veracidade (Principio VI) — sonda de trabalho pendente

- [x] CHK007 - A ausencia de verificacao (git/gh indisponivel) MUST nunca
      virar afirmacao de "sem pendencia"? [Principio VI, Spec §FR-021] {auto}
      Evidencia: invariante `I-P1` (`data-model.md`) e explicita:
      "`merged=unknown` ou `pr_state=unknown` MUST ser reportado como 'nao
      verificado', jamais como 'nao ha trabalho pendente'"; T-51 testa esse
      exato caso.
- [x] CHK008 - Cada campo do `PendingWorkProbe` carrega a fonte (comando
      literal) que o produziu, permitindo auditoria de que a afirmacao nao
      foi fabricada? [Principio VI, Spec §FR-021] {auto}
      Evidencia: `data-model.md::PendingWorkProbe.source` (`string`,
      `NOT NULL`); `research.md` Decision 9 lista os comandos exatos
      (`git symbolic-ref refs/remotes/origin/HEAD`, `gh pr view --json
      url,state`, `gh auth status`).
- [ ] CHK009 - O contrato exato (flags/exit-codes/stdout) da sonda que
      produz o `PendingWorkProbe` esta especificado o bastante para um
      revisor confirmar, por leitura de codigo apos implementado, que ela
      NUNCA infere "merged=no" sem checagem real (ex.: por timeout
      silencioso tratado como "no" em vez de "unknown")? [Principio VI,
      Spec §FR-021] {humano}
      Ligado ao **[Gap]** ja registrado em `checklists/requirements.md`
      CHK002 (contrato de CLI da sonda ainda nao existe como artefato
      dedicado) — sem esse contrato, nao ha como um revisor confirmar
      objetivamente que a implementacao futura respeitara I-P1 em todos os
      caminhos de erro (timeout de rede do `gh`, `git` corrompido, etc.).
      Fica `{humano}` porque decidir SE vale a pena formalizar o contrato
      agora (vs. deixar para a task de `create-tasks` decidir no momento da
      implementacao) e chamada de profundidade/risco do dono do produto,
      nao algo que a spec/plan atuais respondem.

## Constitution — desvio pre-existente (informativo, NAO re-decidir)

- [x] CHK010 - O Constitution Check de `plan.md` distingue claramente o que
      e desvio PRE-EXISTENTE (nao criado por esta feature) do que seria
      violacao NOVA introduzida pelo design desta feature? [Consistencia,
      Principio VI, Spec §Constitution Check] {auto}
      Evidencia: `plan.md` "Re-check de Constitution" pergunta
      explicitamente "Algum MUST passou a ser violado pelo design?" com
      resposta "Nao" e nota separada de que o desvio pre-existente
      (condicao b do carve-out 1.1.0) "permanece, declarado e nao corrigido
      por decisao do operador (dec-022)" — as duas coisas nao sao
      confundidas na mesma frase.
- [x] CHK011 - A resolucao do operador (dec-022: manter como divida
      declarada, sem amendment, sem adapter, sem tarefa de refactor) esta
      registrada como Decisao auditavel E refletida no artefato, nao so
      numa das duas formas? [Rastreabilidade, Auditabilidade] {auto}
      Evidencia: `dec-022` presente em `.decisions[]` do `state.db`
      (registrada por `/feature-00c-resume` ao aplicar a resposta do
      operador ao `block-001`); `plan.md` §Constitution Check e §Fora de
      escopo citam `dec-022` explicitamente nesta onda (dec-024).
- [x] CHK012 - A medicao empirica que fundamenta o desvio (3 arquivos
      invocando `gh`, nao 1) permanece citavel/reprodutivel no artefato,
      evitando que uma futura leitura reintroduza a premissa falsa
      corrigida na onda anterior? [Principio VI] {auto}
      Evidencia: `plan.md` linha 88 mantem a medicao direta com os 3
      arquivos e linhas exatas (`commit-mode.sh`, `issue.sh` L92-93/L241/
      L250/L333+, `cli/lib/session.sh`); `research.md` Decision 9 preserva
      o bloco "CORRECAO DE PREMISSA" como historico, em vez de apagar a
      versao errada.

## Backend misto na linhagem — superficie de ataque

- [x] CHK013 - A decisao de NAO herdar backend (linhagem mista intencional,
      dec-022) introduz alguma superficie nova de leitura cruzada entre
      state-dirs de features diferentes? [Seguranca, Spec §FR-010] {auto}
      Evidencia: `research.md` Decision 14 (reescrita) e `data-model.md`
      confirmam que o backend e resolvido por `state-rw.sh init` a partir
      de config GLOBAL do processo local (`~/.claude/cstk/config`), no
      MESMO state-dir da propria feature — nenhum dado atravessa state-dirs
      de features diferentes; o mecanismo e identico ao `init` ja usado
      hoje para abertura normal, sem superficie nova.
- [x] CHK014 - Os leitores backend-agnosticos (v6.3,
      `state-db-runtime-parity`) que tornam a linhagem mista segura estao
      de fato cobertos por teste de regressao, ou e uma alegacao sem
      verificacao automatizada? [Principio VI, Cobertura] {auto}
      Evidencia: `tests/test_state-parity-sweep.sh` (citado em `CLAUDE.md`
      §state-db-runtime-parity) varre os 15+ leitores contra state-dir
      SQLite populado com grep estatico allowlist; `plan.md` §Escopo item 6
      cita a extensao dessa allowlist para o leitor novo do `--reindex`.

## Notes

- Items `{auto}` resolvidos citando artefato + linha/comando.
- Items `{humano}` em aberto: CHK009 (profundidade do contrato da sonda —
  ligado ao `[Gap]` CHK002 de `requirements.md`).
- Nenhum `[Ambiguity]`/`[Conflict]` de seguranca encontrado nesta rodada.
