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
#                           dec-004 (idempotencia via jq sobre .decisoes[]),
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
  printf '%s/state.json\n' "$1"
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
#   2. Query jq read-only: primeiro .decisoes[] cujo .contexto == ctx
#      AND .onda_id == ONDA -> emitir .id ou string vazia.
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
  _mr_idc_result=$(
    jq -r \
      --arg ctx "Selecao de modelo para subagente $_mr_idc_subagent" \
      --arg onda "$_mr_idc_onda" \
      '[.decisoes[]? | select(.contexto == $ctx and .onda_id == $onda)][0].id // empty' \
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
  -h|--help|help)
    # Reusa o bloco HELP do dispatch acima.
    "$0"
    ;;
  *)
    _mr_die_usage "subcomando desconhecido: '$_MR_SUBCMD' (use 'help' para uso)"
    ;;
esac
