# Referencia de fase: clarify (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   ### 5.e Padrao de dois atores (clarify)

   Em `clarify`, aplique o **padrao de dois atores** (FASE 4):

   a. **Pre-flight**: `spawn-tracker.sh check --state-dir <SD>`. Exit 3 =
      abortar (limite de profundidade atingido — bisneto nao pode spawnar).

      **Checagem de disponibilidade da tool Agent (sug-006/dec-006):**
      ANTES do spawn real (e antes da sequencia de model-routing de
      §5.e.bis), confira se `Agent` esta na SUA lista de tools. NAO
      spawne agente de teste para isso — o spawn de dry-run custava um
      subagente inteiro por clarify e a lista de tools ja e a fonte
      de verdade: o harness retira `Agent` exatamente no limite de
      profundidade (default 3 camadas abaixo da conversa principal;
      verificado empiricamente em 2026-09-27, Claude Code 2.1.283 —
      camadas 1 e 2 tem `Agent`, a 3a nao). Como voce roda na camada 1
      e o asker/answerer na 2, o normal e `Agent` estar presente. Se
      NAO estiver, registre Decisao EXPLICITA de downgrade:

      ```bash
      state-decisions.sh register --state-dir <SD> \
        --agente "orquestrador-00c" --etapa "clarify" \
        --contexto "Tool Agent indisponivel no harness — clarify rodara in-process (orquestrador atuando como answerer)" \
        --opcoes '["spawn-subagentes","in-process-degraded"]' \
        --escolha "in-process-degraded" \
        --justificativa "dec-006 historica documentou esse downgrade; preservamos rigor mas perdemos segundo par-de-olhos do padrao dois-atores. Aviso auditado para retomar quando Agent disponivel."
      ```

      Se `Agent` esta na lista, prossiga normalmente para item (b).
      Esse check evita silent-fallback documentado em dec-006 da
      execucao-fonte.

      **Preservacao FR-004 (model-routing-por-onda, FASE 5.2):** no
      caminho degradado (`in-process-degraded`), o clarify roda
      in-process — NAO ha spawn real de subagente via tool Agent,
      logo NAO ha onde aplicar `model=<MODELO>` (o orquestrador atua
      como answerer no proprio modelo corrente). Portanto a sequencia
      pre-spawn de model-routing (§5.e.bis passos 1-8) NAO roda nesse
      caminho: nem `model-routing.sh invoke`, nem
      `state-decisions.sh register` de "Selecao de modelo para
      subagente". Consequencia: NENHUMA Decisao de model-routing orfa
      e gerada (Invariante I1 preservada — Decisao de modelo so existe
      quando ha spawn real). A unica Decisao do caminho degradado e a
      de downgrade acima (`escolha=in-process-degraded`), cujo
      `contexto` NAO casa com `startswith("Selecao de modelo")` e
      portanto e ignorada pelo orphan-check de model-routing.

   b. **Spawn clarify-asker**:
      - `spawn-tracker.sh enter --state-dir <SD>` (incrementa profundidade).
      - Invoque via tool Agent com `subagent_type: agente-00c-clarify-asker`,
        passando no prompt: `spec_path`, `briefing_path`, `etapa_corrente`,
        `decisoes_anteriores` (de `.decisions`), `quantidade_max_perguntas`.
      - Receba JSON `{ "perguntas": [...] }`.
      - `spawn-tracker.sh leave --state-dir <SD>` (decrementa).
      - Se `perguntas: []` (asker indica que clarify esta completo), pule
        para o item (g) — nao spawne answerer.

   c. **Spawn clarify-answerer** (irmao, nao filho — ambos sao netos do
      orquestrador raiz):
      - `spawn-tracker.sh enter --state-dir <SD>`.
      - Invoque via tool Agent com `subagent_type:
        agente-00c-clarify-answerer`, passando no prompt: `perguntas` (do
        asker), `briefing_path`, `constitution_feature_path`,
        `constitution_toolkit_path`, `stack_sugerida` (de
        `.execution.suggested_stack`), `decisoes_anteriores`.
      - Receba JSON `{ "respostas": [...] }`.
      - `spawn-tracker.sh leave --state-dir <SD>`.

   d. **Aplicar respostas**: para CADA item em `respostas`:
      - **Se `pause_humano: false`**: registre Decisao via
        `state-decisions.sh register --state-dir <SD>
        --agente "clarify-answerer" --etapa "clarify"
        --contexto "<resposta.contexto da pergunta original>"
        --opcoes <pergunta.opcoes_recomendadas como JSON-arr>
        --escolha "<resposta.opcao_escolhida>"
        --justificativa "<resposta.justificativa>"
        --score <resposta.score>
        --referencias <resposta.referencias como JSON-arr>`.
        Capture o `dec-NNN` retornado.
      - **Se `pause_humano: true`**: PRIMEIRO registre a Decisao
        marcando `escolha: "pause-humano"` e `score: 0` (Principio I —
        toda decisao e auditada, inclusive a de pausar). Capture o
        `dec-NNN`. ENTAO chame `bloqueios.sh register --state-dir <SD>
        --decisao-id <dec-NNN> --pergunta "<pergunta.pergunta>"
        --contexto-para-resposta "<resposta.contexto_para_humano>"
        --opcoes-recomendadas <pergunta.opcoes_recomendadas como JSON-arr>`.

   e. **Apply em spec.md** — para respostas validas (nao pause-humano),
      atualize `spec.md` com a decisao tomada (a forma exata depende da
      pergunta — pode ser inserir um requisito FR-NNN, atualizar uma
      secao, ou anotar em "Resolved Ambiguities"). Cada update e uma
      escrita atomica via Edit/Write — o `git-commit` no fim de onda
      consolida tudo.

   f. **Score 0 = fim de onda gracioso** (FR-015, FR-016):
      Se `bloqueios.sh count --state-dir <SD> --pending-only` > 0 apos
      o batch, NAO continue para a proxima etapa nesta onda. Pule
      direto para o item 9 (fim de onda) com `--motivo-termino
      bloqueio_humano`. O lifecycle real do bloqueio (resposta humana
      via `/agente-00c-resume --resposta-bloqueio <id>:<resp>`) e
      tratado em FASE 7.

   g. Etapa clarify completa: prossiga para o item 6.

   ### 5.e.bis Sequencia pre-spawn de subagente (model-routing)

   Esta secao define a sequencia OBRIGATORIA de chamadas antes de cada
   `spawn-tracker.sh enter` + `tool Agent` na fase `clarify` (asker e
   answerer). Implementa FR-010, FR-011, FR-012, FR-016, FR-017 da
   feature `agente-00c-model-routing` e o contrato em
   `docs/specs/agente-00c-model-routing/contracts/orchestrator-integration.md`.

   **Objetivo**: registrar uma Decisao auditavel (entidade `Decisao`,
   FR-015) escolhendo o modelo recomendado para cada subagente,
   ANTES do spawn. A partir da feature `model-routing-por-onda`
   (v4.0.0), a `escolha` da Decisao **e aplicada** no spawn quando
   acionavel (`escolha` ∈ {haiku,sonnet,opus} e `score >= 2`) — vide
   passo 8 e a nota "FR-003 — sugerido vira aplicado" abaixo. Isso
   **revoga** o comportamento audit-only do FR-017 da feature
   original: a premissa "harness nao aceita `model` no spawn" ficou
   obsoleta. A Decisao permanece como rastro auditavel da aplicacao +
   telemetria via review-task.

   **Ordem canonica** (idempotente por onda + subagent_type — FR-012,
   dec-004):

   ```
   1. spawn-tracker.sh check        (FR-013 — depth disponivel?)
   2. ONDA_ID = state-ondas.sh current-id
   3. EXISTING = model-routing.sh idempotent-check     (FR-012)
        exit 0 -> ja existe dec-NNN para (onda, T); pular 4-6
        exit 1 -> prosseguir
   4. JSON = model-routing.sh invoke --subagent-type T --etapa clarify
   5. DEC_ID = state-decisions.sh register             (FR-015, FR-017)
   6. state-ondas.sh record-skill --skill model-selector --decisao-id $DEC_ID
   7. spawn-tracker.sh enter        (incrementa profundidade)
   8. tool Agent (subagent_type=T)  (modelo da dec-NNN APLICADO via
                                     model= quando acionavel; senao herda
                                     frontmatter — vide nota FR-003 abaixo)
   ```

   #### Invariante I1 — "1 Decisao por spawn REAL, nao por spawn potencial"

   Ref: dec-005, Edge Case item 4 da feature
   `agente-00c-model-routing`, FR-015.

   Se o passo (b) `Spawn clarify-asker` retornou `perguntas: []`
   (no-op semantico: nao ha duvidas a responder, fase clarify
   completa), o orquestrador NAO MUST invocar a sequencia 1-7 para
   `clarify-answerer` — porque o answerer NAO sera spawnado.
   Invariante reciproca: para cada Decisao com
   `contexto = "Selecao de modelo para subagente <T>"` deve existir
   exatamente UM `spawn-tracker.sh enter` subsequente com
   `subagent_type=<T>` na mesma onda. Decisao orfa (sem spawn
   correspondente) e violacao de auditoria — review-task reporta
   como finding `model-routing-orphan-decision`.

   Concretamente, o controle de fluxo do orquestrador apos receber a
   resposta do asker e:

   ```
   ASKER_OUTPUT=<JSON do asker>
   PERGUNTAS=$(printf '%s' "$ASKER_OUTPUT" | jq '.perguntas | length')
   if [ "$PERGUNTAS" -eq 0 ]; then
     # Fase clarify completa: NAO invocar 1-7 para answerer.
     # Avancar diretamente para plan (Loop principal passo 5).
     continue
   fi
   # else: rodar a sequencia 1-7 para SUBAGENT_TYPE=clarify-answerer
   ```

   #### Invariante I2 — Retomada idempotente via `/agente-00c-resume`

   Ref: dec-004 (idempotencia via jq em `.decisions[]`), FR-012,
   Edge Case "Retomada via `/agente-00c-resume` no meio da fase clarify".

   Cenario: o processo do orquestrador sofre preempcao/crash ENTRE o
   `state-decisions.sh register` (passo 5) e o `spawn-tracker.sh enter`
   (passo 7) — ou entre o `enter` e o retorno da tool Agent. Ao
   retomar via `/agente-00c-resume`, o orquestrador re-entra na mesma
   onda. Sem protecao, a sequencia 1-7 rodaria de novo e registraria
   uma SEGUNDA Decisao para o mesmo `(wave_id, subagent_type)`,
   inflando `.decisions` e violando SC-001.

   **Protocolo obrigatorio de retomada**: o `/agente-00c-resume` (e
   por simetria `/feature-00c-resume`) DEVE delegar ao orquestrador a
   responsabilidade de rodar o passo 3 (`model-routing.sh
   idempotent-check`) ANTES de qualquer chamada `model-routing.sh
   invoke` ou `state-decisions.sh register`. O fluxo permanece
   identico ao Loop principal: nenhum branch especial para "modo
   retomada" — a propria idempotencia garante o comportamento:

   - **idempotent-check exit 0** → ja existe `dec-NNN` matching;
     stdout traz o id; pular passos 4-6; ir direto para passo 7
     (`spawn-tracker.sh enter`) + passo 8 (tool Agent).
   - **idempotent-check exit 1** → nao existe; rodar passos 4-6
     normalmente.

   Skip silencioso (exit 0 + reaproveitamento da Decisao) e
   AUDITAVEL: o orquestrador NAO precisa registrar Decisao adicional
   "pulei por idempotencia" — o proprio fato de `.decisions` ter
   exatamente 1 entrada por `(wave_id, subagent_type)` apos retomada e
   a evidencia. review-task verifica essa invariante via query jq
   agregada (ver `contracts/orchestrator-integration.md §Invariantes
   consumidas por review-task`).

   Anti-padrao a evitar: tentar "limpar Decisoes parciais" ou rodar a
   sequencia 1-7 incondicionalmente em retomada. Ambos violam FR-012.

   **Bloco Bash referencial** (paths absolutos, flags exatas — paralelo
   ao bloco em §5.f Quality Gates):

   ```bash
   # Pre-flight de spawn (rodar para CADA subagente: asker e answerer)
   #
   # Variaveis esperadas no escopo do orquestrador:
   #   SD                 -> $AGENTE_00C_STATE_DIR (state-dir absoluto)
   #   SUBAGENT_TYPE      -> "agente-00c-clarify-asker" ou
   #                         "agente-00c-clarify-answerer"
   #   ORCHESTRATOR_ID    -> "agente-00c-orchestrator"
   #   RUNTIME_SCRIPTS    -> ~/.claude/skills/agente-00c-runtime/scripts

   # Passo 1: depth disponivel?
   "$RUNTIME_SCRIPTS"/spawn-tracker.sh check \
     --state-dir "$SD" || { echo "abort: depth"; exit 3; }   # teto = const _ST_MAX=3 no script, nao ha flag

   # Passo 2: ONDA_ID corrente
   ONDA_ID=$("$RUNTIME_SCRIPTS"/state-ondas.sh current-id --state-dir "$SD")

   # Passo 3: idempotent-check (FR-012, dec-004)
   if EXISTING_DEC=$("$RUNTIME_SCRIPTS"/model-routing.sh idempotent-check \
        --state-dir "$SD" --onda-id "$ONDA_ID" \
        --subagent-type "$SUBAGENT_TYPE" 2>/dev/null); then
     DEC_ID="$EXISTING_DEC"
     # Log auditavel: pulou model-routing por idempotencia
   else
     # Passo 4: invoke do helper (gera JSON com modelo + score + sinais)
     JSON=$("$RUNTIME_SCRIPTS"/model-routing.sh invoke \
              --subagent-type "$SUBAGENT_TYPE" --etapa clarify)

     # Extrair campos do JSON (jq + saneamento conforme contrato)
     MODELO=$(printf '%s' "$JSON"      | jq -r '.modelo')
     SCORE=$(printf '%s' "$JSON"       | jq -r '.score_runtime')
     SINAIS=$(printf '%s' "$JSON"      | jq -r '.sinais_text')
     IS_FB=$(printf '%s' "$JSON"       | jq -r '.fallback // false')
     FB_REASON=$(printf '%s' "$JSON"   | jq -r '.fallback_reason // ""')

     if [ "$IS_FB" = "true" ]; then
       # Modo fallback (FR-014): escolha "fallback-default", score 0,
       # sem --evidencia (nao aplica a score=0)
       DEC_ID=$("$RUNTIME_SCRIPTS"/state-decisions.sh register \
                  --state-dir "$SD" \
                  --agente "$ORCHESTRATOR_ID" --etapa "clarify" \
                  --contexto "Selecao de modelo para subagente $SUBAGENT_TYPE" \
                  --opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]' \
                  --escolha "fallback-default" \
                  --score 0 \
                  --justificativa "fallback: $FB_REASON")
     else
       # Modo normal (score >= 2 do model-selector)
       DEC_ID=$("$RUNTIME_SCRIPTS"/state-decisions.sh register \
                  --state-dir "$SD" \
                  --agente "$ORCHESTRATOR_ID" --etapa "clarify" \
                  --contexto "Selecao de modelo para subagente $SUBAGENT_TYPE" \
                  --opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]' \
                  --escolha "$MODELO" \
                  --score "$SCORE" \
                  --justificativa "$SINAIS" \
                  --evidencia "$SINAIS")
     fi

     # Passo 6: rastrear skill model-selector no roster da onda
     "$RUNTIME_SCRIPTS"/state-ondas.sh record-skill --state-dir "$SD" \
       --skill model-selector --decisao-id "$DEC_ID"
   fi

   # Passo 7: incrementar depth ANTES do spawn real
   "$RUNTIME_SCRIPTS"/spawn-tracker.sh enter --state-dir "$SD"

   # Passo 7.bis: derivar MODEL_APLICAR da Decisao DEC_ID (FR-003).
   # NAO reusar as vars MODELO/SCORE/IS_FB do passo 4: elas so existem
   # no branch `else`; no caminho idempotente (passo 3) apenas DEC_ID
   # foi setado. Derivar de .decisions[] cobre AMBOS os caminhos sem
   # gerar Decisao orfa. Aplicar o modelo SOMENTE se a Decisao tem
   # escolha ∈ {haiku,sonnet,opus} E score >= 2 (nao-fallback). A
   # escolha "fallback-default" (ou "manter-atual") => OMITIR o param
   # model (herda o frontmatter do agent file) — FR-006.
   ESCOLHA_DEC=$("$RUNTIME_SCRIPTS"/state-rw.sh get --state-dir "$SD" \
     --field ".decisions[] | select(.id == \"$DEC_ID\") | .choice")
   # NB: o campo de score no schema da Decisao e `justification_score`
   # (state-decisions.sh mapeia --score -> .justification_score).
   SCORE_DEC=$("$RUNTIME_SCRIPTS"/state-rw.sh get --state-dir "$SD" \
     --field ".decisions[] | select(.id == \"$DEC_ID\") | .justification_score")
   MODEL_APLICAR=""
   if [ "$SCORE_DEC" -ge 2 ] 2>/dev/null; then
     if [ "$ESCOLHA_DEC" = "haiku" ] || [ "$ESCOLHA_DEC" = "sonnet" ] \
        || [ "$ESCOLHA_DEC" = "opus" ]; then
       MODEL_APLICAR="$ESCOLHA_DEC"
     fi
   fi

   # Passo 8: spawn REAL (tool Agent). FR-003 — aplicar o modelo:
   #   - Se MODEL_APLICAR nao-vazio (escolha ∈ {haiku,sonnet,opus} e
   #     score>=2): invocar a tool Agent COM `model: $MODEL_APLICAR`.
   #   - Senao (fallback-default / manter-atual / score<2): invocar a
   #     tool Agent SEM o param model — herda o `model:` do frontmatter
   #     do agent file (FR-006).
   #
   # if [ -n "$MODEL_APLICAR" ]; then
   #   tool Agent: subagent_type=$SUBAGENT_TYPE, model=$MODEL_APLICAR,
   #               prompt=<conforme §5.e>
   # else
   #   tool Agent: subagent_type=$SUBAGENT_TYPE, prompt=<conforme §5.e>
   # fi
   #
   # Apos retorno: spawn-tracker.sh leave (ja documentado em §5.e).
   ```

   **Importante** (FR-003 — sugerido vira aplicado): a partir desta
   feature (`model-routing-por-onda`, FASE 5), o passo 8 APLICA o
   modelo sugerido no passo 5 quando ele e acionavel — `escolha` ∈
   {haiku,sonnet,opus} e `score >= 2`. Isso revoga o comportamento
   audit-only anterior (a Decisao deixou de ser PURAMENTE auditavel
   para o spawn de clarify). O par Decisao⟷spawn permanece 1-para-1
   (Invariante I1): a aplicacao NAO cria nova Decisao, apenas le a ja
   registrada via `DEC_ID`. Em fallback (`escolha=fallback-default`)
   ou `manter-atual` ou score<2, o param `model` e OMITIDO e o
   subagente herda o `model:` do frontmatter do agent file (FR-006) —
   sem Decisao adicional, sem spawn orfo.

   #### Quoting de `sinais_text` ao chamar `register` (F4.2 — hardening F-002)

   Ref: dec-009 F-002 (medium), FR-006, FR-017,
   `contracts/orchestrator-integration.md §Mapeamento JSON`.

   `sinais_text` carrega texto livre do `model-selector` (linha bruta da
   secao "## Justificativa" do classify.sh). Esse texto PODE conter
   metacaracteres de shell: aspas duplas, aspas simples, `$`, barra
   invertida, parenteses, ate fragmentos hostis injetados via input
   adversarial (ex: `"; DROP TABLE users; --`). Embora `model-routing.sh
   invoke` ja escape via `jq -n --arg sinais "$_mr_sinais"` antes de
   emitir o JSON (F-002 mitigado na fronteira do helper), o orquestrador
   precisa re-extrair `sinais_text` via `jq -r` e repassar para
   `state-decisions.sh register` — e e nessa passagem que mora o risco.

   **Regra obrigatoria**:

   1. Sempre extrair `sinais_text` para uma VARIAVEL intermediaria
      (`SINAIS=$(... | jq -r '.sinais_text')`). Nao consumir o output de
      `jq` diretamente como argumento de `register`.
   2. Passar a variavel para `--justificativa` e `--evidencia` com aspas
      duplas em volta: `--justificativa "$SINAIS"`. Aspas duplas
      preservam o conteudo literal mesmo com whitespace, sem invocar
      word-splitting nem glob expansion.
   3. NUNCA construir o argumento via concatenacao de strings (ex:
      `--justificativa "sinais foram: $SINAIS"`). Concatenar adiciona
      uma camada de re-interpretacao desnecessaria e abre brecha de
      injection se algum dia o snippet for refatorado para `eval`
      indireto (logging, debug, dispatch).
   4. NAO usar `printf` ou `echo` antes de passar — `register` aceita o
      valor literal como argv[N]; reformatar antes corrompe whitespace
      e quebra `jq -r .rationale` downstream em `review-task`.

   Exemplo CORRETO (forma canonica, ja presente em passo 5):

   ```bash
   SINAIS=$(printf '%s' "$JSON" | jq -r '.sinais_text')
   DEC_ID=$("$RUNTIME_SCRIPTS"/state-decisions.sh register \
              --state-dir "$SD" \
              --agente "$ORCHESTRATOR_ID" --etapa "clarify" \
              --contexto "Selecao de modelo para subagente $SUBAGENT_TYPE" \
              --opcoes '["haiku","sonnet","opus","manter-atual","fallback-default"]' \
              --escolha "$MODELO" --score "$SCORE" \
              --justificativa "$SINAIS" \
              --evidencia "$SINAIS")
   ```

   Exemplo INCORRETO (NUNCA faca):

   ```bash
   # ERRADO 1: consome jq diretamente — sem variavel intermediaria.
   # Word-splitting + interpretacao de aspas no output do jq quebra
   # quando sinais contem espaco.
   register --justificativa $(printf '%s' "$JSON" | jq -r '.sinais_text')

   # ERRADO 2: concatenacao com prefixo descritivo. Re-interpreta
   # metacaracteres se a string for ecoada em log via printf "%s\n"
   # sem '%s' (vide F-001). E corrompe auditoria — justificativa
   # passa a ter texto fixo + livre misturados.
   register --justificativa "sinais: $SINAIS"

   # ERRADO 3: passar SEM aspas. Word-splitting separa em multiplos
   # argv, register vai parsear errado.
   register --justificativa $SINAIS
   ```

   Validacao: `tests/test_model-routing.sh` exercita payload sintetico
   contendo aspas duplas + barra invertida + `"; DROP TABLE; --` e
   confirma que (a) o JSON de saida do `invoke` e parseavel via `jq
   -e .`, e (b) a `justificativa` registrada via `state-decisions.sh
   register` preserva o texto literal sem corrupcao. Auditoria visual
   complementar: `grep -nE "jq.*-n" model-routing.sh` deve casar com
   cada bloco de composicao de JSON (atualmente: emissao de fallback e
   emissao de sucesso).

   #### Protocolo de falha do two-step (F4.4 — hardening F-004)

   Ref: dec-009 F-004 (low), F4.4 da feature
   `agente-00c-model-routing`, FR-015 + FR-016.

   Se `state-ondas.sh record-skill` (passo 6) falhar APOS
   `state-decisions.sh register` (passo 5) ter persistido a Decisao,
   o orquestrador-de-projeto DEVE:

   1. **NAO repetir o `register`**: a Decisao ja existe em
      `.decisions[]` com `dec-NNN` assinado. Re-executar produziria
      `dec-NNN+1` duplicada e violaria FR-015 (1 invocacao por spawn).
   2. **Logar via `log_err`** (helper de `_log.sh`): `model-routing:
      record-skill falhou para <DEC_ID>; estado em half-record`.
   3. **Registrar Decisao de reconciliacao** via `state-decisions.sh
      register --score 2` descrevendo o desalinhamento (contexto:
      "Reconciliacao two-step para <DEC_ID> apos record-skill falho").
   4. **Re-tentar `record-skill`** uma unica vez. Se falhar de novo,
      emitir BloqueioHumano via `bloqueios.sh register`.

   Em retomadas (`/agente-00c-resume`), ANTES de qualquer
   `model-routing.sh invoke`, o resume DEVE executar:

   ```bash
   "$RUNTIME_SCRIPTS"/state-decisions-reconcile.sh check \
     --state-dir "$SD"
   # exit 0 -> nenhuma orfa, prosseguir.
   # exit 1 -> stdout TSV: <dec-id>\t<onda-id>\t<subagent-type> por
   #           orfa. Resume DEVE emitir os record-skill missing antes
   #           de qualquer novo spawn, preservando FR-015 + paridade.
   # exit 2 -> erro de uso/IO, abortar com diagnostico.
   ```

   O helper `state-decisions-reconcile.sh` (script auxiliar do
   runtime; F4.4.2) e read-only e idempotente; pode rodar tambem
   como parte de `review-task` para listar half-records cronicos.

   **Compatibilidade com `agente-00c-artifact-cache`** (SC-004 + F2.3):
   `model-routing` e a feature `agente-00c-artifact-cache` operam em
   eixos ORTOGONAIS. Justificativa:

   - O input do `model-routing.sh invoke` vem do CONTEXTO DO SUBAGENTE
     (subagent-type + etapa + input-text derivado do template ou
     override do orquestrador). Nao depende de briefing.md nem de
     constitution.md.
   - O subcomando `idempotent-check` faz query `jq` read-only sobre
     `.decisions[]` em `state.json`. Nao le `state.json.briefing_cache`
     nem `state.json.constitution_cache` — esses campos sao aditivos
     e o helper nunca os referencia.
   - Portanto: ligar/desligar o cache (`briefing_cache.strategy =
     "passthrough"`, ausencia dos campos em execucao legada, ou cache
     populado com resumos) NAO altera o comportamento de `invoke` nem
     de `idempotent-check`. Output JSON deterministico, exit codes
     estaveis, sha256 dos campos de cache preservado antes e depois
     da pipeline (analogo a INV-4, estendido para cache).
   - A onda 1 do `artifact-cache` (popula `briefing_cache` +
     `constitution_cache`) e a onda N do `model-routing` (registra
     Decisao por spawn) podem co-ocorrer no mesmo `state.json` sem
     interferencia mutua.

   Test gate (F2.3.2): `tests/test_model-routing.sh` cobre cenarios
   `scenario_artifact_cache_compat_*` validando que `idempotent-check`
   + `invoke` rodam com `briefing_cache`/`constitution_cache`
   populados em state.json fixture e que sha256 desses campos
   permanece estavel apos a pipeline.

   #### Cap defensivo de invocacoes por onda (F4.3 — hardening F-003)

   Ref: dec-009 F-003 (low), F4.3 da feature
   `agente-00c-model-routing`, SC-006 (<2s por invocacao), Edge Case
   "Loop infinito de retry".

   O helper `model-routing.sh invoke` ja impoe **timeout de 5s** por
   chamada (default; override via `--timeout-seconds N`, N>=1) via
   `_mr_invoke_skill` (subshell + sleep + kill -TERM/-KILL +
   convencao exit 124). Isso garante INV-1 (exit 0 sempre) e SC-006
   (latencia <=6s no pior caso: 5s timeout + 1s margem KILL).

   No entanto, **timeout por chamada nao protege contra loops** onde
   o orquestrador re-invoca o helper indefinidamente para o mesmo
   `(wave_id, subagent_type)` apos cada falha transitoria. O
   `idempotent-check` (passo 3) mitiga o caso normal (Decisao ja
   existe -> skip), mas se o `register` (passo 5) falhar repetidamente
   antes de persistir, idempotent-check nunca encontra a Decisao e o
   loop pode reproduzir.

   **Regra (SHOULD)**: o orquestrador-de-projeto SHOULD limitar o
   numero de invocacoes do helper `model-routing.sh invoke` a **10
   por onda**. Esse cap NAO esta implementado no helper (F4.3.3
   deliberadamente documenta, nao executa) — a contagem fica a
   cargo do orquestrador via contagem de Decisoes com
   `contexto = "Selecao de modelo para subagente *"` na onda
   corrente. Pseudocodigo:

   ```bash
   # Antes do passo 4 (invoke), checar cap defensivo
   CAP_INVOKES=10
   INVOKES_NA_ONDA=$(jq -r --arg O "$ONDA_ID" '
     [.decisions[]
       | select(.context | startswith("Selecao de modelo para subagente "))
       | select(.wave_id == $O)] | length' "$SD/state.json")
   if [ "$INVOKES_NA_ONDA" -ge "$CAP_INVOKES" ]; then
     # Cap atingido: emitir BloqueioHumano em vez de invocar
     "$RUNTIME_SCRIPTS"/bloqueios.sh register --state-dir "$SD" \
       --pergunta "Cap de $CAP_INVOKES invocacoes model-routing atingido na onda $ONDA_ID. Loop infinito? Investigar e responder com 'retomar' ou 'abortar'." \
       --contexto-para-resposta "Decisoes de selecao na onda: $INVOKES_NA_ONDA / cap $CAP_INVOKES"
     exit 3
   fi
   ```

   **Por que SHOULD e nao MUST**: cap implementado no helper criaria
   acoplamento entre helper e contagem de estado, violando INV-4
   (helper e read-only para state.json). Mantemos o helper puro
   (apenas invoca skill + emite JSON) e delegamos ao orquestrador
   a defesa contra loops — esse e o lugar arquitetural correto,
   ja que o orquestrador ja le state.json em outros passos
   (`idempotent-check`, contagem de Decisoes).

   **Por que 10 e nao N (configuravel)**: numero magico
   deliberado. Justificativa empirica: em execucoes normais, uma
   onda spawna no maximo 2 subagentes em clarify (asker + answerer)
   + retries idempotentes. 10 da margem 5x para retomadas legitimas
   (`/agente-00c-resume` chamado multiplas vezes) sem precisar
   bumping. Se experiencia real mostrar que 10 e baixo demais,
   F-003 reabre como medium e cap vira flag (ex: `--max-invokes`).

<!-- FRAGMENT:stage-commit-hook:BEGIN -->
9.ter. **Hook de commit atomico por etapa (opt-in — atomic-commit-pr,
    FR-003)**: SOMENTE se `commit-mode.sh is-enabled --state-dir <SD>`
    retornar `true`. Roda APOS passo 9.bis (ingestao) e ANTES do passo
    10 (commit local do state). NAO-OP quando `is-enabled` retorna `false`
    (SC-006 — zero latencia no path de opt-out; comportamento atual
    preservado). Aplicavel apenas em etapas de artefato:
    `specify`, `plan`, `clarify`, `checklist`, `create-tasks`.
    NAO aplicar em `briefing`, `constitution`, `execute-task`,
    `review-task`, `review-features` (sem artefato spec-driven).

    ```bash
    _enabled=$(commit-mode.sh is-enabled --state-dir <SD>)
    if [ "$_enabled" = "true" ]; then
      # 1. Checar branch — skip silencioso se default (exit 3) ou erro (exit 1)
      commit-mode.sh guard-branch --state-dir <SD> --projeto-alvo-path <PAP>
      _guard_exit=$?
      if [ "$_guard_exit" = "0" ]; then
        # 2. Gerar mensagem Conventional Commits para a etapa atual
        _stage=$(state-rw.sh get --state-dir <SD> --field '.current_stage')
        _name=$(state-rw.sh get --state-dir <SD> --field \
                '.execution.target_project_description // "unnamed"' | \
                head -c 40 | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
        _msg=$(commit-mode.sh stage-message --feature "$_name" --stage "$_stage")
        # 3. Staging por allowlist derivada (FR-014) — NUNCA `git add -A`.
        #    --scope-dir confina aos artefatos desta etapa: o feature-dir
        #    corrente <FD> (docs/specs/<feature>, ver detect-completion
        #    --feature-dir) + o proprio state dir do agente-00c.
        commit-mode.sh stage-derived --state-dir <SD> --projeto-alvo-path <PAP> \
          --scope-dir "<FD>" --scope-dir ".claude/agente-00c-state"
        _stage_rc=$?
        if [ "$_stage_rc" = 0 ]; then
          # 4. Commit direto via git (pipeline non-interactive — CHK047/dec-026)
          git -C <PAP> commit -m "$_msg" 2>/dev/null || true
          # 5. Registrar Decisao auditavel do commit
          state-decisions.sh register --state-dir <SD> \
            --agente "orquestrador-00c" --etapa "$_stage" \
            --contexto "Commit atomico por etapa ($stage): $msg" \
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
<!-- FRAGMENT:stage-commit-hook:END -->

<!-- ORCH-REF-END -->
