# Requirements Checklist: panel-monorepo

**Purpose**: Validar a qualidade dos requisitos desta migração — com foco
deliberado em **falseabilidade dos critérios de aceite**, não em completude
textual. Esta feature não entrega código de produto; entrega uma migração de
repositório/release, cujo risco central já se manifestou nesta própria
execução como "a verificação passa verde sobre a coisa errada" (contagem de
arquivos que passaria verde sem o fix do `.gitignore`; seleção posicional de
asset que confere checksum do pacote errado e sai `verified`; um achado
inventado aprovado por um gate e só pego em double-check manual; um campo
vindo da API sem validação de forma enquanto o equivalente local era
validado). Os itens abaixo perguntam, para cada requisito de maior risco,
"este critério reprovaria se a implementação estivesse errada?" — não "este
critério está escrito?".
**Created**: 2026-08-28
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) |
[quickstart.md](../quickstart.md) | [contracts/serve-asset-selection.md](../contracts/serve-asset-selection.md)

## Falseabilidade dos critérios de aceite de maior risco

- [x] CHK001 - O critério de FR-008 (seleção name-bound do pacote do painel)
  é exercitado por um cenário cuja ordem dos dois pacotes candidatos é
  deliberadamente invertida para forçar reprovação se a lógica ainda fosse
  posicional, em vez de apenas confirmar o caminho feliz? [Mensurabilidade,
  Spec §FR-008] {auto} — Satisfeito: `quickstart.md` Cenário 2 lista o par
  do toolkit **antes** do par do painel e anota explicitamente "com o
  painel primeiro, o código antigo também passaria, e o teste não provaria
  nada" (linhas 53-62).

- [x] CHK002 - O critério de FR-009 (checksum confere mas o payload não é o
  painel = falha) especifica uma saída auditável e distinguível de "sucesso
  silencioso", em vez de apenas "exit != 0"? [Mensurabilidade, Spec §FR-009]
  {auto} — Satisfeito: `quickstart.md` Cenário 4 exige uma linha em
  `enforcement-log.jsonl` com `outcome":"wrong-payload-blocked"` e
  `expected_sha256`/`actual_sha256` iguais e não-nulos (linhas 79-93),
  distinguindo isso do estado atual em que "o mesmo input falha
  silenciosamente do ponto de vista da auditoria".

- [x] CHK003 - O critério de FR-014 (suíte de seleção de pacote sem
  regressão) usa um baseline numérico medido empiricamente no código atual,
  em vez de um número herdado de um documento de entrada não verificado?
  [Mensurabilidade, Spec §FR-014] {auto} — Satisfeito: `quickstart.md`
  Cenário 7 fixa **74** (`test_serve.sh`) e **53**
  (`test_serve-docker.sh`), medidos no commit `90c0417` (dec-025), e anota
  explicitamente que o plano-insumo citava 55 — "a diferença esconderia 19
  cenários numa regressão" (linhas 134-149). Um critério que só dissesse "a
  suíte passa" não capturaria essa regressão, porque a suíte já passa hoje
  com o defeito de seleção presente.

- [x] CHK004 - O critério de FR-022 (aviso de transição na UI) distingue
  "o código do aviso existe" de "o aviso de fato renderiza e permanece
  visível", inclusive sem rede? [Mensurabilidade, Spec §FR-022] {auto} —
  Satisfeito: `quickstart.md` Cenário 12 exige abrir a UI e ver o aviso
  (passo 2-3), depois desconectar a rede e recarregar, confirmando que ele
  "continua visível — é estático, não depende de fetch" (passos 4-5).

- [ ] CHK005 - O invariante I5 do contrato (`bare(tag_name)` da API MUST
  casar `^[0-9A-Za-z][0-9A-Za-z.+-]*$` antes de qualquer derivação,
  fail-closed com linha em stderr) tem um Functional Requirement
  correspondente em `spec.md` e um cenário em `quickstart.md` que force um
  `tag_name` malformado e confirme o fail-closed — em vez de existir apenas
  como texto no contrato? [Completude, Rastreabilidade;
  `contracts/serve-asset-selection.md` §3.2 I5, linhas 86-94] {auto} —
  **[Gap]**: não encontrado. `spec.md` não tem FR nem Acceptance
  Scenario/Edge Case citando validação de forma de `tag_name`.
  `quickstart.md` Cenário 13 testa `CSTK_PANEL_REPO` (variável de ambiente
  local, já validada por regex) — não testa `tag_name` vindo da resposta da
  API, que é precisamente o campo que I5 endurece. O próprio contrato
  registra a motivação ("enquanto `CSTK_PANEL_REPO`, que vem de env, é
  validado em §7" — o dado remoto ficava sem validação de forma equivalente
  ao dado local; achado do gate `owasp-security` reconfirmado, dec-034). Sem
  um cenário que injete um `tag_name` fora do formato, nada reprovaria se
  I5 fosse removida ou nunca implementada. Destino: `/create-tasks` — task
  "adicionar FR de validação de forma de `tag_name`
  (`^[0-9A-Za-z][0-9A-Za-z.+-]*$`) em spec.md, e um cenário de erro em
  quickstart.md com `tag_name` malformado forçando fail-closed".

## Rastreabilidade FR ↔ cenário executável

- [ ] CHK006 - Cada Functional Requirement de `spec.md` tem pelo menos um
  cenário em `quickstart.md` que o cite explicitamente na linha `**Cobre**`
  (não apenas uma menção de passagem em `plan.md`)? [Completude,
  Rastreabilidade; spec.md FR-001..FR-022, quickstart.md] {auto} —
  **[Gap]** parcial: dos 22 FRs, **FR-002, FR-004, FR-005 e FR-006** nunca
  aparecem em nenhuma linha `**Cobre**` de `quickstart.md` (varredura
  `grep -oE 'FR-[0-9]{3}'` confirma ausência total dos quatro IDs no
  arquivo). FR-002 (subdiretório autocontido) e FR-005 (desativação da
  automação independente) têm cobertura indireta plausível via Cenário 7
  (`npm test` autocontido) e o passo 9 da ordem de execução do plano,
  respectivamente — mas sem `Cobre:` explícito. **FR-004** (resolução de
  colisão de nomes de topo entre os dois projetos — README, CHANGELOG,
  CONTRIBUTING, CI) e **FR-006** (histórico do painel congelado vs.
  histórico único contínuo) não têm nenhum Acceptance Scenario, Edge Case
  ou cenário de quickstart com Given/When/Then verificável; aparecem só
  como item de lista na ordem de execução do plano (`plan.md` linha 210,
  222) ou no próprio texto da FR. O gate determinístico
  `requirement-coverage.sh` reportou `covered=22/errors=0` para este
  spec.md — mas esse gate mede correspondência heurística de palavras-chave
  contra Acceptance Scenarios/Edge Cases do próprio `spec.md`, não a
  presença de um cenário executável em `quickstart.md`; "coberto" pela
  heurística não é o mesmo que "falseável". Destino: `/create-tasks` —
  task "adicionar Acceptance Scenario (FR-004) cobrindo colisão de nome de
  topo entre root e `panel/`, com Given/When/Then verificável" e task
  "adicionar cenário de quickstart citando FR-006 explicitamente (histórico
  congelado do CHANGELOG do painel vs. histórico único do monorepo a partir
  da migração)".

- [x] CHK007 - O cenário que, segundo o próprio `plan.md`, é a **única prova
  empírica** que libera os passos 8-9 da ordem de execução (release-ponte e
  arquivamento, FR-019) cita FR-019 na sua rastreabilidade formal
  (`**Cobre**`), e não apenas em metadado secundário? [Rastreabilidade;
  `plan.md` linhas 225-226, `quickstart.md` Cenário 1] {auto} — **[Gap]**:
  não. `quickstart.md` Cenário 1 lista `**Cobre**: FR-008, FR-010, FR-011,
  FR-014, SC-001` (linha 15) — FR-018 e FR-019 não aparecem aí. FR-019
  aparece apenas entre parênteses na linha `**Tipo**: manual, uma vez,
  antes de qualquer arquivamento (FR-019)` (linha 16), um campo de metadado
  que não existe nos outros 15 cenários com esse propósito de
  rastreabilidade. Dado que `plan.md` (linhas 225-226) afirma "o passo 5 é
  o único ponto do plano que **prova** a correção no caminho real; os
  passos 8 e 9 são bloqueados por ele" — a dependência mais crítica do
  plano de execução fica sub-rastreada no artefato que a exercita.
  Destino: `/create-tasks` — task editorial "mover/adicionar FR-018,
  FR-019 à linha `Cobre` do Cenário 1 de quickstart.md".

- [x] CHK008 - Os dois achados `high` aceitos do gate `owasp-security`
  (issues #177/#178) estão registrados por escrito no `plan.md` — não
  apenas no bloqueio humano que os aceitou — incluindo o raio de dano
  específico introduzido por esta migração? [Rastreabilidade, Consistência;
  `plan.md` §"Achados residuais aceitos" linhas 241-279, block-002/dec-029]
  {auto} — Satisfeito: seção dedicada com tabela (achado, onde, issue),
  parágrafo explícito do raio de dano ("Hoje, um comprometimento da release
  do `cstk-panel` atinge o painel e não o toolkit... Depois da fusão, uma
  release publica os dois pares de assets, e um comprometimento dessa
  release atinge ambos"), e uma distinção adicional registrada por escrito
  sobre R2 funcionar "por coincidência de configuração do GitHub" e não por
  verificação de código (linhas 268-274) — evidência de que o raio de dano
  foi pensado além do mínimo exigido pelo bloqueio.

- [x] CHK009 - O escopo do aceite de R1/R2 delimita explicitamente que
  nenhuma tarefa futura pode declará-los resolvidos nem ampliar a exposição
  além do raio descrito, prevenindo que `/create-tasks` os reabra ou os
  feche por engano? [Clareza; `plan.md` linhas 276-279] {auto} —
  Satisfeito: "Nenhuma tarefa deste plano pode citar R1 ou R2 como
  resolvidos, e nenhuma pode ampliar a exposição a eles além do raio
  descrito acima. O fechamento de R1 e R2 é trabalho próprio, rastreado nas
  issues #177 e #178."

## Consistência entre spec / plan / quickstart / contrato

- [x] CHK010 - A ordem de execução do plano declara explicitamente uma
  etapa bloqueante (não apenas recomendação de ordem) para a correção de
  `serve.sh` preceder a primeira release com os dois pares de assets?
  [Dependências, Clareza; `plan.md` linhas 200-203] {auto} — Satisfeito:
  "`serve.sh` corrigido MUST preceder a primeira release que publique os
  dois pares. Publicar primeiro exporia toda instalação atualizada ao
  defeito de seleção posicional."

- [ ] CHK011 - Todo Functional Requirement de `spec.md` está mapeado a
  pelo menos um passo da ordem de execução de 9 passos do `plan.md`, OU há
  nota explícita de que o requisito não exige passo de implementação
  (é satisfeito por estrutura/tooling pré-existente, apenas verificado)?
  [Completude, Consistência; `plan.md` linhas 209-223] {auto} — **[Gap]**:
  FR-007 (governança dupla sem falso conflito) não aparece em nenhum dos 9
  passos da ordem de execução, nem há nota dizendo que ele não exige
  implementação. FR-007 provavelmente não exige código novo — a detecção
  de conflito de governança já existente deveria naturalmente reconhecer
  `panel/` como raiz de projeto assim que ele tiver `docs/constitution.md`
  próprio (efeito colateral do passo 1) — mas isso fica implícito, inferido
  pelo leitor, e verificado só pelo Cenário 8 de quickstart, nunca afirmado
  por escrito no plano. Destino: `/create-tasks` — ajuste editorial em
  `plan.md`: anotar FR-007 como "sem passo de implementação — consequência
  estrutural do passo 1, verificada pelo Cenário 8" (mesmo padrão já usado
  para outras notas de escopo do plano).

- [x] CHK012 - FR-013 (validação de host confiável para a origem de
  sobrescrita) tem critério que aponta o mecanismo concreto de validação
  (mesma allowlist constante), em vez de apenas afirmar "mesma validação já
  aplicada" sem indicar onde? [Clareza; spec.md FR-013; quickstart.md
  Cenário 13, `contracts/serve-asset-selection.md` §7] {auto} — Satisfeito:
  Cenário 13 exercita 3 casos (fork válido com aviso e log,
  `../../etc` rejeitado fail-closed sem cair no default, e um valor com
  barra construído para tentar escapar do formato `owner/repo` mas cujo
  host final continua fixo em `api.github.com`), com referência direta ao
  contrato §7.

## Riscos de segurança aceitos e integridade do processo de design

- [x] CHK013 - Nenhum Functional Requirement novo desta rodada reabre ou
  amplia os dois achados `high` já aceitos (R1: ausência de proveniência/
  attestation; R2: allowlist revalidada apenas pré-redirect)? [Consistência;
  spec.md FR-001..FR-022] {auto} — Satisfeito: nenhuma FR trata de
  assinatura, attestation ou revalidação pós-redirect; a única mudança
  relacionada a integridade nesta rodada é FR-009 (payload vs. checksum),
  que é ortogonal a R1/R2.

- [x] CHK014 - O achado `low` novo introduzido pela própria reconfirmação
  do gate `owasp-security` sobre o desenho corrigido (`bare(tag_name)` sem
  validação de forma) foi endurecido no contrato como invariante rastreável
  (não apenas mencionado em prosa de decisão)? [Rastreabilidade; dec-034,
  `contracts/serve-asset-selection.md` §3.2 I5] {auto} — Satisfeito quanto
  ao contrato (I5 existe, com justificativa e regex explícitos) — mas ver
  CHK005: o endurecimento no contrato não se propagou a um FR verificável
  nem a um cenário de teste. Este item confirma que o achado foi
  **documentado**; CHK005 cobre que ele não está **testável**.

## Dependências, premissas e critérios de sucesso mensuráveis

- [x] CHK015 - SC-001 (100% dos cenários com os dois pacotes candidatos
  resultam no pacote do painel) é mensurável por um número fechado de
  cenários, e não por uma amostra não-enumerada? [Mensurabilidade;
  spec.md SC-001] {auto} — Satisfeito: SC-001 mapeia diretamente aos
  cenários automatizados de FR-014 (Cenário 2 de quickstart + o novo modo
  `both-pairs` em `test_serve.sh`), que são um conjunto fechado e
  contável.

- [x] CHK016 - SC-006 (100% das instalações que atualizam contra o
  repositório original recebem aviso visível) é verificável sem depender
  de telemetria remota, coerente com o Princípio IV (zero coleta remota)?
  [Consistência, Requisitos Não-Funcionais; spec.md SC-006, plan.md
  Constitution Check Princípio IV] {auto} — Satisfeito: `plan.md` resolve
  isso explicitamente como "banner estático embutido no bundle — sem
  feature-flag remoto, sem fetch à API de releases, funcional offline"
  (linha referente ao Princípio IV), e Cenário 12 confirma a propriedade
  offline.

- [x] CHK017 - FR-019 define a ordem exata (a antes de b) entre a
  publicação da release de transição e a verificação da distribuição
  embutida, evitando uma janela em que nenhuma instalação tem caminho de
  atualização funcional? [Clareza, Cobertura de Edge Case; spec.md FR-019,
  Edge Cases linhas 235-238] {auto} — Satisfeito: FR-019 explicita "(a) ...
  publicada; e (b) ... verificada" como pré-condições conjuntas antes de
  desativar/arquivar, e o Edge Case correspondente ("o que acontece se o
  repositório original for arquivado antes...") remete de volta à mesma
  ordem.

- [ ] CHK018 - Fica definido, em algum artefato, **quem ou o quê** atesta
  que a "correta seleção/integridade" exigida pela FR-019(b) foi de fato
  verificada antes do passo 9 (arquivamento) — um humano seguindo o
  Cenário 1 do quickstart, ou algum gate automatizado? [Ambiguity; spec.md
  FR-019, quickstart.md Cenário 1] {humano} — Não encontrado um dono
  explícito desse atesto. `quickstart.md` Cenário 1 declara `**Tipo**:
  manual, uma vez`, o que sugere um humano executando o roteiro antes do
  passo 8/9 — mas nenhum artefato afirma isso como responsabilidade
  formal (quem roda, quando, e onde o resultado fica registrado como
  "verificado" para efeito de liberar o passo 9). Como isso é uma decisão
  de processo de release (quem assina o gate humano antes de arquivar um
  repositório), e não uma lacuna de texto que eu possa resolver citando
  evidência, fica para o dono do produto decidir se formaliza esse passo
  (ex.: registrar como tarefa manual explícita em `create-tasks`, com dono
  nomeado) antes de o plano avançar ao passo 8.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]` com evidência do que falta).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto.
- **Gaps que viram ação** (destino explícito por item, não ficam apenas
  marcados aqui):
  - CHK005 (I5 sem FR/cenário) → `/create-tasks`: nova FR + cenário de
    erro para `tag_name` malformado.
  - CHK006 (FR-004, FR-006 sem cenário executável) → `/create-tasks`: dois
    Acceptance Scenarios/cenários novos.
  - CHK007 (Cenário 1 não cita FR-018/FR-019 em `Cobre`) → `/create-tasks`:
    ajuste editorial de rastreabilidade.
  - CHK011 (FR-007 sem passo no plano) → `/create-tasks`: nota editorial em
    `plan.md`.
  - CHK018 (dono do atesto de verificação pré-passo-9) → decisão do
    operador antes de avançar ao passo 8 da ordem de execução.
- Nenhum item deste checklist reabre os achados `high` aceitos R1/R2
  (issues #177/#178) — CHK013/CHK014 confirmam que o aceite está intacto e
  documentado; o fechamento deles permanece fora do escopo desta feature.
- Resolução: **13** `{auto}` satisfeitos (`[x]`), **4** `[Gap]` abertos
  (CHK005, CHK006, CHK007, CHK011), **1** `{humano}` aguardando decisão do
  dono do produto (CHK018).
