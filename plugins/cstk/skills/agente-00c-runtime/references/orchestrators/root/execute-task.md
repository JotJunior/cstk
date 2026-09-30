# Referencia de fase: execute-task (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   #### Campo `.tasks[]` — outcome de task (FR-018, FR-019)

   Gravado durante a etapa `execute-task`/`review-task` (passo 5/6 do Loop
   principal), UMA entrada por task por execucao. Apos cada task concluir
   (seja pass ou fail), o orquestrador anexa a entrada de outcome ANTES do
   fim de onda (passo 9) e do `sha256-update` (passo 10).

   Schema EXATO (paridade com `agente-00c-feature-orchestrator.md` — mesma
   ordem, mesmo enum):

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
   `title` e o texto descritivo do heading `### {N}.{M} {Titulo} [crit]` da
   task em `tasks.md`; e o UNICO campo de texto livre da camada B e passa por
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
   # caminho atomico auditado (state-history backup + sha256). Substitui o
   # antigo snippet jq hand-rolled (get / . + [$e] / set), que era
   # nao-idempotente e so rodava se o LLM lembrasse de anexar cada task — a
   # causa raiz de tasks perdidas (a ingestao espelha .tasks[] tal-e-qual).
   # NUNCA cp/echo direto no state.json.
   "$RUNTIME_SCRIPTS"/state-ondas.sh record-task --state-dir "$SD" \
     --task-id "$TASK_ID" --titulo "$TASK_TITULO" --wave-id "$WAVE_ID" \
     --outcome "$OUTCOME" --testes-rodados "$TESTES_RODADOS" \
     --testes-passados "$TESTES_PASSADOS" --lint-ok "$LINT_OK" \
     --arquivos "$ARQUIVOS" --origem execute-task
   ```

   REGRA DURA: `touched_files` carrega paths (potencial texto livre) —
   o backup da onda ja passa por `secrets-filter.sh for-backup`, e a
   ingestao da camada B deriva apenas a CONTAGEM (`length`) do array,
   nunca expondo paths brutos na knowledge.db.

   **Rede de seguranca (determinismo)**: o `record-task` acima e o caminho AO
   VIVO, mas ainda depende de o orquestrador chama-lo a cada task. O backstop
   deterministico que GARANTE completude e `state-ondas.sh reconcile-tasks
   --tasks-md <tasks.md>`, invocado pelo `review-task` (SKILL §4.6): le os
   checkboxes concluidos do `tasks.md` e back-filla (`--if-absent`, sem
   clobberar entradas reais) qualquer task concluida ausente de `.tasks[]`.
   Os campos `origem`/`recorded_at` gravados sao ADITIVOS — a ingestao
   seleciona so os 8 campos do contrato e ignora o resto.

   #### Hook de commit por task (opt-in — atomic-commit-pr, FR-004)

   > **Posicao**: APOS `state-ondas.sh record-task` (acima) e ANTES de
   > avancar para a proxima task da onda. Roda SOMENTE na etapa
   > `execute-task`. NAO-OP quando `atomic_commit_enabled = false` (SC-006 —
   > zero latencia no path de opt-out).

   O agrupamento e **always-on por onda** (decisao 0.1.2 / FR-004): todas as
   tasks com `outcome=pass` concluidas na mesma onda sao agrupadas num unico
   commit ranged ao final da onda. Tasks com `outcome=fail` NAO entram na
   lista (US3-AC3). A lista de tasks passadas e resetada a cada onda (nunca
   acumula cross-wave).

   **Sequencia ao concluir TODAS as tasks de uma onda com `execute-task`**:

   ```bash
   # _tasks_passadas = lista de task_ids com outcome=pass acumulada durante a onda
   # Construida incrementalmente: ao registrar record-task com --outcome pass,
   # append o TASK_ID nessa lista.
   #
   # Ao fechar a onda (antes do passo 9 / state-ondas.sh end):
   _enabled=$(commit-mode.sh is-enabled --state-dir <SD>)
   if [ "$_enabled" = "true" ] && [ -n "$_tasks_passadas" ]; then
     # 1. Checar branch — skip silencioso se default (exit 3) ou erro (exit 1)
     commit-mode.sh guard-branch --state-dir <SD> --projeto-alvo-path <PAP>
     _guard_exit=$?
     if [ "$_guard_exit" = "0" ]; then
       # 2. Gerar mensagem para o grupo de tasks (range ou individual)
       _name=$(state-rw.sh get --state-dir <SD> --field \
               '.execution.target_project_description // "unnamed"' | \
               head -c 40 | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
       _ids=$(printf '%s' "$_tasks_passadas" | tr '\n' ',' | sed 's/,$//') # "1.1,1.2,1.3"
       _msg=$(commit-mode.sh task-message --feature "$_name" --task-ids "$_ids")
       # 3. Staging por allowlist derivada (FR-014) — NUNCA `git add -A`.
       #    Sem --scope-dir: tasks tocam qualquer path do repo. O baseline
       #    de untracked ja foi capturado no INICIO desta onda por
       #    `state-ondas.sh start` (best-effort via
       #    .execution.target_project_path) — nao precisa de snapshot
       #    explicito aqui.
       commit-mode.sh stage-derived --state-dir <SD> --projeto-alvo-path <PAP>
       _stage_rc=$?
       if [ "$_stage_rc" = 0 ]; then
         # 4. Commit direto (pipeline non-interactive — CHK047/dec-026)
         git -C <PAP> commit -m "$_msg" 2>/dev/null || true
         # 5. Registrar Decisao auditavel
         state-decisions.sh register --state-dir <SD> \
           --agente "orquestrador-00c" --etapa "execute-task" \
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
   Tasks com `outcome=fail` sao excluidas da lista `_tasks_passadas`.

<!-- ORCH-REF-END -->
