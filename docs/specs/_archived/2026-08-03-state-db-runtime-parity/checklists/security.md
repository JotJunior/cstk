# Security Checklist: state-db-runtime-parity

**Purpose**: Quality gate dos requisitos de seguranca — `--force` auditavel
(MEDIUM/ASI02-03 mitigado na onda 3), os 2 findings LOW do gate owasp
convertidos em itens verificaveis, varredura estatica como controle e
fail-fast de dependencia.
**Created**: 2026-08-02
**Feature**: [spec.md](../spec.md) · [plan.md §Security Review](../plan.md)

> IDs CHK011-CHK019 (continuacao da sequencia unica da feature).

## Force-acquire auditavel (FR-007, MEDIUM/ASI02-03)

- [x] CHK012 - Existe criterio VERIFICAVEL de auditabilidade do force-acquire: teste que asserta que todo force-acquire emite `diag_emit lock-force-acquired`? [Mensurabilidade, Spec §FR-007; Plan §Security Review MEDIUM/ASI02-03] {auto} — evidencia: plan.md:140-141 "teste MUST assertar que todo force-acquire emite `diag_emit lock-force-acquired`".
- [x] CHK013 - A restricao de uso do `--force` (SIGTERM + grace period como pre-condicao; nunca primeiro recurso) esta definida como CONTRATUAL com dono do enforcement explicito (contrato do abort, nao o script)? [Clareza, Spec §FR-007; Contract §2] {auto} — evidencia: contract §2 "Pre-condicao CONTRATUAL (nao verificada pelo script): SIGTERM + grace 60s antes (`feature-00c-abort.md:59-91`)".
- [x] CHK014 - A janela TOCTOU do force-acquire esta explicitamente ACEITA com referencia rastreavel (CHK072 herdado), em vez de silenciosamente ignorada? [Assumption, Plan §Security Review] {auto} — evidencia: plan.md:142-143 "janela TOCTOU herdada de CHK072 (aceita)". NOTA (onda-013): superado por dec-059/CHK019 — a janela deixou de ser aceita e passou a ser MITIGADA (lock com dono/PID); plan atualizado.
- [x] CHK019 - Aceitar a janela TOCTOU herdada (CHK072) em vez de mitiga-la (ex.: lock com dono/PID verificado) reflete o apetite de risco do produto para o freio de emergencia? [Risco, Plan §Security Review] {humano} — RESPONDIDO (block-001/dec-059, onda-013): o operador escolheu `mitigar-lock-com-dono-pid` — a janela NAO e aceita; o lock ganha dono (PID gravado na aquisicao) e o `--force` so consuma com dono comprovadamente morto ou lock legado sem owner (aviso explicito); dono vivo e sempre recusado. Refletido em spec FR-007a e plan §Security Review.

## Findings LOW do gate owasp (onda 3) como requisitos verificaveis

- [x] CHK011 - [LOW/A05] O requisito de compor o SQL do lote multi-campo EXCLUSIVAMENTE pelos helpers de escape existentes (`_sr_sql_literal`, `_sr_exec_col_lookup`, `_sr_sql_quote` → `sql_escape`+`strip_nul`), nunca interpolando `--field`/`--value` crus, esta registrado como requisito de task (F3)? [Completude, Plan §Security Review LOW/A05] {auto} — evidencia: plan.md:136-139 "MUST compor cada fragmento exclusivamente pelos helpers existentes ... (requisito de task F3)".
- [x] CHK015 - [LOW/A04] A materializacao segura esta especificada de forma verificavel: SEMPRE `mktemp` (0600), FORA do state-dir, removida por trap, jamais path previsivel? [Mensurabilidade, Plan §Security Review LOW/A04; Contract §4; Spec §FR-003] {auto} — evidencia: plan.md:144-145 + contract §4 "nunca cria arquivo dentro do state-dir (FR-003)".

## Varredura estatica como controle (FR-009b/FR-010)

- [x] CHK016 - A allowlist de prosa da varredura estatica tem criterio de manutencao especificado (onde vive, como um item novo e adicionado, quem aprova)? [Resolvido, Research Decision 5] {auto} — resolvido na FASE 1/1.1.2 (onda-006): research.md §"Mecanismo da allowlist da camada estatica (CHK016)" — tabela literal em `tests/test_state-parity-sweep.sh`, formato `<script>:<classificacao>` com comentario-justificativa, criterio codigo-real-vs-prosa operacionalizado (comentarios descartados pre-match; string de mensagem = prosa; resto = codigo real), adicao no mesmo commit + review de PR, `codigo-real` restrito ao conjunto canonico.
- [x] CHK018 - Ha requisito garantindo que a falha rapida por `sqlite3` ausente NAO caia para leitura de um `state.json` inexistente (sem fallback silencioso)? [Cobertura, Spec §Edge Cases; §FR-012] {auto} — evidencia: edge case "nunca degrada silenciosamente nem cai para leitura de um `state.json` inexistente".

## Fail-fast de dependencia (FR-012)

- [x] CHK017 - O modo de falha "sqlite3 ausente sob state-dir SQLite" define comportamento fail-fast com diagnostico citando a dependencia E referencia de governanca (carve-out do amendment 1.3.0 da constitution)? [Completude, Spec §FR-012] {auto} — evidencia: FR-012 cita o carve-out nominalmente.

## Notes

- Os 2 LOW do owasp (onda 3) estao integrados como CHK011 e CHK015, ambos
  satisfeitos na spec/plan — a verificacao de implementacao pertence as
  tasks F3/F1.
- `{humano}` CHK019 RESPONDIDO na onda-013 (block-001/dec-059): mitigar com lock dono/PID — nenhum `{humano}` em aberto neste checklist.
- `[Gap]` CHK016 resolvido na FASE 1/1.1.2 (onda-006) — ver item acima.
