# Referencia de fase: checklist (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

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
