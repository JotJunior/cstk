# hooks.sh — deteccao de jq + merge de settings.json + fallback de paste manual.
#
# Ref: docs/specs/cstk-cli/spec.md §FR-009d
#      docs/constitution.md §Principio II (carve-out 1.1.0)
#      docs/specs/cstk-cli/quickstart.md Scenarios 4, 5
#      docs/specs/enforced-guards/{research.md Decision 9, data-model.md
#      GuardHookRegistration} — apply_guard_hooks (US1)
#
# **CONFINAMENTO DE jq (Constitution 1.1.0 §Optional dependencies)**:
# Este e o UNICO arquivo do toolkit autorizado a referenciar `jq`. A
# condicao (b) do carve-out exige confinamento em um unico arquivo; o
# resto do CLI MUST permanecer POSIX puro. Adicionar `jq` em qualquer
# outro `.sh` viola o carve-out e exige nova amendment de constituicao.
#
# Funcoes exportadas:
#   detect_jq                          — exit 0 se jq disponivel, 1 se nao
#   merge_settings <target> <source>   — merge JSON via jq (jq obrigatorio).
#                                         Source novas chaves entram, target
#                                         vence em conflitos. NUNCA executa
#                                         sem jq; NUNCA sobrescreve com `>`.
#   print_paste_block <target> <source>
#                                       — fallback sem jq: imprime bloco
#                                         JSON em stderr com instrucoes
#                                         para o usuario mesclar manualmente.
#   apply_guard_hooks <src_dir> <dest_claude_root> <dry_run>
#                                       — provisiona o hook PreToolUse/Bash
#                                         de enforced-guards (US1): copia
#                                         pretooluse-bash-guard.sh para
#                                         <dest_claude_root>/hooks/ e mescla
#                                         settings.snippet.json. Reusa
#                                         merge_settings/print_paste_block
#                                         (Decision 9 — nenhum mecanismo novo).
#                                         Imprime em stdout uma palavra de
#                                         estado: merged | paste-instructed |
#                                         hooks-only | not-applicable | error.
#
# Garantias defensivas:
#   - merge_settings aborta com exit 1 se jq nao detectado
#   - merge_settings preserva a copia original em <target>.bak antes de mv
#   - Escrita atomica via mktemp + mv
#   - test -f guards antes de qualquer leitura
#
# Deps: jq (opcional via carve-out), mktemp, mv, cp, cat, command, printf.

if [ -n "${_CSTK_HOOKS_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_HOOKS_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"

# detect_jq: imprime nada; retorna 0 se jq esta no PATH, 1 se nao.
detect_jq() {
  command -v jq >/dev/null 2>&1
}

# merge_settings: faz merge recursivo de <source> dentro de <target>.
# Politica: target vence em conflitos (preserva chaves pre-existentes
# nao-conflitantes do usuario). Source contribui chaves novas.
#
# Comportamento:
#   - jq ausente: aborta com exit 1 (use print_paste_block como alternativa)
#   - target nao existe: copia source -> target (sem merge necessario)
#   - target existe: jq -s '.[0] * .[1]' <source> <target> > tmp; mv tmp target
#     (atomic; cria backup .bak antes de sobrescrever)
#   - Validacao JSON: jq aborta com erro nao-zero se source ou target invalido
merge_settings() {
  if [ "$#" -ne 2 ]; then
    log_error "hooks: merge_settings espera 2 argumentos (target, source)"
    return 2
  fi
  _hooks_target=$1
  _hooks_source=$2

  if ! detect_jq; then
    log_error "hooks: merge_settings exige jq (carve-out 1.1.0); use print_paste_block como fallback"
    return 1
  fi
  if [ ! -f "$_hooks_source" ]; then
    log_error "hooks: source JSON nao encontrado: $_hooks_source"
    return 1
  fi

  _hooks_target_dir=$(dirname -- "$_hooks_target")
  if [ ! -d "$_hooks_target_dir" ]; then
    if ! mkdir -p -- "$_hooks_target_dir"; then
      log_error "hooks: nao consegui criar dir pai de $_hooks_target"
      return 1
    fi
  fi

  # Caso 1: target nao existe -> apenas copia source
  if [ ! -f "$_hooks_target" ]; then
    if ! cp -- "$_hooks_source" "$_hooks_target"; then
      log_error "hooks: cp inicial falhou para $_hooks_target"
      return 1
    fi
    log_info "hooks: $_hooks_target criado a partir de $_hooks_source"
    return 0
  fi

  # Caso 2: target existe -> jq merge (target vence)
  # Backup defensivo. test -f guard ja garantiu existencia.
  if ! cp -- "$_hooks_target" "${_hooks_target}.bak"; then
    log_error "hooks: backup de $_hooks_target falhou — abortando sem merge"
    return 1
  fi

  _hooks_tmp=$(mktemp -- "${_hooks_target_dir}/.cstk-merge.XXXXXX") || {
    log_error "hooks: mktemp em $_hooks_target_dir falhou"
    return 1
  }

  # jq -s slurp: le ambos como array; .[0] * .[1] = merge recursivo, segundo vence.
  # Source primeiro, target segundo => target vence em conflitos.
  if ! jq -s '.[0] * .[1]' -- "$_hooks_source" "$_hooks_target" > "$_hooks_tmp" 2>/dev/null; then
    log_error "hooks: jq merge falhou (JSON invalido em source ou target?)"
    rm -f -- "$_hooks_tmp"
    return 1
  fi

  if ! mv -f -- "$_hooks_tmp" "$_hooks_target"; then
    log_error "hooks: mv atomico falhou para $_hooks_target"
    rm -f -- "$_hooks_tmp"
    return 1
  fi

  log_info "hooks: $_hooks_target mesclado (backup em ${_hooks_target}.bak)"
  return 0
}

# print_paste_block: fallback quando jq ausente. Imprime em stderr o JSON
# do source com instrucao clara de onde colar. NUNCA modifica o filesystem.
print_paste_block() {
  if [ "$#" -ne 2 ]; then
    log_error "hooks: print_paste_block espera 2 argumentos (target, source)"
    return 2
  fi
  _pb_target=$1
  _pb_source=$2
  if [ ! -f "$_pb_source" ]; then
    log_error "hooks: source JSON nao encontrado: $_pb_source"
    return 1
  fi
  {
    printf '\n'
    printf '# Hooks to merge manually into %s:\n' "$_pb_target"
    printf '#   1. Abra (ou crie) %s\n' "$_pb_target"
    printf '#   2. Cole o bloco abaixo dentro do objeto raiz, mesclando\n'
    printf '#      chaves existentes manualmente em caso de conflito.\n'
    printf '#   3. Instale jq para automatizar este passo no proximo install.\n'
    printf '# ----- BEGIN PAYLOAD -----\n'
    cat -- "$_pb_source"
    printf '\n# ----- END PAYLOAD -----\n'
  } >&2
  return 0
}

# apply_guard_hooks <src_dir> <dest_claude_root> <dry_run>
#
# Provisiona os hooks de execucao 00c num projeto-alvo:
#   1. Copia <src_dir>/pretooluse-bash-guard.sh para
#      <dest_claude_root>/hooks/pretooluse-bash-guard.sh (chmod +x) —
#      enforced-guards US1, FR-004, research.md Decision 9.
#   1b. Copia <src_dir>/posttooluse-tool-call-tick.sh (metrica de tool
#      calls por onda, sidecar tool-call-ticks.log) quando presente no
#      catalogo. BEST-EFFORT: ausencia (catalogo antigo) ou falha de cp
#      NAO muda a palavra de estado nem aborta — e metrica, nao guarda.
#   2. Mescla <src_dir>/settings.snippet.json em
#      <dest_claude_root>/settings.json via merge_settings (jq) ou
#      print_paste_block (fallback sem jq) — mesma mecanica ja testada dos
#      hooks language-*, nenhum mecanismo de distribuicao novo (FR-017).
#
# <src_dir> = diretorio contendo pretooluse-bash-guard.sh +
# settings.snippet.json (tipicamente <catalog>/skills/agente-00c-runtime/hooks,
# tanto no install quanto no update — cada caller resolve o catalog dir
# apropriado e passa aqui; esta funcao e agnostica a install vs update).
#
# dry_run=1: so reporta via log_info, nao escreve nada no disco.
#
# Chamador e responsavel por decidir SE deve chamar (skill agente-00c-runtime
# resolvida para instalacao/atualizacao E escopo=project — Decision 9 diz
# que --scope global sempre pula, mesma regra ja aplicada a language-*).
#
# Retorno: imprime em stdout UMA palavra de estado (sem newline extra):
#   merged           — settings.json mesclado via jq
#   paste-instructed — jq ausente, bloco impresso em stderr p/ colar manual
#   hooks-only       — script copiado mas settings.snippet.json ausente
#   not-applicable   — <src_dir> ou o proprio script ausente (skill nao
#                      trouxe hooks/ nesta instalacao — nao e erro)
#   error            — falha de I/O (mkdir/cp/merge)
apply_guard_hooks() {
  if [ "$#" -ne 3 ]; then
    log_error "hooks: apply_guard_hooks espera 3 argumentos (src_dir, dest_claude_root, dry_run)"
    printf '%s' "error"
    return 2
  fi
  _agh_src=$1
  _agh_dest_root=$2
  _agh_dry_run=$3

  if [ ! -d "$_agh_src" ]; then
    log_warn "hooks: guard-hooks source ausente: $_agh_src"
    printf '%s' "not-applicable"
    return 0
  fi

  _agh_hook_script="$_agh_src/pretooluse-bash-guard.sh"
  _agh_snippet="$_agh_src/settings.snippet.json"
  _agh_hooks_dst="$_agh_dest_root/hooks"
  _agh_settings_dst="$_agh_dest_root/settings.json"

  if [ ! -f "$_agh_hook_script" ]; then
    log_warn "hooks: pretooluse-bash-guard.sh ausente em $_agh_src"
    printf '%s' "not-applicable"
    return 0
  fi

  _agh_tick_script="$_agh_src/posttooluse-tool-call-tick.sh"

  if [ "$_agh_dry_run" = 1 ]; then
    log_info "[dry-run] guard-hooks: copiaria $_agh_hook_script -> $_agh_hooks_dst/pretooluse-bash-guard.sh"
    if [ -f "$_agh_tick_script" ]; then
      log_info "[dry-run] guard-hooks: copiaria $_agh_tick_script -> $_agh_hooks_dst/posttooluse-tool-call-tick.sh"
    fi
    if [ -f "$_agh_snippet" ]; then
      if detect_jq; then
        log_info "[dry-run] guard-hooks: mesclaria $_agh_snippet -> $_agh_settings_dst (jq)"
        printf '%s' "merged"
      else
        log_info "[dry-run] guard-hooks: imprimiria paste-block (jq ausente)"
        printf '%s' "paste-instructed"
      fi
    else
      printf '%s' "hooks-only"
    fi
    return 0
  fi

  if ! mkdir -p -- "$_agh_hooks_dst" 2>/dev/null; then
    log_error "hooks: nao consegui criar $_agh_hooks_dst"
    printf '%s' "error"
    return 0
  fi
  if ! cp -- "$_agh_hook_script" "$_agh_hooks_dst/pretooluse-bash-guard.sh"; then
    log_error "hooks: cp de pretooluse-bash-guard.sh falhou"
    printf '%s' "error"
    return 0
  fi
  chmod +x -- "$_agh_hooks_dst/pretooluse-bash-guard.sh" 2>/dev/null || :
  log_info "hooks: pretooluse-bash-guard.sh provisionado em $_agh_hooks_dst"

  # Hook de metrica (best-effort): falha aqui nunca degrada o provisionamento
  # do guard — subcontagem de tool_calls e aceitavel, guard ausente nao.
  if [ -f "$_agh_tick_script" ]; then
    if cp -- "$_agh_tick_script" "$_agh_hooks_dst/posttooluse-tool-call-tick.sh" 2>/dev/null; then
      chmod +x -- "$_agh_hooks_dst/posttooluse-tool-call-tick.sh" 2>/dev/null || :
      log_info "hooks: posttooluse-tool-call-tick.sh provisionado em $_agh_hooks_dst"
    else
      log_warn "hooks: cp de posttooluse-tool-call-tick.sh falhou — metrica de tool calls indisponivel (guard intacto)"
    fi
  fi

  if [ ! -f "$_agh_snippet" ]; then
    log_info "hooks: settings.snippet.json ausente em $_agh_src — so hook copiado"
    printf '%s' "hooks-only"
    return 0
  fi

  if detect_jq; then
    if merge_settings "$_agh_settings_dst" "$_agh_snippet"; then
      printf '%s' "merged"
    else
      printf '%s' "error"
    fi
  else
    print_paste_block "$_agh_settings_dst" "$_agh_snippet"
    printf '%s' "paste-instructed"
  fi
  return 0
}
