# Referencia de fase: create-tasks (feature)

> Conteudo movido do prompt-base `agente-00c-feature-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

<!-- FRAGMENT:quality-gates:BEGIN -->
## Quality Gates complementares (pos-artefato, nao-bloqueantes)

> **Origem**: portado da §5.f de `agente-00c-orchestrator.md` (PR #6
> do toolkit, v3.12.0). Heranca em bloco que cobre as 3 skills antes
> orfas (`validate-documentation`, `owasp-security`,
> `validate-docs-rendered`) como gates de qualidade complementares.
> Adaptado ao escopo da feature-00c (sem briefing/constitution/
> review-features) — pipeline tem 3 etapas onde gates se aplicam:
> specify, plan (×2: doc + security), create-tasks.

Apos cada uma das etapas abaixo gerar artefato (validado por
`pipeline.sh detect-completion`), invoque a skill-gate
correspondente como auditoria. Gates produzem RELATORIOS + FINDINGS —
nao bloqueiam por padrao, mas findings de severidade `critical`/`high`
DEVEM virar Decisao informativa (e podem escalar para BloqueioHumano).

Cada invocacao registra `state-ondas.sh record-skill` para que
`/review-task` consiga medir cobertura de gates.

**Higiene da metrica (`--kind`)**: registre `--kind gate` para gates
DETERMINISTICOS de script (ex.: `validate-tasks-template.sh`) e o default
`--kind skill` (omitido) APENAS para invocacoes reais da tool Skill. NUNCA
registre comandos de build/test/lint (`go build`, `eslint`, `tsc` etc.)
via record-skill — poluia a tabela `skills` da knowledge.db; a ingestao
agora filtra `kind=gate`, e comandos avulsos pertencem a
`.tasks[]`/`.events[]`, nao a `skills_invoked`.

| Apos etapa | Gate | Skill | Foco | Decisao apos findings |
|------------|------|-------|------|-----------------------|
| `specify` | doc-quality | `validate-documentation` | spec.md estruturada, sem TBD, sem ambiguidades obvias | findings `critical` → BloqueioHumano; demais → Decisao informativa |
| `plan` | doc-quality | `validate-documentation` | plan.md + research.md + data-model.md coerentes | findings `critical` → BloqueioHumano; demais → Decisao informativa |
| `plan` | security | `owasp-security` | superficie de ataque OWASP/ASVS na arquitetura proposta | findings `critical`/`high` → BloqueioHumano OBRIGATORIO (constitution exige seguranca como principio MUST) |
| `create-tasks` | template-fidelity | `validate-tasks-template.sh` (Bash, **deterministico**) | tasks.md conforma ao template canonico: prefixo FASE, checkboxes `- [ ]`, tag de criticidade, legendas, Matriz de Dependencias, Resumo, Escopo Coberto/Excluido | findings `critical` (sem FASE / sem checkbox / sem criticidade) → Decisao + tentativa de Edit (re-normalizar ao template); `warning` → Decisao informativa |
| `create-tasks` | docs-render | `validate-docs-rendered` | Mermaid parseavel, links internos, frontmatter, code blocks com linguagem | findings `critical` (link 404, Mermaid invalido) → Decisao + tentativa de Edit; demais → Decisao informativa |
| `execute-task → review-task` | convergence | `converge` | divergencia spec-vs-codigo nos paths declarados (US5, FR-015/FR-019) | findings `CRITICAL` → BloqueioHumano (decisao do orquestrador; converge nao trava sozinha); demais → Decisao informativa (a propria skill se auto-registra — ver "### Etapa `converge`: fechamento condicional de onda" na referencia `feature/converge`) |

**Pre-gate deterministico do `create-tasks` (template-fidelity):** roda ANTES
do gate `docs-render` (skeleton antes de render). Motivacao: o `docs-render`
so checa render, nunca conformidade estrutural — quando o backlog e gerado
inline e "esquece" o template (sem checkbox, sem FASE, sem legendas/Escopo/
Matriz), o drift passava silencioso ate um humano notar. Por ser uma checagem
por Bash (e nao uma skill LLM, sujeita ao mesmo modo de falha que gerou o
drift), e determinístico e nao pode ser "esquecido":

```bash
# FD = feature-dir; TASKS = "$FD/tasks.md"
OUT=$(bash "$HOME/.claude/skills/create-tasks/scripts/validate-tasks-template.sh" \
  "$TASKS" --config "$HOME/.claude/skills/create-tasks/config.json" 2>&1) || true
# Exit 1 = drift; cada "FINDING|critical|..." -> Decisao + tentativa de Edit
# re-normalizando ao template (templates/tasks.md), preservando todo o
# conteudo/progresso [x]; "FINDING|warning|..." -> Decisao informativa.
# Exit 0 = conformante. Registrar:
#   record-skill --skill validate-tasks-template --kind gate
# (kind=gate: script deterministico, nao invocacao da tool Skill — fica
# auditavel no state.json e fora da metrica de skills da knowledge.db.)
```

Sequencia padrao por gate:

```bash
# 1. Invocar skill via tool Skill (passar paths do feature-dir como arg)
# Exemplo apos specify:
#   Skill(skill="validate-documentation", args="<feature-dir>/spec.md")

# 2. Capturar saida da skill (relatorio + findings JSON ou MD)

# 3. Registrar invocacao da skill no state.json (FR-020)
state-ondas.sh record-skill --state-dir "$AGENTE_00C_STATE_DIR" \
  --skill validate-documentation --decisao-id <dec-NNN-do-gate>

# 4. Para cada finding critico, registrar Decisao auditavel (FR-017)
state-decisions.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
  --agente "agente-00c-feature-orchestrator" --etapa "<atual>" \
  --contexto "Gate <NOME> reportou: <resumo do finding>" \
  --opcoes '["aceitar-risco-com-justificativa","corrigir-agora","escalar-para-humano"]' \
  --escolha "<escolha>" --justificativa "<...>" --score <0|2|3>

# 5. Se escolha = "escalar-para-humano" OU se gate=security AND
#    severity=critical|high, emitir BloqueioHumano OBRIGATORIO:
bloqueios.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
  --pergunta "Gate <NOME> bloqueou: <resumo>. Resolver agora ou abortar?" \
  --contexto-para-resposta "<detalhe completo do finding>"
```

**Opt-out auditavel**: o orquestrador-de-feature PODE pular um gate
(ex: feature trivial sem superficie de seguranca — pular
`owasp-security`), mas DEVE registrar Decisao explicita justificando:

```bash
state-decisions.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
  --agente "agente-00c-feature-orchestrator" --etapa "plan" \
  --contexto "Skip do gate owasp-security: feature e pure-doc, sem endpoint/dados/auth" \
  --opcoes '["rodar-gate","skip-com-justificativa"]' \
  --escolha "skip-com-justificativa" \
  --justificativa "<...>" --score 3
```

`/review-task` audita skips: feature com >2 gates skipados sem
justificativa solida vira finding `quality-gate-bypass`.

**`convergence` nao participa deste opt-out generico**: nao por ser um
"caso especial fora da maquina de etapas" (FR-006 de `pipeline-converge`
revoga essa leitura) — mas porque `converge` e etapa regular do Loop
principal cujo criterio de conclusao (`pipeline.sh detect-completion
--stage converge`, delegando a `converge-status.sh check`) nao e uma
checagem estrutural manual sujeita a skip do orquestrador; nenhuma flag
de skip existe para ela (FR-015 da feature-base `skill-converge`,
redacao MUST literal). Ver "### Etapa `converge`: fechamento condicional
de onda" na referencia `feature/converge`.

**Posicao no Loop principal**: gates rodam **apos o passo 7 (avancar
fase)** e **antes do passo 8 (gerar backup)** — depois da skill
principal da fase concluir e gerar artefato, mas antes de finalizar a
onda. Se BloqueioHumano for emitido por gate, a onda encerra apos o
backup (passo 8) com Schedule intent: none.

**Warm-up**: as 3 skills-gate (`validate-documentation`,
`validate-docs-rendered`, `owasp-security`) devem ser pre-aprovadas
no warm-up do `/feature-00c` (vide §0 do slash command). Sem warm-up,
a primeira invocacao de gate trava aguardando permissao do operador.
<!-- FRAGMENT:quality-gates:END -->

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
