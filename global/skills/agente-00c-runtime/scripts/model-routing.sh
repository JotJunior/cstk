#!/bin/sh
# model-routing.sh — integra a skill `model-selector` aos orquestradores
# autonomos agente-00c-orchestrator e agente-00c-feature-orchestrator no
# caminho pre-spawn de subagente (fase clarify). Cumpre FR-001..FR-020 da
# feature agente-00c-model-routing.
#
# Ref: docs/specs/agente-00c-model-routing/spec.md FR-001..FR-020
#      docs/specs/agente-00c-model-routing/contracts/model-routing-helper.md
#      docs/specs/agente-00c-model-routing/data-model.md
#      docs/specs/agente-00c-model-routing/plan.md (Phase 1)
#      Decisoes do clarify: dec-003 (score map 0->0, 1->2, 2->3),
#                           dec-004 (idempotencia via jq sobre .decisions[]),
#                           dec-005 (1 invocacao por spawn real),
#                           dec-007 (truncagem 2000+marker+2000 = 4016 bytes)
#
# Subcomandos:
#   model-routing.sh template --subagent-type TYPE
#       — Emite stdout do input textual deterministico para `model-selector`,
#         por TYPE (enum 4 valores). Puro: nenhum side-effect, nenhum I/O de
#         arquivo, output identico para mesmo input (INV-5). FR-002.
#
#   model-routing.sh invoke --subagent-type TYPE --etapa STAGE
#                           [--input-text OVERRIDE]
#                           [--timeout-seconds N]
#       — Sequencia completa: trunca input via dec-007 se necessario, chama
#         `model-selector` via shell com timeout (default 5s), parseia output
#         da skill, retorna JSON canonico em stdout para o orquestrador
#         consumir. SEMPRE exit 0 quando flags validas (INV-1) — falha da
#         skill vira `fallback: true` no JSON (FR-008, FR-009).
#
#   model-routing.sh idempotent-check --state-dir DIR --onda-id ID
#                                     --subagent-type TYPE
#       — Determina se ja existe Decisao registrada para o par (TYPE, ID) na
#         onda corrente, lendo state.json read-only (INV-4). Stdout: dec-NNN
#         + exit 0 (existe); vazio + exit 1 (nao existe); exit 2 (uso). NUNCA
#         escreve state.json. Cumpre FR-012 + dec-004.
#
#   model-routing.sh phase-model-lookup --fase FASE
#       — (feature model-routing-por-onda) Lookup POSIX-puro (sem jq) no
#         mapa versionado references/phase-model-map.txt. Stdout: 'faixa|
#         modelo'; fase desconhecida -> '|manter-atual' (exit 0, nunca
#         erro — FR-020). Path do mapa confinado ao diretorio do runtime
#         (FR-024). Mecanismo PRIMARIO de routing por onda (FR-014).
#
#   model-routing.sh wave-select --state-dir DIR [--etapa FASE] [--task-text DESC]
#       — (feature model-routing-por-onda, FASE 2) Computa o modelo a
#         aplicar na proxima onda em camadas: mapa primario (FR-014) ->
#         refino opcional via invoke (FR-001/019, so execute-task +
#         --task-text) -> override do operador com precedencia (FR-016/
#         023). Idempotente por onda (FR-008). Registra
#         DecisaoDeRoteamentoPorOnda (+ record-skill se refinou, par I3).
#         Stdout: haiku|sonnet|opus|manter-atual. NUNCA aborta (FR-006).
#         --task-text e UNTRUSTED (FR-022); texto livre scrubbed (FR-025).
#
# Exit codes globais:
#   0 sucesso (incluindo fallback graceful do invoke)
#   1 erro generico (state.json ausente em idempotent-check, etc)
#   2 uso incorreto (flag ausente, enum invalido, subcomando desconhecido)
#
# Invariantes (contracts/model-routing-helper.md §Invariantes):
#   INV-1: invoke SEMPRE exit 0 quando flags validas
#   INV-2: invoke retorna JSON parseavel por jq em 100% dos exit-0 casos
#   INV-3: input >4096 bytes -> input_truncado=true + input_bytes <= 4016
#   INV-4: idempotent-check e read-only — paralelizavel sem race
#   INV-5: template e puro — output identico para mesmo input
#   INV-6: helper completo respeita Principio II — #!/bin/sh, set -eu, deps
#          apenas em awk/wc/head/tail/tr/jq (este ultimo herdado do runtime)
#
# Hardening de seguranca (FASE 4 da feature; auditoria de propostas owasp):
#   F-001 (shell injection): --input-text nunca expandido sem aspas; uso de
#         printf '%s\n' em vez de echo; nada de eval/sh -c "$var"
#   F-002 (jq embedding): saida JSON construida exclusivamente via
#         jq -n --arg/--argjson; nunca via concatenacao de strings
#   F-003 (timeout): subprocess `model-selector` wrappado em timeout (5s
#         default; --timeout-seconds para override em teste)
#   F-005 (UTF-8 split): truncagem retrocede ate boundary de codepoint
#         valido (sem split de sequencia multi-byte)
#
# POSIX sh + dependencias canonicas (awk, wc, head, tail, tr) + jq herdado.

set -eu

# Materializacao de estado legivel (feature state-db-runtime-parity, FASE 2):
# sob backend JSON devolve o proprio state.json; sob SQLite (state.db)
# materializa via `state-rw.sh read` num tmp 0600 fora do state-dir. As
# ESCRITAS do wave-select (state-decisions.sh register + state-ondas.sh
# record-skill) ja sao db-aware — so o caminho de leitura passa por aqui.
# Guard MR_SOURCE_ONLY: quando o proprio model-routing.sh e SOURCEADO pelos
# testes (F4.5), $0 aponta para o chamador — o sibling _state-read.sh nao
# resolveria. Nesse modo os helpers de estado nao sao exercitados; pular o
# source preserva o guard sem tocar o caminho de execucao normal.
if [ "${MR_SOURCE_ONLY:-0}" != "1" ]; then
  . "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
  trap state_read_cleanup EXIT INT TERM
fi

_MR_NAME="model-routing"

# ---------- Helpers privados ----------

_mr_die_usage() {
  printf '%s: %s\n' "$_MR_NAME" "$1" >&2
  exit 2
}

_mr_die() {
  printf '%s: %s\n' "$_MR_NAME" "$1" >&2
  exit "${2:-1}"
}

_mr_log() {
  printf '%s: %s\n' "$_MR_NAME" "$1" >&2
}

_mr_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _mr_die "jq nao encontrado no PATH (necessario para este subcomando)" 1
}

_mr_state_file() {
  # Materializa via _state-read.sh (json: proprio state.json; sqlite: tmp).
  # Falha do read sob sqlite propaga via set -e (FR-012 — nunca degrada
  # mudo). Os call-sites preservam seus proprios checks de ausencia.
  state_read_materialize "$1"
}

# Sanitiza arquivo de input do invoke removendo NUL bytes (\000). NUL
# em meio a string e bandeira vermelha em shell pipelines POSIX —
# pode corromper jq encoding e habilitar tricks de byte-injection em
# parsers downstream. Estrategia: re-escreve o arquivo via `tr -d
# '\000'` (POSIX seguro; nao expande variaveis).
#
# F-001 hardening (CHK050 + dec-009): defesa em profundidade alem do
# enum validation e do printf '%s' usado para gravar o input bruto.
# Mesmo que um atacante injete payload com NUL via --input-text, o
# byte e descartado ANTES de chegar ao subprocess da skill.
#
# Argumentos:
#   $1 = caminho do arquivo de input (in-place rewrite via tmp)
# Stdout: vazio. Exit: 0 sempre (rewrite e sempre seguro; sem NUL =
# no-op semantico, copia identica).
#
# Ref: docs/specs/agente-00c-model-routing/tasks.md F4.1.2
#      checklists/requirements.md CHK050
#      dec-009 finding F-001 (medium)
_mr_validate_input() {
  _mr_vi_path=$1
  [ -f "$_mr_vi_path" ] || return 0
  # tr -d '\000' e POSIX e nunca expande shell variables; seguro
  # mesmo com conteudo adversarial. Saida vai para .clean e substitui
  # o original via mv atomico.
  tr -d '\000' < "$_mr_vi_path" > "$_mr_vi_path.clean" 2>/dev/null || {
    # Fallback defensivo: se tr falhar (FS read-only, etc), nao
    # propaga erro — input bruto sera consumido como esta; a skill
    # downstream tratara como entrada qualquer.
    rm -f "$_mr_vi_path.clean" 2>/dev/null
    return 0
  }
  mv "$_mr_vi_path.clean" "$_mr_vi_path" 2>/dev/null || rm -f "$_mr_vi_path.clean" 2>/dev/null
  return 0
}

# ---------- Subcomando: template (F1.2) ----------

# Emite stdout do input textual deterministico para `model-selector` por
# subagent_type. Cumpre FR-002 + INV-5.
#
# Templates inline (sem leitura de arquivo externo — INV-5). Cada
# template e uma string POSIX literal de 3-5 linhas: perfil + entradas
# esperadas + saida esperada. Fonte dos perfis foi global/agents/
# {agente-00c,feature-00c}-clarify-{asker,answerer}.md (lidos uma vez
# no design da feature — documentado em comentario apos cada bloco).
#
# Argumentos: --subagent-type <enum>
#   agente-00c-clarify-asker     -> asker enumerativo de projeto
#   agente-00c-clarify-answerer  -> answerer reflexivo de projeto
#   feature-00c-clarify-asker    -> asker enumerativo de feature
#   feature-00c-clarify-answerer -> answerer reflexivo de feature
#
# Exit codes:
#   0  sucesso (template emitido em stdout, sem newline final extra)
#   2  --subagent-type ausente, vazio ou fora do enum (unknown-subagent-type)
#   2  flag desconhecida
#
# F-001 (shell injection): nenhum input externo eh expandido sem aspas;
#       templates sao strings literais; printf '%s\n' usado em vez de echo.
_mr_cmd_template() {
  _type=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --subagent-type)
        [ "$#" -ge 2 ] || _mr_die_usage "template: --subagent-type requer valor"
        _type=$2
        shift 2
        ;;
      --subagent-type=*)
        _type=${1#--subagent-type=}
        shift
        ;;
      *)
        _mr_die_usage "template: flag desconhecida: $1"
        ;;
    esac
  done

  [ -n "$_type" ] || {
    printf '%s: %s\n' "$_MR_NAME" "template: unknown-subagent-type (--subagent-type ausente)" >&2
    exit 2
  }

  case "$_type" in
    agente-00c-clarify-asker)
      # Fonte: global/agents/agente-00c-clarify-asker.md
      # Perfil: subagente que gera 1-5 perguntas estruturadas via skill
      # clarify. Operacao enumerativa: varre spec do projeto buscando
      # ambiguidades por categoria (escopo, FRs, edge cases, criterios).
      printf '%s\n' \
'enumerative scan of project spec for ambiguities producing up to 5 structured questions.' \
'inputs: spec text of project under SDD pipeline, briefing summary, constitution principles, stack_sugerida hints.' \
'output: JSON array of questions referencing FR ids and edge case ids, max 5 entries, no decisions.'
      ;;
    agente-00c-clarify-answerer)
      # Fonte: global/agents/agente-00c-clarify-answerer.md
      # Perfil: subagente que responde perguntas aplicando heuristica
      # score 0..3 sobre 3 fontes (briefing, constitution_projeto,
      # stack_sugerida). Operacao reflexiva: reconcilia cada pergunta
      # contra fontes; score >=2 decide; score 0 pausa humano.
      printf '%s\n' \
'reflective scoring of clarification questions against project sources producing autonomous answers or human-pause flags.' \
'inputs: array of questions from clarify-asker, briefing path, constitution_projeto path, stack_sugerida summary.' \
'output: JSON array of answers each with score 0..3, justification citing source, pause_humano boolean.'
      ;;
    feature-00c-clarify-asker)
      # Fonte: global/agents/feature-00c-clarify-asker.md
      # Perfil: subagente que gera 1-5 perguntas no escopo de UMA
      # feature dentro de projeto com briefing+constitution ratificados.
      # Diferenca face a agente-00c-clarify-asker: nao ha stack_sugerida
      # (stack ja decidida); spec corrente substitui stack como 3a fonte.
      printf '%s\n' \
'enumerative scan of feature spec for ambiguities producing up to 5 structured questions within a single feature scope.' \
'inputs: feature spec text under SDD pipeline, project briefing summary, project constitution principles.' \
'output: JSON array of questions referencing FR ids and edge case ids, max 5 entries, no decisions.'
      ;;
    feature-00c-clarify-answerer)
      # Fonte: global/agents/feature-00c-clarify-answerer.md
      # Perfil: subagente que responde perguntas aplicando heuristica
      # score 0..3 sobre 3 fontes (briefing, constitution_projeto,
      # spec_corrente). Diferenca face a agente-00c-clarify-answerer: 3a
      # fonte e spec_corrente (no agente-00c e stack_sugerida).
      printf '%s\n' \
'reflective scoring of clarification questions against feature sources producing autonomous answers or human-pause flags.' \
'inputs: array of questions from clarify-asker, briefing path, constitution_projeto path, spec_corrente path.' \
'output: JSON array of answers each with score 0..3, justification citing source, pause_humano boolean.'
      ;;
    *)
      printf '%s: %s\n' "$_MR_NAME" "template: unknown-subagent-type: '$_type'" >&2
      exit 2
      ;;
  esac
}

# ---------- Subcomando: invoke (F1.3) ----------
#
# Cumpre FR-001, FR-005, FR-007, FR-008, FR-013 + INV-1..INV-3.
#
# Fluxo:
#   1. Validar flags (--subagent-type, --etapa, opcional --input-text,
#      --timeout-seconds).
#   2. Resolver input: usar --input-text se passado; senao derivar via
#      _mr_cmd_template (mesmo binario, subcomando template).
#   3. Truncar bytes via _mr_truncate_bytes (dec-007 + INV-3).
#   4. Localizar binario model-selector/scripts/classify.sh.
#      Resolucao: env MODEL_SELECTOR_SCRIPT (testes) > path relativo
#      ao script (DEV) > path canonico ~/.claude/skills/...
#   5. Invocar com timeout POSIX (sem `timeout(1)` — nao garantido no
#      macOS base). Captura stdout/stderr/exit.
#   6. Parsear stdout via awk POSIX (4 secoes: Modelo Sugerido, Score,
#      Justificativa com "sinais detectados:", Alternativa).
#   7. Mapear score skill 0..2 -> score_runtime 0..3 via dec-003.
#   8. Compor JSON canonico via jq -n --arg/--argjson (F-002).
#   9. Em qualquer falha (skill ausente, exit != 0, parse incompleto,
#      tool indisponivel via env): fallback JSON com exit 0 (INV-1).
#
# Defesa F-001: --input-text JAMAIS expandido sem aspas; toda passagem
# para jq usa --arg/--argjson; nenhum eval/sh -c "$var".

# Localiza o classify.sh do model-selector. Precedencia:
#   1. $MODEL_SELECTOR_SCRIPT (override de teste; pode ser caminho a
#      stub ou string vazia para forcar skill-not-found).
#   2. $MODEL_SELECTOR_DISABLED nao-vazio -> retorna vazio para
#      sinalizar tool-skill-unavailable.
#   3. ${0%/*}/../../model-selector/scripts/classify.sh (DEV — quando o
#      runtime corre do repo source).
#   4. ~/.claude/skills/model-selector/scripts/classify.sh (instalacao).
# Stdout: caminho absoluto resolvido OU string vazia se nao encontrado.
_mr_resolve_skill_path() {
  # 1. MODEL_SELECTOR_DISABLED forca caminho de teste para
  #    tool-skill-unavailable. Variavel separada de
  #    MODEL_SELECTOR_SCRIPT para que testes possam diferenciar
  #    skill-not-found (path falso) de tool-skill-unavailable (env flag).
  if [ -n "${MODEL_SELECTOR_DISABLED:-}" ]; then
    printf '%s' "__DISABLED__"
    return 0
  fi

  if [ -n "${MODEL_SELECTOR_SCRIPT-}" ]; then
    printf '%s' "$MODEL_SELECTOR_SCRIPT"
    return 0
  fi

  # Path relativo a este script (DEV): runtime/scripts/<self> ->
  # ../../model-selector/scripts/classify.sh
  _mr_self_dir=${0%/*}
  _mr_candidate_dev="$_mr_self_dir/../../model-selector/scripts/classify.sh"
  if [ -f "$_mr_candidate_dev" ]; then
    printf '%s' "$_mr_candidate_dev"
    return 0
  fi

  _mr_candidate_install="${HOME}/.claude/skills/model-selector/scripts/classify.sh"
  if [ -f "$_mr_candidate_install" ]; then
    printf '%s' "$_mr_candidate_install"
    return 0
  fi

  printf '%s' ""
}

# UTF-8 boundary backoff helpers (F4.5 — hardening F-005).
#
# UTF-8 rules (RFC 3629):
#   - 0xxxxxxx (0x00..0x7F)         = ASCII, byte unico
#   - 10xxxxxx (0x80..0xBF)         = byte de continuacao (middle)
#   - 110xxxxx (0xC0..0xDF)         = lead de sequencia de 2 bytes
#   - 1110xxxx (0xE0..0xEF)         = lead de sequencia de 3 bytes
#   - 11110xxx (0xF0..0xF7)         = lead de sequencia de 4 bytes
#
# Lemos os ultimos / primeiros bytes do segmento via `od -An -tu1` (decimal,
# POSIX-portavel). Olhamos no maximo os 4 ultimos bytes do head e os 4
# primeiros bytes do tail — overhead constante, sem dependencia de awk
# multi-byte.

# Le K bytes do FIM do arquivo $1 e ecoa "byte1 byte2 ... byteK" em decimal,
# em ordem crescente de posicao (do mais antigo para o mais recente).
_mr_tail_bytes_dec() {
  _mr_tbd_file=$1
  _mr_tbd_k=$2
  tail -c "$_mr_tbd_k" "$_mr_tbd_file" 2>/dev/null \
    | od -An -tu1 \
    | tr '\n' ' ' \
    | tr -s ' '
}

# Le K bytes do INICIO do arquivo $1 e ecoa "byte1 byte2 ... byteK" em
# decimal.
_mr_head_bytes_dec() {
  _mr_hbd_file=$1
  _mr_hbd_k=$2
  head -c "$_mr_hbd_k" "$_mr_hbd_file" 2>/dev/null \
    | od -An -tu1 \
    | tr '\n' ' ' \
    | tr -s ' '
}

# Calcula quantos bytes descartar do FIM do head para preservar boundary
# UTF-8. Retorna inteiro >= 0 em stdout.
#
# Estrategia: olhar os ultimos 4 bytes. Caminhar do byte mais recente para
# tras procurando o byte LEAD mais proximo (>= 0xC0). Quando achar:
#   - Calcular largura esperada da sequencia (2, 3 ou 4 bytes).
#   - Contar quantos bytes de continuacao seguem o lead ate o fim.
#   - Se continuacoes >= largura - 1 → sequencia completa, descarte = 0.
#   - Caso contrario → sequencia incompleta, descartar lead + continuacoes
#     parciais (= largura_real_no_buffer bytes).
# Se nao achar lead nos ultimos 4 bytes E o ultimo byte for continuacao,
# isso indica truncagem em meio a sequencia muito longa — descartar todos
# os continuation bytes do fim ate aparecer um lead ou ASCII. Bounded por
# 4 (max largura UTF-8). Se mesmo apos 4 bytes ainda houver continuation,
# desistir e retornar 0 (caminho conservador — entrada nao e UTF-8 valido
# nesse fim, preservar para nao ampliar dano).
_mr_utf8_head_backoff() {
  _mr_uhb_file=$1
  # Pega ultimos 4 bytes em decimal.
  _mr_uhb_bytes=$(_mr_tail_bytes_dec "$_mr_uhb_file" 4)
  # Conta tokens (bytes lidos).
  _mr_uhb_n=$(printf '%s' "$_mr_uhb_bytes" | wc -w | tr -d ' \t\n')
  if [ "$_mr_uhb_n" -eq 0 ]; then
    printf '0\n'
    return 0
  fi

  # Itera do byte mais recente (posicao N) para tras (posicao 1).
  # Em awk POSIX, indice 1..N.
  printf '%s\n' "$_mr_uhb_bytes" | awk -v n="$_mr_uhb_n" '
    {
      for (i = 1; i <= n; i++) b[i] = $i + 0;

      # Caminhar do mais recente (n) para tras procurando lead.
      lead_pos = 0; lead_byte = 0;
      for (i = n; i >= 1; i--) {
        if (b[i] >= 192) {        # 0xC0+ = lead
          lead_pos = i; lead_byte = b[i]; break;
        }
        if (b[i] < 128) {         # ASCII intermediario → tudo OK ate aqui
          # ASCII byte com continuation depois? Improvavel UTF-8 valido,
          # mas se i < n e bytes seguintes sao continuation, eles sao
          # invalidos. Conservador: descartar bytes apos esse ASCII.
          # Numero de bytes a descartar = n - i.
          print (n - i);
          exit;
        }
      }

      if (lead_pos == 0) {
        # Todos os 4 bytes sao continuation (10xxxxxx). Buffer comeca em
        # meio a uma sequencia >4 bytes — invalido UTF-8 valido nao tem
        # codepoint maior que 4 bytes. Descartar todos os 4 = caminho
        # conservador.
        print n;
        exit;
      }

      # Determinar largura esperada pelo lead.
      if (lead_byte >= 240) width = 4;       # 11110xxx
      else if (lead_byte >= 224) width = 3;  # 1110xxxx
      else if (lead_byte >= 192) width = 2;  # 110xxxxx
      else width = 1;

      # Bytes presentes apos o lead (incluindo o lead).
      present = n - lead_pos + 1;

      if (present >= width) {
        # Sequencia completa no buffer. Descarte = 0.
        # (Bytes apos a sequencia sao ASCII validos ou outra sequencia
        # completa — analise recursiva fora do escopo, OK porque o
        # caso comum e lead unico nos ultimos bytes.)
        print 0;
      } else {
        # Sequencia incompleta — descartar lead + continuacoes parciais.
        print present;
      }
    }
  '
}

# Calcula quantos bytes descartar do INICIO do tail para preservar boundary.
# Estrategia: contar quantos bytes consecutivos a partir da posicao 1 sao
# continuation (10xxxxxx, 0x80..0xBF). Esses bytes pertencem a uma
# sequencia que iniciou ANTES do corte → sao orfaos.
_mr_utf8_tail_backoff() {
  _mr_utb_file=$1
  _mr_utb_bytes=$(_mr_head_bytes_dec "$_mr_utb_file" 4)
  _mr_utb_n=$(printf '%s' "$_mr_utb_bytes" | wc -w | tr -d ' \t\n')
  if [ "$_mr_utb_n" -eq 0 ]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "$_mr_utb_bytes" | awk -v n="$_mr_utb_n" '
    {
      drop = 0;
      for (i = 1; i <= n; i++) {
        b = $i + 0;
        if (b >= 128 && b < 192) drop++;   # 10xxxxxx = continuation
        else break;
      }
      print drop;
    }
  '
}

# Trunca conteudo no padrao dec-007: se bytes > 4096, produzir
#   <primeiros 2000 bytes (codepoint-safe)> + "...[truncated]..." +
#   <ultimos 2000 bytes (codepoint-safe)>
# Total maximo = 2000 + 16 (marcador) + 2000 = 4016 bytes (dec-007).
# F4.5 (hardening F-005): apos head -c 2000 / tail -c 2000, aplica backoff
# UTF-8 nas bordas para nao split codepoint multibyte. Backoff pode
# REDUZIR o tamanho final em ate ~3 bytes por borda — output continua
# dentro do teto de 4016, garantia preservada.
#
# Argumentos:
#   $1 = caminho do arquivo de input (caller cria via printf > tmp)
#   $2 = caminho do arquivo de output
# Stdout: duas linhas — "<0|1>\n<bytes_finais>"
_mr_truncate_bytes() {
  _mr_in=$1
  _mr_out=$2
  _mr_threshold=4096
  _mr_size=$(wc -c < "$_mr_in" | tr -d ' \t\n')

  if [ "$_mr_size" -le "$_mr_threshold" ]; then
    cp "$_mr_in" "$_mr_out"
    printf '0\n%s\n' "$_mr_size"
    return 0
  fi

  # Truncagem necessaria. Marcador fixo de 16 bytes entre head e tail.
  # dec-007 fixa total <= 4016 bytes: head(2000) + marker(16) + tail(2000).
  _mr_marker='...[truncated]..'
  head -c 2000 "$_mr_in" > "$_mr_out.head"
  tail -c 2000 "$_mr_in" > "$_mr_out.tail"

  # F4.5 — F-005 boundary backoff (POSIX-pure via od + awk):
  # Head pode terminar no meio de uma sequencia UTF-8 multibyte. Tail
  # pode comecar com bytes de continuacao orfaos. Backoff bounded a
  # 4 bytes por borda (largura max de codepoint UTF-8).
  #
  # Cross-link: F-005 (dec-009 owasp low) + FR-013 + INV-3 + dec-007.
  _mr_head_drop=$(_mr_utf8_head_backoff "$_mr_out.head")
  _mr_tail_drop=$(_mr_utf8_tail_backoff "$_mr_out.tail")

  # Aplica backoff: regrava head removendo ultimos N bytes, tail
  # removendo primeiros M bytes. Sem usar `sed -i` (nao portavel) —
  # head -c <bytes_validos> sobre o proprio arquivo intermediario.
  if [ "$_mr_head_drop" -gt 0 ]; then
    _mr_head_keep=$((2000 - _mr_head_drop))
    head -c "$_mr_head_keep" "$_mr_out.head" > "$_mr_out.head2"
    mv "$_mr_out.head2" "$_mr_out.head"
  fi
  if [ "$_mr_tail_drop" -gt 0 ]; then
    _mr_tail_keep=$((2000 - _mr_tail_drop))
    tail -c "$_mr_tail_keep" "$_mr_out.tail" > "$_mr_out.tail2"
    mv "$_mr_out.tail2" "$_mr_out.tail"
  fi

  cat "$_mr_out.head" > "$_mr_out"
  printf '%s' "$_mr_marker" >> "$_mr_out"
  cat "$_mr_out.tail" >> "$_mr_out"
  rm -f "$_mr_out.head" "$_mr_out.tail"

  _mr_final_size=$(wc -c < "$_mr_out" | tr -d ' \t\n')
  printf '1\n%s\n' "$_mr_final_size"
}

# Parseia stdout da skill model-selector. Output real do classify.sh:
#
#   ## Modelo Sugerido
#   <blank>
#   <modelo>
#   <blank>
#   ## Score
#   <blank>
#   <score 0..2>
#   <blank>
#   rasa=X media=Y profunda=Z faixa=<nome>
#   score=<n> modelo=<x> alternativa=<y>
#   <blank>
#   ## Justificativa
#   <blank>
#   sinais detectados: <lista>; ...
#   <blank>
#   ## Alternativa
#   <blank>
#   <alternativa | "none">
#
# Argumentos: $1 = arquivo com stdout da skill
# Stdout (sucesso): 4 linhas (modelo, score, alternativa, sinais_text)
# Exit: 0 sucesso; 1 parse-failure
#
# Awk POSIX (sem extensoes gawk).
_mr_parse_skill_output() {
  _mr_skill_out=$1
  awk '
    BEGIN {
      modelo=""; score=""; alternativa=""; sinais="";
      st_modelo=0; st_score=0; st_alt=0; st_just=0;
    }
    /^## Modelo Sugerido[[:space:]]*$/ { st_modelo=1; st_score=0; st_alt=0; st_just=0; next }
    /^## Score[[:space:]]*$/           { st_modelo=0; st_score=1; st_alt=0; st_just=0; next }
    /^## Justificativa[[:space:]]*$/   { st_modelo=0; st_score=0; st_alt=0; st_just=1; next }
    /^## Alternativa[[:space:]]*$/     { st_modelo=0; st_score=0; st_alt=1; st_just=0; next }
    /^## /                              { st_modelo=0; st_score=0; st_alt=0; st_just=0; next }
    {
      if ($0 == "") next;
      if (st_modelo && modelo == "") { modelo=$0; next; }
      if (st_score && score == "") {
        # Primeira linha nao-vazia da secao Score = digito 0..2.
        if ($0 ~ /^[0-9]+$/) { score=$0; next; }
      }
      if (st_alt && alternativa == "") { alternativa=$0; next; }
      if (st_just && sinais == "") {
        # Captura primeira linha nao-vazia da justificativa (contem
        # "sinais detectados: ..." quando ha sinais; "nenhum sinal..."
        # quando vazio). Util para auditoria.
        sinais=$0; next;
      }
    }
    END {
      if (modelo == "" || score == "" || alternativa == "") {
        exit 1;
      }
      print modelo;
      print score;
      print alternativa;
      print sinais;
    }
  ' "$_mr_skill_out"
}

# Mapping dec-003: score skill 0..2 -> score runtime 0..3.
#   0 -> 0  (indeterminado -> "evidencia ausente")
#   1 -> 2  (1 sinal -> "evidencia razoavel")
#   2 -> 3  (2+ sinais com teto aplicado -> "evidencia forte")
# Score ausente (string vazia) -> 0.
# Case-statement puro (sem aritmetica).
_mr_map_score() {
  case "$1" in
    0) printf '%s' 0 ;;
    1) printf '%s' 2 ;;
    2) printf '%s' 3 ;;
    *) printf '%s' 0 ;;
  esac
}

# Invoca o classify.sh com timeout POSIX (sem usar timeout(1) que nao
# e padrao em macOS base). Padrao:
#   ( cmd_child > out 2> err & pid=$!
#     ( sleep $timeout && kill -TERM $pid 2>/dev/null ) & watcher=$!
#     wait $pid; rc=$?; kill $watcher 2>/dev/null )
# F-003: subprocess limitado a $timeout segundos. SIGTERM -> processo
# filho recebe sinal; exit code do wait codifica isso (>128 = signal).
#
# Argumentos: $1=script_path $2=input_file $3=stdout_file $4=stderr_file
#             $5=timeout_seconds
# Exit code: do classify (0..255); 124 se foi morto por timeout
# (convencao do GNU timeout que reaproveitamos).
_mr_invoke_skill() {
  _mr_script=$1
  _mr_input=$2
  _mr_outf=$3
  _mr_errf=$4
  _mr_timeout=$5

  # Subshell isolada para nao poluir trap/state do helper. Desabilita
  # `set -e` localmente: o protocolo de timeout deliberadamente
  # produz exits >0 do watcher (via kill) e nao queremos que esses
  # exits propaguem para o exit code do wrapper.
  (
    set +e
    # Invocamos via `sh "$script" < input` para evitar problemas de
    # exec bit em fixtures de teste.
    # F-001: --input-text ja esta em arquivo; nao passamos como arg
    # (evita expansion shell). classify.sh aceita stdin quando $# = 0.
    sh "$_mr_script" < "$_mr_input" > "$_mr_outf" 2> "$_mr_errf" &
    _mr_child=$!

    # Watcher mata o filho se exceder o timeout. Roda em subshell
    # propria para nao receber SIGPIPE/SIGTERM compartilhado.
    #
    # F-perf (descoberto via test_e2e_model_routing.sh SC-006): o
    # watcher fecha stdin/stdout/stderr para que o shell pai nao bloqueie
    # em command substitution `x=$(invoke ...)`. Sem este redirect, mesmo
    # apos `kill $_mr_watcher`, o pipe de stdout do watcher fica aberto
    # ate o `sleep` original retornar (5s+), o que viola SC-006 (<2s
    # overhead) ao quebrar `wait` implicito do command-sub.
    (
      sleep "$_mr_timeout"
      kill -TERM "$_mr_child" 2>/dev/null
      # Segunda chance: forca kill se ainda vivo apos 1s.
      sleep 1
      kill -KILL "$_mr_child" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    _mr_watcher=$!

    # Espera o filho. POSIX `wait $pid` retorna exit do filho.
    wait "$_mr_child" 2>/dev/null
    _mr_rc=$?

    # Mata o watcher (filho terminou primeiro). NAO espera pelo
    # watcher — `wait $watcher` retornaria 143 (SIGTERM) e
    # poluiria o exit code aparente apesar do `set +e`. Apenas
    # signal-and-forget; o reaper do shell limpa.
    kill "$_mr_watcher" 2>/dev/null

    # Se filho morreu por sinal, $rc fica >128. Convenciona 124 como
    # timeout-style (compat GNU timeout) para sinalizar exit-nonzero.
    if [ "$_mr_rc" -gt 128 ]; then
      exit 124
    fi
    exit "$_mr_rc"
  )
}

# Emite JSON de fallback (exit 0, INV-1). $1=reason, $2=stderr_file,
# $3=subagent_type, $4=etapa, $5=input_truncado, $6=input_bytes.
_mr_emit_fallback_json() {
  _mr_reason=$1
  _mr_stderr_f=$2
  _mr_subagent=$3
  _mr_etapa=$4
  _mr_truncado=$5
  _mr_bytes=$6

  # head -c 200 + sanitizacao de null bytes (F-001). Stderr pode estar
  # vazio (skill-not-found) — manter como string vazia, nao null.
  if [ -f "$_mr_stderr_f" ]; then
    _mr_stderr_head=$(head -c 200 "$_mr_stderr_f" 2>/dev/null | tr -d '\000')
  else
    _mr_stderr_head=""
  fi

  jq -n \
    --arg subagent "$_mr_subagent" \
    --arg etapa "$_mr_etapa" \
    --arg reason "$_mr_reason" \
    --arg stderr "$_mr_stderr_head" \
    --argjson truncado "$_mr_truncado" \
    --argjson bytes "$_mr_bytes" \
    '{
      subagent_type: $subagent,
      etapa: $etapa,
      modelo: "fallback-default",
      score_skill: null,
      score_runtime: 0,
      alternativa: null,
      sinais_text: null,
      fallback: true,
      fallback_reason: $reason,
      fallback_stderr_first_200: $stderr,
      input_truncado: $truncado,
      input_bytes: $bytes
    }'
}

_mr_cmd_invoke() {
  _mr_require_jq

  _mr_subagent=""
  _mr_etapa=""
  _mr_input_text=""
  _mr_input_text_set=0
  _mr_timeout=5

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --subagent-type)
        [ "$#" -ge 2 ] || _mr_die_usage "invoke: --subagent-type requer valor"
        _mr_subagent=$2; shift 2 ;;
      --subagent-type=*)
        _mr_subagent=${1#--subagent-type=}; shift ;;
      --etapa)
        [ "$#" -ge 2 ] || _mr_die_usage "invoke: --etapa requer valor"
        _mr_etapa=$2; shift 2 ;;
      --etapa=*)
        _mr_etapa=${1#--etapa=}; shift ;;
      --input-text)
        [ "$#" -ge 2 ] || _mr_die_usage "invoke: --input-text requer valor"
        _mr_input_text=$2; _mr_input_text_set=1; shift 2 ;;
      --input-text=*)
        _mr_input_text=${1#--input-text=}; _mr_input_text_set=1; shift ;;
      --timeout-seconds)
        [ "$#" -ge 2 ] || _mr_die_usage "invoke: --timeout-seconds requer valor"
        _mr_timeout=$2; shift 2 ;;
      --timeout-seconds=*)
        _mr_timeout=${1#--timeout-seconds=}; shift ;;
      *)
        _mr_die_usage "invoke: flag desconhecida: $1" ;;
    esac
  done

  # Validacoes de uso (exit 2).
  [ -n "$_mr_subagent" ] || _mr_die_usage "invoke: --subagent-type ausente"
  [ -n "$_mr_etapa" ] || _mr_die_usage "invoke: --etapa ausente"

  case "$_mr_subagent" in
    agente-00c-clarify-asker|agente-00c-clarify-answerer\
    |feature-00c-clarify-asker|feature-00c-clarify-answerer) ;;
    *) _mr_die_usage "invoke: --subagent-type fora do enum: '$_mr_subagent'" ;;
  esac
  # FR-016: etapa enum hoje = clarify. Futuras fases somam aqui.
  case "$_mr_etapa" in
    clarify) ;;
    *) _mr_die_usage "invoke: --etapa fora do enum: '$_mr_etapa'" ;;
  esac
  # Validar timeout numerico positivo.
  case "$_mr_timeout" in
    ''|*[!0-9]*) _mr_die_usage "invoke: --timeout-seconds nao-numerico: '$_mr_timeout'" ;;
  esac
  [ "$_mr_timeout" -ge 1 ] || _mr_die_usage "invoke: --timeout-seconds deve ser >= 1"

  # Diretorio de trabalho para arquivos temporarios (input bruto,
  # input truncado, stdout/stderr da skill, parser).
  _mr_workdir=$(mktemp -d 2>/dev/null) || _mr_die "falha mktemp -d" 1
  # Guard contra rm -rf erratico: nao usamos $_mr_workdir se vazio.
  trap '[ -n "${_mr_workdir-}" ] && rm -rf "$_mr_workdir"' EXIT INT TERM

  _mr_raw="$_mr_workdir/input.raw"
  _mr_truncated="$_mr_workdir/input.final"
  _mr_skill_stdout="$_mr_workdir/skill.stdout"
  _mr_skill_stderr="$_mr_workdir/skill.stderr"

  # Resolver input.
  if [ "$_mr_input_text_set" = 1 ]; then
    # F-001: usar printf '%s' (nao echo) e nunca expandir sem aspas.
    # CHK050 + F-001: input passa por _mr_validate_input antes de
    # qualquer consumo downstream (remove NUL bytes — defesa em
    # profundidade alem do enum validation).
    printf '%s' "$_mr_input_text" > "$_mr_raw"
    _mr_validate_input "$_mr_raw"
  else
    # Derivar via _mr_cmd_template (mesmo binario, subcomando puro).
    # Reaproveita logica em vez de duplicar templates.
    "$0" template --subagent-type "$_mr_subagent" > "$_mr_raw" 2>/dev/null
    # Templates sao literais POSIX — nao podem conter NUL —, mas
    # passa por _mr_validate_input para preservar invariante uniforme.
    _mr_validate_input "$_mr_raw"
  fi

  # Truncar bytes (dec-007 + INV-3).
  _mr_trunc_info=$(_mr_truncate_bytes "$_mr_raw" "$_mr_truncated")
  _mr_truncado_flag=$(printf '%s' "$_mr_trunc_info" | sed -n '1p')
  _mr_input_bytes=$(printf '%s' "$_mr_trunc_info" | sed -n '2p')
  if [ "$_mr_truncado_flag" = "1" ]; then
    _mr_truncado_json="true"
  else
    _mr_truncado_json="false"
  fi

  # Resolver caminho do classify.sh.
  _mr_skill_path=$(_mr_resolve_skill_path)

  if [ "$_mr_skill_path" = "__DISABLED__" ]; then
    _mr_emit_fallback_json "tool-skill-unavailable" "" \
      "$_mr_subagent" "$_mr_etapa" "$_mr_truncado_json" "$_mr_input_bytes"
    return 0
  fi

  if [ -z "$_mr_skill_path" ] || [ ! -f "$_mr_skill_path" ]; then
    _mr_emit_fallback_json "skill-not-found" "" \
      "$_mr_subagent" "$_mr_etapa" "$_mr_truncado_json" "$_mr_input_bytes"
    return 0
  fi

  # Invocar skill com timeout. Suprimir `set -e` via `|| _mr_skill_exit=$?`
  # — exit != 0 e cenario esperado de fallback (FR-008), nao erro do helper.
  _mr_skill_exit=0
  _mr_invoke_skill "$_mr_skill_path" "$_mr_truncated" \
    "$_mr_skill_stdout" "$_mr_skill_stderr" "$_mr_timeout" \
    || _mr_skill_exit=$?

  if [ "$_mr_skill_exit" -ne 0 ]; then
    _mr_emit_fallback_json "exit-nonzero" "$_mr_skill_stderr" \
      "$_mr_subagent" "$_mr_etapa" "$_mr_truncado_json" "$_mr_input_bytes"
    return 0
  fi

  # Parsear stdout. _mr_parse_skill_output retorna 4 linhas em sucesso.
  _mr_parsed=$(_mr_parse_skill_output "$_mr_skill_stdout" 2>/dev/null) || {
    _mr_emit_fallback_json "parse-failure" "$_mr_skill_stderr" \
      "$_mr_subagent" "$_mr_etapa" "$_mr_truncado_json" "$_mr_input_bytes"
    return 0
  }

  _mr_modelo=$(printf '%s' "$_mr_parsed" | sed -n '1p')
  _mr_score=$(printf '%s' "$_mr_parsed" | sed -n '2p')
  _mr_alt=$(printf '%s' "$_mr_parsed" | sed -n '3p')
  _mr_sinais=$(printf '%s' "$_mr_parsed" | sed -n '4p')

  # Mapping score (dec-003).
  _mr_score_runtime=$(_mr_map_score "$_mr_score")

  # raw_stdout_first_200 com sanitizacao null-byte.
  _mr_raw_head=$(head -c 200 "$_mr_skill_stdout" 2>/dev/null | tr -d '\000')

  # Emite JSON de sucesso via jq -n (F-002).
  jq -n \
    --arg subagent "$_mr_subagent" \
    --arg etapa "$_mr_etapa" \
    --arg modelo "$_mr_modelo" \
    --arg alt "$_mr_alt" \
    --arg sinais "$_mr_sinais" \
    --arg raw "$_mr_raw_head" \
    --argjson score_skill "$_mr_score" \
    --argjson score_runtime "$_mr_score_runtime" \
    --argjson truncado "$_mr_truncado_json" \
    --argjson bytes "$_mr_input_bytes" \
    '{
      subagent_type: $subagent,
      etapa: $etapa,
      modelo: $modelo,
      score_skill: $score_skill,
      score_runtime: $score_runtime,
      alternativa: $alt,
      sinais_text: $sinais,
      fallback: false,
      input_truncado: $truncado,
      input_bytes: $bytes,
      raw_stdout_first_200: $raw
    }'
}

# ---------- Subcomando: idempotent-check (F1.4) ----------
#
# Cumpre FR-012 + dec-004 + INV-4. Determina se ja existe Decisao
# registrada para o par (subagent_type, onda_id) na onda corrente,
# lendo state.json read-only (NUNCA escreve).
#
# Argumentos:
#   --state-dir DIR       diretorio com state.json legivel
#   --onda-id onda-NNN    pattern obrigatorio: ^onda-[0-9]+$ (3+ digitos)
#   --subagent-type TYPE  mesmo enum dos demais subcomandos
#
# Algoritmo:
#   1. Compor contexto canonico:
#        "Selecao de modelo para subagente <SUBAGENT>"
#   2. Query jq read-only: primeiro .decisions[] cujo .context == ctx
#      AND .wave_id == ONDA -> emitir .id ou string vazia (reader-fallback pt-BR).
#   3. Stdout=dec-NNN + exit 0 (existe); stdout vazio + exit 1 (nao
#      existe); exit 2 (erro de uso ou state.json ausente).
#
# Hardening:
#   - F-001: --subagent-type passa para jq via --arg (NAO interpolacao
#     shell). $SUBAGENT NUNCA aparece em string-literal jq.
#   - INV-4: nenhuma escrita ao FS — apenas leitura de state.json.
#     Paralelizavel sem race (validado em scenario_idempotent_check_paralelo).
#
# F1.4.5 cross-link: defesa F-001 aplicada na composicao do contexto.
_mr_cmd_idempotent_check() {
  _mr_require_jq

  _mr_idc_sdir=""
  _mr_idc_onda=""
  _mr_idc_subagent=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ "$#" -ge 2 ] || _mr_die_usage "idempotent-check: --state-dir requer valor"
        _mr_idc_sdir=$2; shift 2 ;;
      --state-dir=*)
        _mr_idc_sdir=${1#--state-dir=}; shift ;;
      --onda-id)
        [ "$#" -ge 2 ] || _mr_die_usage "idempotent-check: --onda-id requer valor"
        _mr_idc_onda=$2; shift 2 ;;
      --onda-id=*)
        _mr_idc_onda=${1#--onda-id=}; shift ;;
      --subagent-type)
        [ "$#" -ge 2 ] || _mr_die_usage "idempotent-check: --subagent-type requer valor"
        _mr_idc_subagent=$2; shift 2 ;;
      --subagent-type=*)
        _mr_idc_subagent=${1#--subagent-type=}; shift ;;
      *)
        _mr_die_usage "idempotent-check: flag desconhecida: $1" ;;
    esac
  done

  # Flags obrigatorias.
  [ -n "$_mr_idc_sdir" ]     || _mr_die_usage "idempotent-check: --state-dir ausente"
  [ -n "$_mr_idc_onda" ]     || _mr_die_usage "idempotent-check: --onda-id ausente"
  [ -n "$_mr_idc_subagent" ] || _mr_die_usage "idempotent-check: --subagent-type ausente"

  # Validar pattern onda-id: ^onda-[0-9]+$ (>= 1 digito; aceita
  # onda-001, onda-099, onda-100, etc). Spec dec-004 / contract dizem
  # exatamente 3 digitos, mas state-ondas usa printf %03d (zero-pad
  # ate 3, mas suporta crescer alem). Usamos >=1 digito para resiliencia
  # com state que rode alem de onda-999. Regex via case POSIX:
  case "$_mr_idc_onda" in
    onda-*)
      _mr_idc_suffix=${_mr_idc_onda#onda-}
      case "$_mr_idc_suffix" in
        ''|*[!0-9]*)
          _mr_die_usage "idempotent-check: --onda-id formato invalido (esperado 'onda-NNN'): '$_mr_idc_onda'" ;;
      esac
      ;;
    *)
      _mr_die_usage "idempotent-check: --onda-id formato invalido (esperado 'onda-NNN'): '$_mr_idc_onda'" ;;
  esac

  # Validar enum subagent-type.
  case "$_mr_idc_subagent" in
    agente-00c-clarify-asker|agente-00c-clarify-answerer\
    |feature-00c-clarify-asker|feature-00c-clarify-answerer) ;;
    *) _mr_die_usage "idempotent-check: --subagent-type fora do enum: '$_mr_idc_subagent'" ;;
  esac

  # state.json deve existir e ser legivel.
  _mr_idc_sf=$(_mr_state_file "$_mr_idc_sdir")
  [ -f "$_mr_idc_sf" ] || _mr_die_usage "idempotent-check: state.json ausente em '$_mr_idc_sdir'"
  [ -r "$_mr_idc_sf" ] || _mr_die_usage "idempotent-check: state.json sem permissao de leitura em '$_mr_idc_sdir'"

  # Query read-only via jq. F-001: SUBAGENT e ONDA passados via --arg
  # (NUNCA interpolacao shell na expressao jq). Contexto canonico
  # alinhado com dec-004 e o que sera registrado em F2/F3.
  # INV-4: leitura pura; nenhum redirect/escrita.
  # Reader (schema-en-migration): chaves EN com fallback pt-BR
  # ((.decisions // .decisoes), (.context // .contexto), (.wave_id // .onda_id)).
  _mr_idc_result=$(
    jq -r \
      --arg ctx "Selecao de modelo para subagente $_mr_idc_subagent" \
      --arg onda "$_mr_idc_onda" \
      '[(.decisions // .decisoes // [])[]? | select((.context // .contexto) == $ctx and (.wave_id // .onda_id) == $onda)][0].id // empty' \
      "$_mr_idc_sf" 2>/dev/null
  ) || _mr_die "idempotent-check: jq query falhou" 1

  if [ -n "$_mr_idc_result" ]; then
    # Decisao ja existe — emitir dec-NNN + exit 0.
    printf '%s\n' "$_mr_idc_result"
    return 0
  fi

  # Nao existe — stdout vazio + exit 1 (FR-012).
  return 1
}

# ---------- phase-model-lookup (feature model-routing-por-onda, FASE 1) ----------
#
# Lookup POSIX-puro (sem jq) no mapa versionado de fase->modelo
# (references/phase-model-map.txt). Mecanismo PRIMARIO do model-routing
# por onda (FR-014).
#
# Uso:
#   model-routing.sh phase-model-lookup --fase <fase>
#
# Saida (stdout): uma linha 'faixa|modelo' (ex.: 'profunda|opus').
#   Fase desconhecida (ou ausente do mapa) -> '|manter-atual' (FR-020 —
#   tolera evolucao do mapa, nunca erro). Exit 0 sempre que --fase valida.
#
# Seguranca (FR-024): o path do mapa e CONFINADO ao diretorio do runtime,
# derivado do diretorio do proprio script ($0 -> dirname -> ../references).
# Nenhum path externo, nenhum input do usuario compoe o path -> traversal
# impossivel por construcao. A flag --fase NUNCA e usada para montar path;
# so e comparada como dado (match exato de campo via case POSIX).
#
# Ref: docs/specs/model-routing-por-onda/contracts/wave-select.md
#        §phase-model-lookup
#      docs/specs/model-routing-por-onda/data-model.md §MapaFaseModelo
#      docs/specs/model-routing-por-onda/spec.md FR-014, FR-020, FR-024
#      docs/specs/model-routing-por-onda/tasks.md 1.2.1..1.2.4

# Resolve o diretorio canonico do mapa, confinado ao runtime (FR-024).
# Deriva de $0 (dirname) -> sobe a scripts/ -> entra em references/.
# Canonicaliza via `cd ... && pwd` (resolve '..' e symlinks de dir sem
# depender de readlink -f, indisponivel no BSD/macOS base). Stdout: path
# absoluto do arquivo de mapa. NAO falha aqui se o arquivo nao existir —
# a checagem -f e feita no consumidor (graceful degradation, FR-020).
_mr_phase_map_path() {
  # Diretorio do script (scripts/). cd+pwd canonicaliza componentes.
  _mr_pm_scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) \
    || _mr_pm_scriptdir=""
  [ -n "$_mr_pm_scriptdir" ] || return 1
  # references/ e irmao de scripts/ dentro da skill agente-00c-runtime.
  printf '%s/../references/phase-model-map.txt\n' "$_mr_pm_scriptdir"
}

_mr_cmd_phase_model_lookup() {
  _mr_pml_fase=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fase)
        [ "$#" -ge 2 ] || _mr_die_usage "phase-model-lookup: --fase requer valor"
        _mr_pml_fase=$2; shift 2 ;;
      --fase=*)
        _mr_pml_fase=${1#--fase=}; shift ;;
      *)
        _mr_die_usage "phase-model-lookup: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_mr_pml_fase" ] || _mr_die_usage "phase-model-lookup: --fase ausente"

  _mr_pml_map=$(_mr_phase_map_path) || {
    # Nao foi possivel resolver o diretorio do runtime: degrada para
    # manter-atual (FR-020), nunca erro.
    printf '|manter-atual\n'
    return 0
  }

  # Mapa ausente/ilegivel -> manter-atual (FR-020 — tolera evolucao).
  [ -f "$_mr_pml_map" ] && [ -r "$_mr_pml_map" ] || {
    printf '|manter-atual\n'
    return 0
  }

  # Parsing POSIX-puro (sem jq). Le linha a linha; ignora comentarios
  # ('#...') e linhas vazias; split por '|' via IFS local no subshell de
  # command-substitution (nao vaza IFS ao caller). Match exato do campo
  # fase.
  #
  # NOTA DE PORTABILIDADE: NAO usar `case ... esac` dentro deste
  # `$( ... )`. Varios `sh` (inclusive bash em modo POSIX no macOS)
  # falham no parse de `case` aninhado em command-substitution
  # ("syntax error near `;;'"). Skip de comentario/branco e feito via
  # expansao de parametro (extracao do 1o caractere), 100% POSIX e sem
  # esse bug.
  #
  # F-001/FR-024: --fase so e COMPARADA como dado (=), nunca interpolada
  # em path nem em comando; sem eval. Usamos read -r para nao interpretar
  # barras invertidas no arquivo de mapa.
  _mr_pml_result=$(
    while IFS='|' read -r _f _fa _mo _rest; do
      # Pular linhas em branco.
      [ -z "$_f" ] && continue
      # Pular comentarios: 1o caractere == '#' (via expansao de parametro).
      _mr_pml_first=${_f%"${_f#?}"}
      [ "$_mr_pml_first" = "#" ] && continue
      if [ "$_f" = "$_mr_pml_fase" ]; then
        printf '%s|%s\n' "$_fa" "$_mo"
        break
      fi
    done < "$_mr_pml_map"
  )

  if [ -n "$_mr_pml_result" ]; then
    printf '%s\n' "$_mr_pml_result"
  else
    # Fase nao encontrada no mapa (FR-020).
    printf '|manter-atual\n'
  fi
  return 0
}

# ---------- wave-select (feature model-routing-por-onda, FASE 2) ----------
#
# Computa o modelo a aplicar na PROXIMA onda do orquestrador e registra a
# DecisaoDeRoteamentoPorOnda auditavel. Mecanismo de selecao em camadas
# (FR-005): mapa primario (FR-014) -> refino opcional (FR-001/019) ->
# override do operador com precedencia (FR-016). Idempotente por onda
# (FR-008). Nunca aborta por indisponibilidade do model-selector (FR-006).
#
# Uso:
#   model-routing.sh wave-select --state-dir <SD> [--etapa <fase>] [--task-text <desc>]
#
# Saida (stdout): UMA linha com o modelo aplicado:
#   haiku | sonnet | opus | manter-atual
#
# Efeito colateral: registra UMA DecisaoDeRoteamentoPorOnda via
# state-decisions.sh register (+ state-ondas.sh record-skill quando o
# refino invocou model-selector — par atomico-logico I3 reusado).
#
# Encoding (dec-006): register tem schema FIXO. Os campos conceituais
# modelo_sugerido / modelo_aplicado / origem sao encodados como tokens
# parseaveis no PREFIXO da justificativa, no formato exato:
#   "sugerido=<m> aplicado=<m> origem=<o> | <texto livre scrubbed>"
# O contexto usa o lead "Selecao de modelo para onda <N> (fase <f>)",
# distinto do lead legado "Selecao de modelo para subagente <T>", para
# o agregador da FASE 6 distinguir as duas geracoes sem colisao (FR-021).
#
# Campo stage/etapa da Decisao = a FASE da onda (specify|plan|...), nao a
# categoria "model-routing" — consumidores derivados (knowledge.db/painel)
# agrupam por stage assumindo etapa SDD. O discriminador de decisao de
# roteamento e o LEAD DO CONTEXTO (acima), nunca o stage. Fase vazia
# degrada para "model-routing" (register exige --etapa nao-vazio).
# Overrides do operador (choice model-override:*) seguem com
# stage=model-routing — sao pre-onda, a fase pode nao ser conhecida.
#
# Exit codes: 0 sucesso (inclui fallback graceful); 2 uso incorreto.
#   NUNCA aborta por model-selector ausente/erro.
#
# Ref: docs/specs/model-routing-por-onda/contracts/wave-select.md
#      docs/specs/model-routing-por-onda/data-model.md §DecisaoDeRoteamentoPorOnda
#      docs/specs/model-routing-por-onda/spec.md FR-001/002/005/006/007/008/
#        015/016/019/022/023/025
#      docs/specs/model-routing-por-onda/tasks.md 2.1..2.4

# Valida modelo contra enum {haiku,sonnet,opus,manter-atual} (SC-007).
# Stdout: o proprio modelo se valido; vazio se invalido. Exit sempre 0.
_mr_ws_valid_model() {
  case "$1" in
    haiku|sonnet|opus|manter-atual) printf '%s' "$1" ;;
    *) printf '%s' "" ;;
  esac
}

# Valida modelo de OVERRIDE contra enum {haiku,sonnet,opus} (FR-023 —
# 'manter-atual' NAO e override valido; override sempre forca um modelo
# concreto). Stdout: o modelo se valido; vazio se invalido. Exit 0.
_mr_ws_valid_override_model() {
  case "$1" in
    haiku|sonnet|opus) printf '%s' "$1" ;;
    *) printf '%s' "" ;;
  esac
}

# Mapeia faixa (rasa|media|profunda) -> modelo. Usado pelo refino para
# ajustar a faixa derivada do mapa. Pura expansao de case (POSIX).
_mr_ws_faixa_to_model() {
  case "$1" in
    rasa)     printf '%s' "haiku" ;;
    media)    printf '%s' "sonnet" ;;
    profunda) printf '%s' "opus" ;;
    *)        printf '%s' "" ;;
  esac
}

# Sanitiza --task-text UNTRUSTED (FR-022): remove NUL, trunca ao teto de
# bytes documentado (_MR_WS_TASKTEXT_MAX). Sem eval/expansao — apenas
# tr+head sobre o valor passado por aspas. Stdout: texto sanitizado.
# Reuso conceitual de F-001/F-002: nada e interpolado em comando/path.
_MR_WS_TASKTEXT_MAX=4096
_mr_ws_sanitize_tasktext() {
  # printf '%s' preserva literal; tr -d remove NUL; head -c trunca ao teto.
  # Pipeline POSIX puro; nenhum metacaractere e interpretado.
  printf '%s' "$1" | tr -d '\000' | head -c "$_MR_WS_TASKTEXT_MAX"
}

# Scrub de texto livre antes de gravar em justificativa (FR-025). Reusa
# secrets-filter.sh scrub (mesmo tratamento da ingestao do recall). Se o
# helper estiver ausente, degrada para no-op (texto bruto) — nunca aborta.
# Stdout: texto scrubbed (ou identico se helper ausente). Exit 0 sempre.
_mr_ws_scrub() {
  _mr_ws_sc_dir=${0%/*}
  _mr_ws_sc_helper="$_mr_ws_sc_dir/secrets-filter.sh"
  if [ -f "$_mr_ws_sc_helper" ]; then
    # secrets-filter le stdin, escreve stdout. Em falha: no-op.
    printf '%s' "$1" | sh "$_mr_ws_sc_helper" scrub 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# Le o primeiro DecisaoDeOverride NAO-consumido para a onda alvo (FR-016).
# Override = Decisao com etapa=model-routing e escolha que comeca com
# "model-override:". "Nao-consumido" = nao existe nenhuma
# DecisaoDeRoteamentoPorOnda posterior cujo contexto referencia a mesma
# onda (a Decisao de roteamento marca o override consumido ao aplica-lo;
# como register e append-only, a presenca de uma Decisao de roteamento
# para a onda ja foi tratada pela idempotencia no passo anterior).
#
# Escopo de UMA onda (FR-023): so casa override cujo contexto referencia
# explicitamente a onda alvo ("... para onda <N>"). Override de onda
# anterior nao vaza.
#
# Args: $1=state_file $2=onda_id
# Stdout: o valor do override (parte apos "model-override:") ou vazio.
# Exit 0 sempre (read-only).
_mr_ws_read_override() {
  _mr_ws_ro_sf=$1
  _mr_ws_ro_onda=$2
  # Reader (schema-en-migration): chaves EN com fallback pt-BR
  # ((.decisions // .decisoes), (.stage // .etapa), (.choice // .escolha),
  #  (.wave_id // .onda_id), (.context // .contexto)).
  jq -r \
    --arg onda "$_mr_ws_ro_onda" \
    '[(.decisions // .decisoes // [])[]?
       | select((.stage // .etapa) == "model-routing")
       | select((.choice // .escolha) | type == "string" and startswith("model-override:"))
       | select(((.wave_id // .onda_id) == $onda)
                or (((.context // .contexto) // "") | test("[Oo]nda " + ($onda | sub("^onda-0*"; "")) + "([^0-9]|$)")))
     ][0] | (.choice // .escolha) // empty' \
    "$_mr_ws_ro_sf" 2>/dev/null | sed -n 's/^model-override://p'
}

_mr_cmd_wave_select() {
  _mr_require_jq

  _mr_ws_sdir=""
  _mr_ws_etapa=""
  _mr_ws_tasktext=""
  _mr_ws_tasktext_set=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ "$#" -ge 2 ] || _mr_die_usage "wave-select: --state-dir requer valor"
        _mr_ws_sdir=$2; shift 2 ;;
      --state-dir=*)
        _mr_ws_sdir=${1#--state-dir=}; shift ;;
      --etapa)
        [ "$#" -ge 2 ] || _mr_die_usage "wave-select: --etapa requer valor"
        _mr_ws_etapa=$2; shift 2 ;;
      --etapa=*)
        _mr_ws_etapa=${1#--etapa=}; shift ;;
      --task-text)
        [ "$#" -ge 2 ] || _mr_die_usage "wave-select: --task-text requer valor"
        _mr_ws_tasktext=$2; _mr_ws_tasktext_set=1; shift 2 ;;
      --task-text=*)
        _mr_ws_tasktext=${1#--task-text=}; _mr_ws_tasktext_set=1; shift ;;
      *)
        _mr_die_usage "wave-select: flag desconhecida: $1" ;;
    esac
  done

  [ -n "$_mr_ws_sdir" ] || _mr_die_usage "wave-select: --state-dir ausente"
  _mr_ws_sf=$(_mr_state_file "$_mr_ws_sdir")
  [ -f "$_mr_ws_sf" ] || _mr_die_usage "wave-select: state.json ausente em '$_mr_ws_sdir'"
  [ -r "$_mr_ws_sf" ] || _mr_die_usage "wave-select: state.json sem leitura em '$_mr_ws_sdir'"

  # ---- Passo 1: resolver fase (flag ou .current_stage) ----
  # Reader (schema-en-migration): EN com fallback pt-BR (.current_stage // .etapa_corrente).
  if [ -z "$_mr_ws_etapa" ]; then
    _mr_ws_etapa=$(jq -r '(.current_stage // .etapa_corrente) // ""' "$_mr_ws_sf" 2>/dev/null) || _mr_ws_etapa=""
  fi
  # Fase vazia e tolerada -> lookup retorna manter-atual (FR-020).

  # ---- Onda corrente (proveniencia da Decisao) ----
  # Reader (schema-en-migration): EN com fallback pt-BR (.waves // .ondas).
  _mr_ws_onda=$(jq -r '((.waves // .ondas) // []) | if length > 0 then .[-1].id else "init" end' \
    "$_mr_ws_sf" 2>/dev/null) || _mr_ws_onda="init"
  [ -n "$_mr_ws_onda" ] || _mr_ws_onda="init"
  # Numero da onda para o contexto humano-legivel ("onda N").
  _mr_ws_onda_n=$(printf '%s' "$_mr_ws_onda" | sed -n 's/^onda-0*\([0-9][0-9]*\)$/\1/p')
  [ -n "$_mr_ws_onda_n" ] || _mr_ws_onda_n="$_mr_ws_onda"

  # ---- Passo 2: idempotencia por onda (FR-008) ----
  # Se ja existe DecisaoDeRoteamentoPorOnda para esta onda, ecoa o modelo
  # ja aplicado e sai SEM registrar 2a Decisao. Lead distinto do legado.
  # Reader (schema-en-migration): chaves EN com fallback pt-BR
  # ((.decisions // .decisoes), (.stage // .etapa), (.context // .contexto),
  #  (.wave_id // .onda_id), (.rationale // .justificativa), (.choice // .escolha)).
  # Discriminador = lead do contexto (FR-021), NAO o stage: Decisoes novas
  # gravam stage=<fase da onda>; legadas gravaram stage=model-routing. O
  # lead casa as duas geracoes sem colisao com overrides/legado-subagente.
  _mr_ws_existing=$(
    jq -r \
      --arg onda "$_mr_ws_onda" \
      '[(.decisions // .decisoes // [])[]?
         | select(((.context // .contexto) // "") | startswith("Selecao de modelo para onda "))
         | select((.wave_id // .onda_id) == $onda)
       ][-1] // empty
       | if . == null then empty
         else (((.rationale // .justificativa) // "") | capture("aplicado=(?<m>[a-z-]+)").m // ((.choice // .escolha) | sub("^model:"; "")))
         end' \
      "$_mr_ws_sf" 2>/dev/null
  ) || _mr_ws_existing=""
  if [ -n "$_mr_ws_existing" ]; then
    # Re-entrada (resume): ecoa o modelo ja decidido, nenhuma 2a Decisao.
    _mr_ws_echo=$(_mr_ws_valid_model "$_mr_ws_existing")
    [ -n "$_mr_ws_echo" ] || _mr_ws_echo="manter-atual"
    printf '%s\n' "$_mr_ws_echo"
    return 0
  fi

  # ---- Passo 2.4: escalonamento mid-onda (FR-015) ----
  # Sinal de subestimacao gravado pelo orquestrador na onda anterior:
  # campo .pending_model_escalation == true. Se presente, a proxima onda
  # parte de opus, independentemente do mapa-base da fase seguinte.
  # Reader (schema-en-migration): EN com fallback pt-BR
  # (.pending_model_escalation // .escalada_modelo_pendente). MAP-GAP: a
  # chave nao esta no mapa congelado §3 — proposta pending_model_escalation.
  _mr_ws_escalada=$(jq -r '(.pending_model_escalation // .escalada_modelo_pendente) // false' "$_mr_ws_sf" 2>/dev/null) \
    || _mr_ws_escalada="false"

  # ---- Passo 4: mapa primario (FR-014) — base de TODA onda ----
  _mr_ws_map_out=$(_mr_cmd_phase_model_lookup --fase "$_mr_ws_etapa" 2>/dev/null) \
    || _mr_ws_map_out="|manter-atual"
  _mr_ws_faixa=${_mr_ws_map_out%%|*}
  _mr_ws_map_model=${_mr_ws_map_out#*|}
  [ -n "$_mr_ws_map_model" ] || _mr_ws_map_model="manter-atual"

  # Base inicial: modelo do mapa. Sugerido parte do mapa.
  _mr_ws_sugerido="$_mr_ws_map_model"
  _mr_ws_aplicado="$_mr_ws_map_model"
  _mr_ws_origem="mapa"
  _mr_ws_score=0
  _mr_ws_nota=""
  _mr_ws_refinou=0

  # Escalada mid-onda tem precedencia sobre o mapa-base (FR-015), mas NAO
  # sobre override do operador (que vem depois e vence tudo).
  if [ "$_mr_ws_escalada" = "true" ]; then
    _mr_ws_sugerido="opus"
    _mr_ws_aplicado="opus"
    _mr_ws_origem="mapa"
    _mr_ws_nota="escalada-mid-onda: subestimacao sinalizada na onda anterior"
  fi

  # ---- Passo 5: refino (so execute-task + task-text) (FR-001/019) ----
  # So roda quando NAO ha escalada pendente (escalada forca opus, refino
  # nao deve rebaixar) e fase==execute-task e ha task-text.
  if [ "$_mr_ws_escalada" != "true" ] \
     && [ "$_mr_ws_etapa" = "execute-task" ] \
     && [ "$_mr_ws_tasktext_set" = 1 ]; then
    # FR-022: sanitizar UNTRUSTED antes de alimentar o classificador.
    _mr_ws_clean=$(_mr_ws_sanitize_tasktext "$_mr_ws_tasktext")
    # invoke roda em subshell isolada; nunca aborta (INV-1). Captura JSON.
    _mr_ws_invoke_json=$(
      "$0" invoke --subagent-type feature-00c-clarify-asker \
        --etapa clarify --input-text "$_mr_ws_clean" 2>/dev/null
    ) || _mr_ws_invoke_json=""
    if [ -n "$_mr_ws_invoke_json" ]; then
      # NOTA: NAO usar `.fallback // true` — jq trata `false` como
      # "vazio" no operador //, devolvendo true para fallback=false.
      # Usar if-then-else explicito sobre o valor booleano.
      _mr_ws_inv_fb=$(printf '%s' "$_mr_ws_invoke_json" \
        | jq -r 'if (.fallback == false) then "false" else "true" end' 2>/dev/null) \
        || _mr_ws_inv_fb="true"
      _mr_ws_inv_score=$(printf '%s' "$_mr_ws_invoke_json" | jq -r '.score_runtime // 0' 2>/dev/null) \
        || _mr_ws_inv_score=0
      _mr_ws_inv_model=$(printf '%s' "$_mr_ws_invoke_json" | jq -r '.modelo // ""' 2>/dev/null) \
        || _mr_ws_inv_model=""
      _mr_ws_inv_sinais=$(printf '%s' "$_mr_ws_invoke_json" | jq -r '.sinais_text // ""' 2>/dev/null) \
        || _mr_ws_inv_sinais=""
      # FR-019: so ajusta a faixa se score>=2 E nao-fallback E modelo
      # sugerido pelo refino e valido no enum {haiku,sonnet,opus}.
      _mr_ws_refined=$(_mr_ws_valid_override_model "$_mr_ws_inv_model")
      case "$_mr_ws_inv_score" in
        2|3)
          if [ "$_mr_ws_inv_fb" = "false" ] && [ -n "$_mr_ws_refined" ]; then
            # O refino integra a SUGESTAO (data-model L57: modelo_sugerido =
            # 'modelo do mapa/refino antes do override'). Logo sugerido segue
            # o refino — divergencia sugerido!=aplicado fica reservada a
            # override-operador/fallback (invariante L63-64 / SC-006). Sem
            # isto, o agregador FASE 6 contaria todo refino como
            # divergencia_sem_rotulo (dec-022).
            _mr_ws_sugerido="$_mr_ws_refined"
            _mr_ws_aplicado="$_mr_ws_refined"
            _mr_ws_origem="refino"
            # CAP em 2 (dec-007): o score_runtime do model-selector pode
            # ser 3, mas a trava do state-decisions.sh register EXIGE
            # --evidencia (>=20 chars, comando+output empirico) para
            # score=3. Os sinais do classify.sh sao heuristica de
            # token-matching, NAO sonda empirica (tsc/grep/test) — logo
            # nao satisfazem o contrato de evidencia do score 3. O score
            # registrado e capado em 2 ("evidencia razoavel"), que e o
            # significado correto de um refino por catalogo de sinais.
            _mr_ws_score=2
            _mr_ws_refinou=1
            # Sinais sao texto livre derivado de input UNTRUSTED -> scrub
            # (FR-025) antes de virar nota auditavel.
            _mr_ws_nota="refino: $(_mr_ws_scrub "$_mr_ws_inv_sinais")"
          fi
          ;;
        *) : ;;  # score<2 -> mantem mapa (FR-019)
      esac
    fi
    # Refino ausente/fallback/score<2 -> mapa prevalece (FR-006/019). No-op.
  fi

  # ---- Passo 3: override do operador (precedencia maxima) (FR-016/023) ----
  _mr_ws_ovr_raw=$(_mr_ws_read_override "$_mr_ws_sf" "$_mr_ws_onda")
  if [ -n "$_mr_ws_ovr_raw" ]; then
    _mr_ws_ovr_valid=$(_mr_ws_valid_override_model "$_mr_ws_ovr_raw")
    if [ -n "$_mr_ws_ovr_valid" ]; then
      # Override valido vence mapa e refino (FR-016).
      _mr_ws_aplicado="$_mr_ws_ovr_valid"
      _mr_ws_origem="override-operador"
      _mr_ws_nota="override-operador consumido (escopo: onda $_mr_ws_onda_n)"
      _mr_ws_refinou=0  # override nao usa model-selector; sem record-skill
    else
      # FR-023: override invalido NUNCA propaga ao spawn. Cai em fallback
      # para o modelo ja computado (mapa/refino) com nota auditavel. O
      # modelo aplicado permanece o que veio do mapa/refino.
      _mr_ws_origem="fallback"
      _mr_ws_nota="override invalido rejeitado (fora do enum {haiku,sonnet,opus}): nao propagado ao spawn"
    fi
  fi

  # ---- Passo 6: validar modelo aplicado contra enum (SC-007) ----
  _mr_ws_final=$(_mr_ws_valid_model "$_mr_ws_aplicado")
  if [ -z "$_mr_ws_final" ]; then
    # Modelo invalido/desconhecido -> manter-atual (origem=fallback).
    _mr_ws_final="manter-atual"
    _mr_ws_aplicado="manter-atual"
    _mr_ws_origem="fallback"
    [ -n "$_mr_ws_nota" ] || _mr_ws_nota="modelo invalido -> manter-atual"
  fi

  # ---- Passo 7: registrar DecisaoDeRoteamentoPorOnda (FR-007) ----
  # escolha = model:<aplicado> no sucesso; manter-atual no fallback puro.
  if [ "$_mr_ws_final" = "manter-atual" ]; then
    _mr_ws_escolha="manter-atual"
  else
    _mr_ws_escolha="model:$_mr_ws_final"
  fi

  # justificativa com tokens parseaveis (dec-006) + nota scrubbed.
  # Formato fixo: "sugerido=<m> aplicado=<m> origem=<o> | <nota>".
  _mr_ws_just_prefix="sugerido=$_mr_ws_sugerido aplicado=$_mr_ws_aplicado origem=$_mr_ws_origem"
  if [ -n "$_mr_ws_nota" ]; then
    _mr_ws_just="$_mr_ws_just_prefix | $_mr_ws_nota"
  else
    _mr_ws_just="$_mr_ws_just_prefix | faixa=$_mr_ws_faixa fase=$_mr_ws_etapa (mapa primario)"
  fi
  # Garantia de >=20 chars (validacao do register) — o prefixo ja excede.

  _mr_ws_ctx="Selecao de modelo para onda $_mr_ws_onda_n (fase $_mr_ws_etapa)"

  _mr_ws_decscript="${0%/*}/state-decisions.sh"
  _mr_ws_ondascript="${0%/*}/state-ondas.sh"

  # stage da Decisao = fase da onda (consumidores derivados agrupam por
  # stage como etapa SDD). Fase vazia degrada para "model-routing" — o
  # register exige --etapa nao-vazio e o lead do contexto ja discrimina.
  _mr_ws_dec_etapa="$_mr_ws_etapa"
  [ -n "$_mr_ws_dec_etapa" ] || _mr_ws_dec_etapa="model-routing"

  # Registrar. score 3 exigiria evidencia; usamos 0 ou 2 (refino) -> ok.
  _mr_ws_dec_id=$(
    sh "$_mr_ws_decscript" register --state-dir "$_mr_ws_sdir" \
      --agente "agente-00c-feature-orchestrator" --etapa "$_mr_ws_dec_etapa" \
      --contexto "$_mr_ws_ctx" \
      --opcoes '["haiku","sonnet","opus","manter-atual"]' \
      --escolha "$_mr_ws_escolha" \
      --justificativa "$_mr_ws_just" \
      --score "$_mr_ws_score" 2>/dev/null
  ) || _mr_ws_dec_id=""

  # ---- record-skill (par I3) somente quando o refino invocou model-selector ----
  # record-skill emite uma contagem em stdout; suprimimos (>/dev/null) para
  # nao poluir o stdout do wave-select, que DEVE conter apenas o modelo.
  if [ "$_mr_ws_refinou" = "1" ] && [ -n "$_mr_ws_dec_id" ]; then
    sh "$_mr_ws_ondascript" record-skill --state-dir "$_mr_ws_sdir" \
      --skill model-selector --decisao-id "$_mr_ws_dec_id" >/dev/null 2>&1 || :
  fi

  # ---- Passo 8: emitir modelo aplicado ----
  printf '%s\n' "$_mr_ws_final"
  return 0
}

# ---------- Dispatch ----------
#
# F4.5 — sourcing guard: testes unitarios do `tests/test_model-routing.sh`
# precisam sourcear o script para chamar helpers internos (_mr_utf8_*)
# isolados. Quando MR_SOURCE_ONLY=1 esta exportado, pulamos o dispatch
# inteiro (HELP + case "$_MR_SUBCMD") e retornamos do source sem efeito
# colateral. Mantemos comportamento default (sem MR_SOURCE_ONLY) identico
# ao anterior para preservar contrato CLI.

if [ "${MR_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
model-routing.sh — integra `model-selector` ao pipeline de spawn de subagentes
dos orquestradores agente-00c (FR-001..FR-020).

USO:
  model-routing.sh template          --subagent-type TYPE
  model-routing.sh invoke            --subagent-type TYPE --etapa STAGE
                                     [--input-text OVERRIDE]
                                     [--timeout-seconds N]
  model-routing.sh idempotent-check  --state-dir DIR --onda-id ID
                                     --subagent-type TYPE
  model-routing.sh phase-model-lookup --fase FASE
  model-routing.sh wave-select       --state-dir DIR [--etapa FASE]
                                     [--task-text DESC]

Enum --subagent-type:
  agente-00c-clarify-asker | agente-00c-clarify-answerer |
  feature-00c-clarify-asker | feature-00c-clarify-answerer

Enum --etapa:
  clarify  (futuras fases entrarao via FR-016 — atualizacao documental)

EXIT:
  0 sucesso (inclui fallback graceful em invoke — INV-1)
  1 erro generico (state.json ausente, jq ausente, etc)
  2 uso incorreto (subcomando desconhecido, flag ausente, enum invalido)

Ref: docs/specs/agente-00c-model-routing/contracts/model-routing-helper.md
HELP
  exit 2
fi

_MR_SUBCMD=$1
shift

case "$_MR_SUBCMD" in
  template)
    _mr_cmd_template "$@"
    ;;
  invoke)
    _mr_cmd_invoke "$@"
    ;;
  idempotent-check)
    _mr_cmd_idempotent_check "$@"
    ;;
  phase-model-lookup)
    _mr_cmd_phase_model_lookup "$@"
    ;;
  wave-select)
    _mr_cmd_wave_select "$@"
    ;;
  -h|--help|help)
    # Reusa o bloco HELP do dispatch acima.
    "$0"
    ;;
  *)
    _mr_die_usage "subcomando desconhecido: '$_MR_SUBCMD' (use 'help' para uso)"
    ;;
esac
