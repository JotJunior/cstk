# hooks.sh — deteccao de jq + merge de settings.json + fallback de paste manual.
#
# Ref: docs/specs/cstk-cli/spec.md §FR-009d
#      docs/constitution.md §Principio II (carve-out 1.1.0)
#      docs/specs/cstk-cli/quickstart.md Scenarios 4, 5
#      docs/specs/enforced-guards/{research.md Decision 9, data-model.md
#      GuardHookRegistration} — apply_guard_hooks (US1)
#
# **CONFINAMENTO DE jq (Constitution 1.1.0 §Optional dependencies)**:
# A condicao (b) do carve-out exige que cada introducao de `jq` fique
# confinada a UM arquivo fonte identificavel (nao que exista um unico
# arquivo autorizado em todo o toolkit — varios ja usam jq sob a mesma
# regra, ex. doctor.sh, recall.sh, plugin-detect.sh). Este arquivo e o
# confinamento original da feature `cstk-cli` (merge de settings.json).
# Adicionar jq num arquivo NOVO exige apenas declarar a dependencia no
# spec/plan da feature que a introduz (condicao c) — nao uma amendment.
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
#   merge_settings_loose_usage <target> <source>
#                                       — append idempotente (NAO jq '*')
#                                         do hook opt-in de consumo avulso
#                                         no array .hooks.PostToolUse[]
#                                         ja populado pelo merge_settings
#                                         base (loose-usage-capture task 3.3).
#   apply_guard_hooks <src_dir> <dest_claude_root> <dry_run> [with_loose_usage]
#                                       — provisiona o hook PreToolUse/Bash
#                                         de enforced-guards (US1): copia
#                                         pretooluse-bash-guard.sh para
#                                         <dest_claude_root>/hooks/ e mescla
#                                         settings.snippet.json. Reusa
#                                         merge_settings/print_paste_block
#                                         (Decision 9 — nenhum mecanismo novo).
#                                         with_loose_usage=1 (opt-in, default
#                                         0) tambem provisiona
#                                         posttooluse-loose-usage.sh.
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
# shellcheck source=./plugin-detect.sh
# Dedup plugin-vence (FR-005, feature claude-plugin-packaging FASE 6):
# hooks_main() consulta plugin_enabled/plugin_hooks_present antes de
# provisionar o snippet classico. Ver contracts/cli-plugin-awareness.md.
. "${CSTK_LIB}/plugin-detect.sh"

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

# merge_settings_loose_usage TARGET SOURCE
#
# Merge ADITIVO especializado para o hook OPT-IN de captura de consumo
# avulso (posttooluse-loose-usage.sh, feature loose-usage-capture task
# 3.3). NAO reusa merge_settings (jq '*' generico): jq's `*` NAO faz merge
# recursivo de ARRAYS — quando os dois lados tem `.hooks.PostToolUse` como
# array, o SEGUNDO operando vence POR INTEIRO, descartando o primeiro
# (verificado empiricamente: `jq -s '.[0]*.[1]'` com dois arrays sempre
# devolve o array do segundo operando, nunca uma uniao). Como o snippet
# base (settings.snippet.json) ja populou target.hooks.PostToolUse com as
# 2 entradas obrigatorias (tick + agent-usage) ANTES deste merge rodar,
# aplicar merge_settings aqui perderia o hook opt-in silenciosamente.
#
# Estrategia: acha (ou cria) a entrada de matcher "*" dentro de
# .hooks.PostToolUse e APPENDA o comando do SOURCE ao array .hooks[] dessa
# entrada, dedup por `.command` (idempotente — reinstalar nao duplica).
# jq obrigatorio (mesmo carve-out de merge_settings); target inexistente
# apenas copia o source (source ja e um settings.json valido e minimo).
merge_settings_loose_usage() {
  if [ "$#" -ne 2 ]; then
    log_error "hooks: merge_settings_loose_usage espera 2 argumentos (target, source)"
    return 2
  fi
  _hooks_target=$1
  _hooks_source=$2

  if ! detect_jq; then
    log_error "hooks: merge_settings_loose_usage exige jq (carve-out 1.1.0); use print_paste_block como fallback"
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

  # Caso 1: target nao existe -> apenas copia source (ja e um settings.json
  # minimo valido, mesmo caso 1 de merge_settings).
  if [ ! -f "$_hooks_target" ]; then
    if ! cp -- "$_hooks_source" "$_hooks_target"; then
      log_error "hooks: cp inicial falhou para $_hooks_target"
      return 1
    fi
    log_info "hooks: $_hooks_target criado a partir de $_hooks_source"
    return 0
  fi

  _hooks_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command // empty' -- "$_hooks_source" 2>/dev/null)
  _hooks_timeout=$(jq -r '.hooks.PostToolUse[0].hooks[0].timeout // 5' -- "$_hooks_source" 2>/dev/null)
  if [ -z "$_hooks_cmd" ]; then
    log_error "hooks: source $_hooks_source nao tem o formato esperado (hooks.PostToolUse[0].hooks[0].command)"
    return 1
  fi

  # Caso 2: target existe -> backup defensivo + append idempotente.
  if ! cp -- "$_hooks_target" "${_hooks_target}.bak"; then
    log_error "hooks: backup de $_hooks_target falhou — abortando sem merge"
    return 1
  fi

  _hooks_tmp=$(mktemp -- "${_hooks_target_dir}/.cstk-merge.XXXXXX") || {
    log_error "hooks: mktemp em $_hooks_target_dir falhou"
    return 1
  }

  if ! jq --arg cmd "$_hooks_cmd" --argjson timeout "$_hooks_timeout" '
    .hooks.PostToolUse = ((.hooks.PostToolUse // [])
      | if any(.[]; .matcher == "*") then
          map(
            if .matcher == "*" then
              .hooks = (
                (.hooks // []) as $eh
                | if ($eh | map(.command) | index($cmd)) then $eh
                  else $eh + [{"type":"command","command":$cmd,"timeout":$timeout}]
                  end
              )
            else . end
          )
        else
          . + [{"matcher":"*","hooks":[{"type":"command","command":$cmd,"timeout":$timeout}]}]
        end)
  ' -- "$_hooks_target" > "$_hooks_tmp" 2>/dev/null; then
    log_error "hooks: jq append falhou (JSON invalido em target?)"
    rm -f -- "$_hooks_tmp"
    return 1
  fi

  if ! mv -f -- "$_hooks_tmp" "$_hooks_target"; then
    log_error "hooks: mv atomico falhou para $_hooks_target"
    rm -f -- "$_hooks_tmp"
    return 1
  fi

  log_info "hooks: $_hooks_target mesclado com hook opt-in de consumo avulso (backup em ${_hooks_target}.bak)"
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
#   1c. Copia <src_dir>/posttooluse-agent-usage.sh (metrica de uso de
#      tokens/tool-uses/duracao por spawn de subagente, sidecar
#      wave-agent-usage.jsonl — wave-token-metrics FASE 2) quando presente
#      no catalogo. Mesma politica BEST-EFFORT do item 1b.
#   2. Mescla <src_dir>/settings.snippet.json em
#      <dest_claude_root>/settings.json via merge_settings (jq) ou
#      print_paste_block (fallback sem jq) — mesma mecanica ja testada dos
#      hooks language-*, nenhum mecanismo de distribuicao novo (FR-017).
#   3. SOMENTE quando <with_loose_usage>=1 (opt-in, default 0 — feature
#      loose-usage-capture task 3.3): copia
#      <src_dir>/posttooluse-loose-usage.sh e mescla (append idempotente,
#      via merge_settings_loose_usage) <src_dir>/settings.loose-usage.snippet.json.
#      Best-effort — falha aqui NUNCA muda a palavra de estado nem os
#      3 hooks obrigatorios (dec-008/FR-006).
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
# Retorno: imprime em stdout UMA palavra de estado (sem newline extra),
# SEMPRE derivada dos 3 hooks OBRIGATORIOS (o opt-in de item 3 nunca altera
# esta palavra — best-effort separado):
#   merged           — settings.json mesclado via jq
#   paste-instructed — jq ausente, bloco impresso em stderr p/ colar manual
#   hooks-only       — script copiado mas settings.snippet.json ausente
#   not-applicable   — <src_dir> ou o proprio script ausente (skill nao
#                      trouxe hooks/ nesta instalacao — nao e erro)
#   error            — falha de I/O (mkdir/cp/merge)
apply_guard_hooks() {
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    log_error "hooks: apply_guard_hooks espera 3 ou 4 argumentos (src_dir, dest_claude_root, dry_run, [with_loose_usage])"
    printf '%s' "error"
    return 2
  fi
  _agh_src=$1
  _agh_dest_root=$2
  _agh_dry_run=$3
  _agh_with_loose=${4:-0}

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
  _agh_usage_script="$_agh_src/posttooluse-agent-usage.sh"
  _agh_loose_script="$_agh_src/posttooluse-loose-usage.sh"
  _agh_loose_snippet="$_agh_src/settings.loose-usage.snippet.json"

  if [ "$_agh_dry_run" = 1 ]; then
    log_info "[dry-run] guard-hooks: copiaria $_agh_hook_script -> $_agh_hooks_dst/pretooluse-bash-guard.sh"
    if [ -f "$_agh_tick_script" ]; then
      log_info "[dry-run] guard-hooks: copiaria $_agh_tick_script -> $_agh_hooks_dst/posttooluse-tool-call-tick.sh"
    fi
    if [ -f "$_agh_usage_script" ]; then
      log_info "[dry-run] guard-hooks: copiaria $_agh_usage_script -> $_agh_hooks_dst/posttooluse-agent-usage.sh"
    fi
    if [ "$_agh_with_loose" = 1 ]; then
      if [ -f "$_agh_loose_script" ]; then
        log_info "[dry-run] guard-hooks: copiaria $_agh_loose_script -> $_agh_hooks_dst/posttooluse-loose-usage.sh (opt-in --with-loose-usage)"
      fi
      if [ -f "$_agh_loose_snippet" ]; then
        if detect_jq; then
          log_info "[dry-run] guard-hooks: mesclaria (append) $_agh_loose_snippet -> $_agh_settings_dst"
        else
          log_info "[dry-run] guard-hooks: imprimiria paste-block do hook opt-in (jq ausente)"
        fi
      fi
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

  # Hook de metrica de uso de tokens por spawn (best-effort, mesma politica
  # do item acima — wave-token-metrics FASE 2).
  if [ -f "$_agh_usage_script" ]; then
    if cp -- "$_agh_usage_script" "$_agh_hooks_dst/posttooluse-agent-usage.sh" 2>/dev/null; then
      chmod +x -- "$_agh_hooks_dst/posttooluse-agent-usage.sh" 2>/dev/null || :
      log_info "hooks: posttooluse-agent-usage.sh provisionado em $_agh_hooks_dst"
    else
      log_warn "hooks: cp de posttooluse-agent-usage.sh falhou — metrica de uso de tokens indisponivel (guard intacto)"
    fi
  fi

  # Hook OPT-IN de consumo avulso: copia do script e best-effort, independe
  # do settings.json e por isso pode rodar aqui. So o MERGE do snippet
  # precisa acontecer DEPOIS do merge base (bloco abaixo) — ver nota la.
  if [ "$_agh_with_loose" = 1 ]; then
    if [ -f "$_agh_loose_script" ]; then
      if cp -- "$_agh_loose_script" "$_agh_hooks_dst/posttooluse-loose-usage.sh" 2>/dev/null; then
        chmod +x -- "$_agh_hooks_dst/posttooluse-loose-usage.sh" 2>/dev/null || :
        log_info "hooks: posttooluse-loose-usage.sh provisionado em $_agh_hooks_dst (opt-in --with-loose-usage)"
      else
        log_warn "hooks: cp de posttooluse-loose-usage.sh falhou — captura de consumo avulso indisponivel (demais hooks intactos)"
      fi
    else
      log_warn "hooks: posttooluse-loose-usage.sh ausente no catalogo — --with-loose-usage sem efeito"
    fi
  fi

  _agh_state="hooks-only"
  if [ -f "$_agh_snippet" ]; then
    if detect_jq; then
      if merge_settings "$_agh_settings_dst" "$_agh_snippet"; then
        _agh_state="merged"
      else
        _agh_state="error"
      fi
    else
      print_paste_block "$_agh_settings_dst" "$_agh_snippet"
      _agh_state="paste-instructed"
    fi
  else
    log_info "hooks: settings.snippet.json ausente em $_agh_src — so hook copiado"
  fi

  # Merge do snippet OPT-IN: OBRIGATORIAMENTE depois do merge base acima.
  # jq's `*` NAO faz merge recursivo de arrays — se este bloco rodasse
  # ANTES do merge base (ordem tentada originalmente), com settings.json
  # ainda inexistente, `merge_settings_loose_usage` criaria settings.json
  # SO com o snippet opt-in; o merge base seguinte entao veria
  # target.hooks.PostToolUse ja populado (so com o comando opt-in) e o
  # `jq -s '.[0]*.[1]'` do merge_settings faria TARGET vencer o array
  # inteiro — descartando o comando do tick/agent-usage. Rodar o append
  # DEPOIS garante que o array PostToolUse ja tem as entradas obrigatorias
  # quando o append (idempotente, por comando) acontece.
  if [ "$_agh_with_loose" = 1 ] && [ -f "$_agh_loose_snippet" ]; then
    if detect_jq; then
      if merge_settings_loose_usage "$_agh_settings_dst" "$_agh_loose_snippet"; then
        log_info "hooks: hook opt-in de consumo avulso registrado em $_agh_settings_dst"
      else
        log_warn "hooks: merge do hook opt-in de consumo avulso falhou (demais hooks intactos)"
      fi
    else
      print_paste_block "$_agh_settings_dst" "$_agh_loose_snippet"
    fi
  elif [ "$_agh_with_loose" = 1 ]; then
    log_warn "hooks: settings.loose-usage.snippet.json ausente no catalogo — --with-loose-usage sem registro automatico"
  fi

  printf '%s' "$_agh_state"
  return 0
}

# ============================================================================
# hooks_main — comando `cstk hooks install`
# ============================================================================
#
# Ref: README.md §"Hooks do runtime 00c" (o contrato do CLI foi arquivado em
#      docs/specs/_archived/cstk-cli/ e nao cobre este subcomando)
#
# PROBLEMA QUE ISTO RESOLVE
# -------------------------
# Ate 5.26.0 o UNICO caminho para provisionar os hooks 00c num projeto-alvo
# era `cstk install --scope project agente-00c-runtime`, que — alem dos 3
# hooks — copia 1 skill + 6 commands + 7 agents para dentro do repo. Ou
# seja: para ativar a guarda fail-closed de Bash o operador precisava
# duplicar 14 artefatos do catalogo global dentro de cada projeto, com o
# custo de ruido no repo (arquivos que acabam versionados) e de drift (duas
# copias do mesmo artefato para manter em sincronia).
#
# `cstk hooks install` faz SO a parte dos hooks. Nao ha regra nova aqui:
# delega integralmente a apply_guard_hooks() (mesma funcao usada por
# install.sh e update.sh), que segue sendo a fonte unica da regra de
# provisionamento.
#
# Sintaxe:
#   cstk hooks install [--project-path PATH] [--catalog DIR] [--dry-run]
#                       [--with-loose-usage]
#
#   --project-path PATH  Raiz do projeto-alvo (default: diretorio corrente).
#                        Os hooks vao para <PATH>/.claude/hooks/ e o merge
#                        acontece em <PATH>/.claude/settings.json.
#   --catalog DIR        Catalogo de origem (default: $HOME/.claude). Os
#                        hooks sao lidos de
#                        <DIR>/skills/agente-00c-runtime/hooks/.
#   --dry-run            Reporta o plano sem escrever.
#   --with-loose-usage   OPT-IN (default DESLIGADA — feature
#                        loose-usage-capture task 3.3.2): tambem provisiona
#                        posttooluse-loose-usage.sh (captura de consumo
#                        avulso fora de execucoes 00c). Sem esta flag,
#                        apply_guard_hooks() se comporta EXATAMENTE como
#                        antes (3 hooks obrigatorios, zero regressao).
#
# Escopo de PROJETO apenas, por construcao: os hooks so fazem sentido
# registrados no settings.json de um projeto (FR-009c — `--scope global`
# sempre pulou o provisionamento). Apontar --project-path para $HOME e
# recusado explicitamente.
#
# Exit codes:
#   0  hooks provisionados (merged) ou plano exibido em --dry-run
#   1  falha de I/O, catalogo sem hooks, ou --project-path invalido
#   2  uso incorreto

_hooks_print_help() {
  cat >&2 <<'HELP'
cstk hooks — provisiona os hooks do runtime 00c num projeto-alvo.

USO:
  cstk hooks install [--project-path PATH] [--catalog DIR] [--dry-run]
                      [--with-loose-usage]

Copia pretooluse-bash-guard.sh + posttooluse-tool-call-tick.sh +
posttooluse-agent-usage.sh para <PATH>/.claude/hooks/ e mescla o bloco de
registro em <PATH>/.claude/settings.json (via jq; sem jq, imprime o bloco
para colagem manual).

--with-loose-usage (opt-in, default DESLIGADA): tambem provisiona
posttooluse-loose-usage.sh, hook que captura consumo avulso (fora de
execucoes agente-00c/feature-00c) num sidecar local. Sem a flag,
comportamento identico a antes desta opcao existir.

Diferenca para `cstk install --scope project agente-00c-runtime`: aquele
comando tambem duplica skill+commands+agents dentro do repo; este toca
APENAS os hooks e o settings.json.

Para conferir o estado atual sem escrever nada:
  guard-hooks-status.sh check --projeto-alvo-path PATH
HELP
}

hooks_main() {
  _hooks_sub="${1:-}"
  [ "$#" -ge 1 ] && shift || :

  case "$_hooks_sub" in
    ''|-h|--help|help)
      _hooks_print_help
      [ -z "$_hooks_sub" ] && return 2
      return 0
      ;;
    install) ;;
    *)
      log_error "hooks: subcomando desconhecido: $_hooks_sub (use: install)"
      return 2
      ;;
  esac

  _hooks_project_path="."
  _hooks_catalog="${HOME:?HOME nao setado}/.claude"
  _hooks_dry_run=0
  _hooks_with_loose=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-path)
        [ "$#" -ge 2 ] || { log_error "hooks install: --project-path exige valor"; return 2; }
        _hooks_project_path=$2; shift 2 ;;
      --project-path=*) _hooks_project_path=${1#--project-path=}; shift ;;
      --catalog)
        [ "$#" -ge 2 ] || { log_error "hooks install: --catalog exige valor"; return 2; }
        _hooks_catalog=$2; shift 2 ;;
      --catalog=*) _hooks_catalog=${1#--catalog=}; shift ;;
      --dry-run) _hooks_dry_run=1; shift ;;
      --with-loose-usage) _hooks_with_loose=1; shift ;;
      -h|--help) _hooks_print_help; return 0 ;;
      *) log_error "hooks install: flag desconhecida: $1"; return 2 ;;
    esac
  done

  if [ ! -d "$_hooks_project_path" ]; then
    log_error "hooks install: --project-path nao e diretorio: $_hooks_project_path"
    return 1
  fi

  # Normaliza para comparar com $HOME sem depender de realpath (nem todo
  # ambiente POSIX tem). `cd` + `pwd -P` resolve symlinks e relativos.
  _hooks_abs=$(CDPATH= cd -- "$_hooks_project_path" 2>/dev/null && pwd -P) \
    || { log_error "hooks install: nao consegui resolver $_hooks_project_path"; return 1; }

  if [ "$_hooks_abs" = "${HOME%/}" ]; then
    log_error "hooks install: --project-path aponta para \$HOME — hooks 00c sao de escopo PROJETO (FR-009c)."
    log_error "hooks install: aponte para a raiz de um projeto-alvo, nao para o diretorio home."
    return 1
  fi

  _hooks_src="$_hooks_catalog/skills/agente-00c-runtime/hooks"
  if [ ! -d "$_hooks_src" ]; then
    log_error "hooks install: catalogo sem hooks 00c: $_hooks_src"
    log_error "hooks install: rode 'cstk install' (ou 'cstk update') antes, ou passe --catalog DIR."
    return 1
  fi

  _hooks_dest="$_hooks_abs/.claude"

  # Dedup plugin-vence (FR-005, contracts/cli-plugin-awareness.md
  # §cstk hooks install): as TRES condicoes exigidas por F4 (dec-027) sao
  # instalado + habilitado + hooks.json MATERIALIZADO. Faltando a terceira
  # (plugin habilitado mas hooks.json ausente/instalacao parcial), o
  # provisionamento classico segue normalmente com aviso de inconsistencia
  # — nunca deixar o projeto sem NENHUMA guarda (o pior resultado possivel
  # do dedup, e vem justamente do caminho feliz aparente).
  if plugin_enabled cstk; then
    if plugin_hooks_present cstk; then
      log_warn "hooks install: plugin 'cstk' habilitado e ja provê hooks/hooks.json — pulando provisionamento classico (dedup, plugin vence)"
      log_warn "hooks install: se houver registro classico pre-existente em $_hooks_dest/settings.json, remova-o (cstk doctor reporta 'duplicated-hooks' com a mesma remediacao)"
      return 0
    else
      log_warn "hooks install: plugin 'cstk' habilitado mas hooks/hooks.json NAO encontrado no install path — instalacao do plugin parece incompleta"
      log_warn "hooks install: provisionando o caminho classico por seguranca (achado F4 — habilitado nao implica funcional)"
    fi
  fi

  _hooks_state=$(apply_guard_hooks "$_hooks_src" "$_hooks_dest" "$_hooks_dry_run" "$_hooks_with_loose")

  case "$_hooks_state" in
    merged)
      if [ "$_hooks_dry_run" = 1 ]; then
        log_info "hooks install: [dry-run] provisionaria os hooks 00c em $_hooks_dest"
      else
        log_info "hooks install: hooks 00c provisionados e registrados em $_hooks_dest"
      fi
      return 0
      ;;
    paste-instructed)
      log_warn "hooks install: jq ausente — hooks copiados, mas o REGISTRO em settings.json"
      log_warn "hooks install: precisa ser colado manualmente (bloco impresso acima)."
      log_warn "hooks install: sem o registro os hooks NAO rodam."
      return 0
      ;;
    hooks-only)
      log_warn "hooks install: settings.snippet.json ausente no catalogo — hooks copiados"
      log_warn "hooks install: mas NAO registrados; eles nao vao rodar. Atualize o catalogo."
      return 0
      ;;
    not-applicable)
      log_error "hooks install: catalogo nao trouxe os hooks 00c (nada a provisionar)"
      return 1
      ;;
    *)
      log_error "hooks install: falha ao provisionar (estado=$_hooks_state)"
      return 1
      ;;
  esac
}
