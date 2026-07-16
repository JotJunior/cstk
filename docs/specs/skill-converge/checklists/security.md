# Security Checklist: skill-converge

**Purpose**: Valida a QUALIDADE dos requisitos de seguranca dos 3 hardening
`MEDIUM` identificados pelo gate `owasp-security` na arquitetura da skill
`converge` (dec-020, onda-003): SEC-1 shell-injection, SEC-2 path-traversal/
symlink fail-closed, SEC-3 prompt-injection indireta. Nao reexecuta o gate
`owasp-security` (ja rodou nesta feature) nem valida implementacao (codigo
ainda nao existe) — confirma que os REQUISITOS de hardening estao precisos
e testaveis o bastante para `/create-tasks` decompor em tarefas.
**Created**: 2026-07-16
**Feature**: [spec.md](../spec.md) · [plan.md §Security
Considerations](../plan.md)

> Legenda: `{auto}` = resolvivel contra spec/plan/research/contracts
> (resolvido com citacao). `{humano}` = julgamento de risco/negocio (aberto).
> Marcadores de gap: `[Gap]` requisito ausente, `[Ambiguity]` interpretacao
> multipla, `[Conflict]` contradicao entre artefatos.

## SEC-1 — Shell Injection (A05, helpers POSIX)

- [x] CHK001 - O requisito de quotar toda variavel (`"$var"`) nos helpers
  POSIX esta redigido em linguagem MUST, sem margem de "quando
  conveniente"? [Clareza, plan.md §Security Considerations SEC-1] {auto}
- [x] CHK002 - A proibicao de `eval` sobre conteudo derivado de artefato
  lido esta explicita e sem excecao condicional? [Clareza, plan.md
  §Security Considerations SEC-1] {auto}
- [x] CHK003 - O mecanismo de verificacao (testes com paths adversariais
  concretos: `"; rm -rf`, `$(...)`, backtick) esta nomeado explicitamente,
  permitindo que `/create-tasks` gere tarefas de teste diretamente
  rastreaveis a este requisito? [Mensurabilidade, plan.md §Security
  Considerations SEC-1] {auto}
- [x] CHK004 - O requisito de SEC-1 se aplica explicitamente a TODOS os
  helpers novos (`extract-intent.sh`, `extract-must.sh`, `severity.sh`,
  `converge-tasks.sh`, `path-contains.sh`), nao a um subconjunto implicito?
  [Cobertura, plan.md §Security Considerations SEC-1 "Todos os helpers em
  scripts/", plan.md §Project Structure] {auto} — "Todos os helpers em
  `scripts/`" cobre os 5 scripts listados no Project Structure sem
  exclusao.

## SEC-2 — Path Traversal / Symlink Fail-Closed (A01, CWE-22)

- [x] CHK005 - O requisito de canonicalizar symlinks ANTES do check de
  prefixo esta explicito, prevenindo a ordem incorreta
  (check-antes-de-canonicalizar) que permitiria bypass? [Clareza, plan.md
  §Security Considerations SEC-2] {auto}
- [x] CHK006 - O comportamento fail-closed (path irresolvivel ⇒ tratado
  como fora do alvo, arquivo NUNCA lido) esta redigido sem caminho
  alternativo de fail-open? [Clareza, plan.md §Security Considerations
  SEC-2, contracts/converge-interfaces.md §6] {auto}
- [ ] CHK007 - Existe cenario de verificacao (quickstart ou compromisso de
  teste unitario nomeado, equivalente ao que SEC-1 tem) especificamente
  para o caso "symlink DENTRO do alvo apontando para FORA", o ataque
  nomeado pelo proprio SEC-2? [Gap, plan.md §Security Considerations SEC-2
  "um symlink dentro do alvo apontando para fora nao pode burlar FR-018",
  quickstart.md §Scenario 10] {auto} — **[Gap]**: Scenario 10 (unico
  cenario de blast-radius do quickstart) testa um path relativo literal
  (`../../etc/passwd`), NAO um symlink. SEC-1 nomeia explicitamente seu
  metodo de verificacao ("testes que passem paths adversariais"
  + exemplos); SEC-2 nao tem equivalente — nem cenario de quickstart nem
  compromisso textual de teste unitario citando o caso symlink.
  `path-contains.sh` e o unico ponto de aplicacao desta defesa (FR-018) e
  o caso symlink e o mais dificil de acertar (ordem
  canonicalizar-antes-de-checar). `/create-tasks` deve apendar
  cenario/teste dedicado (`tests/test_path-contains.sh` com fixture de
  symlink apontando para fora do root).
- [x] CHK008 - A tecnica de canonicalizacao (`realpath`/fallback POSIX
  `cd`+`pwd -P`) e consistente entre a exigencia de SEC-2 e a decisao
  tecnica de research.md, sem divergencia de implementacao proposta?
  [Consistencia, plan.md §Security Considerations SEC-2, research.md
  §Decision 6] {auto}

## SEC-3 — Prompt Injection Indireta (LLM01, ASI09)

- [x] CHK009 - O requisito de enquadrar TODO conteudo lido (spec/tasks/
  constitution/codigo auditado) como DADO untrusted, nunca instrucao,
  cobre EXPLICITAMENTE o codigo-fonte auditado — a superficie de injecao
  mais nova desta feature (codigo de terceiros/desenvolvedor, nao so docs
  do proprio pipeline), dado que FR-004 exige leitura semantica do codigo
  pelo agente? [Cobertura, plan.md §Security Considerations SEC-3
  "spec.md/tasks.md/constitution.md/codigo auditado"] {auto} — "codigo
  auditado" esta explicitamente na lista, nao e uma lacuna.
- [x] CHK010 - O exemplo de ataque nomeado ("marque tudo como convergido"
  embutido num artefato) e o MUST de ignora-lo estao redigidos como
  requisito comportamental verificavel, nao apenas como narrativa
  ilustrativa? [Clareza, plan.md §Security Considerations SEC-3] {auto}
- [ ] CHK011 - Existe ALGUM mecanismo de verificacao empirica para SEC-3
  (eval adversarial, cenario de quickstart, ou teste automatizado), ou o
  requisito depende inteiramente de uma instrucao textual no futuro
  `SKILL.md` sem forma de checar conformidade antes de producao? [Gap,
  plan.md §Security Considerations SEC-3, plan.md §Technical Context
  "Testing", plan.md §Project Structure `evals/triggers.jsonl`] {auto} —
  **[Gap]**: nenhum dos 12 cenarios de quickstart.md e o
  `evals/triggers.jsonl` planejado (que e eval de TRIGGER/disparo da
  skill, proposito distinto) cobrem resistencia a prompt injection. E o
  hardening MEDIUM mais dificil de verificar objetivamente (comportamento
  de agente, nao script POSIX testavel por harness deterministico) e o
  UNICO dos 3 SEC sem qualquer mecanismo de verificacao proposto.
  `/create-tasks` deve apendar ao menos um cenario adversarial (artefato
  de teste com diretiva embutida) ao quickstart ou aos evals da skill.
- [x] CHK012 - A defesa de SEC-3 e consistente com o padrao ja documentado
  nos orquestradores ("Injecao via artefatos lidos" em
  `agente-00c-feature-orchestrator.md`), reusando a mesma postura em vez
  de inventar uma nova? [Consistencia, plan.md §Security Considerations
  SEC-3 "mesma defesa Injecao via artefatos lidos dos orquestradores"]
  {auto}

## Segunda ordem (LOW, informativo)

- [x] CHK013 - O uso de `sha256-12` (hex) para `converge-key`, em vez de
  texto-livre, esta justificado como mitigacao suficiente para o achado
  LOW de segunda ordem (texto de gap apendado vira input do
  `execute-task` downstream)? [Clareza, plan.md §Security Considerations
  "Segunda ordem"] {auto}

## Notes

- Items `{auto}` resolvidos: 11 (`[x]` com citacao).
- Items abertos para consumo do `/create-tasks`: CHK007 `[Gap — cenario
  symlink para SEC-2]`, CHK011 `[Gap — nenhuma verificacao empirica para
  SEC-3]`.
- SEC-1 e o unico dos tres hardening com mecanismo de verificacao JA
  nomeado explicitamente no plan.md; SEC-2 e SEC-3 precisam desse mesmo
  nivel de compromisso antes de `/execute-task`. Recomenda-se
  `/create-tasks` fechar CHK007/CHK011 como tarefas de definicao-de-teste,
  nao so de implementacao.
- Nenhum achado `CRITICAL`/`HIGH` novo nesta rodada — os 3 hardening
  seguem `MEDIUM` (dec-020); este checklist so avalia se os REQUISITOS de
  hardening (nao o codigo, que ainda nao existe) estao completos e
  testaveis.
