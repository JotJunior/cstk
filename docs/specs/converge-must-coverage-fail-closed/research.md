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

## Decision 10: Correção de drift textual na `converge/SKILL.md`

**Decision**: a linha 191 da `converge/SKILL.md` diz "citar as **quatro** linhas
do `--coverage` verbatim"; o `--coverage` imprime **5** linhas hoje (medido:
`... --coverage | wc -l` → `5`) e passará a imprimir **6** com a Decision 1.
O texto é corrigido para citar o relatório inteiro, sem numeral fixo.

**Rationale**: numeral hard-coded em prosa é fonte de drift a cada extensão do
relatório. Está dentro do arquivo já sendo editado; custo marginal zero.
