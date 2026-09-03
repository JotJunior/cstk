# Research: Gate de Convergência Recusa Cobertura Zero de MUST

Documento produzido no Phase 0 do `/plan`. Resolve os unknowns técnicos antes
do design. Toda afirmação sobre comportamento de código abaixo foi medida
neste worktree (`/Users/jot/Projects/_lab/Jot/misc/cstk-converge-must-coverage-fail-closed`)
— nenhuma foi inferida de memória (Constitution VI).

## Decision 1: De onde vem o sinal determinístico de "cobertura zero"

**Decision**: `extract-must.sh --coverage` passa a emitir um **veredito de
vocabulário fechado** como 6ª linha de stdout, e a sinalizar o caso-alvo por
**exit code dedicado 3**:

```
cobertura de MUST: <ok|zero-reconhecida|sem-must-declarado>
```

| Condição (N = ocorrências independentes, M = linhas reconhecidas) | Veredito | Exit |
|---|---|---|
| `M > 0` | `ok` | 0 |
| `N > 0 && M == 0` | `zero-reconhecida` | **3** |
| `N == 0` | `sem-must-declarado` | 0 |
| `constitution.md` ausente | (nenhum veredito) | 1 (inalterado) |
| erro de uso | — | 2 (inalterado) |

**Rationale**: FR-001 exige achado **estruturado**, não observação textual. O
`ConvergenceReport` é redigido pelo agente, então a única forma de tornar o
achado determinístico (Constitution I/II: reprodutibilidade byte-a-byte) é o
agente ramificar sobre um sinal de máquina, não sobre a interpretação das 5
linhas de prosa do relatório atual. A condição `N > 0 && M == 0` **já existe**
no script — linha 221 de `extract-must.sh` (`if [ "$_em_words" -gt 0 ] && [
"$_em_lines" -eq 0 ]`), hoje usada só para um aviso em stderr. Esta feature
promove essa mesma condição a veredito + exit code, sem inventar um segundo
critério que pudesse divergir do primeiro.

Exit code como **sinal de estado** (não erro) tem precedente direto no próprio
diretório: `converge-status.sh check` usa `exit 3` para o veredito `never` —
**verificado no código e em execução**, não inferido de comentário:

- contrato declarado nas linhas **46-48** do script: `3 estado "nunca convergiu"
  (so em check/latest)`;
- implementado por 4 `return 3` em `_cs_status_for_dir` (linhas **266, 271,
  284, 300**);
- **medido**: `check --feature-dir <dir com tasks.md e sem converge-report.md>`
  imprime `never` e retorna `exit=3`.

Não é um padrão novo.

**Verificação de blast radius do exit 3**: `grep -rn 'extract-must'` fora de
`tests/` e de specs arquivadas não encontrou **nenhum caller programático** —
as únicas referências vivas são a prosa da própria `converge/SKILL.md` (linhas
116, 171, 177, 194, 460) e o `CHANGELOG.md`. Nenhum script do repo faz
`extract-must.sh ... && ...` ou roda sob `set -e`. Mudar o exit code do caminho
`--coverage` não quebra nenhum consumidor existente.

**Alternatives considered**:
- *Só prosa na SKILL.md* (agente lê as 5 linhas e decide): é essencialmente o
  estado atual (SKILL.md linhas 183-191) que a spec classifica como
  insuficiente ("não apenas como observação textual"). Rejeitada.
- *Só a linha de veredito, sem exit code*: funciona para o agente, mas deixa
  os testes e qualquer futuro caller sem sinal barato. Aditivo custa 3 linhas.
  Rejeitada por ser estritamente mais fraca.
- *Só o exit code, sem a linha*: perde legibilidade humana do relatório (a
  ETAPA 7 cita o `--coverage` verbatim) e torna a saída dependente de captura
  de `$?`. Rejeitada.
- *Novo script dedicado (`must-coverage-gate.sh`)*: duplicaria a gramática de
  contagem, que o próprio script já documenta como perigo ("duas copias
  driftariam e a metrica de cobertura mediria um parser diferente do que
  roda", linhas 174-175). Rejeitada.

## Decision 2: Onde o achado nasce — ETAPA 3 da SKILL.md, não um script novo

**Decision**: o achado é materializado pelo agente na **ETAPA 3** da
`converge/SKILL.md`, imediatamente após a segunda invocação de
`extract-must.sh`, como um `Gap` sintético que entra no mesmo fluxo das ETAPAS
5→6→7→8 dos demais achados. Nenhum script novo é criado.

**Rationale**: o `Gap` é uma entidade in-memory do agente (não há store
persistente de achados — só o `converge-report.md`, gravado por
`converge-status.sh record`). Injetar o achado sintético no mesmo pipeline
garante, de graça, as quatro propriedades que os FRs pedem: severidade via
`severity.sh` (FR-002), dedup via `gap-key` (idempotência), contagem em `N`
(FR-004) e linha na tabela do `ConvergenceReport` (FR-001).

**Alternatives considered**: gravar o achado direto em `converge-report.md` via
`converge-status.sh` — rejeitada: contornaria a ETAPA 6 (o achado não viraria
tarefa residual em `tasks.md`) e violaria o contrato "nunca edite
converge-report.md fora do converge-status.sh".

## Decision 3: Classificação e severidade do achado (FR-002)

**Decision**: `--type contradicts --priority P1 --must-violated false` → `HIGH`.
`severity.sh` **não é alterado**.

**Rationale**: medição literal neste worktree —

```
--type contradicts --priority P1 --must-violated false   -> HIGH
--type contradicts --priority P1 --must-violated true    -> CRITICAL
--type contradicts --priority none --must-violated false -> MEDIUM
--type contradicts --priority P2 --must-violated false   -> MEDIUM
```

`HIGH` é o único resultado alcançável dessa tabela para o achado, e é o que
FR-002 pede ("severidade mais alta reservada a esse tipo de achado quando
associado a uma prioridade alta" — `contradicts` com `must_violated=false` tem
teto `HIGH`; `CRITICAL` é privilégio da regra 1, reservada a violação de MUST).

- **`must_violated=false`** apesar de o achado ser *sobre* MUST: a violação é de
  **cobertura da verificação**, não de uma regra MUST concreta. Passar `true`
  afirmaria uma violação específica que o parser justamente **não conseguiu
  ler** — inventar o objeto da violação seria exatamente a fabricação que a
  Constitution VI proíbe. Coerente também com a §5.1 da SKILL.md, que já
  define `must_violated=false` quando a lista de princípios está indisponível.
- **`priority=P1`** é **intrínseca ao achado**, declarada por esta feature, não
  derivada de nenhuma story do backlog da feature em convergência — o que
  satisfaz FR-003 (que exige apenas que a **origem** seja a própria verificação
  de cobertura).

**Tensão a resolver explicitamente no texto**: a §5.2 da `converge/SKILL.md`
hoje diz que, sem associação a story, `story_priority = none` e "**nunca** escale
para HIGH por omissão". Essa regra existe para impedir *invenção* de prioridade
por ausência de dado. O achado desta feature não é omissão: o `P1` é **afirmado
por regra escrita**. Sem um carve-out explícito na §5.2 o texto ficaria
autocontraditório — e uma execução futura de `converge` classificaria a própria
SKILL.md como `contradicts`. Por isso o carve-out é entregável obrigatório
(ver `contracts/must-coverage-finding.md` §3).

**Alternatives considered**: `must_violated=true` → `CRITICAL` (rejeitada:
afirma violação inexistente + `CRITICAL` é mais forte que o pedido do
operador); `priority=none` → `MEDIUM` (rejeitada: contraria o pedido explícito
do operador por `contradicts` HIGH).

## Decision 4: Identidade do achado — path, origem e dedup (FR-003)

**Decision**:
- `path` = o path da constituição do projeto-alvo, tal como resolvido na ETAPA 1
  (`$CONSTITUTION`), citado literal.
- `origin` = o token literal fechado **`extract-must --coverage`**.

**Rationale**: FR-003 exige rastreabilidade "de onde o achado veio" e proíbe
citar uma task/FR pré-existente do backlog. Um token literal e estável satisfaz
os dois lados e, de quebra, torna a `gap-key` determinística: a chave é
`sha256-12(normalize(path) + " " + type + " " + normalize(origin))`
(`converge-tasks.sh gap-key`), então `(constitution.md, contradicts,
extract-must --coverage)` produz sempre a mesma chave — o achado é registrado
**uma única vez** por feature e execuções subsequentes o filtram via
`existing-keys` (FR-012 da feature-base `skill-converge` — `docs/specs/_archived/2026-07-28-skill-converge/spec.md`), sem duplicar a fase.

**Alternatives considered**: `origin = FR-001` desta feature (rejeitada:
`converge` roda contra a feature do projeto-alvo, cujo `spec.md` não tem
FR-001 com esse sentido — seria origem fabricada); `origin = "coverage"`
(rejeitada: ambíguo demais para leitura humana no relatório).

## Decision 5: Contagem em `N` e `outcome` (FR-004) — zero mudança de script

**Decision**: nenhuma alteração em `converge-status.sh`.

**Rationale**: a ETAPA 7 já define `N = contagem de achados
missing+partial+contradicts` e `OUTCOME=actionable` quando `N >= 1`; o próprio
`converge-status.sh record` **recusa** `--outcome clean` com `--actionable != 0`
(guarda na linha 362, mensagem literal `outcome=clean exige --actionable 0` na linha 363). Como o achado é
`contradicts`, ele entra em `N` por construção e torna `outcome=clean`
mecanicamente impossível — FR-004 e SC-001 satisfeitos sem código novo. Basta
a ETAPA 7 dizê-lo explicitamente para não depender de inferência do agente.

## Decision 6: Fronteira de não-falso-positivo (FR-005, FR-006, SC-002)

**Decision**: o achado dispara **se e somente se** o veredito for
`zero-reconhecida`. Os outros três estados (`ok`, `sem-must-declarado`,
constitution ausente/exit 1) nunca o produzem.

**Rationale**: mapeamento 1:1 com os requisitos, sem cláusula interpretável:
`sem-must-declarado` ⇒ FR-005 (nenhum MUST declarado, nada a cobrir); `ok` ⇒
FR-006 (cobertura parcial preserva o comportamento de hoje — a 3ª sugestão da
issue #173, deferida); exit 1 ⇒ Edge Case "constituição ausente", cujo
tratamento (`must_violated=false` para todos os Gaps, §5.1) fica intocado. Como
o veredito é calculado das mesmas duas variáveis já existentes (`_em_words`,
`_em_lines`), não há caminho em que veredito e aviso de stderr discordem.

## Decision 7: FR-007/FR-008 — formato rotulado na skill `constitution`

**Decision**: três edições em `plugins/cstk/skills/constitution/`:

1. **§3.2 Regras de Preenchimento** ganha a regra de formato: obrigação de
   princípio se escreve como **linha rotulada** (`**MUST:**` / `**SHOULD:**`
   abrindo bloco, ou bullet `- MUST: ...`), nunca como MUST em prosa corrida.
2. **Texto-semente de Veracidade de Dados** (§3.2) passa a conter uma linha
   `**MUST:**` — e migra de **blockquote (`> `) para bloco de código cercado**.
3. **`templates/constitution.md`** ganha o esqueleto rotulado sob cada
   `[PRINCIPLE_N_DESCRIPTION]`, para o formato ser herdado por construção.

**Rationale — o gotcha do blockquote (medido)**: o parser exige o rótulo no
início da linha (com bullet e/ou negrito opcionais). Medição literal da regex
vigente (`_EM_MUST_RE`, linha 176) contra 5 candidatos:

```
**MUST:**        -> RECONHECIDA
> **MUST:**      -> NAO reconhecida
- MUST:          -> RECONHECIDA
  **MUST:**      -> RECONHECIDA
> - MUST:        -> NAO reconhecida
```

O texto-semente vive hoje **dentro de um blockquote**:
`plugins/cstk/skills/constitution/SKILL.md` linhas **141-147**, todas
prefixadas por `> ` (verificado linha a linha). Um agente
que transcreva o bloco *verbatim* — o que a instrução "Texto-semente" convida a
fazer — carregaria o `> ` junto e produziria uma linha **não reconhecida**,
falhando SC-003 pelo motivo mais bobo possível. Bloco de código cercado remove
a armadilha na origem.

**Rationale — por que a mudança é suficiente para SC-003**: o princípio-semente
já entra no inventário pela via (a) do parser (heading termina em
`(NON-NEGOTIABLE)`), mas isso conta como *princípio emitido*, não como *linha
de regra reconhecida* — `M` continuaria 0. SC-003 pede `M >= 1`; só a linha
rotulada dentro do corpo entrega isso.

**Alternatives considered**: reescrever a seção `## EXEMPLOS DE PRINCIPIOS`
inteira (rejeitada: os exemplos são deliberadamente rótulos curtos de uma linha,
"ilustram formato — adaptar ao domínio", e não pretendem ser corpo de
princípio; mudá-los ampliaria o diff sem tocar em nenhum FR — um exemplo
adicional rotulado basta).

## Decision 8: A 3ª sugestão da issue #173 permanece fora de escopo — sem bloqueio humano

**Decision**: nenhum FR ou SC desta spec exige alterar a gramática do parser.
Nenhum bloqueio humano é aberto por este eixo.

**Rationale**: a verificação é textual e fechada. FR-006 **exige** preservar o
comportamento atual em cobertura parcial, e SC-002 **exige** zero achado quando
`M >= 1` — ambos apontam na direção oposta a alargar o parser. FR-001..FR-005
tratam exclusivamente do caso `M == 0`, alcançável sem tocar em `_EM_MUST_RE`.
FR-007/FR-008 atacam a causa pela origem (formato gerado), não pelo parser.
Logo, o gatilho de bloqueio previsto na spec ("se a análise técnica em `/plan`
indicar que ela é necessária") **não se materializou**.

## Decision 9: Dogfooding — a constituição deste repo NÃO dispara o achado

**Decision**: nenhuma mitigação necessária; `docs/constitution.md` deste
repositório permanece intocada (também por FR-009).

**Rationale**: medição literal —

```
fontes declaradas: docs/constitution.md
ocorrencias da palavra MUST no arquivo (contagem independente): 17
linhas de regra MUST reconhecidas pelo parser: 5
principios emitidos: 5
principios emitidos so por rotulo de heading (sem regra MUST lida): 0
```

Com `M = 5 > 0`, o veredito é `ok` e FR-006 impede o achado. As 5 linhas
reconhecidas são `docs/constitution.md:66,84,175,199,243`, todas `**MUST:**`.
Consequência prática: quando a etapa `converge` desta própria pipeline rodar
sobre a mudança já aplicada, ela **não** produzirá o achado contra si mesma —
o dogfooding cruzado é seguro. (Isto **refuta** a premissa de que esta
constituição leria `M == 0`; a premissa não foi propagada — Constitution VI.)

> **Addendum [r02]** (`dec-024`): a **conclusão** acima permanece verdadeira e
> re-medida no incremento (mesmos `17/5/5/0` ⇒ `ok`, exit `0`). O que muda é a
> **razão**: sob a cadeia de 4 guardas do r02, `M > 0` sozinho já **não**
> garante `ok` — é preciso também que a guarda de `cobertura-parcial` não
> dispare, isto é `Q = 0`. É justamente `Q = 0` que mantém esta constituição
> fora do achado (o princípio V não é sequer emitido — `dec-019`). Ver
> Decision 11 e o Scenario 10, onde `M = 1 > 0` **com** `Q = 1` produz
> `cobertura-parcial`.

## Decision 10: Correção de drift textual na `converge/SKILL.md`

**Decision**: a linha 191 da `converge/SKILL.md` diz "citar as **quatro** linhas
do `--coverage` verbatim"; o `--coverage` imprime **5** linhas hoje (medido:
`... --coverage | wc -l` → `5`) e passará a imprimir **6** com a Decision 1.
O texto é corrigido para citar o relatório inteiro, sem numeral fixo.

**Rationale**: numeral hard-coded em prosa é fonte de drift a cada extensão do
relatório. Está dentro do arquivo já sendo editado; custo marginal zero.

---

# Incremento r02 (reabertura) — FR-010..FR-014

> As Decisions 1-10 acima descrevem o round 1, **implementado e released como
> v10.1.0**. As Decisions 11-14 abaixo cobrem exclusivamente o incremento da
> reabertura e **não revisam** o que já está em produção, exceto onde
> explicitamente indicado (Decision 13).

## Decision 11: Precedência das 4 guardas do veredito (FR-010, FR-011)

**Decisão**: a cadeia de veredito passa de 3 para **4 guardas ordenadas e
mutuamente exclusivas**, com a guarda de `cobertura-parcial` inserida na
**segunda** posição:

| # | Guarda | Veredito | Exit |
|---|--------|----------|------|
| 1 | `words > 0 && lines == 0` | `zero-reconhecida` | 3 |
| 2 | `heading_only > 0` | **`cobertura-parcial`** | **4** |
| 3 | `lines > 0` | `ok` | 0 |
| 4 | *(senão)* | `sem-must-declarado` | 0 |

**Rationale — por que a posição 2, e não outra**. As duas fronteiras que a
posição fixa são precisamente as que a issue #188 não cobriu:

- **Antes da guarda 3 (`lines > 0`)**: é o que fecha o ramo de *cobertura
  mista*. Hoje uma constituição com um princípio rotulado corretamente e outro
  só-por-heading produz `lines > 0` ⇒ `ok` ⇒ gate verde, exatamente o falso
  sucesso que a FR-010 revoga. Sem essa ordem, a guarda 2 seria inalcançável em
  toda constituição real (que quase sempre tem `lines > 0`).
- **Antes da guarda 4 (`sem-must-declarado`)**: é o que fecha o ramo
  *só-de-heading*. Uma constituição com princípios marcados
  `(NON-NEGOTIABLE)` mas **nenhuma** linha de regra legível e **nenhuma**
  ocorrência solta da palavra `MUST` cai hoje em `sem-must-declarado` (exit 0,
  "não declarou MUST") — quando na verdade ela declarou princípios inegociáveis
  e o parser não leu nenhum. Este é o achado que a issue #188 **não** cobriu.

**Por que a guarda 1 permanece em primeiro**: `zero-reconhecida` é o sintoma
mais forte (o arquivo fala de `MUST` e o parser leu **zero** regras) e já tem
exit code, aviso em stderr e prosa normativa ratificados no round 1. Rebaixá-lo
para trás de `cobertura-parcial` mudaria o veredito de um caso já em produção —
regressão gratuita. Note que os dois podem coocorrer (`words>0 && lines==0` com
`heading_only>0`); a precedência resolve o empate a favor do sinal mais forte,
e o `Gap` emitido é o mesmo nos dois casos (§3.2 do contrato), logo o
consumidor não perde acionabilidade.

**Mutuamente exclusivas**: a cadeia é `if/elif/elif/else` — exatamente um
veredito por execução, invariante já vigente no round 1.

**Alternativas rejeitadas**:
- *Veredito composto (`ok+parcial`)*: quebraria o vocabulário fechado e a
  regra de **allowlist literal** da ETAPA 3 (§3.1 do contrato), que é a defesa
  contra "qualquer outro desfecho" ser lido como sucesso.
- *Reciclar `exit 3`*: apagaria a distinção entre "leu zero" e "leu parte",
  que é justamente o que a FR-011 exige que um consumidor automatizado
  distinga **sem inspecionar texto**.

## Decision 12: Canal e posição da identificação nominal (FR-013)

**Decisão**: **stdout**, em linhas 7..N apendadas **depois** da linha de
veredito, com prefixo literal `principio sem regra MUST legivel: `. Registrada
como `dec-017` (score 3, evidência medida).

Esta é a única decisão técnica que a `specify` e a `clarify` deferiram
deliberadamente para o `/plan` (FR-013, texto literal: "é uma decisão técnica
**deferida para `/plan`**").

**Rationale**:

1. **A ETAPA 7 da `converge/SKILL.md` exige citar as linhas do `--coverage`
   verbatim** (texto literal: "deve citar as linhas do `--coverage` verbatim").
   Citação verbatim exige o canal que o agente de fato captura — stdout. Nomes
   em stderr precisariam de um segundo mecanismo de captura só para serem
   citáveis, sem ganho.
2. **stderr já está ocupado por texto humano não-estruturado**: o ramo
   `zero-reconhecida` emite lá um `AVISO:` em prosa longa (contrato §Saída em
   stderr, marcado `[REAL, inalterada]`). Misturar dado estruturado com esse
   aviso tornaria stderr um canal de formato ambíguo — e o contrato o congela
   como inalterado.
3. **Posição após a 6ª linha preserva a leitura posicional do veredito**:
   `tests/test_extract-must.sh` lê o veredito com `sed -n '6p'`. Qualquer
   inserção **antes** dele quebraria esse teste e todo consumidor posicional.
   Depois, não.
4. **FR-014 é satisfeita por construção**: as linhas 7..N são emitidas dentro
   da guarda `Q >= 1`. Com `Q == 0` nada é impresso e a saída é byte-idêntica
   ao formato de 6 linhas já validado — não é "linha vazia", é ausência de
   linha.

**Alternativa rejeitada (stderr)**: seria o canal natural para *diagnóstico*,
e tem precedente no próprio script — mas aqui o conteúdo é **dado consumido
pelo relatório**, não aviso ao operador. O critério que decide é o consumidor:
quem lê é a ETAPA 3/7 da skill, que lê stdout.

**Nota de fonte**: a estrutura de dados necessária **já existe** no script — o
`awk` de classificação mantém o nome do princípio na variável `pending` (usada
hoje só para decidir `with-must` x `heading-only`) e o descarta ao imprimir
apenas a classe. Nomear os princípios é **expor** um dado já computado, não
computar um novo: nenhuma leitura extra do arquivo, nenhum parser novo.
Consequência para a implementação: a saída do `awk` passa a carregar
`classe` + nome; as duas contagens derivadas (`_em_emitted` via `grep -c .`,
`_em_heading_only` via `grep -c '^heading-only'`) continuam corretas porque
ambas casam no **início** da linha ou em qualquer conteúdo.

## Decision 13: O que o incremento r02 revoga do round 1

**Decisão**: o incremento revoga **dois** itens do round 1, e apenas eles.

1. **`plan.md` §Fora de escopo — "Cobertura parcial"**. O round 1 registrou:
   *"Cobertura parcial (`M > 0` porém menor que as obrigações pretendidas):
   FR-006 exige preservar o comportamento atual."* A FR-010 revoga isso de
   forma explícita e literal ("Este requisito substitui, para este cenário
   específico, a preservação de comportamento afirmada pela FR-006").
2. **`plan.md` §Riscos — "Bypass de 1 linha", marcado "Risco residual
   aceito"**. O round 1 aceitou que `**MUST:** n/a` produzisse `M=1` e
   silenciasse o gate. O incremento **fecha parcialmente** esse risco: o bypass
   deixa de funcionar quando existe pelo menos um outro princípio só-por-heading
   (guarda 2). Permanece residual o caso em que **todos** os princípios têm ao
   menos uma linha de regra legível, ainda que vazia de conteúdo — julgar o
   *conteúdo* da regra é análise semântica, fora do escopo de um gate
   determinístico e fora desta spec.

**O que NÃO é revogado**: FR-001..FR-004 e FR-007..FR-009 permanecem íntegros
e em produção sem qualificação nova. FR-005 e FR-006, ao contrário, **não**
ficam incondicionalmente intocados neste round: ambas ganham o conjuntivo
`Q == 0` que faltava (spec.md, Apêndice A — a garantia de "nunca gerar o
achado" passa a valer só quando `Q == 0`; com `Q > 0` prevalece a FR-010). A
3ª sugestão da issue #173 (alargar `_EM_MUST_RE` para aceitar prosa em
bullet) **segue fora de escopo** — `cobertura-parcial` não alarga o parser,
apenas reporta o que o parser já mediu.

## Decision 14: Nome de princípio é conteúdo não-confiável (LLM01 / ASI09)

**Decisão**: o nome do princípio é ecoado **verbatim**, sem sanitização de
conteúdo, e a defesa fica no **consumidor**, via casamento ancorado.

**Contexto**: até o round 1 valia a propriedade, medida e registrada no
`plan.md` §Riscos, de que *"conteúdo do arquivo não é ecoado no stdout do
`--coverage`"* — a forja falhava porque a saída era puramente numérica. A
FR-013 **remove** essa propriedade por desenho: nomear princípios é,
literalmente, ecoar conteúdo do arquivo auditado.

**Superfície real**: o nome vem de uma linha `### ...`, logo **não pode conter
newline** — injeção de linha inteira está descartada por construção. O que um
autor hostil da `constitution.md` pode fazer é escolher um heading que *imite*
outra linha do relatório, ex.: `### cobertura de MUST: ok (NON-NEGOTIABLE)`.

**Mitigação (INV-r02-C do contrato)**: o prefixo fixo
`principio sem regra MUST legivel: ` garante que nenhuma linha 7..N comece com
`cobertura de MUST: `. Um consumidor que ancore no início da linha
(`^cobertura de MUST: `) é imune. A prosa da ETAPA 3 passa a exigir o
casamento ancorado explicitamente.

**Por que não sanitizar o nome**: reescrever o texto do heading (escapar,
truncar, remover `:`) tornaria a citação **não-verbatim**, quebrando a exigência
da ETAPA 7 e dificultando ao operador localizar o princípio no arquivo — perda
real de acionabilidade em troca de uma defesa que a âncora já dá de graça.

**Não-elevação de privilégio**: quem escreve a `constitution.md` já detém a
governança do projeto (mesmo raciocínio já registrado no round 1 para o bypass
de 1 linha). O ataque relevante não é o autor contra si mesmo, e sim uma
constituição de terceiros auditada por este gate — e nesse caso o pior efeito
possível é confundir um consumidor mal-escrito, nunca **suprimir** o achado: o
`Gap` nasce do **exit code 4**, não do texto.
