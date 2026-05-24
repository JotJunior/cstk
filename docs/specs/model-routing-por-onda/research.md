# Research — model-routing-por-onda (Phase 0)

Decisões técnicas que resolvem os unknowns antes do design. Todas aterradas
empiricamente na sessão de bugfix/validação que originou a feature.

## Decision 1 — Onde mora o mapa fase→modelo (FR-014)

**Decision**: novo arquivo de dados versionado
`global/skills/agente-00c-runtime/references/phase-model-map.txt`, formato tabela
simples `fase|faixa|modelo` (uma linha por fase do pipeline), lido por um novo
subcomando POSIX-puro do helper de routing. Espelha o precedente do catálogo
`references/sinais.md` do model-selector.

**Rationale**: dado versionado e auditável, editável sem tocar código, alinhado
ao Princípio II (POSIX, sem jq para o lookup — é match de string simples). O mapa
é global do toolkit (não por-projeto), logo vive junto do runtime.

**Alternatives considered**:
- Hardcode no `model-routing.sh`: rejeitado — menos visível/editável, mistura
  política com mecanismo.
- `config.json` por projeto: rejeitado — overkill; o recorte "3 faixas" é uma
  política global do toolkit, não varia por projeto.

## Decision 2 — Onde computar a seleção por onda (command/resume vs orquestrador)

**Decision**: a seleção acontece no **command/resume (top-level)**, ANTES do
spawn do orquestrador, via novo subcomando `model-routing.sh wave-select`. O
top-level é quem tem a tool Agent disponível e executa o spawn; o orquestrador é
subagente e não re-spawna a si mesmo.

**Rationale**: a fronteira de onda = o ponto de spawn top-level (validado: cada
onda é nova invocação do orquestrador via resume). É o único lugar onde o param
`model` do spawn pode ser definido.

**Alternatives considered**:
- Dentro do orquestrador: rejeitado — não pode aplicar modelo a si próprio
  (modelo fixado no spawn; agente não troca mid-run).

## Decision 3 — Como o resume lê o override do operador (FR-016)

**Decision**: o operador registra uma **Decisão manual de override** com marcação
convencionada (campo `escolha = "model-override:<haiku|sonnet|opus>"`, etapa
`model-routing`, contexto começando com `Override de modelo para onda <N>`). O
`wave-select` procura uma Decisão de override **não-consumida** para a próxima
onda; se existir, ela tem **precedência** sobre o mapa e o refino, e é marcada
como consumida na Decisão de roteamento resultante (origem = `override-operador`).

**Rationale**: reusa o mecanismo auditável de Decisões já existente, mantém
suggest-only, sem ampliar superfície de CLI. Consistente com a escolha do operador
na clarificação.

**Alternatives considered**:
- Flag `--model` na command/resume: rejeitado como mecanismo primário — exigiria
  registrar a Decisão de override de qualquer forma para auditoria (FR-007). Pode
  virar açúcar opcional numa iteração futura, fora de escopo.
- Campo em config local: rejeitado — bom para política fixa, ruim para override
  pontual de uma onda.

## Decision 4 — Como passar `model` ao spawn a partir de um command markdown

**Decision**: o command instrui o top-level a (a) executar `wave-select` via Bash
capturando o modelo resolvido em stdout, (b) incluir `model: <chosen>` no bloco
`Agent(...)` do spawn do orquestrador. Quando o resultado é `manter-atual`, o
param `model` é **omitido** (herda o modelo da sessão).

**Rationale**: a tool Agent aceita `model` com precedência sobre frontmatter; o
command é quem spawna. Omitir em `manter-atual` preserva degradação graciosa.

**Alternatives considered**:
- Frontmatter `model:` no agent do orquestrador: rejeitado para seleção dinâmica
  (frontmatter é estático; não muda por onda). Continua válido como piso estático
  para os subagentes clarify (já aplicado fora desta feature).

## Decision 5 — Como alimentar contexto ao model-selector para o refino (FR-001)

**Decision**: `wave-select` passa `--input-text` ao `model-routing.sh invoke` com
a **descrição da tarefa corrente da onda** (quando a fase é `execute-task`: o
título/descrição da tarefa do `tasks.md`/state), NÃO o nome da fase. O refino só
atua quando há texto de tarefa com sinais reconhecíveis; nas demais fases o mapa
(D1) decide sozinho.

**Rationale**: validado empiricamente que o catálogo é de **verbos de tarefa** —
alimentar nome de fase ("execute-task") retorna sempre `indeterminado`. Alimentar
a descrição da tarefa é o único input com chance de casar sinais.

**Alternatives considered**:
- Alimentar nome de fase: rejeitado — sempre indeterminado (medido).
- Não usar model-selector: rejeitado — perde a granularidade por-tarefa em
  execute-task, que é onde a complexidade real varia.

## Decision 6 — Expansão do catálogo (FR-018) e teste (SC-008)

**Decision**: expandir `references/sinais.md` com termos de fase/complexidade e
formas flexionadas comuns (ex.: projetar/projete/projeto, refatorar/refatore,
analisar/analise, migrar/migracao), mantendo o formato de tabela e o match por
token exato (motor inalterado). Criar corpus de teste rotulado em
`tests/fixtures/` e medir taxa de `indeterminado` ≤ 25% (SC-008).

**Achado de implementação**: o `classify.sh` em runtime **não** hardcoda a
contagem de linhas (só valida existência/legibilidade do arquivo) — expandir é
seguro no motor. PORÉM o snippet de validação documentado em `sinais.md` ("Esperado:
16") e qualquer teste que asserte 15/16 linhas (`test_model_selector_*`) DEVEM ser
atualizados junto com a expansão.

**Rationale**: aumenta recall sem alterar o motor de match (preserva Princípio II
e simplicidade). Corpus de teste torna SC-008 verificável.

**Alternatives considered**:
- Stemming/fuzzy match: rejeitado — adiciona complexidade ao motor POSIX, fora do
  espírito MVP; ganho marginal sobre flexões explícitas.
</content>
