# doctor.sh — comando `cstk doctor`.
#
# Ref: docs/specs/cstk-cli/contracts/cli-commands.md §doctor
#      docs/specs/cstk-cli/spec.md §SC-007
#      docs/specs/cstk-cli/quickstart.md Scenario 10
#
# Funcao exportada:
#   doctor_main "$@"
#
# Sintaxe:
#   cstk doctor [--scope global|project] [--fix]
#   cstk doctor --deps
#
# Comportamento:
#   1. Le manifest do scope; le diretorios em scope_dir/
#   2. Classifica cada skill em uma destas categorias:
#        OK      — entry no manifest + dir em disco + hash match
#        EDITED  — entry no manifest + dir em disco + hash mismatch
#        MISSING — entry no manifest, mas dir ausente em disco
#        ORPHAN  — dir em disco, mas sem entry no manifest: NAO pertence a
#                  colecao do cstk. Informativo, NAO conta como drift e
#                  NAO afeta o exit (`~/.claude/skills/` e compartilhado
#                  com plugins e skills de terceiros; cobrar do operador
#                  algo que o cstk nem instalou e falso positivo).
#   3. Reporta achados em stderr; resumo final
#   4. --fix: remove entries MISSING; recalcula source_sha256 de skills OK
#      (refresh, ainda que normalmente nao haja diff). NUNCA modifica
#      conteudo de skills (FR-007: third-party preservado; EDITED fica
#      inalterado para preservar trabalho do usuario).
#
# --deps (feature state-backend-config, FASE 4, task 4.3): modo de
# diagnostico DISTINTO e READ-ONLY, aditivo a --fix/--scope (que
# permanecem com comportamento inalterado quando --deps NAO e passado).
# Reporta em STDOUT (nao stderr — um gate de CI precisa da saida no
# caminho de falha tambem): presenca+versao de sqlite3 e jq, o
# effective_backend e o reason (delegados a `state-backend.sh resolve`
# via cli/lib/config.sh — doctor.sh NAO reimplementa a decisao de
# backend). "Nunca configurado" NUNCA e anomalia (FR-008).
#
# Exit codes:
#   0 sem drift OU --fix executado (best-effort reconciliation)
#   1 drift detectado sem --fix
#   2 uso incorreto
#
# Exit codes (--deps):
#   0 nenhuma anomalia detectada
#   1 ao menos uma anomalia (dependencia ausente ou abaixo do minimo)
#
# Secao "Distribution Paths" (feature claude-plugin-packaging, FASE 6,
# task 6.3; contract cli-plugin-awareness.md §cstk doctor): emitida SOMENTE
# quando o plugin "cstk" e detectado como habilitado via
# plugin_settings_enabled (sinal fraco, so settings.json — mantem a secao
# visivel mesmo com installed_plugins.json corrompido, contrato Scenario
# 7). Reporta o alinhamento entre o catalogo classico (~/.claude/skills) e
# o catalogo do plugin (<installPath>/skills) por hash de conteudo das
# skills DO MANIFEST do cstk (NUNCA o diretorio inteiro — ~/.claude/skills
# e compartilhado com plugins e skills de terceiros; NUNCA pelo
# campo version do registro nativo — pode vir "unknown"). Nao interage com
# --scope/--fix/--deps; roda sempre que aplicavel, independente das outras
# flags (SC-006: ausencia de plugin = zero diferenca observavel).
#
# Secao "Shadowed Scope" (feature doctor-shadowed-scope, FASE 2; contract
# doctor-shadowed-scope-output.md §2/§3): compara a copia de ESCOPO DE
# PROJETO (./.claude/<kind>/<name>.md, kind em {agents,commands}) contra o
# CATALOGO (~/.claude/<kind>/<name>.md) por CONTEUDO (hash_file das duas
# pontas, nunca o sha gravado no manifesto de projeto — que so descreve o
# lado de projeto e nunca muda sozinho, entao a comparacao intra-escopo
# antiga sempre reportava OK). Roda SEMPRE, independente de --scope/--fix
# (senao o operador que roda `cstk doctor` puro, caso majoritario com
# default --scope global, continuaria vendo o falso OK). Emitida entre o
# sumario classico e "Distribution Paths". `./.claude/<kind>/.cstk-manifest`
# e UNTRUSTED (pode ser versionado por um repositorio de terceiro) — ver
# regras R1-R6 no contrato §7. section_rc e a CONSTANTE 0 (report-only,
# contrato §4/INV-RC): nenhuma entrada desta secao move o exit code do
# `cstk doctor`. Declaracao de cobertura + rotulo de veredito (contrato
# §3.4/§3.5) ficam para a FASE 3 desta feature.

if [ -n "${_CSTK_DOCTOR_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_DOCTOR_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/compat.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hash.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/manifest.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/config.sh"
# shellcheck source=/dev/null
# plugin-detect.sh (feature claude-plugin-packaging FASE 6): alimenta a
# secao "Distribution Paths" (_doctor_distribution_paths). jq confinado
# la (amendment 1.1.0); doctor.sh so consome as funcoes exportadas.
. "${CSTK_LIB}/plugin-detect.sh"
# shellcheck source=/dev/null
# manifest-coverage.sh (feature doctor-shadowed-scope): primitivas de
# validacao/sanitizacao/formatacao para a secao "Shadowed Scope"
# (_doctor_shadowed_scope). Manifesto de projeto e UNTRUSTED — a lib
# confina o tratamento hostil (R1-R5); doctor.sh so consome as funcoes.
. "${CSTK_LIB}/manifest-coverage.sh"

_doctor_print_help() {
  cat >&2 <<'HELP'
cstk doctor — verifica integridade da instalacao (manifest vs disco).

USO:
  cstk doctor [--scope global|project] [--fix]
  cstk doctor --deps

OPCOES:
  --scope S   global (default) ou project
  --fix       Reconcilia: remove entries MISSING; recalcula hash de OK.
              NUNCA modifica conteudo de skills.
  --deps      Diagnostico read-only de dependencias (sqlite3, jq) e do
              backend efetivo de estado (state-backend-config). Modo
              distinto: ignora --fix/--scope. Relatorio em stdout, util
              como gate de CI: `cstk doctor --deps || exit 1`.

CLASSIFICACAO:
  OK       entry + dir + hash batem
  EDITED   entry + dir, mas hash diverge (edit local — use cstk update --force)
  MISSING  entry sem dir (use --fix para limpar manifest)
  ORPHAN   dir sem entry — fora da colecao do cstk (plugin, skill de
           terceiro, skill local). Informativo: NAO e drift, NAO afeta o
           exit e nunca teve reparo associado (--fix sempre preservou).

DISTRIBUTION PATHS (secao condicional, so quando o plugin "cstk" do
Claude Code esta habilitado neste ambiente — sem plugin, zero saida
nova): compara o catalogo classico (~/.claude/skills) com o catalogo do
plugin por hash de conteudo. Estados: plugin-only, aligned, diverged,
duplicated-hooks (hooks classicos registrados no projeto ALEM do
plugin), undetermined (registros nativos ilegiveis — nunca fatal).

EXIT:
  0  sem drift, ou --fix executado (ou --deps sem anomalia). Skills
     ORPHAN nao afetam o exit — logo `cstk doctor || exit 1` segue
     utilizavel como gate de CI num ~/.claude/skills compartilhado.
  1  drift detectado sem --fix (EDITED/MISSING — apenas o que o cstk
     instalou), ou --deps com anomalia, ou Distribution Paths
     reportando diverged/duplicated-hooks
HELP
}

doctor_main() {
  _doctor_reset_state

  if ! _doctor_parse_args "$@"; then
    return 2
  fi

  if [ "$_doctor_help" = 1 ]; then
    _doctor_print_help
    return 0
  fi

  if [ "$_doctor_deps" = 1 ]; then
    if _doctor_deps_run; then
      return 0
    fi
    return 1
  fi

  # Varre todos os 3 kinds. Skills usa hash_dir (artefato = pasta);
  # commands/agents usam hash_file (artefato = .md solto).
  for _doctor_current_kind in skills commands agents; do
    if ! _doctor_walk_kind "$_doctor_current_kind"; then
      return 1
    fi
  done

  # Aplica --fix se solicitado, antes do report final.
  if [ "$_doctor_fix" = 1 ]; then
    _doctor_apply_fix
  fi

  _doctor_emit_report

  # Shadowed Scope (feature doctor-shadowed-scope, FASE 2): report-only por
  # construcao (section_rc constante 0, contrato §4/INV-RC) — deliberadamente
  # FORA do OU logico abaixo: nenhuma entrada desta secao pode mover o exit
  # code do `cstk doctor` (manifesto de projeto e UNTRUSTED, contrato §7 —
  # ver docstring da funcao). Retorno nao e capturado (sempre 0 por
  # construcao; capturar so para nunca usar seria ruido morto).
  _doctor_shadowed_scope

  # Distribution Paths (FASE 6, task 6.3): independente de --scope/--fix —
  # nao ha acao de --fix para divergencia entre catalogo classico e
  # plugin (remediacao e sempre manual: cstk update / /plugin update /
  # editar settings.json). Por isso o resultado NUNCA e suprimido pelo
  # ramo --fix abaixo (ao contrario do drift de manifest, que --fix pode
  # legitimamente zerar).
  _doctor_distribution_paths
  _doctor_dp_rc=$?

  if [ "$_doctor_fix" = 1 ]; then
    [ "$_doctor_dp_rc" = 0 ] || return 1
    return 0
  fi
  if [ "$_doctor_count_drift" -gt 0 ] || [ "$_doctor_dp_rc" != 0 ]; then
    return 1
  fi
  return 0
}

# _doctor_walk_kind <kind> — varre manifest+disco para um kind especifico.
# Resolve scope_dir + manifest_path do kind, classifica entries, detecta
# ORPHAN. Tolerante a kind sem instalacao (manifest e dir ausentes).
_doctor_walk_kind() {
  _dwk_kind=$1
  case "$_doctor_scope" in
    global)  _doctor_scope_dir="${HOME:?HOME nao setado}/.claude/$_dwk_kind" ;;
    project) _doctor_scope_dir="./.claude/$_dwk_kind" ;;
    *) log_error "doctor: scope invalido"; return 1 ;;
  esac
  _doctor_manifest_path=$(manifest_default_path "$_doctor_scope" "$_dwk_kind") || return 1
  _doctor_seen=""

  # Walk manifest entries primeiro
  if [ -f "$_doctor_manifest_path" ]; then
    _doctor_old_ifs=$IFS
    IFS='
'
    for _line in $(read_manifest "$_doctor_manifest_path"); do
      IFS=$_doctor_old_ifs
      _skill=$(printf '%s' "$_line" | awk -F'\t' '{print $1}')
      _stored_sha=$(printf '%s' "$_line" | awk -F'\t' '{print $3}')
      _doctor_classify_entry "$_skill" "$_stored_sha" "$_dwk_kind"
      IFS='
'
    done
    IFS=$_doctor_old_ifs
  fi

  # Walk disk em scope_dir/ — quem nao tem entry vira ORPHAN
  if [ -d "$_doctor_scope_dir" ]; then
    case "$_dwk_kind" in
      skills)
        # Skills sao diretorios filho.
        for _d in "$_doctor_scope_dir"/*; do
          [ -d "$_d" ] || continue
          _name=$(basename -- "$_d")
          case "$_name" in
            .cstk.lock|.cstk-manifest|.*) continue ;;
          esac
          if ! _doctor_in_seen "$_name"; then
            _doctor_record "$_name" ORPHAN "" "$_dwk_kind"
          fi
        done
        ;;
      commands|agents)
        # Commands e agents sao .md soltos. Nome sem extensao = identidade.
        for _f in "$_doctor_scope_dir"/*.md; do
          [ -f "$_f" ] || continue
          _name=$(basename -- "$_f" .md)
          if ! _doctor_in_seen "$_name"; then
            _doctor_record "$_name" ORPHAN "" "$_dwk_kind"
          fi
        done
        ;;
    esac
  fi
  return 0
}

_doctor_reset_state() {
  _doctor_help=0
  _doctor_fix=0
  _doctor_deps=0
  _doctor_scope=global
  _doctor_scope_dir=""
  _doctor_manifest_path=""
  _doctor_seen=""
  _doctor_findings=""
  _doctor_count_ok=0
  _doctor_count_edited=0
  _doctor_count_missing=0
  _doctor_count_orphan=0
  _doctor_count_drift=0
}

_doctor_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) _doctor_help=1; shift ;;
      --fix) _doctor_fix=1; shift ;;
      --deps) _doctor_deps=1; shift ;;
      --scope)
        if [ "$#" -lt 2 ]; then log_error "doctor: --scope exige valor"; return 1; fi
        case "$2" in
          global|project) _doctor_scope=$2 ;;
          *) log_error "doctor: --scope invalido: $2"; return 1 ;;
        esac
        shift 2
        ;;
      --scope=*)
        _doctor_scope=${1#--scope=}
        case "$_doctor_scope" in
          global|project) ;;
          *) log_error "doctor: --scope invalido"; return 1 ;;
        esac
        shift
        ;;
      --) shift; break ;;
      -*) log_error "doctor: flag desconhecida: $1"; return 1 ;;
      *) log_error "doctor: argumento posicional inesperado: $1"; return 1 ;;
    esac
  done
  return 0
}

# _doctor_classify_entry <name> <stored_sha> <kind>
# Para kind=skills usa hash_dir; commands/agents usam hash_file no .md correspondente.
_doctor_classify_entry() {
  _ce_skill=$1
  _ce_stored=$2
  _ce_kind=$3
  _doctor_seen="$_doctor_seen
$_ce_skill"

  case "$_ce_kind" in
    skills)
      _ce_target="$_doctor_scope_dir/$_ce_skill"
      if [ ! -d "$_ce_target" ]; then
        _doctor_record "$_ce_skill" MISSING "" "$_ce_kind"
        return 0
      fi
      _ce_hash=$(hash_dir "$_ce_target" 2>/dev/null) || _ce_hash=""
      ;;
    commands|agents)
      _ce_target="$_doctor_scope_dir/$_ce_skill.md"
      if [ ! -f "$_ce_target" ]; then
        _doctor_record "$_ce_skill" MISSING "" "$_ce_kind"
        return 0
      fi
      _ce_hash=$(hash_file "$_ce_target" 2>/dev/null) || _ce_hash=""
      ;;
    *)
      log_error "doctor: kind invalido em classify_entry: $_ce_kind"
      return 1
      ;;
  esac

  if [ "$_ce_hash" = "$_ce_stored" ]; then
    _doctor_record "$_ce_skill" OK "$_ce_hash" "$_ce_kind"
  else
    _doctor_record "$_ce_skill" EDITED "$_ce_hash" "$_ce_kind"
  fi
}

_doctor_in_seen() {
  case "$_doctor_seen" in
    *"
$1"*) return 0 ;;
  esac
  return 1
}

# _doctor_record: anota status; mantem em $_doctor_findings (status\tskill\tdetail\tkind).
_doctor_record() {
  _r_skill=$1
  _r_status=$2
  _r_detail=$3
  _r_kind=${4:-skills}
  _doctor_findings="$_doctor_findings
$_r_status	$_r_skill	$_r_detail	$_r_kind"
  case "$_r_status" in
    OK) _doctor_count_ok=$((_doctor_count_ok + 1)) ;;
    EDITED)
      _doctor_count_edited=$((_doctor_count_edited + 1))
      _doctor_count_drift=$((_doctor_count_drift + 1))
      ;;
    MISSING)
      _doctor_count_missing=$((_doctor_count_missing + 1))
      _doctor_count_drift=$((_doctor_count_drift + 1))
      ;;
    ORPHAN)
      # NAO conta como drift, de proposito: `~/.claude/skills/` e espaco
      # COMPARTILHADO (plugins da Anthropic, skills de terceiros, skills
      # locais do operador). Uma pasta que o cstk nunca instalou nao e
      # "drift do cstk" — e simplesmente algo fora da colecao dele.
      #
      # Enquanto ORPHAN gateava, `cstk doctor || exit 1` virava falso
      # positivo assim que qualquer skill de terceiro aparecia no disco, e
      # o operador nao tinha acao nenhuma a tomar (o proprio `--fix`
      # sempre preservou ORPHAN — nunca houve reparo associado). Continua
      # LISTADO como informativo: some do gate, nao da visibilidade.
      _doctor_count_orphan=$((_doctor_count_orphan + 1))
      ;;
  esac
}

# _doctor_apply_fix: implementa --fix. Reparos seguros apenas:
#   - MISSING: remove entry do manifest
#   - OK: recalcula hash e re-upserta (refresh; idempotente)
# NAO toca: EDITED (preserva edits do usuario), ORPHAN (preserva third-party).
_doctor_apply_fix() {
  _df_old_ifs=$IFS
  IFS='
'
  for _f in $_doctor_findings; do
    IFS=$_df_old_ifs
    _status=$(printf '%s' "$_f" | awk -F'\t' '{print $1}')
    _skill=$(printf '%s' "$_f" | awk -F'\t' '{print $2}')
    _detail=$(printf '%s' "$_f" | awk -F'\t' '{print $3}')
    _kind=$(printf '%s' "$_f" | awk -F'\t' '{print $4}')
    [ -n "$_kind" ] || _kind=skills
    _mf=$(manifest_default_path "$_doctor_scope" "$_kind") || continue
    # Para skills, mantem mensagem historica (sem prefixo de kind) para
    # compatibilidade backward com testes/usuarios de versoes anteriores.
    _label=$_skill
    case "$_kind" in
      commands|agents) _label="$_kind/$_skill" ;;
    esac
    case "$_status" in
      MISSING)
        if ! remove_entry "$_mf" "$_skill"; then
          log_error "doctor --fix: remove_entry falhou para $_label"
        else
          log_info "doctor --fix: removida entry MISSING $_label"
        fi
        ;;
      OK)
        # Refresh: reusa entry atual mas com hash recalculado (no-op se nao mudou)
        _entry=$(lookup_entry "$_mf" "$_skill") || continue
        _ver=$(printf '%s' "$_entry" | awk -F'\t' '{print $2}')
        _ts=$(printf '%s' "$_entry" | awk -F'\t' '{print $4}')
        upsert_entry "$_mf" "$_skill" "$_ver" "$_detail" "$_ts" 2>/dev/null || :
        ;;
    esac
    IFS='
'
  done
  IFS=$_df_old_ifs
}

_doctor_emit_report() {
  {
    printf '==> cstk doctor (scope: %s)\n' "$_doctor_scope"
    if [ -n "$_doctor_findings" ]; then
      _emit_old_ifs=$IFS
      IFS='
'
      for _f in $_doctor_findings; do
        IFS=$_emit_old_ifs
        _status=$(printf '%s' "$_f" | awk -F'\t' '{print $1}')
        _skill=$(printf '%s' "$_f" | awk -F'\t' '{print $2}')
        _kind=$(printf '%s' "$_f" | awk -F'\t' '{print $4}')
        [ -n "$_kind" ] || _kind=skills
        # Mostra prefixo de kind so para nao-skills, p/ nao alterar saida historica.
        _label=$_skill
        case "$_kind" in
          commands|agents) _label="$_kind/$_skill" ;;
        esac
        case "$_status" in
          OK)      printf '  [OK]       %s\n' "$_label" ;;
          EDITED)  printf '  [EDITED]   %s    local edits detected\n' "$_label" ;;
          MISSING) printf '  [MISSING]  %s    in manifest, not on disk\n' "$_label" ;;
          ORPHAN)  printf '  [ORPHAN]   %s    nao gerenciada pelo cstk (informativo)\n' "$_label" ;;
        esac
        IFS='
'
      done
      IFS=$_emit_old_ifs
    fi
    printf '  ---\n'
    printf '  ok:      %d\n' "$_doctor_count_ok"
    printf '  edited:  %d\n' "$_doctor_count_edited"
    printf '  missing: %d\n' "$_doctor_count_missing"
    if [ "$_doctor_count_orphan" -gt 0 ]; then
      printf '  orphan:  %d  (nao gerenciadas pelo cstk — informativo, nao e drift)\n' "$_doctor_count_orphan"
    else
      printf '  orphan:  %d\n' "$_doctor_count_orphan"
    fi
    if [ "$_doctor_count_drift" -gt 0 ]; then
      if [ "$_doctor_fix" = 1 ]; then
        printf '  --fix executado: entries MISSING removidas; EDITED/ORPHAN preservados.\n'
      else
        printf '  [DRIFT] %d issue(s). Run with --fix to reconcile manifest.\n' "$_doctor_count_drift"
      fi
    fi
  } >&2
}

# _doctor_lookup_catalog_version <kind> <name> -> versao do catalogo em
# stdout, ou "?" quando indisponivel (nome sem entrada no manifesto global,
# manifesto global ausente/ilegivel). NUNCA inferida — contrato §3.2:
# "<cver> sai vazio como ? quando o manifesto global nao tem entrada para
# <name> — nunca inferido". <name> ja foi aprovado por manifest_name_is_safe
# antes de chegar aqui (chamado so a partir de _doctor_shadow_verdict).
_doctor_lookup_catalog_version() {
  _lcv_kind=$1
  _lcv_name=$2
  if ! _lcv_gmanifest=$(manifest_default_path global "$_lcv_kind" 2>/dev/null); then
    printf '?'
    return 0
  fi
  if _lcv_entry=$(lookup_entry "$_lcv_gmanifest" "$_lcv_name" 2>/dev/null); then
    printf '%s' "$_lcv_entry" | awk -F'\t' '{print $2}'
  else
    printf '?'
  fi
}

# _doctor_shadow_verdict <kind> <name> <project_version> -> imprime a linha
# de achado (contrato §3.2) em stderr e o `state` do ShadowVerdict em
# stdout (data-model.md Entity ShadowVerdict; arvore de decisao literal).
# Chamado SOMENTE para registros ja `recognized` (manifest_record_is_valid
# no caller) — <name> ja passou por manifest_name_is_safe (R1).
#
# Ordem da arvore (literal, nao reordenar):
#   1. symlink em qualquer ponta            -> indeterminate (symlink)      [R2]
#   2. copia de projeto ausente             -> indeterminate (projeto-ausente)
#   3. artefato do catalogo ausente         -> unmanaged-upstream           [FR-010]
#   4. hash_file falhou em qualquer ponta   -> indeterminate (hash-indisponivel)
#   5. project_hash == catalog_hash         -> shadow-current
#   6. caso contrario                       -> shadowed                    [FR-003]
_doctor_shadow_verdict() {
  _sv_kind=$1
  _sv_name=$2
  _sv_pver=$3

  _sv_proj_path="./.claude/$_sv_kind/$_sv_name.md"
  _sv_cat_path="${HOME:?HOME nao setado}/.claude/$_sv_kind/$_sv_name.md"
  # R3: name sanitizado antes de qualquer impressao (defesa em profundidade
  # — manifest_name_is_safe ja restringe o charset, mas a regra e a mesma
  # para todo campo untrusted impresso).
  _sv_name_safe=$(manifest_scrub_text "$_sv_name")

  # R2: symlink em QUALQUER ponta, ANTES de qualquer stat/hash que possa
  # seguir o link. `[ -h ]` casa symlink quebrado tambem (path pode nao
  # existir como arquivo regular) — por isso roda antes dos testes -f.
  if [ -h "$_sv_proj_path" ] || [ -h "$_sv_cat_path" ]; then
    printf '  %-22s%s/%s    comparacao impossivel: symlink\n' \
      "[indeterminate]" "$_sv_kind" "$_sv_name_safe" >&2
    printf 'indeterminate'
    return 0
  fi

  if [ ! -f "$_sv_proj_path" ]; then
    printf '  %-22s%s/%s    comparacao impossivel: projeto-ausente\n' \
      "[indeterminate]" "$_sv_kind" "$_sv_name_safe" >&2
    printf 'indeterminate'
    return 0
  fi

  if [ ! -f "$_sv_cat_path" ]; then
    printf '  %-22s%s/%s    sem correspondente no catalogo atual (removido/renomeado upstream)\n' \
      "[unmanaged-upstream]" "$_sv_kind" "$_sv_name_safe" >&2
    printf 'unmanaged-upstream'
    return 0
  fi

  # R6: hash so e calculado/impresso para paths que passaram R1 (name_safe,
  # no caller) e R2 (symlink, acima) — as duas pontas ja satisfazem isso.
  _sv_phash=$(hash_file "$_sv_proj_path" 2>/dev/null) || _sv_phash=""
  _sv_chash=$(hash_file "$_sv_cat_path" 2>/dev/null) || _sv_chash=""

  if [ -z "$_sv_phash" ] || [ -z "$_sv_chash" ]; then
    printf '  %-22s%s/%s    comparacao impossivel: hash-indisponivel\n' \
      "[indeterminate]" "$_sv_kind" "$_sv_name_safe" >&2
    printf 'indeterminate'
    return 0
  fi

  if [ "$_sv_phash" = "$_sv_chash" ]; then
    printf '  %-22s%s/%s    identico ao catalogo (%s...)\n' \
      "[shadow-current]" "$_sv_kind" "$_sv_name_safe" \
      "$(printf '%s' "$_sv_chash" | cut -c1-12)" >&2
    printf 'shadow-current'
    return 0
  fi

  # FR-005: a saida MUST NOT afirmar qual lado esta desatualizado (sem fonte
  # rastreavel para isso — mesma postura de _doctor_distribution_paths).
  # Mostra os dois lados; quem decide e o operador.
  _sv_cver=$(_doctor_lookup_catalog_version "$_sv_kind" "$_sv_name")
  [ -n "$_sv_cver" ] || _sv_cver='?'
  _sv_cver_safe=$(manifest_scrub_text "$_sv_cver")
  _sv_pver_safe=$(manifest_scrub_text "$_sv_pver")

  printf '  %-22s%s/%s    projeto %s (%s...) != catalogo %s (%s...)\n' \
    "[shadowed]" "$_sv_kind" "$_sv_name_safe" "$_sv_pver_safe" \
    "$(printf '%s' "$_sv_phash" | cut -c1-12)" "$_sv_cver_safe" \
    "$(printf '%s' "$_sv_chash" | cut -c1-12)" >&2
  printf 'shadowed'
  return 0
}

# _doctor_ss_scan_kind <kind> -> numero de registros `shadowed` em stdout
# (usado so para decidir se o bloco de remediacao e emitido). Emite as
# linhas de achado (via _doctor_shadow_verdict) em stderr como efeito
# colateral, uma por registro `recognized`.
#
# R4: o laco de iteracao roda sob `set -f` num SUBSHELL (restaurado ao
# sair por construcao — o subshell termina), IFS=newline — precedente
# literal `cli/lib/recall.sh fts_query_escape()`. Impede que uma linha de
# dados contendo `*` sofra pathname expansion (Cenario 9.d).
#
# R5: `manifest_within_cap` MUST ser checado antes de iterar — fonte sobre
# o teto e pulada por completo nesta secao (FASE 3 a reporta como
# unreadable/teto-excedido na declaracao de cobertura).
#
# R1: registros `unrecognized` (nome fora de forma, campos invalidos) NUNCA
# chegam a _doctor_shadow_verdict — ficam de fora da arvore de decisao por
# inteiro (contam so no denominador da cobertura, FASE 3).
_doctor_ss_scan_kind() {
  _ssk_kind=$1
  _ssk_manifest="./.claude/$_ssk_kind/.cstk-manifest"

  if [ ! -f "$_ssk_manifest" ]; then
    printf '0'
    return 0
  fi
  if ! manifest_within_cap "$_ssk_manifest"; then
    printf '0'
    return 0
  fi

  (
    set -f
    _ssk_ifs=$IFS
    IFS='
'
    _ssk_shadowed=0
    # shellcheck disable=SC2013 # for-in-command deliberado: IFS=newline +
    # set -f (R4) isolam este laco de word-splitting e pathname expansion.
    for _ssk_line in $(awk '/^[[:space:]]*$/ { next } /^#/ { next } { print }' "$_ssk_manifest" 2>/dev/null); do
      IFS=$_ssk_ifs
      if manifest_record_is_valid "$_ssk_line"; then
        _ssk_name=$(printf '%s' "$_ssk_line" | awk -F'\t' '{print $1}')
        _ssk_pver=$(printf '%s' "$_ssk_line" | awk -F'\t' '{print $2}')
        _ssk_state=$(_doctor_shadow_verdict "$_ssk_kind" "$_ssk_name" "$_ssk_pver")
        if [ "$_ssk_state" = "shadowed" ]; then
          _ssk_shadowed=$((_ssk_shadowed + 1))
        fi
      fi
      IFS='
'
    done
    IFS=$_ssk_ifs
    printf '%s' "$_ssk_shadowed"
  )
}

# _doctor_shadowed_scope — secao "Shadowed Scope" (feature
# doctor-shadowed-scope, FASE 2; contract doctor-shadowed-scope-output.md
# §2/§3.1-3.3, data-model.md Entity ShadowVerdict). Ver docstring no
# cabecalho do arquivo para o desenho completo (D2-D4, FR-004/FR-005).
#
# Declaracao de cobertura + rotulo de veredito (contrato §3.4/§3.5) ainda
# NAO sao emitidos por esta secao — FASE 3 desta feature.
#
# section_rc e a CONSTANTE 0 (contrato §4/INV-RC, data-model.md): produzido
# por `return 0` no fim da funcao — NUNCA acumulado a partir de
# count_shadowed ou de qualquer estado. Report-only por desenho: input
# controlado por terceiro (manifesto de projeto, contrato §7) pode produzir
# diagnostico, nunca veredito.
_doctor_shadowed_scope() {
  printf '\n==> Shadowed Scope (escopo de projeto vs catalogo)\n' >&2

  _ss_count_shadowed=0
  for _ss_kind in agents commands; do
    _ss_kind_shadowed=$(_doctor_ss_scan_kind "$_ss_kind")
    _ss_count_shadowed=$((_ss_count_shadowed + _ss_kind_shadowed))
  done

  # Bloco de remediacao (§3.3): so quando ha >=1 shadowed. Redacao normativa
  # por FR-005 — NAO trata a copia divergente como erro (sombrear e fluxo
  # legitimo: testar uma definicao antes de instalar).
  if [ "$_ss_count_shadowed" -gt 0 ]; then
    {
      printf '  remediacao: para realinhar a copia de projeto ao catalogo, reinstale no\n'
      printf '              escopo do projeto; para manter a copia local divergente de\n'
      printf '              proposito, nenhuma acao e necessaria — este relato e\n'
      printf '              informativo sobre a divergencia, nao uma exigencia.\n'
    } >&2
  fi

  return 0
}

# _doctor_distribution_paths — secao "Distribution Paths" (FASE 6, task
# 6.3; contract cli-plugin-awareness.md §cstk doctor, data-model.md Entity
# Installation Alignment Report). Read-only, sem --fix associado.
#
# GATE de exibicao: plugin_settings_enabled cstk (sinal FRACO, so
# settings.json) — se falhar, a secao inteira e OMITIDA (status classic-
# only implicito, sem imprimir nada, SC-006). Isso e deliberadamente MAIS
# TOLERANTE que plugin_enabled (que exige os 2 sinais validos): o
# contrato exige que installed_plugins.json corrompido AINDA mostre a
# secao (com status=undetermined), desde que settings.json confirme
# habilitado — Scenario 7 do quickstart.
#
# Determinacao de status (nesta ordem — duplicated-hooks tem precedencia
# sobre aligned/diverged, pois e o achado mais acionavel: efeito duplo
# real, nao so drift de conteudo):
#   1. installPath nao resolve (installed_plugins.json ilegivel/corrompido
#      apesar do settings.json dizer habilitado) -> undetermined
#   2. settings.json DESTE PROJETO (./.claude/settings.json, cwd) ja tem o
#      snippet classico de hooks registrado -> duplicated-hooks
#   3. ~/.claude/skills ausente -> plugin-only
#   4. hash_dir_catalog(classico) == hash_dir_catalog(plugin), ambos
#      restritos aos nomes do manifest -> aligned
#   5. hashes calculados mas diferentes -> diverged (divergencia REAL de
#      conteudo do cstk; terceiros e `evals/` nao entram na conta)
#   6. manifest vazio/ilegivel, ou qualquer hash falhar -> undetermined
#
# NOTA sobre "diverged" e ordenacao temporal (Constitution VI — nunca
# inventar dado factual): o contrato pede para "apontar qual esta
# desatualizado", mas TAMBEM proibe inferir isso por timestamp/mtime, e
# nao ha terceira fonte de verdade disponivel em tempo de execucao (o
# operador pode nao ter o repo cstk clonado). Reportar uma ordem sem fonte
# rastreavel seria fabricar dado (violacao direta do Principio VI) —
# em vez disso, o relatorio mostra AMBOS os hashes truncados e AMBAS as
# remediacoes possiveis, deixando o operador decidir com contexto que so
# ele tem (o que rodou por ultimo).
#
# Saida em stderr (mesmo canal do relatorio principal). Retorno (via
# echo do exit code, NAO stdout — consumido por doctor_main via $?):
#   0  omitida, plugin-only, aligned, ou undetermined
#   1  diverged ou duplicated-hooks
_doctor_distribution_paths() {
  if ! plugin_settings_enabled cstk; then
    return 0
  fi

  _dp_classic_root="${HOME:?HOME nao setado}/.claude/skills"
  _dp_project_settings="./.claude/settings.json"

  if ! _dp_plugin_root=$(plugin_install_path cstk); then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [undetermined] registro de instalacao do plugin ilegivel/ausente,\n'
      printf '                 apesar de settings.json indicar habilitado.\n'
      printf '                 Degradando para classic-only (nenhum erro fatal).\n'
    } >&2
    return 0
  fi

  # duplicated-hooks tem precedencia — checagem barata (grep -F, sem jq).
  # Olha os DOIS arquivos de registro do projeto (issue #135, `cstk hooks
  # install --local`): settings.json e settings.local.json somam.
  _dp_dup_files=""
  for _dp_f in "$_dp_project_settings" "./.claude/settings.local.json"; do
    if [ -f "$_dp_f" ] && grep -qF "pretooluse-bash-guard.sh" "$_dp_f" 2>/dev/null; then
      _dp_dup_files="${_dp_dup_files:+$_dp_dup_files, }$_dp_f"
    fi
  done
  if [ -n "$_dp_dup_files" ]; then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [duplicated-hooks] plugin habilitado E registro classico de hooks\n'
      printf '                     presente em %s\n' "$_dp_dup_files"
      printf '  remediacao: rode `cstk hooks install` no projeto — ele oferece remover\n'
      printf '              o registro classico (ou `--remove-classic` para nao perguntar).\n'
      printf '              Remove apenas as entradas dos hooks 00c, preserva hooks de\n'
      printf '              terceiros e grava backup em <arquivo>.bak-pre-dedup.\n'
      printf '              `cstk hooks status` mostra em qual arquivo esta cada registro.\n'
    } >&2
    return 1
  fi

  if [ ! -d "$_dp_classic_root" ]; then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [plugin-only] catalogo classico ausente (%s); so o plugin esta presente.\n' "$_dp_classic_root"
    } >&2
    return 0
  fi

  # Compara SO as skills que o cstk possui (nomes do manifest), nunca o
  # diretorio inteiro: `~/.claude/skills/` e compartilhado, e hashear tudo
  # fazia 13 skills de terceiro divergirem dois catalogos identicos no que
  # e do cstk. `evals/` (removida do tarball por build-release.sh) e
  # `.DS_Store` tambem saem — ver cabecalho de hash_dir_catalog.
  _dp_names=$(read_manifest "$(manifest_default_path "$_doctor_scope" skills)" 2>/dev/null \
    | awk -F'\t' '{print $1}' | grep -v '^#' | grep -v '^$')

  if [ -z "$_dp_names" ]; then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [undetermined] manifest de skills vazio/ilegivel — sem base para comparar.\n'
    } >&2
    return 0
  fi

  _dp_classic_hash=$(printf '%s\n' "$_dp_names" | hash_dir_catalog "$_dp_classic_root" 2>/dev/null) || _dp_classic_hash=""
  _dp_plugin_hash=$(printf '%s\n' "$_dp_names" | hash_dir_catalog "$_dp_plugin_root/skills" 2>/dev/null) || _dp_plugin_hash=""

  if [ -z "$_dp_classic_hash" ] || [ -z "$_dp_plugin_hash" ]; then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [undetermined] nao foi possivel calcular hash_dir de um dos dois caminhos.\n'
    } >&2
    return 0
  fi

  if [ "$_dp_classic_hash" = "$_dp_plugin_hash" ]; then
    {
      printf '\n==> Distribution Paths (plugin cstk)\n'
      printf '  [aligned] OK: catalogo classico e plugin alinhados (mesmo conteudo\n'
      printf '            nas skills do manifest do cstk).\n'
    } >&2
    return 0
  fi

  {
    printf '\n==> Distribution Paths (plugin cstk)\n'
    printf '  [diverged] catalogo classico e plugin tem conteudo diferente:\n'
    printf '    classico (%s): %s\n' "$_dp_classic_root" "$(printf '%s' "$_dp_classic_hash" | cut -c1-12)..."
    printf '    plugin   (%s): %s\n' "$_dp_plugin_root/skills" "$(printf '%s' "$_dp_plugin_hash" | cut -c1-12)..."
    printf '  remediacao: se o CLASSICO estiver desatualizado, rode `cstk update`;\n'
    printf '              se o PLUGIN estiver desatualizado, rode `/plugin update cstk@cstk`.\n'
    printf '              (o hash nao revela qual lado mudou por ultimo — confira qual\n'
    printf '              caminho voce atualizou mais recentemente.)\n'
  } >&2
  return 1
}

# _doctor_deps_run — modo `cstk doctor --deps` (feature state-backend-config,
# FASE 4, task 4.3). Read-only. Delega a decisao de backend a
# `state-backend.sh resolve` (via cli/lib/config.sh) — NAO reimplementa
# parsing de config nem logica de decisao. Detecta sqlite3/jq apenas para
# fins de RELATO (presenca + versao), nunca para decidir o backend.
#
# Relatorio SEMPRE em stdout (sucesso e anomalia — contrato de gate de CI,
# cli-surface.md). Exit 0 sem anomalia; 1 com >=1 anomalia. "Nunca
# configurado" NUNCA e anomalia (FR-008, data-model.md dominio de reason).
_doctor_deps_run() {
  _ddr_effective="json"
  _ddr_reason="desconhecido"

  if command -v config_state_backend_resolve >/dev/null 2>&1; then
    _ddr_resolve_out=$(config_state_backend_resolve 2>/dev/null) || _ddr_resolve_out=""
  else
    _ddr_resolve_out=""
  fi

  if [ -n "$_ddr_resolve_out" ]; then
    _ddr_old_ifs=$IFS
    IFS='
'
    for _ddr_line in $_ddr_resolve_out; do
      case "$_ddr_line" in
        effective_backend=*) _ddr_effective=${_ddr_line#effective_backend=} ;;
        reason=*)            _ddr_reason=${_ddr_line#reason=} ;;
      esac
    done
    IFS=$_ddr_old_ifs
  fi

  # Deteccao de sqlite3 (relato apenas). GOTCHA (research.md Decision 8):
  # sob `set -e` em chamadores estritos, `x=$(cmd); rc=$?` mataria o shell —
  # usa a forma `if x=$(cmd); then`.
  _ddr_sqlite_present="nao"
  _ddr_sqlite_version=""
  if command -v sqlite3 >/dev/null 2>&1; then
    _ddr_sqlite_present="sim"
    if _ddr_sqlite_raw=$(sqlite3 --version 2>/dev/null); then
      _ddr_sqlite_version=$(printf '%s\n' "$_ddr_sqlite_raw" | cut -d' ' -f1)
    fi
  fi

  # Deteccao de jq (relato apenas; ausencia e SEMPRE anomalia — vide
  # data-model.md, carve-out amendment 1.3.0 da constitution).
  _ddr_jq_present="nao"
  _ddr_jq_version=""
  if command -v jq >/dev/null 2>&1; then
    _ddr_jq_present="sim"
    if _ddr_jq_raw=$(jq --version 2>/dev/null); then
      _ddr_jq_version="$_ddr_jq_raw"
    fi
  fi

  _ddr_anomaly=0
  case "$_ddr_reason" in
    configurado-dependencia-abaixo-do-minimo|configurado-dependencia-ausente)
      _ddr_anomaly=1
      ;;
  esac
  if [ "$_ddr_jq_present" != "sim" ]; then
    _ddr_anomaly=1
  fi

  printf '==> cstk doctor --deps\n'
  printf '  sqlite3: presente=%s versao=%s minima=3.45.1\n' \
    "$_ddr_sqlite_present" "${_ddr_sqlite_version:-N/A}"
  printf '  jq:      presente=%s versao=%s\n' \
    "$_ddr_jq_present" "${_ddr_jq_version:-N/A}"
  printf '  effective_backend: %s\n' "$_ddr_effective"
  printf '  reason:            %s\n' "$_ddr_reason"
  if [ "$_ddr_anomaly" -eq 1 ]; then
    printf '  [ANOMALY] dependencia ausente ou abaixo do minimo suportado.\n'
  else
    printf '  ---\n  sem anomalias.\n'
  fi

  [ "$_ddr_anomaly" -eq 0 ]
}
