# Security Checklist: Ranking Composto no cstk recall

**Purpose**: Validar a qualidade dos requisitos com implicacao de seguranca
desta feature (superficie de injecao via literal interpolado, amplificacao
de memory poisoning, degradacao silenciosa de erro) — nao reexecuta o gate
`owasp-security` ja rodado sobre `plan.md` (2 rodadas, zero HIGH
remanescente), apenas audita se os requisitos de `spec.md` capturam
corretamente o que foi decidido.
**Created**: 2026-08-20
**Feature**: [spec.md](../spec.md)

## Input Validation / Injection

- [x] CHK001 - A spec ou o plano definem, de forma normativa, que nao ha entrada de operador nem variavel de ambiente interpolada na consulta SQL de ranking? [Clareza, Plan §Riscos F1] {auto} — F1 (HIGH) foi fechado por **eliminacao de superficie**: `bloqueio_humano` `block-002` respondido em `dec-021` (opcao B — sem env var; fixture com `source_ts` relativos ao relogio real); `contract §3` normatiza a ausencia como I-12/I-13.
- [x] CHK002 - O unico valor interpolado sem escaping previo (instante de referencia) segue a mesma politica de escaping ja aplicada aos demais literais do arquivo? [Consistencia, Plan §Findings F10] {auto} — finding F10 (MEDIUM) da 2a rodada do gate de seguranca foi tratado com clausula normativa "Escaping cumulativo do literal" no contrato §3.1, alinhando ao precedente ja medido no codigo (L1384).

## Robustez / Disponibilidade

- [ ] CHK003 - Existe um requisito, no proprio `spec.md`, sobre o limite superior do bonus de recencia quando o dado de entrada (`source_ts`) e anomalo (futuro, clock skew)? [Edge Case, Gap] {auto} — **[Gap]** (mesmo achado de `requirements.md` CHK020): o clamp `max(0.0, ...)` que impede o bonus de explodir (`~900` medido sem clamp, finding F2 HIGH) e normativo apenas em `plan.md`/`contracts/cstk-recall-ranking.md`, nao em `spec.md`. Ja mitigado tecnicamente; item registrado para rastreabilidade cross-checklist.
- [x] CHK004 - O comportamento em falha da dependencia de tempo (`date -u`) esta definido de forma que a degradacao seja previsivel, nao dependente do implementador? [Completude, Plan §Findings F11] {auto} — finding F11 (MEDIUM) resultou em clausula normativa "Falha do `date`" no contrato §3.1: fallback fixo `1970-01-01T00:00:00Z`, consistente com 4 usos ja existentes no arquivo (L1273/L2203/L2803/L2866).
- [x] CHK005 - Uma falha de query SQL e distinguivel, nos requisitos, de "nenhum resultado encontrado" (para nao mascarar erro como resultado vazio)? [Completude, Plan §Riscos F7] {auto} — invariante I-10 do contrato exige checar o exit do `sqlite3` separadamente e emitir aviso (`log_warn`); tratado explicitamente como risco de seguranca (F7) e nao apenas robustez cosmetica, porque o read-back loop dos orquestradores decidiria com memoria incompleta sem perceber.

## Threat Modeling / Risco Aceito

- [x] CHK006 - O risco de amplificacao de memory poisoning via reforco de autoridade do tipo `memory` esta documentado com o vetor de ataque explicito (nao apenas "seguro por padrao")? [Traceability, Plan §Riscos F6] {auto} — F6 documenta o vetor completo: `type` e "escolhivel por quem escreve o `state.json`", o bonus `+0.30` "promove justamente o tipo mais facil de forjar", no canal `--limit 4` que "alimenta prompt de agente autonomo" — nada omitido ou suavizado.
- [x] CHK007 - Os controles compensatorios do risco aceito (F6) sao descritos com os limites honestos deles, evitando alegar protecao que nao existe? [Clareza, Plan §Riscos F6] {auto} — o proprio plano declara o limite: "o rotulo sinaliza, mas nao impede a selecao" — nao ha alegacao de mitigacao completa, coerente com o Principio de veracidade (Constitution VI).
- [ ] CHK008 - O risco aceito F6 (MEDIUM) tem ratificacao formal do dono do produto como Decisao auditavel, distinta de apenas constar na prosa do plano? [Risco, Plan §"Findings HIGH"] {humano} — duplicata intencional de CHK027 em `requirements.md`: o plano relata que a aceitacao "foi promovida a Decisao auditavel propria nesta onda", mas a confirmacao final de que essa e a postura desejada do produto (aceitar sem mitigacao adicional nesta feature) permanece decisao humana, nao uma verificacao que o agente possa fechar sozinho.

## Notes

- Este checklist e complementar ao gate `owasp-security` ja executado sobre
  `plan.md` (2 rodadas — ver `plan.md` §"Resultado dos Quality Gates da fase
  `plan`"): aqui valida-se apenas se os requisitos/decisoes resultantes
  daquele gate estao coerentemente capturados como requisito, nao se
  reexecuta a analise de vulnerabilidade em si.
- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`). Items `{humano}` ficam `[ ]` aguardando decisao do
  dono do produto.

### Resolucao

- **{auto} resolvidos**: 6 (`[x]` com evidencia citada)
- **{humano} aguardando decisao**: 1 (CHK008)
- **Gaps abertos**: 1 (CHK003 — `[Gap]`, mesmo achado de CHK020 em `requirements.md`)

### Proximos Passos

- CHK008 — confirmar com o dono do produto que a Decisao de risco aceito (F6) referida no plano e suficiente, sem exigir mitigacao adicional nesta feature.
- CHK003 — mesmo destino de CHK020 em `requirements.md` (`/create-tasks` pode registrar tarefa de teste do clamp; comportamento ja mitigado no plano/contrato).
- `/create-tasks` — decompor este plano em backlog executavel.
