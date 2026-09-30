# Referencia de fase: execute-task (feature)

> Conteudo movido do prompt-base `agente-00c-feature-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

7.bis (ADITIVO — hook de commit por task, opt-in — atomic-commit-pr, FR-004):
    SOMENTE se `commit-mode.sh is-enabled --state-dir $STATE_DIR` retornar `true`
    E a fase corrente for `execute-task`. NAO-OP quando `is-enabled` retorna `false`
    (SC-006 — zero latencia no path de opt-out). Agrupamento always-on por onda
    (decisao 0.1.2 / FR-004): todas as tasks com `outcome=pass` da onda sao
    agrupadas num unico commit ranged ao final. Tasks `outcome=fail` sao excluidas.
    Lista `_tasks_passadas` e resetada a cada onda (nao acumula cross-wave).

    Sequencia ao concluir TODAS as tasks de uma onda com `execute-task`:

    ```bash
    _enabled=$(commit-mode.sh is-enabled --state-dir "$STATE_DIR")
    if [ "$_enabled" = "true" ] && [ -n "$_tasks_passadas" ]; then
      PAP=$(state-rw.sh get --state-dir "$STATE_DIR" \
            --field '.execution.target_project_path')
      # 1. Checar branch — skip silencioso se default (exit 3) ou erro (exit 1)
      commit-mode.sh guard-branch --state-dir "$STATE_DIR" \
        --projeto-alvo-path "$PAP"
      _guard_exit=$?
      if [ "$_guard_exit" = "0" ]; then
        # 2. Gerar mensagem para o grupo de tasks (range ou individual)
        _ids=$(printf '%s' "$_tasks_passadas" | tr '\n' ',' | sed 's/,$//') # "1.1,1.2"
        _msg=$(commit-mode.sh task-message --feature "$SHORT_NAME" --task-ids "$_ids")
        # 3. Staging por allowlist derivada (FR-014) — NUNCA `git add -A`.
        #    Sem --scope-dir: tasks tocam qualquer path do repo. O baseline
        #    de untracked ja foi capturado no INICIO desta onda por
        #    `state-ondas.sh start` (passo 3.bis/4, best-effort via
        #    .execution.target_project_path) — nao precisa de snapshot
        #    explicito aqui.
        commit-mode.sh stage-derived --state-dir "$STATE_DIR" \
          --projeto-alvo-path "$PAP"
        _stage_rc=$?
        if [ "$_stage_rc" = 0 ]; then
          # 4. Commit direto (pipeline non-interactive — CHK047/dec-026)
          git -C "$PAP" commit -m "$_msg" 2>/dev/null || true
          # 5. Registrar Decisao auditavel
          state-decisions.sh register --state-dir "$STATE_DIR" \
            --agente "agente-00c-feature-orchestrator" --etapa "execute-task" \
            --contexto "Commit atomico por task (onda): $_msg" \
            --opcoes '["commit","skip"]' --escolha "commit" \
            --justificativa "atomic_commit_enabled=true; tasks passadas: $_ids" \
            --score 2
        elif [ "$_stage_rc" = 3 ]; then
          log_out "commit-mode: allowlist vazia — commit por task pulado nesta onda (nada staged)"
        else
          log_out "commit-mode: stage-derived falhou (exit $_stage_rc) — commit por task pulado nesta onda"
        fi
      else
        log_out "commit-mode: guard-branch exit $_guard_exit — commit por task pulado nesta onda"
      fi
    fi
    ```

    REGRA DURA: qualquer falha no bloco acima e NO-OP silencioso (best-effort).
    O commit por task e ADITIVO ao record-task/backup/end — nunca os substitui.
    NUNCA `git add -A`/`git add .`/`git add --all` (FR-014, living-specs).

### Campo `.tasks[]` — outcome de task (FR-018, FR-019)

Gravado durante a fase `execute-task`/`review-task` (passo 7 do Loop
principal), UMA entrada por task por execucao. Apos cada task concluir
(seja pass ou fail), o orquestrador-de-feature anexa a entrada de outcome
ANTES de gerar o backup da onda (passo 8) e recomputar o hash (passo 9).

Schema EXATO (paridade com `agente-00c-orchestrator.md` — mesma ordem,
mesmo enum):

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `task_id` | string | sim | identificador da task (ex: `4.1`) |
| `title` | string | sim | titulo descritivo da task (do heading em `tasks.md`); UX do painel |
| `wave_id` | string | sim | onda em que a task rodou (proveniencia) |
| `outcome` | enum `pass`\|`fail` | sim | conjunto fechado |
| `tests_run` | int | sim | 0 se nao aplicavel |
| `tests_passed` | int | sim | `<= tests_run` |
| `lint_ok` | bool | sim | gate de lint passou? |
| `touched_files` | string[] | sim | paths relativos; contagem derivada na ingestao |

**Chave natural** (clarify Q2 / dec-006): `(project, feature, execution_id, task_id)`.
`title` e o texto descritivo do heading `### {N}.{M} {Titulo} [crit]` da task
em `tasks.md`; e o UNICO campo de texto livre da camada B e passa por
`secrets-filter.sh` na ingestao (recall.sh). Se indisponivel, gravar `""`.

Escrita via runtime ja auditado (contract layer-b §5) — NAO inventar
novo mecanismo:

```bash
# touched_files via git diff da onda; WAVE_ID = state-ondas.sh current-id;
# TASK_ID = task corrente; TASK_TITULO = titulo do heading em tasks.md ("" se
# nao resolvido); OUTCOME = pass|fail.
ARQUIVOS=$(git -C "$PAP" diff --name-only HEAD~1..HEAD 2>/dev/null \
            | jq -R . | jq -s . 2>/dev/null || echo '[]')

# Gravar via state-ondas.sh record-task: upsert idempotente por task_id,
# caminho atomico auditado (state-history backup + sha256). Substitui o antigo
# snippet jq hand-rolled (get / . + [$e] / set), que era nao-idempotente e so
# rodava se o LLM lembrasse de anexar cada task — a causa raiz de tasks perdidas
# (a ingestao espelha .tasks[] tal-e-qual). NUNCA cp/echo direto no state.json.
"$RUNTIME_SCRIPTS"/state-ondas.sh record-task --state-dir "$SD" \
  --task-id "$TASK_ID" --titulo "$TASK_TITULO" --wave-id "$WAVE_ID" \
  --outcome "$OUTCOME" --testes-rodados "$TESTES_RODADOS" \
  --testes-passados "$TESTES_PASSADOS" --lint-ok "$LINT_OK" \
  --arquivos "$ARQUIVOS" --origem execute-task
```

REGRA DURA: `touched_files` carrega paths (potencial texto livre) —
o backup da onda (passo 8) ja passa por `secrets-filter.sh for-backup`,
e a ingestao da camada B deriva apenas a CONTAGEM (`length`) do array,
nunca expondo paths brutos na knowledge.db.

**Rede de seguranca (determinismo)**: o `record-task` acima e o caminho AO
VIVO, mas ainda depende de o orquestrador chama-lo a cada task. O backstop
deterministico que GARANTE completude e `state-ondas.sh reconcile-tasks
--tasks-md <tasks.md>`, invocado pelo `review-task` (SKILL §4.6): le os
checkboxes concluidos do `tasks.md` e back-filla (`--if-absent`, sem
clobberar entradas reais) qualquer task concluida ausente de `.tasks[]`. Os
campos `origem`/`recorded_at` gravados pelo `record-task` sao ADITIVOS — a
ingestao seleciona so os 8 campos do contrato e ignora o resto.

<!-- ORCH-REF-END -->
