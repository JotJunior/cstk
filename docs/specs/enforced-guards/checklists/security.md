# Security Checklist: enforced-guards

**Purpose**: Valida a QUALIDADE dos requisitos de seguranca das tres frentes
enforced (US1 interceptacao Bash fail-closed, US2 integridade fail-closed, US3
allowlist de hosts) — nao a implementacao. "Unit tests for English."
**Created**: 2026-07-05
**Feature**: [spec.md](../spec.md)

> Legenda: `{auto}` = resolvivel contra spec/plan/contracts (resolvido com
> citacao). `{humano}` = julgamento de risco/negocio (aberto). Marcadores de
> gap: `[Gap]` requisito ausente, `[Ambiguity]` interpretacao multipla,
> `[Conflict]` contradicao entre artefatos.

## Interceptacao enforced de Bash (US1) — fail-closed

- [x] CHK001 - O requisito de bloqueio-por-padrao quando o mecanismo de checagem falha internamente esta especificado (fail-closed, nao fail-open)? [Completude, Spec §FR-007] {auto} — SIM: FR-007 + Clarifications Q1 ("Fail-closed — o hook bloqueia o comando quando o mecanismo de checagem falha internamente, tratando a falha como equivalente a 'comando nao autorizado'").
- [x] CHK002 - O motivo de bloqueio por falha de mecanismo e requerido como distinguivel do bloqueio por violacao de regra? [Clareza, Spec §FR-007] {auto} — SIM: contract/pretooluse-hook.md prefixos `MECANISMO_FALHOU` vs `REGRA_VIOLADA`; quickstart Scenario 4 valida.
- [x] CHK003 - O escopo de "quando" o hook age esta quantificado (so execucao ativa vs toda sessao)? [Clareza, Spec §FR-006] {auto} — SIM: FR-006 + Clarifications Q2/dec-012 (opcao A): valida so quando ha state/lock ativo; sessoes interativas do operador fora do escopo (quickstart Scenario 3).
- [x] CHK004 - A deteccao de "execucao ativa" tem fonte de verdade definida? [Completude, plan §Storage / data-model EnforcementDecisionLog] {auto} — SIM: presenca de `.claude/agente-00c-state/state.json` ou `.claude/feature-00c-state/*/state.json` com status em_andamento (contract/pretooluse-hook.md Input, campo cwd).
- [x] CHK005 - O requisito de nao introduzir atraso perceptivel para comandos permitidos e mensuravel? [Mensurabilidade, Spec §FR-003/SC-004] {auto} — SIM: plan §Performance Goals orca ~200ms no caso comum, timeout 5s (data-model GuardHookRegistration.timeout); SC-004 exige 100% dos fluxos legitimos sem passo manual.
- [x] CHK006 - A preservacao da camada advisory existente (defesa em profundidade) esta explicita como requisito? [Completude, Spec §FR-005/FR-015] {auto} — SIM: FR-005 e FR-015 exigem que advisory permaneca; plan §Summary reforca "Nenhuma das tres frentes remove a camada advisory".
- [ ] CHK007 - O comportamento quando ha MULTIPLAS execucoes ativas simultaneas (agente-00c E feature-00c, ou varios feature-00c-state/<short>) esta definido para o campo `detected_execution`/`detected_execution_path`? [Gap, data-model EnforcementDecisionLog] {auto} — [Gap]: data-model diz "qual state.json disparou a deteccao" mas nao define precedencia/tie-break quando mais de um match existe. create-tasks deve definir regra (ex: first-match deterministico) ou documentar.
- [x] CHK008 - O provisionamento automatico via install/update (sem passo manual nao-documentado) esta especificado? [Completude, Spec §FR-004/FR-017/SC-006] {auto} — SIM: FR-004 + FR-017 + SC-006; plan §Source Code aponta `hooks.sh apply_guard_hooks()` + ramo em install.sh/update.sh (research Decision 9).

## Verificacao de integridade fail-closed (US2)

- [x] CHK009 - O requisito de NAO tratar ausencia de dado de integridade como sucesso esta explicito? [Clareza, Spec §FR-009] {auto} — SIM: FR-009 "MUST NOT tratar a ausencia do dado como equivalente a uma verificacao bem-sucedida"; data-model IntegrityVerificationOutcome enum `unverifiable-blocked` (default novo).
- [x] CHK010 - O caminho de bypass explicito do operador esta especificado e distinguivel do fluxo automatico? [Completude, Spec §FR-008/FR-009] {auto} — SIM: `--allow-unverified` / `CSTK_SERVE_ALLOW_UNVERIFIED=1` (quickstart Scenario 6, data-model bypass_method flag|env).
- [x] CHK011 - A regressao de bloqueio por divergencia de checksum (comportamento ja existente) esta protegida como requisito? [Consistencia, Spec §FR-010] {auto} — SIM: FR-010 "MUST ser preservado"; quickstart Scenario 7 valida que bypass NAO se aplica a mismatch (so a nao-verificavel).
- [x] CHK012 - O aviso de alta visibilidade a cada bypass (evitar fail-open silencioso por env var esquecida) esta especificado? [Clareza, plan §Threat Model] {auto} — SIM: plan Threat Model MUST "aviso de alta visibilidade em stderr toda vez que disparar" (achado owasp corrigido, dec-018/dec-019).
- [x] CHK013 - A decisao de bypass e requerida como registrada de forma revisavel posteriormente? [Completude, Spec §FR-011/SC-005] {auto} — SIM: FR-011 + SC-005; contract/enforcement-log.md linha `source:serve-integrity outcome:unverifiable-bypassed`.

## Allowlist de hosts confiaveis (US3)

- [x] CHK014 - A comparacao de host e requerida por igualdade EXATA (nao substring) para prevenir spoofing? [Clareza, contracts/trusted-hosts.md §Garantias] {auto} — SIM: contract MUST match exato + MUST NOT `case *pattern*`; cita CWE-290; rejeita `github.com.evil.com` e `evil.com/?x=github.com`.
- [x] CHK015 - A normalizacao case-insensitive e remocao de userinfo antes da comparacao estao especificadas? [Completude, contracts/trusted-hosts.md] {auto} — SIM: contract exige lowercase + userinfo removido antes de comparar; reusa `_serve_check_host_allowlist` ja testada.
- [x] CHK016 - A isencao de `file://` da checagem de host esta explicita (fluxo dev local preservado)? [Consistencia, Spec §FR-014] {auto} — SIM: FR-014 + contract §Caso file:// + quickstart Scenario 10.
- [x] CHK017 - A rejeicao ocorre ANTES de qualquer transferencia de dado (zero bytes) como requisito? [Mensurabilidade, Spec §FR-013/SC-003] {auto} — SIM: FR-013 "antes de qualquer transferencia"; SC-003 100%; quickstart Scenario 8 verifica ausencia de arquivo temporario.
- [x] CHK018 - A lista concreta de hosts confiaveis tem fonte rastreavel (nao inventada)? [Traceability, Constitution §VI] {auto} — SIM: 4 hosts (`github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `api.github.com`) de `cli/lib/serve.sh:31`, ja em producao (contracts/trusted-hosts.md); spec §Out of Scope exigia fonte, atendida.

## Auditoria e protecao de secrets (FR-016, Principio I/VI)

- [x] CHK019 - O campo `command` do log e requerido a passar por `secrets-filter.sh scrub` antes do append? [Completude, contracts/enforcement-log.md §Garantias] {auto} — SIM: contract MUST + data-model EnforcementDecisionLog "MUST passar por secrets-filter.sh scrub" (Decision 10, owasp).
- [ ] CHK020 - A ORDEM entre scrub e truncagem-a-500-chars do `command` esta especificada (scrub-antes-de-truncar evita cortar token deixando secret parcial)? [Ambiguity, data-model EnforcementDecisionLog] {auto} — [Ambiguity]: data-model diz "truncado a 500 chars; MUST passar por secrets-filter.sh scrub antes do append" mas NAO fixa a ordem relativa. Truncar antes de scrub pode partir um token e escapar do regex. create-tasks deve fixar scrub-entao-truncar.
- [x] CHK021 - O log e append-only e imutavel como requisito de auditoria? [Completude, contracts/enforcement-log.md §Garantias] {auto} — SIM: contract "Append-only... sempre >> no fim"; data-model State Transitions "N/A — append-only, sem update/delete".
- [x] CHK022 - Falha ao escrever o log NAO compromete a decisao de bloqueio/permissao (log e auditoria, nao gate)? [Consistencia, contracts/pretooluse-hook.md §Efeito colateral] {auto} — SIM: contract "Falha ao escrever o log NAO MUST impedir a decisao... best-effort logada em stderr".
- [x] CHK023 - Todo evento de enforcement (bloqueio US1, bypass US2, rejeicao US3) e requerido auditavel, nao so visivel em terminal? [Cobertura, Spec §FR-016/SC-005] {auto} — SIM: FR-016 cobre as 3 frentes; SC-005 "revisaveis... nao apenas visiveis momentaneamente".

## Threat model e limites declarados

- [x] CHK024 - O que a feature NAO protege esta declarado explicitamente (nao alegar garantia mais forte que a real)? [Clareza, plan §Threat Model / Spec §US1-AS3] {auto} — SIM: plan Threat Model declara que adulteracao deliberada de settings.json por quem ja tem acesso de escrita esta fora do modelo (research Decision 11).
- [ ] CHK025 - O apetite de risco por deixar retencao/rotacao do `enforcement-log.jsonl` fora da v1 (arquivo cresce sem limite) e aceitavel para o dono do produto? [Risco, contracts/enforcement-log.md §Garantias] {humano} — decisao do dono: contract registra como "possivel debito tecnico futuro"; spec nao tem FR de retencao. Aguardando ratificacao de que crescimento ilimitado do log e aceitavel na v1.

## Notes

- Items `{auto}` resolvidos: 22 (`[x]` com citacao).
- Items abertos para consumo do create-tasks: CHK007 [Gap], CHK020 [Ambiguity].
- Item `{humano}` aguardando dono do produto: CHK025 (risco de retencao de log).
