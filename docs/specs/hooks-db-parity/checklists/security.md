# Security Checklist: Paridade Backend-Agnostica dos Hooks 00C

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca da feature
`hooks-db-parity` — uma guarda fail-closed cujo bug atual (fail-open silencioso
sob backend SQLite) e, ele proprio, uma regressao de seguranca. O foco e se os
requisitos escritos sao completos, nao-ambiguos e verificaveis; nao se o codigo
funciona.
**Created**: 2026-08-03
**Feature**: [spec.md](../spec.md)
**Insumo**: gate `owasp-security` da onda 3 (plan.md §Security Review) —
SEC-H1/SEC-H2 High aprovados com mitigacoes pelo operador em `dec-026`;
SEC-M1/M2/M3 Medium mitigados no contrato; SEC-L1/L2 Low aceitos como residual.

## Completude dos requisitos de fail-closed

- [x] CHK001 - Os requisitos definem comportamento esperado para CADA estado possivel da sonda de execucao ativa, sem estado orfao? [Completude, data-model §ActiveExecutionProbe] {auto}
      → Enum fechado de 3 valores (`ativa`/`inativa`/`indeterminada`, exit 0/1/2) com destino definido para cada um: FR-001 (ativa), FR-007 (inativa), FR-003/FR-004 (indeterminada).
- [x] CHK002 - O requisito distingue explicitamente "ausencia total de state" de "state presente porem ilegivel", em vez de tratar ambos como um unico caso? [Clareza, Spec §FR-007] {auto}
      → FR-007 nomeia a distincao e roteia cada lado: ausencia = "fora de escopo"; `state.db` presente porem corrompido cai em FR-003/FR-004.
- [x] CHK003 - O requisito de fail-closed enumera QUAIS classes de falha o acionam, em vez de dizer apenas "em caso de erro"? [Clareza, Spec §FR-003] {auto}
      → FR-003 lista tres: dependencia ausente, arquivo corrompido, erro de leitura.
- [x] CHK004 - O requisito de fail-open dos hooks de metrica especifica o que "no-op silencioso" significa de forma observavel? [Mensurabilidade, Spec §FR-004] {auto}
      → FR-004 decompoe em tres condicoes verificaveis: sem stdout, sem stderr de erro, sem interferencia na tool call.
- [x] CHK005 - Os requisitos deixam inequivoco que os dois hooks de metrica NAO devem herdar o fail-closed do hook de guarda? [Consistencia, Spec §FR-003 vs §FR-004] {auto}
      → FR-003 e FR-004 separam os hooks por nome e atribuem posturas opostas explicitamente; contracts/hook-io.md §"Modos de no-op (fail-open)" repete a separacao por evento.
- [ ] CHK006 - O estouro do orcamento de tempo da propria deteccao esta definido como uma classe de falha nos requisitos (e nao apenas como risco de performance)? [Gap, Spec §FR-003; plan §SEC-H2] {auto}
      → **[Gap]**: FR-003 enumera dependencia ausente / corrompido / erro de leitura, mas NAO nomeia "excedeu o tempo limite" como falha de mecanismo. A mitigacao existe no plano (fase 0 + auto-teto interno, plan §SEC-H2, dec-026), porem sem requisito correspondente na spec o gate fica sem criterio de aceite. Destino: `/create-tasks` — task "elevar auto-teto de deteccao a requisito explicito de FR-003".
- [ ] CHK007 - Os requisitos definem a fronteira de confianca do carregamento do proprio codigo de deteccao (de onde o helper pode ser sourceado)? [Gap, contracts/hook-active-exec.md §"Ordem MODIFICADA"/§"Pre-condicao de sourcing"] {auto}
      → **[Gap]** no nivel da spec: o contrato define a ordem invertida (`$HOME` antes de `<cwd>`) e o pre-check inline como MUST, mas nenhum FR da spec cobre integridade de carregamento. Aprovado como desenho em `dec-026`; falta o requisito rastreavel. Destino: `/create-tasks`.

## Clareza e nao-ambiguidade

- [x] CHK008 - A precedencia entre execucoes concorrentes esta especificada de forma deterministica e sem empate possivel? [Clareza, Spec §FR-002; data-model §"Regra de desempate"] {auto}
      → Tres niveis totalmente ordenados: `agente-00c` > `feature-00c`; entre features, menor short-name byte-wise (`LC_ALL=C`); dentro de um state-dir, `state.db` > `state.json`.
- [x] CHK009 - Esta definido se um state-dir ilegivel curto-circuita a varredura ou apenas contamina o resultado final? [Clareza, data-model §"Precedencia de `ativa` sobre `indeterminada`"] {auto}
      → Explicito: "um state-dir ilegivel **nao** curto-circuita a varredura; `indeterminada` so e o resultado final se nenhuma execucao ativa foi confirmada".
- [x] CHK010 - O conjunto de status considerados "execucao ativa" esta enumerado, em vez de descrito por adjetivo? [Clareza, Spec §FR-001; data-model §"Validation rules"] {auto}
      → Conjunto fechado `em_andamento` + `aguardando_humano`; `abortada`/`concluida` explicitamente nao-ativos, ancorados no `CHECK` da coluna `execution.status`.
- [ ] CHK011 - O "teto defensivo de state-dirs sondados por invocacao" esta quantificado? [Ambiguity, contracts/hook-active-exec.md §SEC-M3] {auto}
      → **[Ambiguity]**: o contrato exige "aplicar teto defensivo" sem nenhum numero, e nenhum outro artefato o fixa (verificado por varredura em todos os 7 artefatos: unica ocorrencia e a linha do SEC-M3). Sem valor, o requisito nao e verificavel nem testavel. Destino: `/clarify`.

## Consistencia entre artefatos

- [ ] CHK012 - O criterio de sucesso de latencia e consistente com o teto que o gate automatizado de fato impoe? [Conflict, Spec §SC-003/§FR-005 vs research §Decision 3 + quickstart §Cenario 7] {auto}
      → **[Conflict]**: SC-003 exige que a latencia "permaneca dentro do orcamento hoje praticado (~30 ms metricas / ~177 ms guarda), verificado por gate automatizado", mas o gate especificado usa tetos de **150 ms** e **400 ms** (5x o orcamento, justificado por ruido de CI). Um build pode passar no gate e ainda assim violar SC-003 como literalmente escrito. Destino: `/clarify` — separar "orcamento de projeto" de "teto de regressao do gate" no texto de SC-003/FR-005.
- [x] CHK013 - O requisito de nao-interferencia em sessoes manuais e consistente entre a spec e o delta da capability existente? [Consistencia, Spec §FR-006/§SC-004 vs §"Delta Requirements"/bash-guard-enforcement FR-006 MODIFIED] {auto}
      → Ambos afirmam a mesma restricao com o mesmo escopo, e o delta adiciona apenas a clausula "independente do backend"; nenhuma contradicao.
- [x] CHK014 - A proibicao de leitura stale esta consistente entre pesquisa, plano e contrato? [Consistencia, research §Decision 1.a; plan §Riscos; contracts/hook-active-exec.md] {auto}
      → `immutable=1` proibido nos tres: "rejeitado" (research), "proibido por contrato" (plan §Riscos), "e **proibido** neste contrato" (contrato) — com a mesma justificativa (decisao de guarda nao pode usar leitura stale).

## Protecao de dados e superficie de ataque

- [x] CHK015 - Existe requisito de que o motivo do bloqueio seja sanitizado antes de ser persistido/exibido? [Completude, contracts/hook-io.md §stdout] {auto}
      → MUST explicito: o motivo passa por `secrets-filter.sh scrub` **antes** de compor a saida (ordem scrub-antes-de-truncar preservada do comportamento atual).
- [x] CHK016 - Os requisitos garantem que a deteccao e estritamente read-only sobre o documento de estado? [Completude, plan §Technical Context/Constraints] {auto}
      → Constraint declarada: "nenhum write dentro do documento de estado"; `mode=ro`/`-readonly` no contrato; efeitos colaterais restritos a sidecars e ao `enforcement-log.jsonl`.
- [x] CHK017 - Os requisitos eliminam superficie de injecao na consulta ao backend SQLite? [Completude, plan §"Pontos positivos confirmados"; contracts/hook-active-exec.md §SEC-M1] {auto}
      → SQL constante sem interpolacao de dado externo (`SELECT status FROM execution LIMIT 1`), e SEC-M1 proibe interpolar path cru em URI `file:...` (usar `sqlite3 -readonly` ou escapar `?`, `#`, `%`).
- [x] CHK018 - Ha requisito de que a feature nao introduz saida de dados da maquina? [Completude, plan §Constitution Check Principio IV] {auto}
      → PASS registrado: nenhuma chamada de rede introduzida; sidecars locais ao state-dir; `enforcement-log.jsonl` local ao projeto.
- [x] CHK019 - O comportamento sob concorrencia com escrita transacional do orquestrador esta coberto por requisito, e nao so por nota tecnica? [Cobertura, Spec §Edge Cases (3o); contracts/hook-active-exec.md §SEC-M2] {auto}
      → Edge case explicito ("nao pode travar nem falhar de forma a violar fail-open/fail-closed"), com mitigacao vinculada (`PRAGMA busy_timeout=200`).

## Risco residual aceito (decidido pelo operador)

- [x] CHK020 - O residual do SEC-H1 (host sem instalacao global, onde `<cwd>` volta a ser o unico candidato) foi explicitamente aceito por quem detem o risco? [Risco, plan §SEC-H1 "Residual aceito"; dec-026] {humano}
      → Decidido pelo operador em `dec-026` (score 3): `aprovar-com-mitigacoes-sech1-e-task-verificacao-sech2`. Aceite ancorado no fato de que essa configuracao e identica a superficie ja existente do guard hoje.
- [x] CHK021 - Os findings Low (SEC-L1 umask do sidecar, SEC-L2 TOCTOU inerente) foram aceitos como residual em vez de silenciosamente omitidos? [Risco, plan §Findings; dec-026] {humano}
      → Ambos permanecem tabelados como findings com severidade e mapeamento OWASP; aceite coberto pelo escopo de `dec-026`. SEC-L2 e inerente (janela entre checagem e execucao) e nao removivel por desenho.
- [ ] CHK022 - O apetite de risco para o valor concreto do teto defensivo (CHK011) e do auto-teto interno (CHK006) esta definido pelo dono? [Risco, plan §SEC-H2/§SEC-M3] {humano}
      → Em aberto: `dec-026` aprovou a EXISTENCIA de ambos os mecanismos, nao os valores numericos. Decidir antes de `/execute-task` da fase 2.

## Notes

- Items `{auto}` foram resolvidos contra os artefatos com citacao rastreavel; `[x]` sem citacao seria alegacao, nao verificacao.
- Items `{humano}` marcados `[x]` foram decididos pelo operador em `dec-026` (registro auditavel no state da execucao), nao auto-marcados pelo agente.
- Gaps abertos tem destino explicito (`/clarify` ou `/create-tasks`) — ver §Follow-up no relatorio da onda.
