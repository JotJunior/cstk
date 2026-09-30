# Referencia de fase: create-tasks (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   ### 5.c Create-tasks (skill obrigatoria + validacao de formato)

   Proibido escrever `tasks.md` direto. Sequencia:

   1. Invoque `Skill(skill="create-tasks", args="<spec + plan paths>")`
      — args tambem cita o tier de entrega vigente, lido exclusivamente
      via `delivery-tier.sh get --state-dir <SD>` (INV-5). Distinto da
      calibracao de profundidade de `briefing`/`specify`/`plan`
      (FR-004, ver **5.d.quater**): aqui o tier alimenta a divisao
      BINARIA nuvem/nao-nuvem do backlog (FR-006, ver `create-tasks/
      SKILL.md` §Organizacao de Fases).
   2. Registre invocacao:
      ```bash
      state-ondas.sh record-skill --state-dir <SD> --skill create-tasks \
        --decisao-id <dec-NNN>
      ```
   3. Valide via `pipeline.sh detect-completion --stage create-tasks` —
      primitiva roda `_pl_validate_tasks` (header + FASE + legendas
      `[C]/[A]/[M]` + Matriz Dependencias + Resumo Quantitativo +
      Escopo Coberto + Escopo Excluido).
   4. Falha de validacao = registre Decisao + tentativa de Edit para
      adicionar secoes faltantes OU re-invoque a skill com prompt
      explicito sobre o template (`plugins/cstk/skills/create-tasks/templates/tasks.md`).
      Nao avance a etapa enquanto detect-completion exit != 0.

<!-- FRAGMENT:quality-gates:BEGIN -->
   ### 5.f Quality Gates complementares (pos-artefato, nao-bloqueantes)

   Apos `detect-completion` confirmar artefato de uma das etapas abaixo,
   invoque a skill-gate correspondente como auditoria de qualidade. Os
   gates produzem RELATORIOS e FINDINGS — eles nao bloqueiam a pipeline
   por padrao, mas findings de severidade `critical`/`high` DEVEM virar
   Decisao informativa (e, conforme criterio do orquestrador, podem
   escalar para BloqueioHumano).

   Cada invocacao registra `state-ondas.sh record-skill` para que
   `/review-task` e `/review-features` consigam medir cobertura de gates.

   **Higiene da metrica (`--kind`)**: registre `--kind gate` para gates
   DETERMINISTICOS de script (ex.: `validate-tasks-template.sh`) e o
   default `--kind skill` (omitido) APENAS para invocacoes reais da tool
   Skill. NUNCA registre comandos de build/test/lint (`go build`,
   `eslint`, `tsc` etc.) via record-skill — isso poluia a tabela
   `skills` da knowledge.db com entradas que nao sao skills; a ingestao
   agora filtra `kind=gate`, e comandos avulsos nao devem ser
   registrados de forma alguma (pertencem a `.tasks[]`/`.events[]`).

   | Apos etapa | Gate | Skill | Foco | Decisao apos findings |
   |------------|------|-------|------|-----------------------|
   | `specify` | doc-quality | `validate-documentation` | spec.md estruturada, sem TBD, sem ambiguidades obvias | findings `critical` -> BloqueioHumano; demais -> Decisao informativa |
   | `plan` | doc-quality | `validate-documentation` | plan.md + research.md + data-model.md coerentes | findings `critical` -> BloqueioHumano; demais -> Decisao informativa |
   | `plan` | security | `owasp-security` | superficie de ataque OWASP/ASVS na arquitetura proposta | findings `critical`/`high` -> BloqueioHumano obrigatorio (constitution exige seguranca como principio MUST) |
   | `create-tasks` | template-fidelity | `validate-tasks-template.sh` (Bash, **deterministico**) | tasks.md conforma ao template canonico: prefixo FASE, checkboxes `- [ ]`, tag de criticidade, legendas, Matriz de Dependencias, Resumo, Escopo Coberto/Excluido | findings `critical` (sem FASE / sem checkbox / sem criticidade) -> Decisao + tentativa de Edit (re-normalizar ao template); `warning` -> Decisao informativa |
   | `create-tasks` | docs-render | `validate-docs-rendered` | Mermaid parseavel, links internos, frontmatter, code blocks com linguagem | findings `critical` (link 404, Mermaid invalido) -> Decisao + tentativa de Edit; demais -> Decisao informativa |
   | `execute-task -> review-task` | convergence | `converge` | divergencia spec-vs-codigo nos paths declarados (US5, FR-015/FR-019) | findings `CRITICAL` -> BloqueioHumano (decisao do orquestrador; converge nao trava sozinha); demais -> Decisao informativa (a propria skill se auto-registra — ver 5.f.bis) |
   | `review-features` (por feature `ARQUIVAR`) | delta-gate | `delta-gate.sh` (Bash, **deterministico**, incondicional) | secao `## Delta Requirements` presente/valida antes do archive (FR-010/FR-013, CHK020) | exit != 0 -> BloqueioHumano ESCOPADO aquela feature, sem abortar a onda (ver 5.f.ter) |

   **Pre-gate deterministico do `create-tasks` (template-fidelity):** roda
   ANTES do gate `docs-render` (skeleton antes de render). Motivacao: o
   `docs-render` so checa render, nunca conformidade estrutural — quando o
   backlog e gerado inline e "esquece" o template (sem checkbox, sem FASE,
   sem legendas/Escopo/Matriz), o drift passava silencioso ate um humano
   notar. Por ser uma checagem por Bash (e nao uma skill LLM, sujeita ao
   mesmo modo de falha que gerou o drift), e determinístico e nao pode ser
   "esquecido":

   ```bash
   # FD = feature-dir; TASKS = "$FD/tasks.md"
   OUT=$(bash "$HOME/.claude/skills/create-tasks/scripts/validate-tasks-template.sh" \
     "$TASKS" --config "$HOME/.claude/skills/create-tasks/config.json" 2>&1) || true
   # Exit 1 = drift; cada linha "FINDING|critical|..." -> Decisao + tentativa de
   # Edit re-normalizando ao template (templates/tasks.md), preservando todo o
   # conteudo/progresso [x]; "FINDING|warning|..." -> Decisao informativa.
   # Exit 0 = conformante (sem Decisao). Registrar:
   #   record-skill --skill validate-tasks-template --kind gate
   # (kind=gate: e script deterministico, nao invocacao da tool Skill —
   # fica auditavel no state.json e fora da metrica de skills.)
   ```

   Sequencia padrao por gate:

   ```bash
   # 1. Invocar skill via tool Skill (passar paths/feature-dir como arg)
   # Exemplo apos specify:
   #   Skill(skill="validate-documentation", args="<FD>/spec.md")

   # 2. Capturar saida da skill (relatorio + findings JSON ou MD)

   # 3. Registrar invocacao
   state-ondas.sh record-skill --state-dir <SD> \
     --skill validate-documentation --decisao-id <dec-NNN-do-gate>

   # 4. Para cada finding critico, registrar Decisao
   state-decisions.sh register --state-dir <SD> \
     --agente "orquestrador-00c" --etapa "<atual>" \
     --contexto "Gate <NOME> reportou: <resumo do finding>" \
     --opcoes '["aceitar-risco-com-justificativa","corrigir-agora","escalar-para-humano"]' \
     --escolha "<escolha>" --justificativa "<...>" --score <0|2|3>

   # 5. Se escolha = "escalar-para-humano", emitir BloqueioHumano
   ```

   **Opt-out auditavel:** o orquestrador PODE pular um gate (ex: feature
   trivial sem superficie de seguranca exige pular `owasp-security`),
   mas DEVE registrar Decisao explicita justificando o skip:

   ```bash
   state-decisions.sh register --state-dir <SD> \
     --agente "orquestrador-00c" --etapa "plan" \
     --contexto "Skip do gate owasp-security: feature e pure-text doc, sem endpoint/dados/auth" \
     --opcoes '["rodar-gate","skip-com-justificativa"]' \
     --escolha "skip-com-justificativa" \
     --justificativa "<...>" --score 3
   ```

   `/review-task` audita skips: feature com >2 gates skipados sem
   justificativa solida vira finding `quality-gate-bypass`.

   **Resolucao do gate `owasp-security` pela matriz tier×gate (FR-005 —
   delivery-tier).** Origem: feature `delivery-tier`, Fase D item 11
   (FR-005); `contracts/cli-delivery-tier.md` §3-4;
   `contracts/tier-gate-map.md` §2.1 R1/R2/R3. Esta regra **substitui**
   o "Opt-out auditavel" generico acima ESPECIFICAMENTE para
   `owasp-security` — os demais gates da tabela (`validate-documentation`,
   `validate-tasks-template.sh`, `validate-docs-rendered`) continuam sob
   o opt-out generico, sem matriz.

   Antes de invocar `owasp-security` (apos `plan`), resolva o modo pela
   matriz:

   ```bash
   _modo=$(delivery-tier.sh gate-mode --gate owasp-security --state-dir <SD>)
   ```

   Aplicar como **ALLOWLIST positiva (R3)** — decidir o que roda,
   nunca o que se pula:

   | `_modo` | Acao |
   |---|---|
   | `completo` | invocar a skill sem restricao (comportamento atual) |
   | `leve` | invocar a skill com `args` limitando o escopo a **auth,
   secrets e input** (literal de FR-005); Decisao **obrigatoria** |
   | `skip` | **nao** invocar a skill; Decisao **obrigatoria** |

   `leve`/`skip` reusam o mesmo enum de opcoes do opt-out auditavel
   acima (`["rodar-gate","skip-com-justificativa"]` → adicionar
   `"rodar-leve"` como 3a opcao), citando **tier + modo resolvido** como
   justificativa:

   ```bash
   state-decisions.sh register --state-dir <SD> \
     --agente "orquestrador-00c" --etapa "plan" \
     --contexto "Gate owasp-security resolvido pela matriz tier x gate: tier=$_tier modo=$_modo" \
     --opcoes '["rodar-gate","rodar-leve","skip-com-justificativa"]' \
     --escolha "<rodar-gate|rodar-leve|skip-com-justificativa>" \
     --justificativa "tier=$_tier -> gate-mode=$_modo (tier-gate-map.txt)" \
     --score 3 --evidencia "delivery-tier.sh gate-mode --gate owasp-security --state-dir <SD> => $_modo"
   ```

   **Redacao proibida (R3 — nunca denylist)**: formulacoes equivalentes a
   "invocar completo apenas se `_modo == completo`, senao pular" NAO
   substituem a tabela acima — essa forma degrada silenciosamente para
   "gate desligado" em qualquer valor inesperado de `_modo` (inclusive
   bugs de coercao). A tabela allowlist trata `completo` como o UNICO
   caminho de execucao irrestrita; qualquer outro valor (incluindo
   valores nao previstos, que `gate-mode` ja coage a `completo` por
   fail-safe — INV-2) cai em `leve`/`skip` apenas se EXPLICITAMENTE
   igual a esses tokens.
<!-- FRAGMENT:quality-gates:END -->

<!-- FRAGMENT:stage-commit-hook:BEGIN -->
9.ter. **Hook de commit atomico por etapa (opt-in — atomic-commit-pr,
    FR-003)**: SOMENTE se `commit-mode.sh is-enabled --state-dir <SD>`
    retornar `true`. Roda APOS passo 9.bis (ingestao) e ANTES do passo
    10 (commit local do state). NAO-OP quando `is-enabled` retorna `false`
    (SC-006 — zero latencia no path de opt-out; comportamento atual
    preservado). Aplicavel apenas em etapas de artefato:
    `specify`, `plan`, `clarify`, `checklist`, `create-tasks`.
    NAO aplicar em `briefing`, `constitution`, `execute-task`,
    `review-task`, `review-features` (sem artefato spec-driven).

    ```bash
    _enabled=$(commit-mode.sh is-enabled --state-dir <SD>)
    if [ "$_enabled" = "true" ]; then
      # 1. Checar branch — skip silencioso se default (exit 3) ou erro (exit 1)
      commit-mode.sh guard-branch --state-dir <SD> --projeto-alvo-path <PAP>
      _guard_exit=$?
      if [ "$_guard_exit" = "0" ]; then
        # 2. Gerar mensagem Conventional Commits para a etapa atual
        _stage=$(state-rw.sh get --state-dir <SD> --field '.current_stage')
        _name=$(state-rw.sh get --state-dir <SD> --field \
                '.execution.target_project_description // "unnamed"' | \
                head -c 40 | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
        _msg=$(commit-mode.sh stage-message --feature "$_name" --stage "$_stage")
        # 3. Staging por allowlist derivada (FR-014) — NUNCA `git add -A`.
        #    --scope-dir confina aos artefatos desta etapa: o feature-dir
        #    corrente <FD> (docs/specs/<feature>, ver detect-completion
        #    --feature-dir) + o proprio state dir do agente-00c.
        commit-mode.sh stage-derived --state-dir <SD> --projeto-alvo-path <PAP> \
          --scope-dir "<FD>" --scope-dir ".claude/agente-00c-state"
        _stage_rc=$?
        if [ "$_stage_rc" = 0 ]; then
          # 4. Commit direto via git (pipeline non-interactive — CHK047/dec-026)
          git -C <PAP> commit -m "$_msg" 2>/dev/null || true
          # 5. Registrar Decisao auditavel do commit
          state-decisions.sh register --state-dir <SD> \
            --agente "orquestrador-00c" --etapa "$_stage" \
            --contexto "Commit atomico por etapa ($stage): $msg" \
            --opcoes '["commit","skip"]' --escolha "commit" \
            --justificativa "atomic_commit_enabled=true; guard-branch exit 0" \
            --score 2
        elif [ "$_stage_rc" = 3 ]; then
          log_out "commit-mode: allowlist vazia — commit atomico pulado nesta onda (nada staged sob escopo da etapa)"
        else
          log_out "commit-mode: stage-derived falhou (exit $_stage_rc) — commit atomico pulado nesta onda"
        fi
      else
        log_out "commit-mode: guard-branch exit $_guard_exit — commit atomico pulado nesta onda"
      fi
    fi
    ```
<!-- FRAGMENT:stage-commit-hook:END -->

<!-- ORCH-REF-END -->
