#!/bin/sh
# validate-sdd.sh — motor deterministico dos perfis spec-profile e
# plan-profile da skill validate-documentation.
#
# Ref: docs/specs/validate-docs-sdd-profile/contracts/validate-sdd-cli.md
#      docs/specs/validate-docs-sdd-profile/quickstart.md (12 cenarios)
#      docs/specs/validate-docs-sdd-profile/spec.md FR-001..FR-018
#
# Uso:
#   validate-sdd.sh FILE [--sdd-spec | --sdd-plan] [--spec SPEC_MD]
#
#   --sdd-spec        Forca o spec-profile (ignora deteccao por path).
#   --sdd-plan        Forca o plan-profile (ignora deteccao por path).
#   --spec SPEC_MD    spec.md explicita para o check dangling-fr-sc-ref.
#                      Default: <dir-de-FILE>/spec.md (convencao
#                      docs/specs/<feature>/), so quando FILE segue essa
#                      convencao.
#
# Selecao de perfil (precedencia — FR-014/FR-015/FR-016):
#   1. Flag explicita --sdd-spec/--sdd-plan vence tudo.
#   2. Deteccao automatica por convencao de path:
#        */docs/specs/<feature>/spec.md                    -> spec-profile
#        */docs/specs/<feature>/{plan,research,data-model,
#          quickstart}.md ou .../contracts/*.md             -> plan-profile
#   3. Nem flag nem convencao -> perfil indeterminado, exit 2.
#
# Saida (stdout), uma linha por achado + linha de resultado final:
#   FINDING|<severity>|<code>|<mensagem>
#   RESULT|<file>|profile=<spec|plan>|errors=<N>|warnings=<M>
#   severity in {error, warning, info}
#
# Exit codes:
#   0  zero achados de severidade error (avisos/infos nao bloqueiam)
#   1  >=1 achado error
#   2  uso incorreto / arquivo inexistente / flags conflitantes / perfil
#      indeterminado
#
# POSIX sh puro (Constitution II) — sem bash-ismos, sem GNU-only.

set -eu

_VSDD_NAME="validate-sdd"

usage() {
  cat <<'USAGE' >&2
Uso: validate-sdd.sh FILE [--sdd-spec | --sdd-plan] [--spec SPEC_MD]

Valida FILE contra o spec-profile ou plan-profile da skill
validate-documentation. Perfil resolvido por flag explicita ou por
deteccao automatica de path (docs/specs/<feature>/...).

Emite linhas FINDING|severity|code|msg e uma linha RESULT final.
Exit: 0 conformante (so avisos/infos); 1 reprovado (>=1 erro);
2 uso incorreto / arquivo ausente / perfil indeterminado.
USAGE
}

FILE=""
FORCE_SPEC=0
FORCE_PLAN=0
SPEC_MD_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --sdd-spec)
      FORCE_SPEC=1; shift ;;
    --sdd-plan)
      FORCE_PLAN=1; shift ;;
    --spec)
      [ $# -ge 2 ] || { usage; exit 2; }
      SPEC_MD_ARG="$2"; shift 2 ;;
    --spec=*)
      SPEC_MD_ARG="${1#--spec=}"; shift ;;
    -h|--help)
      usage; exit 2 ;;
    --*)
      printf '%s: opcao desconhecida: %s\n' "$_VSDD_NAME" "$1" >&2
      usage; exit 2 ;;
    *)
      if [ -z "$FILE" ]; then FILE="$1"; shift
      else
        printf '%s: argumento extra: %s\n' "$_VSDD_NAME" "$1" >&2
        usage; exit 2
      fi ;;
  esac
done

if [ -z "$FILE" ]; then
  usage; exit 2
fi

if [ "$FORCE_SPEC" -eq 1 ] && [ "$FORCE_PLAN" -eq 1 ]; then
  printf '%s: --sdd-spec e --sdd-plan sao mutuamente exclusivas\n' "$_VSDD_NAME" >&2
  exit 2
fi

if [ ! -f "$FILE" ]; then
  printf '%s: arquivo nao encontrado: %s\n' "$_VSDD_NAME" "$FILE" >&2
  exit 2
fi

# --- Selecao de perfil ---------------------------------------------------

PROFILE=""

# Prefixa com "./" quando FILE e relativo e ja comeca literalmente com
# "docs/specs/..." — assim UM SO padrao ("*/docs/specs/...") cobre tanto o
# path absoluto (/repo/docs/specs/...) quanto o relativo (que sem esse
# prefixo nao teria "/" antes de "docs" e o glob "*/" nao bateria). Sempre
# calculado (mesmo com flag explicita) porque a resolucao do --spec default
# mais abaixo tambem depende dele.
case "$FILE" in
  docs/specs/*) _detect_path="./$FILE" ;;
  *) _detect_path="$FILE" ;;
esac

if [ "$FORCE_SPEC" -eq 1 ]; then
  PROFILE="spec"
elif [ "$FORCE_PLAN" -eq 1 ]; then
  PROFILE="plan"
else
  case "$_detect_path" in
    */docs/specs/*/spec.md)
      PROFILE="spec" ;;
    */docs/specs/*/plan.md|*/docs/specs/*/research.md|*/docs/specs/*/data-model.md|*/docs/specs/*/quickstart.md)
      PROFILE="plan" ;;
    */docs/specs/*/contracts/*.md)
      PROFILE="plan" ;;
    *)
      PROFILE="" ;;
  esac
fi

if [ -z "$PROFILE" ]; then
  printf "Perfil nao determinado para '%s': path fora da convencao docs/specs/<feature>/ e nenhuma flag informada. Use --sdd-spec ou --sdd-plan.\n" "$FILE" >&2
  exit 2
fi

# --- Resolucao do --spec default (so quando FILE segue a convencao) -----
# A flag explicita --spec aceita QUALQUER path (inclusive fixtures de
# teste fora de docs/specs/) — a restricao de convencao aplica-se SOMENTE
# ao default automatico (CHK014).

SPEC_MD="$SPEC_MD_ARG"
if [ -z "$SPEC_MD" ]; then
  case "$_detect_path" in
    */docs/specs/*/contracts/*.md)
      _dir=$(dirname "$FILE")
      _parent=$(dirname "$_dir")
      SPEC_MD="$_parent/spec.md" ;;
    */docs/specs/*/*.md)
      _dir=$(dirname "$FILE")
      SPEC_MD="$_dir/spec.md" ;;
    *)
      SPEC_MD="" ;;
  esac
fi

# Buffer de findings em arquivo temporario, nao em contador de variavel de
# shell. Alguns checks abaixo iteram matches via `printf ... | while read`,
# e esse padrao roda o corpo do loop em SUBSHELL no POSIX sh — incrementos
# em variavel global feitos de dentro do subshell somem quando ele termina
# (mesma classe de bug documentada em validate-docs-rendered/validate.sh:
# "padrao defeituoso HISTORICO"). Escrever em arquivo via `>>` e seguro
# porque e I/O real, nao estado de variavel — sobrevive ao fim do subshell.
FINDINGS_TMP=$(mktemp)
trap 'rm -f "$FINDINGS_TMP"' EXIT

emit() { # emit SEVERITY CODE MSG
  printf 'FINDING|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS_TMP"
}

has_section() { # has_section HEADER_TEXT
  grep -qE "^##[[:space:]]+${1}[[:space:]]*\$" "$FILE" 2>/dev/null
}

count_matches() { # count_matches REGEX -> stdout N (0 se nenhuma)
  _n=$(grep -cE "$1" "$FILE" 2>/dev/null) || _n=0
  printf '%s' "$_n"
}

# ==========================================================================
# spec-profile (US1) — FR-001..FR-007 + duplicate-id (Gotcha "IDs
# duplicados dentro do mesmo documento sao erro, nao aviso" do SKILL.md)
# ==========================================================================

validate_spec_profile() {
  # FR-001 — 3 secoes obrigatorias
  for _sec in "User Scenarios & Testing" "Requirements" "Success Criteria"; do
    has_section "$_sec" \
      || emit error missing-section "Secao obrigatoria ausente: ${_sec}"
  done

  # FR-004 — no maximo 3 [NEEDS CLARIFICATION]. Casa so o prefixo (nao
  # exige "]" imediato) porque o formato real usado por /specify inclui a
  # pergunta inline: "[NEEDS CLARIFICATION: pergunta especifica]"
  # (specify/SKILL.md:230) — nao apenas o marcador bare.
  _nc=$(count_matches '\[NEEDS CLARIFICATION')
  if [ "$_nc" -gt 3 ]; then
    emit error too-many-clarifications "contagem=${_nc} excede limite=3 de marcadores [NEEDS CLARIFICATION]"
  fi

  # duplicate-id — ID FR-/SC- definido (formato **FR-NNN**) mais de uma vez.
  # Reusa a convencao ja aplicada ao perfil UC existente (SKILL.md, Gotcha
  # "IDs duplicados dentro do mesmo documento sao erro, nao aviso") — nao
  # introduz FR novo (CHK004/CHK013 [Gap] resolvido em create-tasks).
  _dup_ids=$(grep -oE '\*\*(FR|SC)-[0-9]+\*\*' "$FILE" 2>/dev/null \
    | tr -d '*' | sort | uniq -d) || _dup_ids=""
  if [ -n "$_dup_ids" ]; then
    for _id in $_dup_ids; do
      emit error duplicate-id "ID duplicado dentro do documento: ${_id}"
    done
  fi

  # FR-002 — termo de stack/framework/lib especifica no corpo da spec.
  # Wordlist calibrada contra specify/examples/spec-bad.md anti-padrao 1
  # (bcrypt, PostgreSQL) — deliberadamente restrita a nomes concretos de
  # linguagem/framework/lib/DB, nao termos genericos de dominio (API, CLI,
  # JSON, Bash) que aparecem legitimamente em specs de ferramentas de dev.
  _impl_regex='\<(bcrypt|argon2|postgresql|postgres|mysql|mongodb|redis|kafka|rabbitmq|react|vue\.js|angular|django|flask|fastapi|spring|rails|laravel|express\.js|node\.js|typescript|javascript|graphql|grpc)\>'
  _impl_hits=$(grep -inE "$_impl_regex" "$FILE" 2>/dev/null) || _impl_hits=""
  if [ -n "$_impl_hits" ]; then
    printf '%s\n' "$_impl_hits" | while IFS=: read -r _ln _rest; do
      _term=$(printf '%s' "$_rest" | grep -oiE "$_impl_regex" | head -n 1)
      emit error impl-detail-in-spec "Termo de implementacao/stack na linha ${_ln}: ${_term}"
    done
  fi

  # FR-003 — Success Criterion sem metrica quantificavel OU com jargao
  # tecnico. Escopo: linhas de item de lista dentro de Success Criteria
  # (**SC-NNN**: ...).
  _sc_lines=$(grep -nE '^\s*-\s+\*\*SC-[0-9]+\*\*' "$FILE" 2>/dev/null) || _sc_lines=""
  if [ -n "$_sc_lines" ]; then
    printf '%s\n' "$_sc_lines" | while IFS=: read -r _ln _rest; do
      _sc_id=$(printf '%s' "$_rest" | grep -oE 'SC-[0-9]+' | head -n 1)
      # "API" (idem "CLI"/"JSON") NAO entra aqui: e termo generico de
      # dominio, legitimo em specs de ferramentas de dev — o SKILL.md
      # promete explicitamente que nao dispara falso-positivo. Reproduzido
      # em campo: SC-002 com "servicos Go que expoem API HTTP" era
      # rejeitado. Ficam so termos de performance de implementacao.
      if printf '%s' "$_rest" | grep -qiE '\<(TPS|paint time|render time)\>'; then
        emit error sc-not-measurable "${_sc_id} usa jargao tecnico de implementacao (linha ${_ln})"
      elif ! printf '%s' "$_rest" | grep -qE '[0-9]'; then
        emit error sc-not-measurable "${_sc_id} sem metrica quantificavel (linha ${_ln})"
      fi
    done
  fi

  # FR-005 — secao deixada com placeholder N/A residual (aviso).
  _na_lines=$(count_matches '^[[:space:]]*N/A[[:space:]]*$')
  if [ "$_na_lines" -gt 0 ]; then
    emit warning na-placeholder-section "Secao com placeholder 'N/A' residual em vez de removida (${_na_lines} ocorrencia(s))"
  fi

  # FR-006 — adjetivo vago sem quantificacao em Requirements/Success
  # Criteria. Escopo restrito ao padrao "MUST (be) <adj>" / "deve ser
  # <adj>" para minimizar falso-positivo contra prosa legitima (ex.:
  # "diagnostico rapido" fora desse padrao NAO dispara).
  _vague_en='MUST[[:space:]]+(be[[:space:]]+)?(fast|secure|robust|intuitive|simple|responsive|efficient|reliable|scalable|user-friendly|easy)\>'
  _vague_pt='deve[[:space:]]+ser[[:space:]]+(rapido|simples|robusto|seguro|intuitivo|eficiente|responsivo|confiavel|escalavel)\>'
  _vague_hits=$(grep -inE "${_vague_en}|${_vague_pt}" "$FILE" 2>/dev/null) || _vague_hits=""
  if [ -n "$_vague_hits" ]; then
    printf '%s\n' "$_vague_hits" | while IFS=: read -r _ln _rest; do
      emit warning vague-adjective "Adjetivo vago sem quantificacao na linha ${_ln}"
    done
  fi

  # FR-007 — user story acoplada a outra (nao testavel isoladamente).
  if grep -qiE '\(requer[[:space:]].*(story|completa)' "$FILE" 2>/dev/null; then
    emit warning coupled-user-story "User story parece depender de outra para ser testada isoladamente (padrao '(requer ...')"
  fi
}

# ==========================================================================
# plan-profile (US2) — FR-008..FR-012
# ==========================================================================

validate_plan_profile() {
  _base=$(basename "$FILE")
  _is_plan_md=0
  [ "$_base" = "plan.md" ] && _is_plan_md=1
  _is_contract=0
  case "$FILE" in
    */contracts/*.md) _is_contract=1 ;;
  esac

  # FR-008 — 4 secoes obrigatorias, so em plan.md
  if [ "$_is_plan_md" -eq 1 ]; then
    for _sec in "Summary" "Technical Context" "Constitution Check" "Project Structure"; do
      has_section "$_sec" \
        || emit error missing-section "Secao obrigatoria ausente: ${_sec}"
    done
  fi

  # FR-009 — placeholder de template nao preenchido, em qualquer artefato
  # /plan (plan.md, research.md, data-model.md, quickstart.md, contracts).
  # Listas paralelas (regex ERE escapada / texto literal para a mensagem) em
  # vez de derivar o texto via tr -d — mais simples que desescapar em runtime.
  _tok_idx=0
  for _tok_regex in '\[FEATURE\]' '\[DATE\]' '\[short-name\]' '\[Topico\]' '\[Endpoint/Command/Event\]'; do
    _tok_idx=$((_tok_idx + 1))
    case "$_tok_idx" in
      1) _tok_display='[FEATURE]' ;;
      2) _tok_display='[DATE]' ;;
      3) _tok_display='[short-name]' ;;
      4) _tok_display='[Topico]' ;;
      5) _tok_display='[Endpoint/Command/Event]' ;;
    esac
    _hits=$(count_matches "$_tok_regex")
    if [ "$_hits" -gt 0 ]; then
      emit error template-placeholder "Token de template nao preenchido: ${_tok_display} (${_hits} ocorrencia(s))"
    fi
  done

  # FR-011 — [NEEDS CLARIFICATION] remanescente, so em plan.md
  if [ "$_is_plan_md" -eq 1 ]; then
    _nc=$(count_matches '\[NEEDS CLARIFICATION')
    if [ "$_nc" -gt 0 ]; then
      emit error residual-clarification "plan.md contem ${_nc} marcador(es) [NEEDS CLARIFICATION] remanescente(s)"
    fi
  fi

  # FR-010 — entrada de contracts/*.md sem rotulo real-vs-proposto.
  # Heuristico documento-nivel (research.md Decision 6/CHK015): se o
  # arquivo documenta um Command/Endpoint/Event (heading dedicado) e NAO
  # contem NENHUM rotulo real-vs-proposto reconhecido em todo o
  # documento, reporta erro. Fronteira: nao resolve link/anchor (FR-013).
  if [ "$_is_contract" -eq 1 ]; then
    _entry_hits=$(count_matches '^#{1,3}[[:space:]].*\<(Command|Endpoint|Event)\>')
    if [ "$_entry_hits" -gt 0 ]; then
      _label_hits=$(count_matches '\[PROPOSTA|\[EXISTENTE')
      if [ "$_label_hits" -eq 0 ]; then
        emit error unlabeled-contract "Entrada de contrato sem rotulo inequivoco real-vs-proposto ([PROPOSTA ...] ou equivalente)"
      fi
    fi
  fi

  # FR-012 — ID FR-/SC- citado em plan.md que nao existe na spec.md
  # correspondente. Checagem SEMANTICA apenas (FR-013): nunca resolve
  # path/anchor no disco.
  if [ "$_is_plan_md" -eq 1 ]; then
    if [ -n "$SPEC_MD" ] && [ -f "$SPEC_MD" ]; then
      _cited=$(grep -oE '\<(FR|SC)-[0-9]+\>' "$FILE" 2>/dev/null | sort -u) || _cited=""
      if [ -n "$_cited" ]; then
        for _id in $_cited; do
          if ! grep -qE "\*\*${_id}\*\*" "$SPEC_MD" 2>/dev/null; then
            emit error dangling-fr-sc-ref "plan.md cita ${_id}, ausente na spec.md correspondente (${SPEC_MD})"
          fi
        done
      fi
    fi
  fi
}

# ==========================================================================

if [ "$PROFILE" = "spec" ]; then
  validate_spec_profile
else
  validate_plan_profile
fi

# Recalcula contadores a partir do arquivo (nao de variavel incrementada em
# subshell — ver comentario acima de FINDINGS_TMP). VAR=$(grep -c ...) || VAR=0
# e o padrao seguro (grep -c sai 1 sem match, imprimindo "0"; o || so
# dispara no exit code, nunca duplica a saida).
ERRORS=$(grep -c '^FINDING|error|' "$FINDINGS_TMP" 2>/dev/null) || ERRORS=0
WARNINGS=$(grep -c '^FINDING|warning|' "$FINDINGS_TMP" 2>/dev/null) || WARNINGS=0
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}

cat "$FINDINGS_TMP"
printf 'RESULT|%s|profile=%s|errors=%d|warnings=%d\n' "$FILE" "$PROFILE" "$ERRORS" "$WARNINGS"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0
