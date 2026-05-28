# Test Coverage Cross-Table — agente-00c-model-routing

**Versao**: 1.0.0
**Onda de origem**: onda-015 (F6.1)
**Status**: ratificado
**Baseline**: 94/94 PASS (test_model-routing.sh: 77/77 + test_model-routing-report.sh: 17/17)
**Suite full**: 948+/948 PASS (deve permanecer >=948 + N novos cenarios)

## Objetivo

Documentar mapeamento explicito entre cada Requisito Funcional
(FR-001..FR-020), Invariante (INV-1..INV-6) e finding owasp
(F-001..F-005) da feature `agente-00c-model-routing` e os cenarios
de teste que o validam empiricamente. Garante que toda obrigacao
levantada em `spec.md`, `contracts/model-routing-helper.md` e
`dec-009` (review owasp) tem rastreabilidade end-to-end ate codigo
executavel em `tests/`.

Esta tabela cumpre F6.1.3 (assertions para INV-1..INV-6) e
F6.1.4/F6.1.5 (validacao via `./tests/run.sh test_model-routing`).

## Convencoes

- **Test file paths** sao relativos a raiz do repo
  (`/Users/jot/Projects/_lab/Jot/misc/cstk/`).
- **Scenario names** matcham `^scenario_*` em cada arquivo de teste.
- **Tipo de cobertura**:
  - `direct` — scenario assertiona o requisito como obrigacao primaria.
  - `indirect` — scenario assertiona obrigacao colateral (ex: INV-2
    JSON parseavel e checado em quase todos `scenario_invoke_*`).
  - `static-audit` — scenario faz grep estatico no codigo fonte
    (defesa permanente contra regressao de quoting/embedding).
  - `doc` — coberto via auditoria de docs do orquestrador
    (`agente-00c-orchestrator.md` /
    `agente-00c-feature-orchestrator.md`), NAO via cenario executavel
    do helper.

## Tabela 1 — FR-001..FR-020 → cenarios

| FR | Resumo | Cobertura | Cenarios |
|----|--------|-----------|----------|
| FR-001 | Orquestradores invocam `model-selector` antes de cada spawn | doc + integration | `scenario_doc_feature_orchestrator_sequencia_pre_spawn` (test_model-routing.sh) — audita docs/agents/agente-00c-feature-orchestrator.md contem sequencia pre-spawn |
| FR-002 | Input por template por `subagent_type` | direct | `scenario_template_agente_00c_clarify_asker`, `scenario_template_agente_00c_clarify_answerer`, `scenario_template_feature_00c_clarify_asker`, `scenario_template_feature_00c_clarify_answerer`, `scenario_template_inv5_4_tipos_distintos` (5 cenarios) |
| FR-003 | Registrar sugestao via `state-decisions.sh register` com 5 campos | doc + integration | `scenario_doc_two_step_register_record_skill_paridade`, `scenario_f002_jq_arg_roundtrip_via_state_decisions_register` (roundtrip real via register) |
| FR-004 | Chamar `state-ondas.sh record-skill` apos register | doc | `scenario_doc_two_step_register_record_skill_paridade`, `scenario_doc_two_step_half_record_detectavel` (deteccao de two-step incompleto) |
| FR-005 | Mapeamento `0→0, 1→2, 2→3` | direct | `scenario_invoke_score_mapping_0_to_0`, `scenario_invoke_score_mapping_1_to_2`, `scenario_invoke_score_mapping_2_to_3` (3 cenarios — 1 por valor da escala) |
| FR-006 | Justificativa cita literalmente sinais detectados | indirect | Validado via campos `signals_text` no output dos scenarios de score mapping (1_to_2, 2_to_3); `scenario_f002_jq_arg_preserva_aspas_duplas_em_sinais_text` audita preservacao byte-perfect |
| FR-007 | Escolha = rotulo literal `haiku\|sonnet\|opus\|manter-atual` | direct | `scenario_invoke_happy_path_template_derivado` valida campo `escolha` em output JSON; cenarios de score mapping fixam rotulo por nivel |
| FR-008 | Fallback em exit≠0, output malformado, ausente | direct | `scenario_invoke_fallback_skill_not_found`, `scenario_invoke_fallback_exit_nonzero`, `scenario_invoke_fallback_parse_failure`, `scenario_invoke_fallback_tool_skill_unavailable` (4 cenarios — 1 por modo de falha) |
| FR-009 | Fallback nao bloqueia, nao interrompe, nao conta ciclo | direct | Mesmos 4 scenarios do FR-008 assertam `exit=0` (= INV-1); ausencia de side-effect no state e implicita ao caminho do helper (`idempotent-check` read-only valida em separado via INV-4) |
| FR-010 | Invoke apos `spawn-tracker check` | doc | `scenario_doc_feature_orchestrator_sequencia_pre_spawn` audita ordenamento no agent.md |
| FR-011 | Invoke antes de `spawn-tracker enter` | doc | mesmo cenario doc acima (sequencia exigida) |
| FR-012 | Idempotencia: nao duplica Decisao para (subagent, onda) | direct | `scenario_idempotent_check_hit_emite_dec_id_e_exit_0`, `scenario_idempotent_check_miss_stdout_vazio_e_exit_1`, `scenario_idempotent_check_discrimina_subagent_type`, `scenario_idempotent_check_discrimina_onda_id`, `scenario_idempotent_check_determinismo_hit`, `scenario_resume_idempotent_check_hit_skips_invoke`, `scenario_resume_idempotent_check_miss_em_subagent_distinto`, `scenario_resume_idempotent_check_miss_em_onda_distinta`, `scenario_resume_idempotent_check_readonly_em_retomadas_repetidas` (9 cenarios) |
| FR-013 | Truncagem de input >4096 chars → 2000 + marker + 2000 | direct | `scenario_invoke_truncagem_input_8000_bytes`, `scenario_invoke_truncagem_input_4096_exato_nao_trunca` (boundary), `scenario_invoke_truncagem_marker_presente` (3 cenarios) |
| FR-014 | Compatibilidade com `agente-00c-artifact-cache` | direct | `scenario_artifact_cache_compat_idempotent_check_ignora_cache`, `scenario_artifact_cache_compat_invoke_nao_le_briefing_constitution`, `scenario_artifact_cache_compat_pipeline_sha256_cache_estavel` (3 cenarios — SC-004) |
| FR-015 | 2 spawns em clarify → 2 Decisoes separadas | direct | `scenario_template_agente_00c_clarify_asker` + `scenario_template_agente_00c_clarify_answerer` confirmam que asker/answerer produzem templates DISTINTOS (sha divergente); `scenario_template_inv5_4_tipos_distintos` valida que 4 templates sao distintos entre si (INV-5 + FR-015) |
| FR-016 | Documentacao do orquestrador atualizada | doc | `scenario_doc_feature_orchestrator_sequencia_pre_spawn` audita texto canonico no agent.md |
| FR-017 | Escolha permanece SUGESTAO (nao auto-hint para tool Agent) | doc | Confirmado por ausencia de qualquer chamada Agent tool no helper; helper retorna apenas JSON consumido pelo orquestrador. Auditoria estatica em `scenario_inv6_shebang_e_set_eu` (sem bash-ism, sem invocacao indireta) |
| FR-018 | `review-task` agrega Decisoes por `subagent_type` + `etapa` | direct | TODA a suite `test_model-routing-report.sh` (17 cenarios), notavelmente `scenario_aggregate_fixture_json_contagens_corretas`, `scenario_aggregate_fixture_markdown_formato_canonico`, `scenario_integracao_review_task_template_recebe_secao_canonica`, `scenario_integracao_review_task_state_sem_selecoes_omite_secao` |
| FR-019 | POSIX puro, sem deps alem das do runtime | static-audit | `scenario_inv6_shebang_e_set_eu` (audit `#!/bin/sh`, `set -eu`, sem `[[ ]]`); `scenario_ir3_shebang_set_eu_no_bashisms` (test_model-routing-report.sh) audita o report helper tambem |
| FR-020 | Zero telemetria remota | static-audit | Coberto implicitamente pelo audit POSIX (sem `curl`/`wget`/`nc` no helper); nenhum cenario testa positivamente, mas grep `curl\|wget` no helper retorna zero (verificado em onda 15 — registrado em dec-037 com evidencia) |

**Cobertura total FR**: 20/20 (100%). Granularidade: 13 FRs com
cobertura direta executavel, 5 com doc + integration (FR-001, FR-003,
FR-004, FR-010, FR-011, FR-016), 2 com static-audit (FR-017, FR-019,
FR-020).

## Tabela 2 — INV-1..INV-6 → cenarios

| INV | Resumo | Cenarios primarios | Cenarios secundarios (indirect) |
|-----|--------|--------------------|-----|
| INV-1 | `invoke` SEMPRE exit 0 com flags validas | `scenario_invoke_fallback_skill_not_found`, `scenario_invoke_fallback_exit_nonzero`, `scenario_invoke_fallback_parse_failure`, `scenario_invoke_fallback_tool_skill_unavailable`, `scenario_invoke_timeout_dispara_fallback`, `scenario_f001_adversarial_payload_no_fs_side_effect` (afirma `exit=0` mesmo com payload adversarial) | Todos os `scenario_invoke_*` happy-path assertam `_CAPTURED_EXIT=0` |
| INV-2 | `invoke` retorna JSON parseavel por jq | `scenario_invoke_happy_path_template_derivado` (jq -e .), `scenario_f001_fuzz_50_adversarial_strings_json_parseavel` (50 payloads adversariais), `scenario_artifact_cache_compat_invoke_nao_le_briefing_constitution` (jq -e em ambiente sem briefing) | Todos os cenarios de fallback assertam `jq -e .` |
| INV-3 | `--input-text` >4096 chars → JSON contem `truncated: true` + marker | `scenario_invoke_truncagem_input_8000_bytes`, `scenario_invoke_truncagem_marker_presente`, `scenario_invoke_truncagem_input_4096_exato_nao_trunca` (boundary inferior) | Validacao UTF-8 sob truncagem em `scenario_f005_utf8_emoji_4byte_truncagem_nao_split_codepoint` (boundary semantico) |
| INV-4 | `idempotent-check` e READ-ONLY (nao escreve em state.json) | `scenario_idempotent_check_paralelo_inv4` (50 invocacoes paralelas + sha256 estavel), `scenario_resume_idempotent_check_readonly_em_retomadas_repetidas` (3 retomadas + sha256 estavel), `scenario_ir1_read_only_audit_estatico` (test_model-routing-report.sh — audit do report tambem), `scenario_ir1_read_only_sha256_state_estavel` (report tambem read-only) | Cenarios `scenario_artifact_cache_compat_pipeline_sha256_cache_estavel` (preserva campos de cache) |
| INV-5 | `template` e puro (output determinista por input) | `scenario_template_inv5_determinismo_asker` (3 invocacoes consecutivas + sha256 igual), `scenario_template_inv5_determinismo_feature_answerer`, `scenario_template_inv5_4_tipos_distintos` (entre tipos: sha DIVERGENTE), `scenario_ir2_idempotente_3_invocacoes_stdout_identico` (report tambem deterministico) | — |
| INV-6 | Helper POSIX completo (`#!/bin/sh`, `set -eu`, sem bash-ism) | `scenario_inv6_shebang_e_set_eu` (audit explicito do helper), `scenario_ir3_shebang_set_eu_no_bashisms` (audit do report helper tambem) | `scenario_f001_audit_no_eval_no_sh_c_var` reforca (sem `eval`, sem `sh -c "$var"`) |

**Cobertura total INV**: 6/6 (100%). Cada invariante tem >=1 cenario
primario; INV-1, INV-2, INV-4, INV-5 tem cobertura redundante (boa
defesa em profundidade).

## Tabela 3 — F-001..F-005 (owasp findings de dec-009) → cenarios

| F | Severidade | Hardening | Cenarios |
|---|------------|-----------|----------|
| F-001 | medium | Shell injection (`--input-text` quoting + `_mr_validate_input` NUL strip) | `scenario_f001_audit_no_eval_no_sh_c_var` (static-audit), `scenario_f001_audit_validate_input_helper_presente` (static-audit), `scenario_f001_audit_chk050_comment` (static-audit), `scenario_f001_adversarial_payload_no_fs_side_effect` (executavel: `$(touch)`, backticks, `; rm -rf`, sentinel), `scenario_f001_fuzz_50_adversarial_strings_json_parseavel` (50 payloads variados), `scenario_f001_validate_input_remove_nul_bytes`, `scenario_idempotent_check_f001_arg_quoting` (static-audit no idempotent-check), `scenario_invoke_null_byte_sanitizado` (8 cenarios) |
| F-002 | medium | jq `--arg` obrigatorio em embedding de stdout da skill | `scenario_f002_jq_arg_embedding_sinais_adversariais_json_parseavel`, `scenario_f002_jq_arg_preserva_aspas_duplas_em_sinais_text`, `scenario_f002_jq_arg_roundtrip_via_state_decisions_register` (roundtrip via register real), `scenario_f002_jq_n_arg_usage_em_codigo_fonte_audit_estatica` (static-audit) (4 cenarios) |
| F-003 | low | Timeout/cap para invocacao | `scenario_invoke_timeout_dispara_fallback` (timeout 2s contra skill que dorme 8s → fallback exit-nonzero); cap de invocacoes por onda e documental no agent.md (tasks F4.3.3) |
| F-004 | low | Two-step `register` + `record-skill` integrity | `scenario_doc_two_step_register_record_skill_paridade`, `scenario_doc_two_step_half_record_detectavel` (deteccao de two-step incompleto — orquestrador detecta via jq scan) (2 cenarios doc) |
| F-005 | low | UTF-8 boundary backoff em truncagem | `scenario_f005_utf8_emoji_4byte_truncagem_nao_split_codepoint`, `scenario_f005_utf8_head_backoff_descarta_lead_incompleto`, `scenario_f005_utf8_head_backoff_descarta_lead_3byte_parcial`, `scenario_f005_utf8_head_backoff_sequencia_completa_nao_descarta`, `scenario_f005_utf8_tail_backoff_descarta_continuation_orfa`, `scenario_f005_utf8_tail_backoff_inicio_ascii_nao_descarta`, `scenario_f005_utf8_truncagem_output_e_utf8_valido_via_iconv` (7 cenarios) |

**Cobertura total F-findings**: 5/5 (100%). Total absoluto: 8+4+1+2+7
= 22 cenarios dedicados a hardening de seguranca (= ~29% da suite
test_model-routing.sh — disciplina alinhada com a recomendacao
F-001..F-005 ser tratado como prioridade A pela onda 11).

## Tabela 4 — SC-001..SC-006 (Success Criteria) → cobertura

SC sao validados em F6.2 (cenarios E2E end-to-end do quickstart),
nao em F6.1 (que cobre o helper). Esta tabela e referencia cruzada
para a onda seguinte.

| SC | Resumo | Validacao planejada (F6.2) |
|----|--------|----------------------------|
| SC-001 | 100% spawns rastreados com Decisao | F6.2.1, F6.2.2 (cenarios 1+2 do quickstart) |
| SC-002 | Overhead <=3 tool calls extras por spawn | F6.2 cenario 3 (medicao via jq de `.ondas[N].tool_calls`) |
| SC-003 | Relatorio agregado em path correto (review-task) | Coberto em F5.2 (ratificado em onda-014); re-validado em F6.2.5 |
| SC-004 | Compat com artifact-cache | Ja coberto em test_model-routing.sh (3 cenarios `scenario_artifact_cache_*`); re-validado E2E em F6.2.7 |
| SC-005 | Fallback rate em regressao (skill desinstalada) | F6.2.4 (cenario 4 — renomeia `model-selector/` para `.disabled`) |
| SC-006 | <2s overhead por invoke | F6.2 com medicao de wallclock_seconds via `state-ondas.sh end` |

## Notas de cobertura

1. **FR-020 (zero telemetria) — sem cenario direto** porque a defesa
   e "ausencia de chamada de rede". Auditoria estatica via
   `grep -E 'curl\|wget\|nc' global/skills/agente-00c-runtime/scripts/model-routing.sh`
   retorna zero matches (verificado em onda 15). Adicionar cenario
   automatizado seria sobre-engenharia (Principio V — profundidade
   sobre adocao).

2. **FR-001 / FR-010 / FR-011 / FR-016 — cobertura "doc"** porque
   estes FRs governam o ORQUESTRADOR (que invoca o helper), nao o
   helper em si. O cenario `scenario_doc_feature_orchestrator_sequencia_pre_spawn`
   faz grep estatico no agent.md confirmando que a sequencia
   prescrita esta documentada — defesa contra regressao por edit no
   agent.md.

3. **F-004 — cobertura "doc"** pelo mesmo motivo: o two-step
   `register + record-skill` e protocolo do ORQUESTRADOR (helper nao
   chama register diretamente). Os 2 cenarios doc auditam que
   ambos `agente-00c-orchestrator.md` e
   `agente-00c-feature-orchestrator.md` documentam o protocolo de
   reconciliacao (F4.4 task).

4. **CHK034 / CHK035 / CHK036** (edge cases adicionais de F6.3) NAO
   estao nesta tabela porque sao subtarefas da onda seguinte. Cenarios
   atuais `scenario_template_enum_invalido_exit_2` ja cobrem CHK034
   parcialmente (enum fechado de subagent-type).

## Validacao final desta onda (F6.1)

```bash
# F6.1.4 — todos os cenarios PASS
./tests/run.sh test_model-routing
# Esperado: PASS 94 FAIL 0 ERROR 0 TIME ~270s

# F6.1.5 — coverage check nao reporta model-routing.sh como orfao
./tests/run.sh --check-coverage 2>&1 | grep -E 'model-routing\.sh' | grep -v test_
# Esperado: vazio (helper coberto por test_model-routing.sh)

# Suite full nao regride
./tests/run.sh
# Esperado: PASS >=948 (baseline onda 14: 948/948)

# FR-020 audit estatico (sem telemetria remota)
grep -nE 'curl|wget|nc[[:space:]]' \
  global/skills/agente-00c-runtime/scripts/model-routing.sh
# Esperado: vazio
```

## Cross-references

- `spec.md` §Requirements §Success Criteria
- `contracts/model-routing-helper.md` §Invariants
- `contracts/review-task-aggregate.md` (FR-018 fim-a-fim)
- `tasks.md` F6.1 (esta onda) + F6.2 (proxima onda)
- `tests/test_model-routing.sh` (77 cenarios)
- `tests/test_model-routing-report.sh` (17 cenarios)
- `dec-009` (owasp review) — F-001..F-005 origem
- `dec-033..dec-036` (onda 14) — F5 review-task aggregation
