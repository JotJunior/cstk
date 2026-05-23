# Security Checklist: model-selector

**Purpose**: Quality gate para os REQUISITOS de seguranca, confinamento
e zero coleta remota — Principio IV da constitution do toolkit. Items
validam se a *spec* + *plan* exprimem com clareza suficiente como o
zero-rede, o confinamento de `jq`, a ausencia de spawn de subagente, o
tratamento defensivo de input do operador e o registro auditavel das
sugestoes serao verificados. NAO testam implementacao.
**Created**: 2026-05-21
**Feature**: [`../spec.md`](../spec.md) | [`../plan.md`](../plan.md)
**Dominio**: security (zero-rede + confinamento + auditabilidade)
**Soft cap**: 25 items
**Numeracao**: continua de skill.md (CHK045) → CHK046..

---

## Zero coleta remota (Principio IV)

- [ ] CHK046 - O requisito "zero invocacoes externas de rede" (FR-016 / SC-005) define EXATAMENTE quais primitivas constituem "rede" (curl, wget, nc, /dev/tcp, ssh, getent hosts, dig, host, busca DNS) ou apenas a tripla `curl|wget|http`? [Gap, Spec §FR-016, Spec §SC-005]
- [ ] CHK047 - Sao os requisitos de exclusao "exceto comentarios" (SC-005) consistentes com a verificacao automatizada proposta (`grep -rn 'curl\\|wget\\|http'`)? grep nao distingue comentario de codigo — risco de falso positivo. [Consistencia, Spec §SC-005, Plan §Constitution Check]
- [ ] CHK048 - Pode o requisito "zero rede" ser estendido para deteccao em transitive deps (jq carrega lib que faz lookup DNS?) ou e checado apenas em arquivos da propria skill? [Ambiguity, Spec §FR-016]
- [ ] CHK049 - O requisito de teste `test_model_selector_zero_rede.sh` (Plan §Project Structure) define o mecanismo de bloqueio (unshare network namespace? sandbox? grep estatico?) ou e nome de arquivo sem contrato? [Gap, Plan §Project Structure]

## Confinamento de jq (FR-010a)

- [ ] CHK050 - O requisito "jq confinado em UM arquivo identificavel" (FR-010a (b)) define EXATAMENTE quais expansoes do termo `jq` contam (`jq`, `\bjq\b`, `jq-1.6`, alias `j`)? Plan menciona apenas `grep -rn '\\bjq\\b'`. [Ambiguity, Spec §FR-010a, Plan §Conformidade]
- [ ] CHK051 - Sao os requisitos do teste `test_report_jq_confinement.sh` (Plan §Project Structure) declarados (exit non-zero se >1 arquivo cita jq? exit zero se arquivo unico = scripts/report.sh?) ou apenas nome de arquivo? [Gap, Plan §Conformidade]
- [ ] CHK052 - O requisito de declaracao em "3 lugares concretos" (FR-010a (c): spec, plan, research) define criterio de aceite por lugar (texto mencionado vs. secao dedicada vs. tabela formal) ou e mera contagem? [Mensurabilidade, Plan §Conformidade]
- [ ] CHK053 - Sao os requisitos de exclusao da regra de confinamento (CHANGELOG.md cita jq — conta como violacao? README cita — conta?) ou apenas codigo executavel? [Ambiguity, Spec §FR-010a]

## Blast radius confinado (sem spawn, sem efeito colateral)

- [ ] CHK054 - O requisito "skill nao spawna subagente" (Gotcha FR-013e + Edge Case "loop") tem criterio operacional verificavel (grep por `Task`, `Agent`, `claude-code`, `subagent`)? [Mensurabilidade, Spec §FR-013, Spec §Edge Cases]
- [ ] CHK055 - Sao os requisitos "informativa, nunca prescritiva" (FR-006: nao chama `/model`, nao manipula estado de sessao) consistentes entre FR-006, Gotcha (a) FR-013, e Decision 3 do research? [Consistencia, Spec §FR-006, Spec §FR-013, Plan §Summary]
- [ ] CHK056 - O requisito de leitura read-only do state.json no `report.sh` (FR-012) tem criterio (nenhum `>`, `>>`, `tee`, `cp -f`, `mv` no script) ou apenas afirmacao? [Mensurabilidade, Spec §FR-012]
- [ ] CHK057 - Sao os requisitos de "single-shot por invocacao" (Edge Case loop + Principio IV) consistentes com a ausencia de estado proprio (FR-015 N/A explicito)? [Consistencia, Spec §FR-015, Spec §Edge Cases]

## Tratamento defensivo de input

- [ ] CHK058 - O requisito "input rejeita null-byte" (Plan §Security) define o comportamento esperado (silencioso? exit code N? stderr? sanitiza e processa?) ou apenas a regra? [Ambiguity, Plan §Technical Context]
- [ ] CHK059 - Sao os requisitos para input contendo metacaracteres do shell (`$`, `` ` ``, `\\`, `;`, `&&`) tratados explicitamente ou apenas implicitos em "sem eval"? [Gap, Plan §Technical Context]
- [ ] CHK060 - O requisito "sem find sobre paths derivados do input" (Plan §Security) inclui paths construidos via concatenacao indireta (variavel intermediaria, expansao de glob)? [Ambiguity, Plan §Technical Context]
- [ ] CHK061 - Sao os requisitos de limite de tamanho do input (1KB? 10KB? sem limite?) declarados ou diferidos? Sem limite = risco de DoS local via input gigante. [Gap, Spec §FR-001, Plan §Technical Context]
- [ ] CHK062 - O requisito de input "tokens minimos = 3 → manter-atual score 0" (Decision 7) define o que conta como token (resultado do `tr` de Decision 2) e e robusto contra unicode/multibyte? [Ambiguity, Plan §Summary]

## Auditabilidade da Decisao (FR-007/FR-009)

- [ ] CHK063 - O requisito "Decisao auditavel com 5 campos obrigatorios + score 0..3 + justificativa" (FR-007) cita explicitamente os 5 campos (contexto, opcoes, escolha, justificativa, agente) ou delega ao runtime sem listar? [Gap, Spec §FR-007]
- [ ] CHK064 - Sao os requisitos de "rejeitar sem justificativa = violacao FR-EVI-001" (FR-009) verificaveis (state-decisions.sh rejeita score 3 sem evidencia; mas score 2 sem justificativa?) ou ficam dependentes do runtime? [Consistencia, Spec §FR-009]
- [ ] CHK065 - O requisito de "referencia ao SugestaoDeModelo originador" (Key Entities) define o formato (id de sugestao? hash do JSON? cita literal?) ou apenas conceito? [Ambiguity, Spec §Key Entities]
- [ ] CHK066 - Sao os requisitos de persistencia em `metricas_acumuladas.model_selector` (FR-011) tolerantes a corrupcao do state.json (campo inexistente, tipo errado, JSON malformado)? [Gap, Spec §FR-011]

## Score 3 e evidencia empirica (FR-002 / FR-EVI-001)

- [ ] CHK067 - O requisito "teto pratico = 2 na heuristica auto-invocada" (FR-002b / dec-006) define o que mudaria para destravar score 3 (qual heuristica empirica seria aceita)? [Ambiguity, Spec §FR-002]
- [ ] CHK068 - Sao os requisitos de "evidencia empirica = comando + output literal" (FR-EVI-001 referencia indireta via runtime) declarados no spec da feature ou apenas no runtime? Risco de Gotcha FR-013d ser informativo demais. [Gap, Spec §FR-013]
- [ ] CHK069 - O requisito "match de verbo no input nao satisfaz FR-EVI-001" (dec-006) tem teste correspondente (input com verbo + assercao de score <=2)? [Cobertura, Spec §FR-002, Plan §Project Structure]

## Falsos positivos e fail-safe

- [ ] CHK070 - O requisito SC-006 "zero falsos positivos haiku em verbos de design" cobre TODOS os 4 verbos listados (refatore, projete, arquitete, escolha) com teste discreto, ou agrega num so? [Cobertura, Spec §SC-006]

## Notes

- Marcar items concluidos com `[x]`
- Numeracao continua de skill.md (terminou em CHK045) — proxima onda /create-tasks nao gera CHKs
- Rastreabilidade: 25/25 items com referencia explicita = 100%
- Dimensoes cobertas: Gap (8), Ambiguity (8), Mensurabilidade (4), Consistencia (3), Cobertura (2)
- Items deferidos para `/analyze`: cross-check de consistencia spec ↔ plan ↔ research ↔ contracts/ ↔ data-model
