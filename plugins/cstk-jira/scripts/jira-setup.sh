#!/bin/sh
# jira-setup.sh — logica deterministica de apoio a skill interativa
# `jira-setup` (feature cstk-jira, FASE 6 tarefa 6.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig; docs/specs/
#      cstk-jira/checklists/ux.md CHK004/CHK006; docs/specs/cstk-jira/
#      checklists/api.md CHK006; docs/specs/cstk-jira/contracts/jira-rest.md
#      R5/R8; plugins/cstk-jira/skills/jira-setup/SKILL.md.
#
# A skill (LLM) conduz a entrevista e chama `jira-io.sh request`/`json-get`
# para descobrir tipos de issue (R8) e transicoes (R5). Este script cobre
# APENAS a parte deterministica que precisa de teste automatizado (POSIX
# sh puro, sem `jq`):
#
#   jira-setup.sh check-status-mapping PENDING IN_PROGRESS PASS FAIL \
#                                       STATUS [STATUS...]
#       — PENDING/IN_PROGRESS/PASS/FAIL sao os nomes de status escolhidos
#         pelo operador para o mapeamento local `pending`/`in_progress`/
#         `pass`/`fail`; STATUS... e a lista de status REALMENTE descoberta
#         no workflow do projeto (extraida pela skill de
#         `GET .../transitions` R5, campo `transitions[].to.name`).
#         Regras (data-model.md Entity ProjectConfig "Validation rules"):
#           1. FAIL MUST ser diferente de PASS.
#           2. Os 4 valores MUST estar entre os status descobertos (nunca
#              digitados de memoria pelo agente/operador).
#         Falha de qualquer regra => diagnostico em stderr LISTANDO os
#         status disponiveis descobertos no mesmo fluxo (ux CHK004) e
#         exit 1. Sucesso => exit 0, sem stdout.
#
#   jira-setup.sh check-field-support FIELD_ID [FIELD_ID...]
#       — r02 FASE 21 tarefa 21.5.1 (plan.md Project Structure (delta)
#         `jira-setup.sh` check-field-support + fluxo 7; data-model.md
#         ProjectConfig `labels_enabled`/`fix_versions_on_subtask`;
#         contracts/jira-rest.md R8 "campos de um tipo" — `GET
#         .../issuetypes/{issueTypeId}` -> `fields`/`results`, array de
#         `FieldCreateMetadata` com `fieldId` obrigatorio). Le de STDIN,
#         um `fieldId` por linha, a lista de campos REALMENTE presentes na
#         tela de criacao do tipo (extraida pela skill de R8 via
#         `jira-io.sh json-get` — a rede/jq ficam na skill, este script e
#         puro/deterministico, mesma divisao de `check-status-mapping`/R5 e
#         `check-link-type`/R16). Para cada FIELD_ID pedido no argv,
#         imprime `FIELD_ID=on` (presente na lista de stdin) ou
#         `FIELD_ID=off` (ausente) em stdout, um por linha, exit 0 sempre
#         (nunca falha por campo ausente — ausencia e um resultado valido,
#         nao um erro; a skill decide o que fazer com `off`). Sem
#         `jq`/cliente HTTP; nao valida IDs de campo contra allowlist
#         alguma (fieldId e o vocabulario do proprio Jira, ecoado de volta
#         tal como veio).
#
#   jira-setup.sh check-link-type ID CANDIDATE_ID...
#       — r02 FASE 18 tarefa 18.1.1 (contracts/plugin-scripts.md
#         `jira-setup.sh check-link-type`; research.md Decision R2-6;
#         spec.md FR-025 Clarification): ID e o `link_type_id` que o
#         operador confirmou; CANDIDATE_ID... e a lista de ids REALMENTE
#         devolvida por `GET /rest/api/3/issueLinkType` (R16) NESTA MESMA
#         execucao (SEC-13) — a skill descobre via `jira-io.sh
#         request GET`, este script so valida a MEMBERSHIP (mesmo
#         idioma de `check-status-mapping`/R5: a network fica na skill,
#         o script e puro/deterministico). ID fora da lista => exit 1
#         com a lista de candidatos no diagnostico; nunca aceita um id
#         digitado de memoria.
#
#   jira-setup.sh resolve-link-type
#       — r02 FASE 18 tarefa 18.2.1/18.2.2 (research.md Decision R2-6;
#         spec.md FR-025 Clarification): usado quando `link_type_id` esta
#         VAZIO em ProjectConfig (operador nao confirmou nenhum na ETAPA 7
#         do setup). Le de stdin, uma linha TAB-separada por tipo REALMENTE
#         devolvido por R16 NESTA MESMA execucao (SEC-13, mesmo idioma de
#         check-link-type): `ID<TAB>INWARD<TAB>OUTWARD`. Compara
#         (case-insensitive) `INWARD` e `OUTWARD` contra a raiz fixa
#         "block" (nunca vocabulario arbitrario); candidato = linha cujas
#         DUAS frases contem a raiz. Exatamente 1 candidato -> imprime o
#         `ID` em stdout, exit 0. 0 candidatos -> exit 1, diagnostico
#         "unrepresentable reason=no_link_type". 2+ candidatos (ambiguidade)
#         -> exit 1, diagnostico "unrepresentable reason=ambiguous_link_type"
#         (NUNCA escolhe arbitrariamente o primeiro). Puro/deterministico —
#         nenhuma chamada de rede aqui (a leitura de R16 fica na skill/no
#         motor de sync, mesma divisao de responsabilidade de
#         check-link-type).
#
#   jira-setup.sh write-config KEY=VALUE [KEY=VALUE...]
#       — Grava `ProjectConfig` (mesmo arquivo/formato de `jira-config.sh`,
#         `${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}`) de forma
#         ATOMICA: parte do config JA EXISTENTE (quando houver, r02 FASE 19
#         task 19.1.4 — permite `create-project` gravar SO `project_key`
#         sem apagar campos ja configurados), aplica os pares KEY=VALUE
#         informados por CIMA (last-write-wins por chave), valida com
#         `jira-config.sh validate` (delega, nunca duplica as regras) e SO
#         ENTAO move (`mv`, mesma particao) para o caminho final. Se a
#         validacao falhar, o arquivo temporario e removido e o caminho
#         final NUNCA e tocado — nenhum config parcial ou invalido chega a
#         existir como arquivo "final" (ux CHK006/FR-007, tasks.md 6.1.5).
#         Sem config previo (caso comum de FASE 6, ETAPA 8 "tudo ou nada"),
#         o merge e um no-op e o comportamento e IDENTICO ao r01. Apos
#         gravar com sucesso, devolve (best-effort) eventos `auth_failed`
#         do outbox a `queued` via `jira-sync.sh requeue-auth-failed`
#         (FR-016 / data-model.md OutboxEvent auth_failed->queued, tasks.md
#         12.6.1); e (best-effort, r02 FASE 22 tarefa 22.1.2) limpa toda
#         linha `state=blocked` de `jira-milestones.tsv` de TODAS as
#         features via `jira-sync.sh milestone-unblock` (achado 22.1,
#         research.md Decision R2-4).
#
#   (validate-project-key KEY vive em `jira-io.sh`, nao aqui —
#   contracts/plugin-scripts.md lista a validacao de KEY junto de
#   `validate-segment`/`validate-version-name`, mesma familia sem jq/
#   cliente HTTP; `create-project`/`consent-question` abaixo delegam a ela.)
#
#   jira-setup.sh consent-question --name N --key K --template T
#       — r02 FASE 19 tarefa 19.1.6 (plan.md SEC-9): imprime em stdout a
#         pergunta de gate humano a registrar via `bloqueios.sh register`,
#         JA CONTENDO o marcador literal exigido por SEC-9: `cstk-jira:
#         create-project key=<K> name-sha256=<H> template=<T>` (H = SHA-256
#         de N via `jira-io.sh sha256-stdin` — o NOME em si nunca entra no
#         marcador, so o hash, mesma cautela de nao gravar dado sensivel
#         em texto plano usada pelo SyncMarker). O orquestrador consome
#         esta saida tal-e-qual em vez de redigir a pergunta a mao (nunca
#         parafraseia o marcador — SEC-9 exige substring LITERAL).
#
#   jira-setup.sh create-project --name N --key K --template T
#                                (--confirm-key K | --consent-block ID)
#       — r02 FASE 19 tarefa 19.1.2 (contracts/jira-rest.md R18; plan.md
#         SEC-7/SEC-9; FR-024): (1) `validate-project-key K`; (2)
#         `GET /rest/api/3/project/K` — `200` => projeto ja existe, exit 1
#         SEM chamar R18 (reuse, nunca duplica); (3) consentimento
#         verificavel: SEM execucao 00c ativa no cwd (mesma deteccao de
#         `.lock` do hook `posttooluse-jira-sync.sh`) SO `--confirm-key` e
#         aceito e MUST repetir K exatamente; COM execucao 00c ativa SO
#         `--consent-block block-NNN` e aceito, validado contra as 4
#         condicoes de SEC-9 (bloqueio `respondido`, marcador literal
#         batendo K/H/T, resposta == `criar-projeto`, `block-NNN` nunca
#         consumido antes — consumo append-only em
#         `<dir-do-config>/runtime/consumed-consents.tsv`); qualquer
#         condicao falha => exit 2 SEM requisicao alguma; (4)
#         `leadAccountId` SEMPRE de `GET /rest/api/3/myself` (nunca
#         digitado); (5) `POST /rest/api/3/project` (R18) com
#         `projectTypeKey=software` fixo. `403` => `permission_denied`
#         (exit 7) + texto de orientacao para criacao manual — NUNCA
#         credencial invalida. Sucesso (`201`) => `write-config
#         project_key=K` (merge, preserva campos ja configurados) + marca
#         `block-NNN` como consumido quando aplicavel.
#
# Convencoes (Principio II / mesmas de jira-config.sh):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral (mapeamento/config invalido/
#   projeto ja existe); 2 uso incorreto/consentimento invalido;
#   7 permission_denied (403 em R18, propagado de jira-io.sh).
#
# Credencial: `create-project` fala com o Jira exclusivamente via
# `jira-io.sh request` (mesma disciplina do resto do plugin — Credential
# nunca passa por este script em texto plano).

set -eu

_JS_NAME="jira-setup"

_js_die_usage() { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit 2; }
_js_die()       { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit "${2:-1}"; }

_js_usage() {
  cat <<'HELP'
jira-setup.sh — apoio deterministico a skill interativa jira-setup

USO:
  jira-setup.sh check-status-mapping PENDING IN_PROGRESS PASS FAIL STATUS...
      Valida o mapeamento local -> status Jira contra a lista de status
      REALMENTE descoberta (R5). Rejeita FAIL == PASS e qualquer valor fora
      da lista descoberta, listando os status disponiveis no diagnostico.

  jira-setup.sh check-field-support FIELD_ID [FIELD_ID...]
      Le de stdin um fieldId por linha (campos REALMENTE presentes na tela
      de criacao do tipo, extraidos pela skill de R8). Para cada FIELD_ID
      pedido, imprime FIELD_ID=on|off. Sempre exit 0.

  jira-setup.sh check-link-type ID CANDIDATE_ID...
      Valida que ID (link_type_id confirmado pelo operador) esta entre os
      CANDIDATE_ID... devolvidos por GET /rest/api/3/issueLinkType (R16)
      nesta execucao. ID fora da lista => exit 1 com os candidatos.

  jira-setup.sh resolve-link-type
      Le de stdin linhas ID<TAB>INWARD<TAB>OUTWARD (tipos de R16 desta
      execucao). Exatamente 1 linha com inward E outward contendo "block"
      (case-insensitive) => imprime o ID, exit 0. 0 ou 2+ candidatos =>
      exit 1 com "unrepresentable reason=no_link_type|ambiguous_link_type".

  jira-setup.sh write-config KEY=VALUE [KEY=VALUE...]
      Grava ProjectConfig atomicamente (merge com config existente + temp
      file + jira-config.sh validate + mv). Config invalido/incompleto =>
      nada e gravado no caminho final.

  (validate-project-key KEY vive em jira-io.sh, nao aqui.)

  jira-setup.sh consent-question --name N --key K --template T
      Imprime a pergunta de gate humano (SEC-9) com o marcador literal
      cstk-jira:create-project key=K name-sha256=H template=T.

  jira-setup.sh create-project --name N --key K --template T
                               (--confirm-key K | --consent-block ID)
      Cria projeto Jira via R18 SO com consentimento verificavel (SEC-7/
      SEC-9). Ver cabecalho do arquivo para o fluxo completo.

EXIT CODES:
  0 sucesso   1 mapeamento/config invalido/projeto ja existe
  2 uso incorreto/consentimento invalido
  7 permission_denied (403 em R18)
HELP
}

# _js_script_dir — diretorio deste script (mesma tecnica de jira-io.sh
# _ji_script_dir), usado para localizar jira-config.sh irmao.
_js_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

_JS_JIRA_CONFIG_SCRIPT="$(_js_script_dir)/jira-config.sh"

# r02 FASE 19 tarefa 19.1.2: `create-project` fala com o Jira SO via
# jira-io.sh (mesma disciplina do resto do plugin — nenhum outro arquivo
# alem de jira-io.sh referencia jq/cliente HTTP, Constitution II
# carve-out 1.1.0 condicao b).
_JS_JIRA_IO_SCRIPT="$(_js_script_dir)/jira-io.sh"

# FASE 12 tarefa 12.6.1 (FR-016 / data-model.md OutboxEvent
# auth_failed->queued): apos `write-config` gravar com sucesso, devolve
# eventos `auth_failed` a `queued` — a credencial e GLOBAL ao projeto
# (`_JS_CONFIG_FILE` acima), entao uma reconfiguracao bem-sucedida vale
# para todas as features do outbox compartilhado (sem --feature).
_JS_JIRA_SYNC_SCRIPT="$(_js_script_dir)/jira-sync.sh"

# Mesmo path/convencao de _JC_CONFIG_FILE em jira-config.sh — as duas
# ferramentas MUST concordar sobre onde o ProjectConfig vive.
_JS_CONFIG_FILE="${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}"

# _js_contains VALUE STATUS... -> exit 0 se VALUE casa (igualdade exata,
# case-sensitive) com algum dos STATUS seguintes.
_js_contains() {
  _jsc_needle="$1"
  shift
  for _jsc_hay in "$@"; do
    [ "$_jsc_needle" = "$_jsc_hay" ] && return 0
  done
  return 1
}

# _js_json_str JSON KEY -> valor de um campo string simples ("key":"value"),
# 1a ocorrencia. Mesma tecnica de jira-sync.sh::_js_json_str e
# hooks/posttooluse-jira-sync.sh::_pjs_json_str (grep/sed puros — jq fica
# exclusivo de jira-io.sh, Constitution II carve-out 1.1.0 condicao b).
# Usado so para ler campos do JSON de BloqueioHumano (`bloqueios.sh get`),
# nunca para falar com o Jira.
_js_json_str() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*"'"$2"'"[ 	]*:[ 	]*"\([^"]*\)".*/\1/p' | head -n 1
}

# r02 FASE 19 tarefa 19.1.4 (contracts/jira-rest.md R18 CONFIRMADO):
# templates `software` REAIS do OpenAPI (nunca digitados de memoria —
# copiados da descricao do proprio schema, ja citada em
# contracts/jira-rest.md). Um por linha (IFS=newline no loop de
# _js_template_allowed).
_JS_R18_TEMPLATES='com.pyxis.greenhopper.jira:gh-simplified-agility-kanban
com.pyxis.greenhopper.jira:gh-simplified-agility-scrum
com.pyxis.greenhopper.jira:gh-simplified-basic
com.pyxis.greenhopper.jira:gh-simplified-kanban-classic
com.pyxis.greenhopper.jira:gh-simplified-scrum-classic'

# _js_template_allowed T -> exit 0 se T e um dos 5 projectTemplateKey de
# software documentados no OpenAPI de R18 (contracts/jira-rest.md).
_js_template_allowed() {
  _jsta_needle="$1"
  _jsta_old_ifs=$IFS
  IFS='
'
  for _jsta_cand in $_JS_R18_TEMPLATES; do
    if [ "$_jsta_needle" = "$_jsta_cand" ]; then
      IFS=$_jsta_old_ifs
      return 0
    fi
  done
  IFS=$_jsta_old_ifs
  return 1
}

# _js_runtime_bloqueios -> path do helper `bloqueios.sh` do runtime
# `agente-00c-runtime`, se localizavel (mesma ordem/idioma de
# jira-sync.sh::_js_runtime_state_rw, task 13.1.1: `jq` fica RESTRITO ao
# proprio runtime sob o carve-out 1.3.0 — este script so o CONSOME de
# fora, nunca reimplementa leitura/parse de BloqueioHumano). Ordem de
# fontes (a 1a que existir vence): `$CSTK_LIB/../skills/agente-00c-runtime/
# scripts` ou `~/.claude/skills/agente-00c-runtime/scripts`. String vazia
# se nenhuma existir — o chamador trata como "runtime indisponivel" (SEC-9
# falha fechada: sem runtime, `--consent-block` NUNCA e aceito).
_js_runtime_bloqueios() {
  if [ -n "${CSTK_LIB:-}" ] \
     && [ -r "$CSTK_LIB/../skills/agente-00c-runtime/scripts/bloqueios.sh" ]; then
    printf '%s\n' "$CSTK_LIB/../skills/agente-00c-runtime/scripts/bloqueios.sh"
    return 0
  fi
  if [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/bloqueios.sh" ]; then
    printf '%s\n' "$HOME/.claude/skills/agente-00c-runtime/scripts/bloqueios.sh"
    return 0
  fi
  return 0
}

# _js_detect_00c_active -> imprime o state-dir (relativo ao cwd) da UNICA
# execucao 00c ativa detectada e retorna 0; retorna 3 se nenhuma execucao
# ativa foi encontrada; retorna 4 se 2+ candidatos foram encontrados
# (ambiguo — SEC-9 falha fechada, nunca escolhe arbitrariamente). Mesma
# deteccao de `.lock` de hooks/posttooluse-jira-sync.sh (secao 2): 1 dir
# `.claude/feature-00c-state/<short>/.lock` OU
# `.claude/agente-00c-state/.lock`. Sempre relativo ao cwd (mesma
# convencao de _JS_CONFIG_FILE — este script nunca aceita project-dir por
# argumento).
_js_detect_00c_active() {
  _jsda_candidates=0
  _jsda_dir=""
  if [ -d "./.claude/feature-00c-state" ]; then
    for _jsda_d in ./.claude/feature-00c-state/*/; do
      [ -d "$_jsda_d" ] || continue
      if [ -d "${_jsda_d}.lock" ]; then
        _jsda_candidates=$((_jsda_candidates + 1))
        _jsda_dir=${_jsda_d%/}
      fi
    done
  fi
  if [ -d "./.claude/agente-00c-state/.lock" ]; then
    _jsda_candidates=$((_jsda_candidates + 1))
    _jsda_dir="./.claude/agente-00c-state"
  fi
  case "$_jsda_candidates" in
    0) return 3 ;;
    1) printf '%s\n' "$_jsda_dir"; return 0 ;;
    *) return 4 ;;
  esac
}

# _js_consumed_consents_file -> path do arquivo append-only de consumo de
# bloqueios de SEC-9 (r02 FASE 19 tarefa 19.1.3), no mesmo diretorio
# "runtime" ja usado por hooks/posttooluse-jira-sync.sh para hook.log e
# outbox.tsv (`<dir-do-config>/runtime/`), NUNCA versionado.
_js_consumed_consents_file() {
  printf '%s/runtime/consumed-consents.tsv\n' "$(dirname -- "$_JS_CONFIG_FILE")"
}

_js_cmd_check_status_mapping() {
  [ "$#" -ge 5 ] || _js_die_usage \
    "check-status-mapping requer PENDING IN_PROGRESS PASS FAIL e ao menos 1 STATUS"
  _jscm_pending="$1"
  _jscm_inprogress="$2"
  _jscm_pass="$3"
  _jscm_fail="$4"
  shift 4
  # "$@" agora e a lista de status descobertos (STATUS...)
  _jscm_list=$(printf '%s, ' "$@")
  _jscm_list=${_jscm_list%, }

  if [ "$_jscm_fail" = "$_jscm_pass" ]; then
    _js_die "status_fail e status_pass nao podem ser o mesmo ('$_jscm_pass') — escolha um status distinto do workflow. Status disponiveis: $_jscm_list"
  fi

  for _jscm_label_val in \
    "pending:$_jscm_pending" \
    "in_progress:$_jscm_inprogress" \
    "pass:$_jscm_pass" \
    "fail:$_jscm_fail"
  do
    _jscm_label=${_jscm_label_val%%:*}
    _jscm_val=${_jscm_label_val#*:}
    if ! _js_contains "$_jscm_val" "$@"; then
      _js_die "status '$_jscm_val' (mapeado para '$_jscm_label') nao esta entre os status descobertos no workflow do projeto. Status disponiveis: $_jscm_list"
    fi
  done

  return 0
}

# _js_cmd_check_field_support FIELD_ID [FIELD_ID...] — r02 FASE 21 tarefa
# 21.5.1 (ver cabecalho do arquivo). Le de stdin um fieldId REALMENTE
# presente na tela de criacao do tipo por linha (linhas vazias ignoradas);
# para cada FIELD_ID pedido no argv, imprime `FIELD_ID=on`/`FIELD_ID=off`.
# Nunca falha por ausencia — a ausencia de um campo e um resultado valido
# (a skill grava `off` no ProjectConfig), nao um erro de uso.
_js_cmd_check_field_support() {
  [ "$#" -ge 1 ] || _js_die_usage \
    "check-field-support requer ao menos 1 FIELD_ID"

  _jscfs_present=""
  while IFS= read -r _jscfs_line || [ -n "$_jscfs_line" ]; do
    [ -n "$_jscfs_line" ] || continue
    _jscfs_present="$_jscfs_present
$_jscfs_line"
  done

  for _jscfs_id in "$@"; do
    _jscfs_status="off"
    _jscfs_old_ifs=$IFS
    IFS='
'
    for _jscfs_candidate in $_jscfs_present; do
      [ -n "$_jscfs_candidate" ] || continue
      if [ "$_jscfs_candidate" = "$_jscfs_id" ]; then
        _jscfs_status="on"
      fi
    done
    IFS=$_jscfs_old_ifs
    printf '%s=%s\n' "$_jscfs_id" "$_jscfs_status"
  done
  return 0
}

# _js_cmd_check_link_type ID CANDIDATE_ID... — r02 FASE 18 tarefa 18.1.1
# (SEC-13): membership PURA (mesmo idioma de _js_cmd_check_status_mapping
# com R5) — ID so e aceito se estiver entre os CANDIDATE_ID... que a skill
# leu de R16 nesta execucao. NUNCA um id digitado de memoria (a lista vem
# sempre de fora, nunca de um literal fixo aqui).
_js_cmd_check_link_type() {
  [ "$#" -ge 2 ] || _js_die_usage \
    "check-link-type requer ID e ao menos 1 CANDIDATE_ID"
  _jsclt_id="$1"
  shift
  _jsclt_list=$(printf '%s, ' "$@")
  _jsclt_list=${_jsclt_list%, }

  _js_contains "$_jsclt_id" "$@" \
    || _js_die "link_type_id '$_jsclt_id' nao esta entre os candidatos devolvidos por GET /rest/api/3/issueLinkType (R16) nesta execucao. Candidatos: $_jsclt_list"

  return 0
}

# _js_cmd_resolve_link_type — r02 FASE 18 tarefa 18.2.1/18.2.2. Le de
# stdin: ID<TAB>INWARD<TAB>OUTWARD por linha (candidatos de R16 nesta
# execucao, SEC-13). Nunca aceita argumentos posicionais (a lista so pode
# vir de stdin — evita truncamento de shell/awk em frases com espaco).
_js_cmd_resolve_link_type() {
  [ "$#" -eq 0 ] || _js_die_usage \
    "resolve-link-type nao aceita argumentos (leia via stdin: ID<TAB>INWARD<TAB>OUTWARD por linha)"

  _jsrlt_out=$(awk -F '\t' '
    BEGIN { n = 0; nmatch = 0 }
    NF >= 3 && $1 != "" {
      n++
      inward = tolower($2)
      outward = tolower($3)
      if (index(inward, "block") > 0 && index(outward, "block") > 0) {
        nmatch++
        matched[nmatch] = $1
      }
    }
    END {
      print n
      print nmatch
      for (i = 1; i <= nmatch; i++) print matched[i]
    }
  ')

  _jsrlt_n=$(printf '%s\n' "$_jsrlt_out" | sed -n '1p')
  _jsrlt_nmatch=$(printf '%s\n' "$_jsrlt_out" | sed -n '2p')

  case "$_jsrlt_nmatch" in
    1)
      printf '%s\n' "$_jsrlt_out" | sed -n '3p'
      return 0
      ;;
    0)
      _js_die "unrepresentable reason=no_link_type: nenhum dos $_jsrlt_n tipo(s) de R16 tem inward E outward contendo 'block' (case-insensitive) — link_type_id automatico indisponivel"
      ;;
    *)
      _jsrlt_matched_list=$(printf '%s\n' "$_jsrlt_out" | sed -n '3,$p' | tr '\n' ',' | sed 's/,$//')
      _js_die "unrepresentable reason=ambiguous_link_type: $_jsrlt_nmatch candidatos casam 'block' em inward e outward ($_jsrlt_matched_list) — escolha arbitraria proibida, confirme link_type_id manualmente no setup"
      ;;
  esac
}

_js_cmd_write_config() {
  [ "$#" -ge 1 ] || _js_die_usage "write-config requer ao menos um KEY=VALUE"

  _jswc_dir=$(dirname -- "$_JS_CONFIG_FILE")
  mkdir -p -- "$_jswc_dir" 2>/dev/null \
    || _js_die "nao foi possivel criar diretorio: $_jswc_dir"

  _jswc_tmp="$_jswc_dir/.jira-setup-config.tmp.$$"
  _jswc_err="$_jswc_tmp.err"
  # trap de limpeza — nunca deixa temp file para tras em falha inesperada.
  trap 'rm -f "$_jswc_tmp" "$_jswc_err" 2>/dev/null || :' EXIT INT TERM

  : > "$_jswc_tmp"

  # Valida a forma KEY=VALUE de TODOS os argumentos ANTES de tocar o
  # arquivo temporario (evita montar um merge parcial se o ULTIMO
  # argumento estiver malformado).
  for _jswc_kv in "$@"; do
    case "$_jswc_kv" in
      *=*) : ;;
      *) _js_die_usage "argumento invalido (esperado KEY=VALUE): $_jswc_kv" ;;
    esac
  done

  # r02 FASE 19 tarefa 19.1.4: merge com o config EXISTENTE (quando
  # houver) — copia toda linha KEY=VALUE do arquivo atual cuja KEY nao
  # esteja entre os argumentos recebidos (as chaves recebidas SUBSTITUEM,
  # nunca duplicam). Sem config previo (caso comum de FASE 6 ETAPA 8,
  # "tudo ou nada"), o loop abaixo e um no-op e o comportamento e IDENTICO
  # ao r01 (arquivo final = so os argumentos recebidos).
  if [ -f "$_JS_CONFIG_FILE" ]; then
    while IFS= read -r _jswc_line || [ -n "$_jswc_line" ]; do
      case "$_jswc_line" in
        ''|'#'*) continue ;;
        *=*)
          _jswc_k=${_jswc_line%%=*}
          _jswc_overridden="no"
          for _jswc_kv in "$@"; do
            case "$_jswc_kv" in
              "$_jswc_k"=*) _jswc_overridden="yes" ;;
            esac
          done
          [ "$_jswc_overridden" = "yes" ] || printf '%s\n' "$_jswc_line" >> "$_jswc_tmp"
          ;;
        *) : ;;
      esac
    done < "$_JS_CONFIG_FILE"
  fi

  for _jswc_kv in "$@"; do
    printf '%s\n' "$_jswc_kv" >> "$_jswc_tmp"
  done

  if ! CSTK_JIRA_CONFIG="$_jswc_tmp" "$_JS_JIRA_CONFIG_SCRIPT" validate \
        >/dev/null 2>"$_jswc_err"; then
    _jswc_diag=$(cat -- "$_jswc_err" 2>/dev/null || :)
    _js_die "config invalido — NADA foi gravado em $_JS_CONFIG_FILE: $_jswc_diag"
  fi

  mv -- "$_jswc_tmp" "$_JS_CONFIG_FILE"
  trap - EXIT INT TERM

  # FASE 12 tarefa 12.6.1 (FR-016 / data-model.md OutboxEvent
  # auth_failed->queued): ProjectConfig acabou de ser gravado com sucesso —
  # a skill so chega ate aqui (ETAPA 7) apos a credencial ja ter sido
  # validada na ETAPA 2 (`jira-io.sh request GET /rest/api/3/myself`).
  # Devolve qualquer evento `auth_failed` a `queued` para o proximo drain
  # reprocessar. Best-effort/aditivo: nunca desfaz a gravacao acima nem
  # falha write-config caso o outbox nao exista ou jira-sync.sh nao esteja
  # disponivel (ex.: ambiente de teste isolado sem o script irmao).
  if [ -x "$_JS_JIRA_SYNC_SCRIPT" ]; then
    if _jswc_requeue_out=$("$_JS_JIRA_SYNC_SCRIPT" requeue-auth-failed 2>&1); then
      printf '%s\n' "$_jswc_requeue_out"
    else
      printf '%s: aviso — requeue-auth-failed falhou apos gravar config (nao bloqueia a reconfiguracao): %s\n' \
        "$_JS_NAME" "$_jswc_requeue_out" >&2
    fi

    # r02 FASE 22 tarefa 22.1.2 (achado 22.1, research.md Decision R2-4
    # "`jira-setup.sh write-config` limpa o bloqueio"): a transicao
    # `blocked --> current` do data-model.md so acontecia depois de uma
    # nova RESOLUCAO de marco bem-sucedida, mas a guarda de 22.1.1 nunca
    # deixava essa nova tentativa acontecer (`state=blocked` persistia
    # para sempre no sidecar). Limpa (best-effort, mesmo idioma de
    # requeue-auth-failed acima) toda linha `state=blocked` de
    # `jira-milestones.tsv` de TODAS as features apos reconfiguracao bem-
    # sucedida — a proxima `milestone ensure` volta a tentar R13/R12.
    if _jswc_unblock_out=$("$_JS_JIRA_SYNC_SCRIPT" milestone-unblock 2>&1); then
      printf '%s\n' "$_jswc_unblock_out"
    else
      printf '%s: aviso — milestone-unblock falhou apos gravar config (nao bloqueia a reconfiguracao): %s\n' \
        "$_JS_NAME" "$_jswc_unblock_out" >&2
    fi
  fi

  return 0
}

# _js_validate_project_key KEY — r02 FASE 19 tarefa 19.1.1. NAO e
# subcomando proprio de jira-setup.sh (contracts/plugin-scripts.md lista
# `validate-project-key` sob `jira-io.sh`, junto de `validate-segment`/
# `validate-version-name` — mesma familia de validacao pura sem jq/cliente
# HTTP): esta funcao so DELEGA, nunca duplica a regra do OpenAPI R18.
# Propaga o exit code de jira-io.sh (2 em uso incorreto/falha de validacao)
# sem reinterpretar a mensagem.
_js_validate_project_key() {
  "$_JS_JIRA_IO_SCRIPT" validate-project-key "$1"
}

# _js_project_create_policy -> imprime a politica efetiva de
# `project_create` (`gated`/`never`) — r02 FASE 21 tarefa 21.6.1
# (data-model.md ProjectConfig `project_create`, default `gated`).
# `jira-config.sh get` sem config (exit 3, plugin inativo) ou sem a chave
# (exit 1) sao tratados IGUALMENTE como ausencia => default `gated` (NAO
# desabilita a oferta) — so o valor LITERAL `never` bloqueia.
_js_project_create_policy() {
  _jspcp_val=$("$_JS_JIRA_CONFIG_SCRIPT" get project_create 2>/dev/null) || _jspcp_val=""
  [ -n "$_jspcp_val" ] || _jspcp_val="gated"
  printf '%s\n' "$_jspcp_val"
}

# _js_cmd_consent_question --name N --key K --template T — r02 FASE 19
# tarefa 19.1.6 (plan.md SEC-9): imprime a pergunta de gate humano JA COM
# o marcador literal exigido por SEC-9 embutido — o orquestrador consome
# esta saida tal-e-qual em vez de redigir/parafrasear o marcador a mao
# (SEC-9 exige substring LITERAL na hora de validar `--consent-block`).
_js_cmd_consent_question() {
  _jscq_name=""
  _jscq_key=""
  _jscq_template=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        [ "$#" -ge 2 ] || _js_die_usage "--name requer argumento"
        _jscq_name="$2"; shift 2 ;;
      --key)
        [ "$#" -ge 2 ] || _js_die_usage "--key requer argumento"
        _jscq_key="$2"; shift 2 ;;
      --template)
        [ "$#" -ge 2 ] || _js_die_usage "--template requer argumento"
        _jscq_template="$2"; shift 2 ;;
      *)
        _js_die_usage "consent-question: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_jscq_name" ] || _js_die_usage "consent-question requer --name"
  [ -n "$_jscq_key" ] || _js_die_usage "consent-question requer --key"
  [ -n "$_jscq_template" ] || _js_die_usage "consent-question requer --template"

  # r02 FASE 21 tarefa 21.6.1 (FR-024): project_create=never desabilita a
  # oferta inteira — nem a pergunta de gate e gerada. Sem requisicao (a
  # leitura de ProjectConfig e local).
  [ "$(_js_project_create_policy)" != "never" ] \
    || _js_die_usage "consent-question: project_create=never no ProjectConfig — criacao de projeto desabilitada por politica (FR-024); oriente criacao manual na UI do Jira"

  _js_validate_project_key "$_jscq_key"

  _jscq_sha=$(printf '%s' "$_jscq_name" | "$_JS_JIRA_IO_SCRIPT" sha256-stdin)

  printf 'Autorizar a CRIACAO de um novo projeto no Jira Cloud com nome "%s" (key=%s, template=%s)? Isto e IRREVERSIVEL por este plugin (FR-012 nunca exclui). Responda EXATAMENTE "criar-projeto" para autorizar; qualquer outra resposta (inclusive vazia/timeout) NUNCA cria o projeto. Marcador (nao remover, verificado literalmente): cstk-jira:create-project key=%s name-sha256=%s template=%s\n' \
    "$_jscq_name" "$_jscq_key" "$_jscq_template" "$_jscq_key" "$_jscq_sha" "$_jscq_template"
  return 0
}

# _js_cmd_create_project — r02 FASE 19 tarefa 19.1.2 (contracts/jira-rest.md
# R18; plan.md SEC-7/SEC-9; FR-024). Ver cabecalho do arquivo para o fluxo
# completo (5 passos) e a matriz de consentimento verificavel.
_js_cmd_create_project() {
  _jscp_name=""
  _jscp_key=""
  _jscp_template=""
  _jscp_confirm_key=""
  _jscp_consent_block=""
  _jscp_have_confirm="no"
  _jscp_have_consent="no"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        [ "$#" -ge 2 ] || _js_die_usage "--name requer argumento"
        _jscp_name="$2"; shift 2 ;;
      --key)
        [ "$#" -ge 2 ] || _js_die_usage "--key requer argumento"
        _jscp_key="$2"; shift 2 ;;
      --template)
        [ "$#" -ge 2 ] || _js_die_usage "--template requer argumento"
        _jscp_template="$2"; shift 2 ;;
      --confirm-key)
        [ "$#" -ge 2 ] || _js_die_usage "--confirm-key requer argumento"
        _jscp_confirm_key="$2"; _jscp_have_confirm="yes"; shift 2 ;;
      --consent-block)
        [ "$#" -ge 2 ] || _js_die_usage "--consent-block requer argumento"
        _jscp_consent_block="$2"; _jscp_have_consent="yes"; shift 2 ;;
      *)
        _js_die_usage "create-project: argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_jscp_name" ] || _js_die_usage "create-project requer --name"
  [ -n "$_jscp_key" ] || _js_die_usage "create-project requer --key"
  [ -n "$_jscp_template" ] || _js_die_usage "create-project requer --template"
  if [ "$_jscp_have_confirm" = "yes" ] && [ "$_jscp_have_consent" = "yes" ]; then
    _js_die_usage "create-project: informe --confirm-key OU --consent-block, nunca os dois"
  fi
  if [ "$_jscp_have_confirm" = "no" ] && [ "$_jscp_have_consent" = "no" ]; then
    _js_die_usage "create-project requer --confirm-key K OU --consent-block block-NNN"
  fi

  # (0) r02 FASE 21 tarefa 21.6.1 (FR-024): project_create=never desabilita
  # a criacao inteira — recusa ANTES de qualquer validacao/requisicao,
  # mesmo com --confirm-key/--consent-block validos.
  [ "$(_js_project_create_policy)" != "never" ] \
    || _js_die_usage "create-project: project_create=never no ProjectConfig — criacao de projeto desabilitada por politica (FR-024); oriente criacao manual na UI do Jira"

  # (1) validate-project-key
  _js_validate_project_key "$_jscp_key"

  # template contra o enum REAL do OpenAPI (r02 FASE 19 task 19.1.4) — NUNCA
  # aceita template digitado de memoria fora dos 5 documentados.
  _js_template_allowed "$_jscp_template" \
    || _js_die_usage "create-project: --template fora do enum de projectTemplateKey 'software' documentado no OpenAPI R18: $_jscp_template"

  # (2) modo de consentimento — PURAMENTE local (nenhuma chamada de rede
  # ainda): decidido ANTES do getProject (mesmo com contracts/plugin-
  # scripts.md descrevendo getProject como o passo seguinte na prosa) para
  # que "--confirm-key com valor errado"/"modo errado" falhem SEM QUALQUER
  # requisicao (19.1.7 — leitura literal de "sem requisicao"), nao so sem
  # R18.
  _jscp_active="no"
  _jscp_active_dir=""
  if _jscp_detected_dir=$(_js_detect_00c_active); then
    _jscp_active="yes"
    _jscp_active_dir="$_jscp_detected_dir"
  fi

  if [ "$_jscp_active" = "yes" ]; then
    [ "$_jscp_have_consent" = "yes" ] \
      || _js_die_usage "create-project: execucao 00c ativa detectada em $_jscp_active_dir — SO --consent-block e aceito (nunca --confirm-key)"
  else
    [ "$_jscp_have_confirm" = "yes" ] \
      || _js_die_usage "create-project: sem execucao 00c ativa (ou deteccao ambigua) — SO --confirm-key e aceito (nunca --consent-block)"
    [ "$_jscp_confirm_key" = "$_jscp_key" ] \
      || _js_die_usage "create-project: --confirm-key deve repetir a key EXATAMENTE ('$_jscp_key')"
  fi

  # (3) getProject: 200 => ja existe, reuse SEM criar; senao livre p/ o gate.
  "$_JS_JIRA_IO_SCRIPT" validate-segment "$_jscp_key"
  _jscp_get_err=$(mktemp "${TMPDIR:-/tmp}/jira-setup-r18get.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario"
  if _jscp_get_resp=$("$_JS_JIRA_IO_SCRIPT" request GET "/rest/api/3/project/$_jscp_key" 2>"$_jscp_get_err"); then
    _jscp_get_ec=0
  else
    _jscp_get_ec=$?
  fi
  _jscp_get_status=$(grep '^http_status=' "$_jscp_get_err" | tail -n 1 | cut -d= -f2)
  rm -f "$_jscp_get_err"

  if [ "$_jscp_get_status" = "200" ]; then
    _js_die "projeto '$_jscp_key' ja existe — reuse-o (jira-setup nunca cria duplicado)"
  fi
  if [ "$_jscp_get_ec" -ne 0 ] && [ "$_jscp_get_status" != "404" ]; then
    _js_die "falha ao checar existencia previa do projeto '$_jscp_key' via GET /rest/api/3/project (pre-check de R18)"
  fi

  # (3.bis) consentimento verificavel completo (SEC-7/SEC-9) — leitura de
  # bloqueio via `bloqueios.sh` e LOCAL (le state.json/state.db no disco,
  # nunca fala com o Jira), entao nao conta como "requisicao" no sentido
  # de rede — so a partir daqui uma falha de SEC-9 ainda evita R18/myself.
  _jscp_consumed_file=""
  if [ "$_jscp_have_consent" = "yes" ]; then
    _jscp_bloqueios=$(_js_runtime_bloqueios)
    [ -n "$_jscp_bloqueios" ] \
      || _js_die_usage "create-project: runtime agente-00c-runtime (bloqueios.sh) nao localizavel — impossivel verificar consentimento (SEC-9), NUNCA prossegue sem verificacao"

    # (d) uso unico — checado ANTES de ler o bloqueio (falha fechada: nao
    # importa se o bloqueio ainda esta 'respondido' no state, um
    # block-NNN ja consumido NUNCA autoriza de novo).
    _jscp_consumed_file=$(_js_consumed_consents_file)
    if [ -f "$_jscp_consumed_file" ] && grep -qxF "$_jscp_consent_block" "$_jscp_consumed_file"; then
      _js_die_usage "create-project: bloqueio $_jscp_consent_block ja foi consumido antes (SEC-9: uso unico)"
    fi

    if ! _jscp_block_json=$("$_jscp_bloqueios" get --state-dir "$_jscp_active_dir" --block-id "$_jscp_consent_block" 2>/dev/null); then
      _js_die_usage "create-project: bloqueio $_jscp_consent_block nao encontrado em $_jscp_active_dir"
    fi

    # (a) respondido
    _jscp_block_status=$(_js_json_str "$_jscp_block_json" status)
    [ "$_jscp_block_status" = "respondido" ] \
      || _js_die_usage "create-project: bloqueio $_jscp_consent_block nao esta respondido (status='$_jscp_block_status')"

    # (b) marcador literal batendo K/H/T
    _jscp_name_sha=$(printf '%s' "$_jscp_name" | "$_JS_JIRA_IO_SCRIPT" sha256-stdin)
    _jscp_marker="cstk-jira:create-project key=$_jscp_key name-sha256=$_jscp_name_sha template=$_jscp_template"
    _jscp_question=$(_js_json_str "$_jscp_block_json" question)
    case "$_jscp_question" in
      *"$_jscp_marker"*) : ;;
      *) _js_die_usage "create-project: bloqueio $_jscp_consent_block nao contem o marcador SEC-9 esperado (key/name-sha256/template devem bater EXATAMENTE) — nao autoriza esta criacao" ;;
    esac

    # (c) resposta afirmativa fixa
    _jscp_answer=$(_js_json_str "$_jscp_block_json" human_answer)
    [ "$_jscp_answer" = "criar-projeto" ] \
      || _js_die_usage "create-project: bloqueio $_jscp_consent_block respondido, mas a resposta nao e 'criar-projeto' (obtido '$_jscp_answer')"
  fi

  # (4) leadAccountId SEMPRE de GET /rest/api/3/myself (nunca digitado)
  _jscp_me_resp=$("$_JS_JIRA_IO_SCRIPT" request GET /rest/api/3/myself 2>/dev/null) \
    || _js_die "falha ao obter usuario autenticado via GET /rest/api/3/myself"
  _jscp_lead=$(printf '%s' "$_jscp_me_resp" | "$_JS_JIRA_IO_SCRIPT" json-get '.accountId')
  [ -n "$_jscp_lead" ] || _js_die "resposta de GET /rest/api/3/myself sem campo accountId"

  # (5) POST /rest/api/3/project (R18)
  _jscp_body=$("$_JS_JIRA_IO_SCRIPT" json-build project --name "$_jscp_name" \
    --key "$_jscp_key" --lead-account-id "$_jscp_lead" --template "$_jscp_template")
  _jscp_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-setup-r18body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario"
  printf '%s' "$_jscp_body" > "$_jscp_body_file"
  _jscp_post_err=$(mktemp "${TMPDIR:-/tmp}/jira-setup-r18post.XXXXXX") \
    || { rm -f "$_jscp_body_file"; _js_die "falha ao criar arquivo temporario"; }

  if _jscp_resp=$("$_JS_JIRA_IO_SCRIPT" request POST /rest/api/3/project \
      --body-file "$_jscp_body_file" --op R18 2>"$_jscp_post_err"); then
    _jscp_ec=0
  else
    _jscp_ec=$?
  fi
  rm -f "$_jscp_body_file"

  if [ "$_jscp_ec" = "7" ]; then
    _jscp_diag=$(cat -- "$_jscp_post_err" 2>/dev/null || :)
    rm -f "$_jscp_post_err"
    printf '%s: %s\n' "$_JS_NAME" "$_jscp_diag" >&2
    # 19.1.5: texto de orientacao para criacao manual — NUNCA tratado como
    # credencial invalida.
    printf '%s: criacao de projeto negada por permissao insuficiente (falta a permissao global Administer Jira) — crie o projeto manualmente na UI do Jira, ou peca a um administrador do site para usar a tool createJiraProject do Rovo MCP.\n' \
      "$_JS_NAME" >&2
    exit 7
  fi
  if [ "$_jscp_ec" -ne 0 ]; then
    _jscp_diag=$(cat -- "$_jscp_post_err" 2>/dev/null || :)
    rm -f "$_jscp_post_err"
    _js_die "falha ao criar projeto via POST /rest/api/3/project (R18): $_jscp_diag"
  fi
  rm -f "$_jscp_post_err" 2>/dev/null || :

  _jscp_key_out=$(printf '%s' "$_jscp_resp" | "$_JS_JIRA_IO_SCRIPT" json-get '.key')
  [ -n "$_jscp_key_out" ] || _js_die "resposta de POST /rest/api/3/project (R18) sem campo key"

  # Sucesso: grava project_key (merge — preserva demais campos ja
  # configurados, tarefa 19.1.4) e marca o bloqueio como consumido (SEC-9,
  # uso unico) SO DEPOIS do sucesso (uma falha de rede nunca queima o
  # consentimento).
  _js_cmd_write_config "project_key=$_jscp_key_out"

  if [ -n "$_jscp_consumed_file" ]; then
    mkdir -p -- "$(dirname -- "$_jscp_consumed_file")" 2>/dev/null || :
    printf '%s\n' "$_jscp_consent_block" >> "$_jscp_consumed_file"
  fi

  printf '%s\n' "$_jscp_key_out"
  return 0
}

# --- dispatcher ---------------------------------------------------------

_js_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_js_sub" in
  ''|-h|--help|help)
    _js_usage
    exit 0
    ;;
  check-status-mapping)
    _js_cmd_check_status_mapping "$@"
    ;;
  check-field-support)
    _js_cmd_check_field_support "$@"
    ;;
  check-link-type)
    _js_cmd_check_link_type "$@"
    ;;
  resolve-link-type)
    _js_cmd_resolve_link_type "$@"
    ;;
  write-config)
    _js_cmd_write_config "$@"
    ;;
  consent-question)
    _js_cmd_consent_question "$@"
    ;;
  create-project)
    _js_cmd_create_project "$@"
    ;;
  *)
    _js_die_usage "subcomando desconhecido: $_js_sub (validos: check-status-mapping, check-field-support, check-link-type, resolve-link-type, write-config, consent-question, create-project — validate-project-key vive em jira-io.sh)"
    ;;
esac
