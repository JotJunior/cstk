# SECURITY Checklist: roadmap-wave

**Purpose**: Validar a qualidade dos requisitos/mitigacoes de seguranca
declarados para `roadmap-wave` — foco no achado aberto sobre o
projeto-alvo parametrizado (F3, `git -C` sobre repo hostil) e nos
demais achados do gate `owasp-security` ja registrados em dec-018.
**Created**: 2026-08-18
**Feature**: [spec.md](../spec.md)

## Autenticacao/Autorizacao — N/A declarado

- [x] CHK001 - O plano declara explicitamente a ausencia de superficie
  de authN/authZ nova (sem endpoint, sem usuario, sem sessao de
  rede)? [Completude] {auto}
  Evidencia: plan.md Constitution Check "IV. Zero coleta remota
  (NON-NEGOTIABLE) | PASS | tudo local... Nenhuma chamada de rede".

## Protecao de Dados / Injecao de conteudo nao-confiavel

- [x] CHK002 - Existe requisito de rotulagem explicita (UNTRUSTED) para
  a saida de `roadmap-frontier.sh` (que pode conter prosa de terceiro
  em `### Avisos`) antes de injeta-la no turno do operador? [Spec §F1]
  {auto}
  Evidencia: `contracts/roadmap-wave-command.md` §5.1 (F1 MEDIUM,
  LLM01/ASI09) — MUST citado com precedente ja aplicado no read-back
  loop; INV-5 (§6) reforca "repassada tal-e-qual, NUNCA resumida nem
  reforcada como conflito confirmado".
- [x] CHK003 - O helper consumido (`roadmap-frontier.sh`) ja aplica
  sanitizacao propria (allowlist de token, truncamento, teto por par)
  antes de emitir avisos de sobreposicao, e essa sanitizacao e citada
  como camada JA existente (nao reimplementada por esta feature)?
  [Consistencia] {auto}
  Evidencia: `contracts/roadmap-wave-command.md` §5.1 — "o helper ja
  faz a parte dele (allowlist de token, truncamento a 128 chars, teto
  de 10 tokens por par, rotulo `roadmap-prose-untrusted` —
  `roadmap-frontier.sh:317-318`, `:431`)".

## Input Validation — teto (`--max`)

- [x] CHK004 - O requisito de teto define uma faixa MAXIMA absoluta
  (nao so um default), impedindo `--max` scriptado com valor absurdo
  em modo nao-interativo? [Spec §F2] {auto}
  Evidencia: `contracts/roadmap-wave-command.md` §5.2 (F2 MEDIUM,
  LLM10/ASI02) + §3.2 "`--max` agora e `1..8`, fail-closed acima
  disso"; quickstart.md C17 "Teto fora da faixa".
- [x] CHK005 - Existe cenario de teste dedicado que exercite o teto
  mal-formado (nao-numerico) alem do teto fora de faixa (numerico
  excessivo)? [Cobertura] {auto}
  Evidencia: quickstart.md C10 "Teto mal-formado e fail-closed
  (FR-007)" cobre nao-numerico; C17 cobre fora de faixa — as duas
  classes de entrada invalida tem cenario proprio.

## Path/Repo Hostil — projeto-alvo parametrizado (achado central desta rodada)

- [ ] CHK006 - O achado F3 (repo hostil apontado via
  `--projeto-alvo-path`, executando `git -C` que pode disparar codigo
  via `.git/config`/`core.fsmonitor`) tem mitigacao TECNICA no codigo
  (nao apenas declaracao textual no command)? [Gap, F3] {auto}
  NAO satisfeito. `contracts/roadmap-wave-command.md` §5.3 define o
  MUST como puramente declarativo: (1) o command afirma no proprio
  texto a premissa de confianca, (2) o projeto-alvo nunca e derivado de
  conteudo lido, (3) o blast radius nomeia o projeto-alvo resolvido.
  Nenhum dos tres itens valida programaticamente que o path resolve
  para dentro de uma fronteira confiavel — `roadmap-frontier.sh:121-
  136` (`_rf_reject_dotdot`) so rejeita a sintaxe `..`, nunca resolve o
  path real nem checa contra um allowlist/raiz coordenadora. Isso e
  a SEGUNDA metade de `contracts/roadmap-frontier.md` §3.1 (rejeitar
  path que "resolver para fora do repo coordenador"), que o proprio
  `roadmap-frontier.sh:47-52` (DIVERGENCIA CONHECIDA, corrigida para
  honestidade no commit `7d1b71d`) admite nunca ter sido implementada.
- [ ] CHK007 - A diretriz mais recente do operador (contencao real
  bloqueante para a FASE 2 de `roadmap-wave`) esta refletida em algum
  FR/MUST rastreavel em spec.md ou contract, ou existe apenas como
  Decisao de onda (dec-022) sem materializacao no artefato? [Conflict]
  {auto}
  NAO materializada nos artefatos: `spec.md` nao tem FR sobre
  contencao de path; `contracts/roadmap-wave-command.md` §5.3 continua
  descrevendo mitigacao prosa-only (nao alterada nesta onda — checklist
  nao edita plan/contract). Registrado apenas como dec-022
  (`state-decisions.sh`, etapa checklist) e como CHK006 acima. Destino:
  `/create-tasks` deve criar uma tarefa explicita de definicao de
  escopo tecnico (ex.: `realpath`/validacao contra raiz coordenadora em
  `resolve-offer` ou em `roadmap-frontier.sh`) — a IMPLEMENTACAO em si
  fica fora do papel do checklist.
- [ ] CHK008 - Ha decisao ratificada sobre QUEM implementa a contencao
  real, dado que `plan.md` (Project Structure) marca
  `roadmap-frontier.sh` como "CONSUMIDO tal-e-qual — nao alterar"?
  [Risco] {humano}
  Aberto: se a contencao tecnica for exigida, ela precisa ou (a)
  alterar `roadmap-frontier.sh` (contradiz o plano atual "nao alterar",
  que pertence a outra feature/`roadmap-parallel-launch`) ou (b)
  implementar uma segunda checagem redundante no `resolve-offer` novo
  desta feature (path novo, sem tocar o helper existente). Essa
  decisao de arquitetura cabe ao dono do produto/plan, nao ao gate de
  checklist.
- [x] CHK009 - O risco residual de TOCTOU entre a checagem de
  contencao (se vier a existir) e a chamada real a `git -C` esta
  reconhecido como classe de risco documentada em vez de assumido como
  eliminado? [Clareza] {auto}
  Evidencia: `contracts/roadmap-wave-command.md` §5.5 (F5 LOW, TOCTOU
  ja documentado para a guarda anti-duplicidade) estabelece o padrao
  de "residual declarado honestamente... NUNCA afirmar que a
  duplicidade esta eliminada" — mesmo padrao normativo aplicavel a
  qualquer contencao de path que vier a ser adicionada.

## Rastreabilidade sug-001 → correcao aplicada

- [x] CHK010 - A parte de honestidade do achado sug-001 (header do
  script afirmando nao invocar `git -C` quando de fato invoca) foi
  corrigida e a correcao e verificavel no codigo publicado? [Spec
  §sug-001] {auto}
  Evidencia: `roadmap-frontier.sh:42-43` hoje afirma "este script
  INVOCA `git -C \"$EXCLUDE_ACTIVE_REPO\" worktree list`" (grep
  confirmado nesta onda) — reverte a alegacao anterior "nao invoca
  `git -C` diretamente". Commit `7d1b71d` (branch corrente).
- [x] CHK011 - A correcao de honestidade inclui uma declaracao explicita
  da divergencia conhecida entre o contrato irmao e a implementacao
  real (nao apenas silenciar o aviso)? [Clareza] {auto}
  Evidencia: `roadmap-frontier.sh:47-52` — bloco "DIVERGENCIA CONHECIDA
  (v8.2.0)" cita `contracts/roadmap-frontier.md` §3.1 e admite
  textualmente que so a checagem sintatica de `..` esta implementada.

## Logging / Auditabilidade

- [x] CHK012 - A ausencia de trilha auditavel persistente para a
  decisao de lancamento (esta feature nao tem `state.json`) tem
  mitigacao compensatoria definida (eco explicito ao operador)? [Spec
  §F4] {auto}
  Evidencia: `contracts/roadmap-wave-command.md` §5.4 (F4 LOW, A09) —
  MUST "o command ecoa explicitamente ao operador o que resolveu
  (`source`, `launch`, `max` efetivo e a lista final)".

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Conflict]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- **CHK006/CHK007/CHK008** sao o achado central desta rodada de
  checklist: a correcao de honestidade (sug-001) esta feita, mas a
  contencao TECNICA real segue em aberto e, por instrucao do operador
  recebida nesta onda, NAO deve ser tratada como resolvida. Ver dec-022
  (`state-decisions.sh`, etapa checklist) e `checklists/requirements.md`
  CHK005/CHK017/CHK020 para a mesma lacuna vista pelo angulo de
  completude/NFR/conflito de requisitos.
- Destino declarado para os 3 items `[Gap]`/`[Conflict]` abertos:
  `/create-tasks` deve gerar uma tarefa de definicao-e-implementacao de
  escopo (nao uma mera nota) para que a FASE 2 nao seja dada como
  concluida com a mitigacao apenas em prosa.
