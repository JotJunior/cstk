#!/bin/sh
# pipeline.sh — state machine canonica da pipeline SDD do agente-00C.
#
# Ref: docs/specs/agente-00c/spec.md FR-004
#      docs/specs/agente-00c/plan.md §Summary
#      docs/specs/agente-00c/tasks.md FASE 3.1
#
# Subcomandos:
#   pipeline.sh stages
#       — imprime as 10 etapas canonicas (uma por linha)
#   pipeline.sh next-stage --current STAGE
#       — imprime proxima etapa em ordem linear (vazio se ja na ultima)
#   pipeline.sh prev-stage --current STAGE
#       — imprime etapa anterior (para retro-execucao)
#   pipeline.sh detect-completion --feature-dir DIR --stage STAGE
#                                  [--projeto-alvo-path PAP]
#       — exit 0 se artefato esperado da etapa existe; exit 1 se nao
#       — Mapeamento etapa -> artefato esperado (no feature-dir):
#           briefing       -> briefing.md (com validacao de estrutura)
#           constitution   -> constitution.md
#           specify        -> spec.md
#           clarify        -> spec.md (assume editado pela skill clarify)
#           plan           -> plan.md
#           checklist      -> checklists/ (qualquer .md dentro)
#           create-tasks   -> tasks.md (com validacao de estrutura)
#           execute-task   -> presenca de pelo menos 1 [x] em tasks.md
#           review-task    -> sempre passa (review e cross-task — sem artefato)
#           review-features -> sempre passa
#       — `briefing` e `constitution` sao artefatos PROJECT-LEVEL (uma vez por
#         projeto, nao por feature). As skills `briefing` e `constitution`
#         salvam em paths do `/initialize-docs` (hierarquia numerada):
#           briefing      -> docs/01-briefing-discovery/briefing.md
#           constitution  -> docs/constitution.md
#         Quando `--projeto-alvo-path PAP` e passado, esses paths sao
#         aceitos como fallback alem do feature-dir convencional. Isso
#         resolve o conflito com `/initialize-docs` (issue #3) sem quebrar
#         o layout SDD canonico.
#       — Validacao estrutural: briefing e create-tasks tem validacao de
#         template alem da existencia do arquivo. Ver `_pl_validate_<stage>`.
#         exit 1 com motivo na stderr quando estrutura nao bate. (Razao:
#         exec-2026-05-18-iniciacao-membro mostrou que orquestrador pode
#         escrever tasks.md fora-de-padrao sem invocar skill — leniencia
#         do detect-completion mascarou o drift.)
#   pipeline.sh constitution-conflict --projeto-alvo-path PAP --feature-dir FD
#       — detecta se docs/constitution.md global existe enquanto a etapa
#         constitution e iniciada para uma feature. Saida:
#           exit 0 = sem conflito (so existe um, ou nenhum)
#           exit 1 = CONFLITO: global existe + feature ja tem constitution
#                   propria criada sem coordenacao formal
#           exit 2 = ALERTA: global existe e feature constitution ainda nao
#                   foi criada — orquestrador deve emitir BloqueioHumano
#                   com 3 opcoes (atualizar global / criar delta com
#                   Sync Impact Report / abortar) antes de invocar a skill.
#         Razao (exec-2026-05-18-iniciacao-membro dec-004): orquestrador
#         detectou constitution global existente mas decidiu sozinho criar
#         feature-delta com 8 principios — padrao nao previsto pela skill
#         constitution. detect-completion aceitou silenciosamente.
#   pipeline.sh skill-conflict --skill NAME --projeto-alvo-path PATH
#       — emite info se a skill existe em ambos local e global
#       — exit 0 (info); exit 1 (so global); exit 2 (so local); exit 3 (nenhum)
#       — Sempre, skill local vence (quando ambas existem) — output indica isso
#   pipeline.sh require-blockade-resolved --state-dir SD --etapa STAGE
#       — para --etapa constitution: valida que o BloqueioHumano pre-flight
#         (exigido quando constitution-conflict retorna exit=2) foi
#         registrado E respondido por humano antes da skill ser invocada.
#         Identifica decisao pre-flight pela presenca das 3 opcoes
#         canonicas (atualizar-global-via-bump-SemVer /
#         criar-feature-delta-com-sync-impact-report /
#         abortar-feature-sem-principios-proprios) em opcoes_consideradas.
#         exit 0 = bloqueio resolvido com resposta valida — skill pode ser
#                  invocada
#         exit 1 = ausencia de decisao pre-flight OU bloqueio nao registrado
#                  OU bloqueio nao respondido OU resposta "abortar"
#         exit 2 = uso incorreto
#         Razao: orchestrator.md secao 5.b exige BloqueioHumano antes de
#         invocar Skill(constitution) quando exit=2. dec-004 do projeto
#         github-pages-cstk-manual bypassou esse protocolo. Este subcomando
#         fecha o caminho no runtime — agente deve rodar antes da invocacao
#         e abortar se exit != 0.
#
# POSIX sh + jq necessario apenas para require-blockade-resolved
# (demais subcomandos usam FS + listas hardcoded).

set -eu

_PL_NAME="pipeline"

# Lista canonica em ordem (FR-004; tasks.md 3.1.1).
_PL_STAGES_LIST="briefing constitution specify clarify plan checklist create-tasks execute-task review-task review-features"

_pl_die_usage() {
  printf '%s: %s\n' "$_PL_NAME" "$1" >&2
  exit 2
}

_pl_die() {
  printf '%s: %s\n' "$_PL_NAME" "$1" >&2
  exit "${2:-1}"
}

_pl_print_help() {
  cat >&2 <<'HELP'
pipeline.sh — state machine canonica da pipeline SDD do agente-00C.

USO:
  pipeline.sh stages
  pipeline.sh next-stage --current STAGE
  pipeline.sh prev-stage --current STAGE
  pipeline.sh detect-completion --feature-dir DIR --stage STAGE
                                [--projeto-alvo-path PAP]
  pipeline.sh constitution-conflict --projeto-alvo-path PAP --feature-dir FD
  pipeline.sh skill-conflict --skill NAME --projeto-alvo-path PATH
  pipeline.sh require-blockade-resolved --state-dir SD --etapa STAGE

EXIT:
  0 sucesso (ou skill conflict info; ou constitution sem conflito;
              ou bloqueio resolvido com resposta valida)
  1 nao-completion / so global / outro / CONFLITO de constitution /
    bloqueio pre-flight pendente ou rejeitado
  2 uso incorreto / so local / ALERTA pre-skill constitution
  3 nenhuma skill encontrada
HELP
}

_pl_is_valid_stage() {
  for _s in $_PL_STAGES_LIST; do
    [ "$_s" = "$1" ] && return 0
  done
  return 1
}

_pl_cmd_stages() {
  for _s in $_PL_STAGES_LIST; do
    printf '%s\n' "$_s"
  done
}

_pl_cmd_next_stage() {
  _curr=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --current) _curr=$2; shift 2 ;;
      *) _pl_die_usage "next-stage: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_curr" ] || _pl_die_usage "next-stage: --current obrigatorio"
  _pl_is_valid_stage "$_curr" || _pl_die "etapa desconhecida: $_curr (use 'stages')" 1
  _take_next=0
  for _s in $_PL_STAGES_LIST; do
    if [ "$_take_next" = 1 ]; then
      printf '%s\n' "$_s"
      return 0
    fi
    [ "$_s" = "$_curr" ] && _take_next=1
  done
  # Caiu fora do loop -> ja na ultima etapa: sem proxima.
  return 0
}

_pl_cmd_prev_stage() {
  _curr=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --current) _curr=$2; shift 2 ;;
      *) _pl_die_usage "prev-stage: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_curr" ] || _pl_die_usage "prev-stage: --current obrigatorio"
  _pl_is_valid_stage "$_curr" || _pl_die "etapa desconhecida: $_curr" 1
  _prev=""
  for _s in $_PL_STAGES_LIST; do
    if [ "$_s" = "$_curr" ]; then
      [ -n "$_prev" ] && printf '%s\n' "$_prev"
      return 0
    fi
    _prev=$_s
  done
  return 0
}

# Validacao estrutural de briefing.md. Verifica secoes minimas do template
# da skill briefing (global/skills/briefing/templates/briefing.md):
#   - Header "# Project Briefing" ou "# Briefing"
#   - Pelo menos 4 das 8 secoes nucleares do template:
#       Visao, Usuarios, Escopo, Prioridades, Restricoes, Stack,
#       Qualidade, Futuro (ou variantes)
# Razao: lenient demais aceitava .md vazio ou rascunho.
_pl_validate_briefing() {
  _bf=$1
  [ -f "$_bf" ] || { echo "pipeline: briefing nao encontrado: $_bf" >&2; return 1; }
  # Header valido
  if ! head -5 "$_bf" 2>/dev/null | grep -Eqi '^#[[:space:]]+(project[[:space:]]+)?briefing'; then
    echo "pipeline: briefing sem header '# (Project )?Briefing' nas primeiras 5 linhas" >&2
    return 1
  fi
  # Conta secoes nucleares (case-insensitive, em qualquer nivel de heading)
  _matches=$(grep -Eci '^#+[[:space:]]+([0-9]+\.[[:space:]]*)?(visao|usuarios|escopo|prioridades|restricoes|stack|qualidade|futuro)' "$_bf" 2>/dev/null || true)
  if [ "${_matches:-0}" -lt 4 ]; then
    echo "pipeline: briefing tem apenas ${_matches:-0} de >=4 secoes nucleares (Visao/Usuarios/Escopo/Prioridades/Restricoes/Stack/Qualidade/Futuro)" >&2
    return 1
  fi
  return 0
}

# Validacao estrutural de tasks.md. Verifica conformidade com template da
# skill create-tasks (global/skills/create-tasks/templates/tasks.md):
#   1. Header "# Tarefas" ou "# Tasks"
#   2. Pelo menos 1 secao "## FASE"
#   3. Legenda de criticidade [C]/[A]/[M] OU sinalizacao explicita por linha
#   4. Matriz de Dependencias (Mermaid ou ASCII)
#   5. Resumo Quantitativo
#   6. Escopo Coberto (ou variante)
#   7. Escopo Excluido (ou variante)
# Razao: exec-2026-05-18-iniciacao-membro produziu tasks.md sem invocar a
# skill, usando P0/P1/P2/P3 em vez de [C]/[A]/[M] e sem matriz/resumo/escopo.
# Validacao garante que se a skill nao foi invocada (ou foi invocada errado),
# detect-completion REJEITA o avanco da etapa.
_pl_validate_tasks() {
  _tf=$1
  [ -f "$_tf" ] || { echo "pipeline: tasks.md nao encontrado: $_tf" >&2; return 1; }
  _missing=""
  # 1. Header
  if ! head -3 "$_tf" 2>/dev/null | grep -Eqi '^#[[:space:]]+(tarefas|tasks)'; then
    _missing="$_missing\n  - header '# Tarefas' ou '# Tasks' nas primeiras 3 linhas"
  fi
  # 2. Pelo menos 1 FASE
  if ! grep -Eq '^##[[:space:]]+FASE[[:space:]]+[0-9]+' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - secao '## FASE N - ...' (deve haver pelo menos 1)"
  fi
  # 3. Legenda de criticidade [C]/[A]/[M] (em corpo ou cabecalho)
  if ! grep -Eq '\[C\]|\[A\]|\[M\]' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - criticidade no padrao [C]/[A]/[M] (Critico/Alto/Medio); P0/P1/P2 NAO e aceito"
  fi
  # 4. Matriz de Dependencias
  if ! grep -Eqi '^##[[:space:]]+matriz[[:space:]]+de[[:space:]]+dependencias' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - secao '## Matriz de Dependencias' (Mermaid flowchart ou ASCII)"
  fi
  # 5. Resumo Quantitativo
  if ! grep -Eqi '^##[[:space:]]+resumo[[:space:]]+quantitativo' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - secao '## Resumo Quantitativo' (tabela com totais por fase)"
  fi
  # 6. Escopo Coberto
  if ! grep -Eqi '^##[[:space:]]+escopo[[:space:]]+(coberto|incluido)' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - secao '## Escopo Coberto' (lista do que esta no MVP)"
  fi
  # 7. Escopo Excluido
  if ! grep -Eqi '^##[[:space:]]+escopo[[:space:]]+(excluido|fora)' "$_tf" 2>/dev/null; then
    _missing="$_missing\n  - secao '## Escopo Excluido' (lista do que NAO esta no MVP)"
  fi

  if [ -n "$_missing" ]; then
    printf 'pipeline: tasks.md fora-do-padrao da skill create-tasks. Faltam:%b\n' "$_missing" >&2
    printf '  Acao: invoque a skill create-tasks via tool Skill ao inves de escrever tasks.md direto.\n' >&2
    printf '  Template: global/skills/create-tasks/templates/tasks.md\n' >&2
    return 1
  fi
  return 0
}

# detect-completion: artefato esperado por etapa.
#
# Fallback PAP (issue #3): briefing e constitution sao project-level. Quando
# `--projeto-alvo-path PAP` e passado, alem do feature-dir convencional, os
# paths do /initialize-docs sao aceitos:
#   briefing      -> $PAP/docs/01-briefing-discovery/briefing.md
#   constitution  -> $PAP/docs/constitution.md
_pl_cmd_detect_completion() {
  _fd=""
  _st=""
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature-dir)        _fd=$2;  shift 2 ;;
      --stage)              _st=$2;  shift 2 ;;
      --projeto-alvo-path)  _pap=$2; shift 2 ;;
      *) _pl_die_usage "detect-completion: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_fd" ] || _pl_die_usage "detect-completion: --feature-dir obrigatorio"
  [ -n "$_st" ] || _pl_die_usage "detect-completion: --stage obrigatorio"
  _pl_is_valid_stage "$_st" || _pl_die "detect-completion: etapa desconhecida: $_st" 2
  [ -d "$_fd" ] || _pl_die "detect-completion: feature-dir nao existe: $_fd" 1

  case "$_st" in
    briefing)
      # feature-dir OR (com PAP) hierarquia numerada do /initialize-docs.
      # Valida estrutura: header + >=4 secoes nucleares.
      if [ -f "$_fd/briefing.md" ]; then
        _pl_validate_briefing "$_fd/briefing.md" || return 1
        return 0
      elif [ -n "$_pap" ] && [ -f "$_pap/docs/01-briefing-discovery/briefing.md" ]; then
        _pl_validate_briefing "$_pap/docs/01-briefing-discovery/briefing.md" || return 1
        return 0
      else
        return 1
      fi
      ;;
    constitution)
      # feature-dir OR (com PAP) docs/constitution.md (root convencional).
      # Detecta conflito raiz-vs-feature: se ambos existem, exige que feature
      # constitution declare 'Predecessor: docs/constitution.md' (defesa
      # contra dec-004 da execucao-fonte que criou feature-delta silencioso).
      if [ -f "$_fd/constitution.md" ] && [ -n "$_pap" ] && [ -f "$_pap/docs/constitution.md" ]; then
        if ! head -30 "$_fd/constitution.md" 2>/dev/null | grep -Eqi 'predecessor|constitution[[:space:]]+global|docs/constitution\.md'; then
          echo "pipeline: feature constitution existe MAS nao referencia a global em $_pap/docs/constitution.md" >&2
          echo "pipeline: adicione 'Predecessor: docs/constitution.md vX.Y.Z' no topo OU use 'constitution-conflict' antes de criar" >&2
          return 1
        fi
        return 0
      elif [ -f "$_fd/constitution.md" ]; then
        return 0
      elif [ -n "$_pap" ] && [ -f "$_pap/docs/constitution.md" ]; then
        return 0
      else
        return 1
      fi
      ;;
    specify|clarify) [ -f "$_fd/spec.md" ]             || return 1 ;;
    plan)            [ -f "$_fd/plan.md" ]             || return 1 ;;
    checklist)
      # Qualquer .md dentro de checklists/ conta
      if [ ! -d "$_fd/checklists" ]; then
        return 1
      fi
      _found=$(find "$_fd/checklists" -maxdepth 1 -type f -name '*.md' 2>/dev/null | head -1)
      [ -n "$_found" ] || return 1
      ;;
    create-tasks)
      # Existencia + validacao de estrutura do template.
      [ -f "$_fd/tasks.md" ] || return 1
      _pl_validate_tasks "$_fd/tasks.md" || return 1
      ;;
    execute-task)
      # Pelo menos 1 marcacao [x] em tasks.md
      [ -f "$_fd/tasks.md" ] || return 1
      grep -q '^[[:space:]]*-[[:space:]]*\[x\]' "$_fd/tasks.md" 2>/dev/null || return 1
      ;;
    review-task|review-features)
      # Etapas de review nao deixam artefato persistente — sempre completas
      # (cabe ao orquestrador decidir invocar ou pular; aqui retornamos 0).
      return 0
      ;;
  esac
  return 0
}

# constitution-conflict: detecta conflito entre constitution raiz e feature.
#
# Saidas:
#   exit 0 = sem conflito (so existe um, ou nenhum, ou ambos coordenados)
#   exit 1 = CONFLITO: ambos existem, feature constitution NAO referencia raiz
#   exit 2 = ALERTA pre-skill: raiz existe + feature NAO criada ainda. O
#            orquestrador DEVE emitir BloqueioHumano com 3 opcoes
#            (atualizar global / criar delta com Sync Impact / abortar)
#            antes de invocar a skill constitution.
#
# Razao (exec-2026-05-18-iniciacao-membro dec-004): orquestrador detectou
# constitution global existente mas decidiu sozinho criar feature-delta
# com 8 principios. detect-completion aceitou silenciosamente. Este
# subcomando expoe o conflito antes da skill correr.
_pl_cmd_constitution_conflict() {
  _pap=""
  _fd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      --feature-dir)       _fd=$2;  shift 2 ;;
      *) _pl_die_usage "constitution-conflict: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _pl_die_usage "constitution-conflict: --projeto-alvo-path obrigatorio"
  [ -n "$_fd" ]  || _pl_die_usage "constitution-conflict: --feature-dir obrigatorio"

  _root="$_pap/docs/constitution.md"
  _feat="$_fd/constitution.md"
  _has_root=0
  _has_feat=0
  [ -f "$_root" ] && _has_root=1
  [ -f "$_feat" ] && _has_feat=1

  if [ "$_has_root" = 0 ] && [ "$_has_feat" = 0 ]; then
    printf 'status: none-exists\n'
    return 0
  fi
  if [ "$_has_root" = 1 ] && [ "$_has_feat" = 0 ]; then
    # Raiz existe + feature ainda nao criada — orquestrador deve emitir
    # BloqueioHumano ANTES de invocar a skill constitution.
    cat <<INFO
status: pre-skill-alert
root: $_root
feature_dir: $_fd
action_required: |
  Antes de invocar skill constitution para esta feature, registre
  BloqueioHumano (bloqueios.sh register) com 3 opcoes:
    a) atualizar-global  — feature adiciona principios via bump SemVer
                           em docs/constitution.md (skill constitution
                           detecta diff e propoe MAJOR/MINOR).
    b) criar-delta-com-sync-impact — feature cria
                           docs/specs/<feature>/constitution.md COM
                           header 'Predecessor: docs/constitution.md
                           vX.Y.Z' + tabela de Reforco/Especializacao.
                           Sync Impact Report obrigatorio.
    c) abortar           — feature nao requer principios proprios.
  Sem decisao explicita do operador, NAO crie feature constitution.
INFO
    return 2
  fi
  if [ "$_has_root" = 0 ] && [ "$_has_feat" = 1 ]; then
    # So feature, sem raiz — caso permitido (projeto sem constitution global).
    printf 'status: only-feature\nfeature: %s\n' "$_feat"
    return 0
  fi
  # Ambos existem — verifica se feature constitution referencia a raiz.
  if head -30 "$_feat" 2>/dev/null | grep -Eqi 'predecessor|constitution[[:space:]]+global|docs/constitution\.md'; then
    cat <<INFO
status: coordinated
root: $_root
feature: $_feat
note: feature constitution referencia a global (header com Predecessor)
INFO
    return 0
  fi
  cat >&2 <<INFO
status: conflict
root: $_root
feature: $_feat
problem: feature constitution NAO declara 'Predecessor:' nem referencia
         docs/constitution.md no header — padrao silencioso de delta
         (dec-004 da execucao-fonte). Edite o feature/constitution.md
         para incluir tabela de Reforco/Especializacao + Sync Impact Report,
         OU mova os principios para a global via bump SemVer.
INFO
  return 1
}

# skill-conflict: detecta skill com mesmo nome em local + global.
# Local em <projeto-alvo>/.claude/skills/ ; global em ~/.claude/skills/.
_pl_cmd_skill_conflict() {
  _skill=""
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skill)             _skill=$2; shift 2 ;;
      --projeto-alvo-path) _pap=$2;   shift 2 ;;
      *) _pl_die_usage "skill-conflict: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_skill" ] || _pl_die_usage "skill-conflict: --skill obrigatorio"
  [ -n "$_pap" ]   || _pl_die_usage "skill-conflict: --projeto-alvo-path obrigatorio"

  _local="$_pap/.claude/skills/$_skill"
  _global="${HOME:?HOME nao setado}/.claude/skills/$_skill"
  _has_local=0
  _has_global=0
  [ -d "$_local" ]  && _has_local=1
  [ -d "$_global" ] && _has_global=1

  if [ "$_has_local" = 1 ] && [ "$_has_global" = 1 ]; then
    # Conflito: ambas. Local vence.
    cat <<INFO
status: conflict
resolution: local-wins
local: $_local
global: $_global
recommendation: registrar Decisao informativa com refs aos dois paths
INFO
    return 0
  fi
  if [ "$_has_local" = 1 ] && [ "$_has_global" = 0 ]; then
    printf 'status: only-local\nlocal: %s\n' "$_local"
    return 2
  fi
  if [ "$_has_local" = 0 ] && [ "$_has_global" = 1 ]; then
    printf 'status: only-global\nglobal: %s\n' "$_global"
    return 1
  fi
  printf 'status: not-found\nskill: %s\n' "$_skill"
  return 3
}

# require-blockade-resolved: enforcement de protocolo pre-flight.
# Para --etapa constitution: garante que decisao pre-flight (identificada
# por opcoes canonicas) existe + bloqueio associado foi respondido por
# humano + resposta nao e "abortar".
_pl_cmd_require_blockade_resolved() {
  _sd=""
  _et=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --etapa)     _et=$2; shift 2 ;;
      *) _pl_die_usage "require-blockade-resolved: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _pl_die_usage "require-blockade-resolved: --state-dir obrigatorio"
  [ -n "$_et" ] || _pl_die_usage "require-blockade-resolved: --etapa obrigatorio"

  command -v jq >/dev/null 2>&1 \
    || _pl_die "require-blockade-resolved: jq nao encontrado no PATH" 1

  _sf="$_sd/state.json"
  [ -f "$_sf" ] || _pl_die "require-blockade-resolved: state.json ausente em $_sd" 1

  # Hoje so suportamos enforcement para --etapa constitution. Demais
  # etapas retornam exit 0 (nao bloqueado) por design — outras travas
  # podem ser adicionadas conforme protocolos cresam.
  case "$_et" in
    constitution) ;;
    *)
      printf 'status: not-enforced\nstage: %s\nnote: enforcement aplicavel apenas a --etapa constitution\n' "$_et"
      return 0
      ;;
  esac

  # Localiza decisao pre-flight: filtra por opcoes contendo as 3 strings
  # canonicas do BloqueioHumano exigido em orchestrator.md secao 5.b.
  _dec_id=$(jq -r '
    [.decisoes // [] | .[]
      | select(
          (.opcoes_consideradas // []) as $op
          | ($op | index("atualizar-global-via-bump-SemVer") != null)
            and ($op | index("criar-feature-delta-com-sync-impact-report") != null)
            and ($op | index("abortar-feature-sem-principios-proprios") != null)
        )
      | .id
    ] | last // ""
  ' "$_sf")

  if [ -z "$_dec_id" ]; then
    cat >&2 <<INFO
status: missing-preflight-decision
problem: nenhuma decisao pre-flight com as 3 opcoes canonicas encontrada.
         Antes de invocar Skill(constitution) com constitution-conflict
         exit=2, registre:
           1. state-decisions.sh register --etapa constitution --score 0 \\
              --opcoes '["atualizar-global-via-bump-SemVer",
                          "criar-feature-delta-com-sync-impact-report",
                          "abortar-feature-sem-principios-proprios"]' \\
              --escolha pause-humano ...
           2. bloqueios.sh register --decisao-id <dec-NNN> ...
           3. aguardar resposta humana
           4. re-rodar este subcomando
INFO
    return 1
  fi

  # Localiza bloqueio FK-linkado a essa decisao.
  _block_json=$(jq --arg id "$_dec_id" '
    .bloqueios_humanos // []
    | map(select(.decisao_id == $id))
    | last // null
  ' "$_sf")

  if [ "$_block_json" = "null" ]; then
    cat >&2 <<INFO
status: missing-blockade
preflight_decision: $_dec_id
problem: decisao pre-flight existe mas nenhum BloqueioHumano foi
         registrado para ela. Rode:
           bloqueios.sh register --state-dir $_sd --decisao-id $_dec_id \\
             --pergunta "Detectei docs/constitution.md global. Como tratar?" \\
             --contexto-para-resposta "..." \\
             --opcoes-recomendadas '["atualizar-global-via-bump-SemVer",
                                     "criar-feature-delta-com-sync-impact-report",
                                     "abortar-feature-sem-principios-proprios"]'
INFO
    return 1
  fi

  _bl_status=$(printf '%s' "$_block_json" | jq -r '.status')
  _bl_resp=$(printf '%s' "$_block_json" | jq -r '.resposta_humana // ""')
  _bl_id=$(printf '%s' "$_block_json" | jq -r '.id')

  if [ "$_bl_status" != "respondido" ]; then
    cat >&2 <<INFO
status: blockade-pending
preflight_decision: $_dec_id
blockade_id: $_bl_id
blockade_status: $_bl_status
problem: BloqueioHumano existe mas nao foi respondido pelo humano.
         Aguarde resposta antes de invocar Skill(constitution).
INFO
    return 1
  fi

  # Valida que a resposta e uma das 2 opcoes que autorizam invocacao
  # da skill. "abortar-feature-sem-principios-proprios" resolve o
  # bloqueio mas NAO autoriza skill — a feature continua sem
  # constitution propria.
  case "$_bl_resp" in
    atualizar-global-via-bump-SemVer|criar-feature-delta-com-sync-impact-report)
      cat <<INFO
status: resolved
preflight_decision: $_dec_id
blockade_id: $_bl_id
human_response: $_bl_resp
note: skill constitution pode ser invocada
INFO
      return 0
      ;;
    abortar-feature-sem-principios-proprios)
      cat >&2 <<INFO
status: blockade-resolved-abort
preflight_decision: $_dec_id
blockade_id: $_bl_id
human_response: $_bl_resp
problem: humano escolheu abortar. NAO invoque Skill(constitution) —
         a feature seguira sem principios proprios. Avance para a
         proxima etapa da pipeline.
INFO
      return 1
      ;;
    *)
      cat >&2 <<INFO
status: blockade-invalid-response
preflight_decision: $_dec_id
blockade_id: $_bl_id
human_response: $_bl_resp
problem: resposta humana nao bate com nenhuma das 3 opcoes canonicas
         (atualizar-global-via-bump-SemVer /
         criar-feature-delta-com-sync-impact-report /
         abortar-feature-sem-principios-proprios). Registre nova
         decisao + bloqueio com resposta valida.
INFO
      return 1
      ;;
  esac
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  _pl_print_help
  exit 2
fi

_PL_SUBCMD=$1
shift

case "$_PL_SUBCMD" in
  stages)                     _pl_cmd_stages "$@" ;;
  next-stage)                 _pl_cmd_next_stage "$@" ;;
  prev-stage)                 _pl_cmd_prev_stage "$@" ;;
  detect-completion)          _pl_cmd_detect_completion "$@" ;;
  constitution-conflict)      _pl_cmd_constitution_conflict "$@" ;;
  skill-conflict)             _pl_cmd_skill_conflict "$@" ;;
  require-blockade-resolved)  _pl_cmd_require_blockade_resolved "$@" ;;
  -h|--help|help)             _pl_print_help; exit 0 ;;
  *) _pl_die_usage "subcomando desconhecido: $_PL_SUBCMD (use --help)" ;;
esac
