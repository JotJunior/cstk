# Quickstart: Decisoes estruturais exigem gate humano

Cenarios que validam a implementacao end-to-end. Cada cenario e executavel e
mapeia a um Independent Test / Acceptance Scenario da spec.

Convencao: `SD` = state-dir da execucao de teste;
`RS` = `plugins/cstk/skills/agente-00c-runtime/scripts`.

## Scenario 1: Decisao estrutural com escolha autonoma e recusada (US1, FR-003)

1. Criar state-dir de teste e inicializar estado (`state-rw.sh init`).
2. Tentar registrar decisao de linguagem/runtime decidindo sozinho, com o
   score maximo e evidencia empirica real:
   ```sh
   "$RS"/state-decisions.sh register --state-dir "$SD" \
     --agente "agente-00c-feature-orchestrator" --etapa "plan" \
     --classe estrutural --eixo linguagem-runtime \
     --contexto "Escolha do runtime do motor de extracao do projeto-alvo" \
     --opcoes '["reusar-motor-python","reescrever-em-node","bloqueio-humano"]' \
     --escolha "reusar-motor-python" --score 3 \
     --evidencia "python3 -V => Python 3.14.0; motor legado roda sem alteracao" \
     --justificativa "Reuso elimina reescrita completa do motor de extracao"
   ```
3. **Expected**: exit `1`; stderr cita a classe (`estrutural`), o eixo
   (`linguagem-runtime`) e a sequencia correta (registrar com escolha de
   bloqueio humano + `score 0`, depois `bloqueios.sh register`).
   `state-decisions.sh count --state-dir "$SD"` permanece **inalterado** — nada
   foi gravado (INV-C3). Score 3 com evidencia real **nao** compra a decisao.
4. Repetir a chamada identica trocando apenas `--agente` para `"operador"`.
5. **Expected (INV-C5, emenda dec-024)**: exit `1` e a **mesma** mensagem. O
   campo de agente nao tem poder sobre a trava — declarar-se humano nao e
   consentir.
6. Repetir com `--consentimento block-999` (id inexistente).
7. **Expected**: exit `1`, mensagem `consentimento-invalido` citando o id e o
   status encontrado; nada gravado. A trava so cede diante de um bloqueio que de
   fato exista nesta execucao e esteja `respondido`.

## Scenario 2: Caminho correto grava e abre bloqueio (US1, Acceptance 2)

1. Repetir o registro com `--escolha bloqueio-humano --score 0` (sem
   `--evidencia`), mantendo `--classe estrutural --eixo linguagem-runtime`.
2. Registrar o bloqueio: `"$RS"/bloqueios.sh register --state-dir "$SD"
   --decisao-id dec-NNN --pergunta ... --contexto-para-resposta ...`.
3. Encerrar a onda com `state-ondas.sh end --motivo-termino bloqueio_humano`.
4. **Expected**: `dec-NNN` em stdout, exit 0; `bloqueios.sh count --pending-only`
   retorna 1; a onda encerra em `bloqueio_humano`; o relatorio identifica a
   Decisao como estrutural, mostra o eixo e **nao** a marca como anomalia.
5. Responder: `"$RS"/bloqueios.sh respond --state-dir "$SD" --block-id block-NNN
   --resposta "..."`; em seguida registrar a Decisao de conclusao com
   `--classe estrutural --eixo linguagem-runtime --escolha <opcao concreta>
   --score 2 --consentimento block-NNN`.
6. **Expected**: exit 0, gravado; o relatorio mostra `Consentimento: block-NNN` e
   **nao** marca anomalia, ainda que `--agente` seja o proprio orquestrador.
   Pre-condicao: o bloqueio foi registrado com
   `--chave-assunto axis:linguagem-runtime`.
7. Registrar outra Decisao estrutural, agora com `--eixo persistencia`, citando
   o **mesmo** `--consentimento block-NNN`.
8. **Expected (dec-030)**: exit `1`, mensagem `consentimento-de-outro-assunto`
   citando `axis:linguagem-runtime` vs `axis:persistencia`; nada gravado.
   Consentimento nao e cheque em branco.

## Scenario 3: Classe obrigatoria quando ha token de bloqueio (US1, Acceptance 5)

1. Registrar decisao com `bloqueio-humano` entre `--opcoes` e **sem** `--classe`.
2. **Expected**: exit `1`, mensagem `classe-obrigatoria`, nada gravado.
3. Repetir a mesma chamada pela tool MCP `record_decision` omitindo
   `decision_class`.
4. **Expected**: `outcome = "rejected"` com
   `reason` iniciando por `STRUCTURAL_CLASS_REQUIRED` (paridade FR-004).

## Scenario 4: Regressao zero em decisao operacional (US1, Acceptance 4 / FR-005)

1. Registrar decisao comum (`--classe operacional`, ou **sem** `--classe`), com
   `--score 2`, sem token de bloqueio nas opcoes.
2. **Expected**: exit 0, `dec-NNN` gravado, nenhuma pausa, nenhum bloqueio novo.
   A suite existente `tests/test_state-decisions.sh` (44 funcoes `scenario_*`) passa sem
   alteracao de expectativa — nenhum cenario atual muda de resultado.

## Scenario 5: Item Alto do briefing vira bloqueio, nao pesquisa (US2, FR-007/FR-008)

1. Montar briefing de teste com a tabela `## Itens a Definir` contendo uma linha
   de impacto `Alto` (ex.: item de linguagem do motor) e outras `Medio`/`Baixo`.
2. `"$RS"/briefing-items.sh list-high --briefing <path>`.
3. **Expected**: exatamente 1 linha de item em stdout
   (`item_key<TAB>item<TAB>dimensao`) seguida de `STATUS<TAB>ok`, exit 0.
4. Iniciar a etapa `plan` em modo autonomo com esse briefing.
5. **Expected**: um bloqueio humano por item Alto pendente, onda encerrada em
   `bloqueio_humano`, e **`plan.md` inexistente** — a skill `plan` nao chega a
   ser invocada (Independent Test da US2).
6. **Expected (dedup)**: o bloqueio registrado carrega
   `subject_key = briefing-item:<item_key>`.
7. Responder ao bloqueio e retomar.
8. **Expected**: a etapa prossegue e o item **nao** e re-perguntado —
   `bloqueios.sh list --status respondido --chave-assunto briefing-item:<key>`
   retorna a linha, e e esse retorno (nao um julgamento sobre o texto) que
   suprime a pergunta.
9. Reescrever o texto do item no briefing e retomar de novo.
10. **Expected**: o item **e** re-perguntado — chave nova, assunto novo
    (comportamento deliberado, spec Edge Cases).

## Scenario 6: Parser tolerante nao falha a onda (US2, Edge Cases)

1. `list-high` contra `docs/01-briefing-discovery/briefing.md` deste repo, cujas
   celulas de impacto trazem prosa anexada (`Medio (ambicao ...)`,
   `Baixo hoje, sobe conforme ...`).
2. **Expected**: nenhuma linha de item, `STATUS<TAB>sem-itens-alto`, exit 0,
   nenhum aviso de erro de parse — os tokens `Medio`/`Baixo` sao reconhecidos
   apesar da prosa.
3. `list-high` contra um briefing com a heading `## Itens a Definir` mas em
   **lista numerada, sem tabela** (existe no repo em
   `docs/specs/_archived/github-pages-cstk-manual/briefing.md`).
4. **Expected**: `STATUS<TAB>tabela-irreconhecivel`, aviso em stderr, exit `0` —
   jamais exit != 0.
5. `list-high` contra path inexistente.
6. **Expected**: `STATUS<TAB>briefing-ausente`, aviso em stderr, exit `0`.
7. **Expected (finding M2)**: os quatro casos sao **distinguiveis entre si** pelo
   token de STATUS. Especificamente, o passo 6 (sem briefing) nunca produz a
   mesma saida do passo 2 (briefing lido, zero itens Alto).
8. `list-high` contra briefing cuja celula `Item` contenha TAB e CR.
9. **Expected (finding L1)**: a linha de saida continua com exatamente 3 campos;
   nenhum conteudo do briefing acrescenta coluna.

## Scenario 7: Ambiente alvo ausente reprova o plano (US3, FR-010 / SC-003)

1. `plan.md` de teste cujo Technical Context traz a linha do template intacta:
   `**Target Platform**: [ex: Kubernetes, Vercel, mobile ou NEEDS CLARIFICATION]`.
2. `validate-sdd.sh <plan.md> --sdd-plan`.
3. **Expected**: linha `FINDING|error|target-platform-unresolved|...` presente e
   exit `1`. (Hoje esse mesmo arquivo **passa** nesse campo, porque o regex de
   `residual-clarification` exige `[NEEDS CLARIFICATION` com colchete colado —
   este cenario e a prova da lacuna que a US3 fecha.)
4. Preencher o campo com valor concreto, sem citar fonte.
5. **Expected**: `FINDING|warning|target-platform-unsourced|...`, exit `0`
   (aviso nao reprova).
6. Preencher com valor concreto citando `briefing`, `constitution` ou `dec-NNN`.
7. **Expected**: nenhum dos dois findings; saida identica a atual nos demais
   checks.

## Scenario 8: Roundtrip End-to-End — helper, MCP, state.db e export

Cenario de borda **real**, sem mock e sem fixture: a feature atravessa POSIX sh,
SQLite, TypeScript/zod e o export JSON. E aqui que um drift de nome de campo
(`decision_class` vs `--classe`) apareceria.

1. Subir a sessao MCP de verdade contra o state-dir de teste
   (`cstk mcp start --state-dir "$SD"`) e chamar a tool `record_decision` com
   `decision_class: "estrutural"`, `structural_axis: "stack-frameworks"`,
   `choice: "bloqueio-humano"`, `justification_score: 0`.
2. **Expected**: `outcome = "accepted"`, `result.decision_id = dec-NNN`.
3. Ler de volta pelo export: `"$RS"/state-rw.sh read --state-dir "$SD"`.
4. Comparar o shape do objeto em `.decisions[]` contra `data-model.md`:
   - nomes de campo (`decision_class`, `structural_axis`,
     `human_consent_block_id` — snake_case, ingles);
   - valores literais do enum (`estrutural`, `stack-frameworks`);
   - ausencia de qualquer campo pt-BR duplicado.
4.bis Responder ao bloqueio e chamar `record_decision` de novo com
   `human_consent_block_id: "block-NNN"` e escolha concreta.
   **Expected**: `accepted`. Repetir com um id inexistente:
   `outcome = "rejected"`, `reason` iniciando por `HUMAN_CONSENT_INVALID`
   (paridade FR-004 — a mensagem nasce do helper, nao do zod).
5. Rodar o mesmo fluxo com backend `state.json` (sem `state.db`).
6. **Expected**: **zero divergencia** entre os dois backends, entre a flag do
   helper e o campo persistido, e entre o persistido e o contrato declarado. O
   relatorio (`report.sh emit`) exibe classe e eixo em ambos os backends.

## Scenario 9: Execucao ja em andamento continua operavel (FR-013, Decision 3)

1. Tomar um `state.db` criado **antes** desta feature (schema sem as colunas
   novas) — ex.: copia de um state-dir existente.
2. Registrar uma decisao **operacional** sem `--classe`.
3. **Expected**: exit 0, gravado normalmente; nenhum erro `no such column`.
4. Registrar uma decisao **estrutural** pelo caminho correto.
5. **Expected**: `state-db-schema.sh ensure` acrescenta as colunas de forma
   idempotente e a gravacao conclui; reexecutar `ensure` e no-op.
6. **Expected (finding M3)**: gerar relatorio contra o `state.db` **sem** as
   colunas novas nao emite nenhum `ALTER TABLE` — verificavel deixando o arquivo
   somente-leitura: a leitura conclui, a escrita e que falharia.
7. Gerar o relatorio de uma execucao antiga, com Decisoes **sem** classe.
8. **Expected**: relatorio legivel; Decisoes legadas aparecem como classe **nao
   declarada** — nunca reclassificadas como `operacional`, nunca marcadas como
   anomalia por mera ausencia (FR-013).

## Scenario 10: Anomalia de governanca e reportada, nao corrigida (US4, FR-012)

1. Estado de teste contendo uma Decisao estrutural com `choice` fora da familia
   de bloqueio e **sem** `human_consent_block_id` — simula estado legado ou
   bypass.
2. Gerar relatorio e rodar `review-task`.
3. **Expected**: a Decisao aparece marcada como **anomalia de governanca**, com o
   agente decisor visivel como informacao; `review-task` reporta as contagens
   (estruturais, anomalias). A Decisao **nao** e reescrita nem reaberta
   automaticamente (append-only, spec Edge Cases).
4. Repetir o passo 1 com a mesma Decisao, porem `agent = "operador"`.
5. **Expected (emenda dec-024)**: continua marcada como anomalia. O campo de
   agente **nao** absolve — era exatamente este o bypass que a versao anterior
   do predicado nao detectava.
6. Repetir com `human_consent_block_id` apontando um bloqueio ainda
   `aguardando`.
7. **Expected**: o registro sequer e aceito (R6, `consentimento-invalido`); logo
   este estado so e alcancavel por escrita direta no banco — limitacao L2
   declarada na spec.
8. Em execucao saudavel pos-feature, a contagem de anomalias e **0** (SC-002).
