# Referencia de fase: checklist (feature)

> Conteudo movido do prompt-base `agente-00c-feature-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

<!-- FRAGMENT:stage-commit-hook:BEGIN -->
10.qui (ADITIVO — hook de commit atomico por etapa, opt-in — atomic-commit-pr,
    FR-003/FR-013): SOMENTE se `commit-mode.sh is-enabled --state-dir $STATE_DIR`
    retornar `true`. Roda APOS passo 10.qua e ANTES do passo 11. NAO-OP quando
    `is-enabled` retorna `false` (SC-006 — zero latencia no path de opt-out;
    comportamento atual preservado). Aplicavel apenas em etapas de artefato:
    `specify`, `plan`, `clarify`, `checklist`, `create-tasks`. NAO aplicar em
    `execute-task`, `review-task` (tasks tem hook proprio — passo 7 + FASE 5).

    ```bash
    _enabled=$(commit-mode.sh is-enabled --state-dir "$STATE_DIR")
    if [ "$_enabled" = "true" ]; then
      PAP=$(state-rw.sh get --state-dir "$STATE_DIR" \
            --field '.execution.target_project_path')
      # 1. Checar branch — skip silencioso se default (exit 3) ou erro (exit 1)
      commit-mode.sh guard-branch --state-dir "$STATE_DIR" \
        --projeto-alvo-path "$PAP"
      _guard_exit=$?
      if [ "$_guard_exit" = "0" ]; then
        # 2. Gerar mensagem Conventional Commits para a etapa atual
        _stage=$(state-rw.sh get --state-dir "$STATE_DIR" --field '.current_stage')
        _msg=$(commit-mode.sh stage-message \
               --feature "$SHORT_NAME" --stage "$_stage")
        # 3. Staging por allowlist derivada (FR-014) — NUNCA `git add -A`.
        #    --scope-dir confina aos artefatos desta etapa: spec/plan/
        #    tasks da feature + o proprio state dir da execucao.
        commit-mode.sh stage-derived --state-dir "$STATE_DIR" \
          --projeto-alvo-path "$PAP" \
          --scope-dir "docs/specs/$SHORT_NAME" \
          --scope-dir ".claude/feature-00c-state/$SHORT_NAME"
        _stage_rc=$?
        if [ "$_stage_rc" = 0 ]; then
          # 4. Commit direto via git (pipeline non-interactive — CHK047/dec-026)
          git -C "$PAP" commit -m "$_msg" 2>/dev/null || true
          # 5. Registrar Decisao auditavel do commit
          state-decisions.sh register --state-dir "$STATE_DIR" \
            --agente "agente-00c-feature-orchestrator" --etapa "$_stage" \
            --contexto "Commit atomico por etapa ($_stage): $_msg" \
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

    NUNCA `git add -A`/`git add .`/`git add --all` (FR-014, living-specs).
<!-- FRAGMENT:stage-commit-hook:END -->

<!-- ORCH-REF-END -->
