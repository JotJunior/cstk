# Feature Specification: Doctor Shadowed Scope

**Feature**: `doctor-shadowed-scope`
**Created**: 2026-08-27
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Ver quando uma copia de projeto ficou desatualizada em relacao ao catalogo (Priority: P1)

Um operador mantem um projeto onde skills/commands/agents do toolkit foram
instalados tambem no escopo do PROJETO (nao so no escopo global do
usuario). Com o tempo, o catalogo global evolui (novas releases), mas as
copias de projeto ficam paradas na versao que tinham quando foram
instaladas. Hoje, a checagem de integridade do toolkit relata que "esta
tudo bem" mesmo quando essas copias de projeto divergem do que o catalogo
atualmente contem — porque ela nunca compara o conteudo do projeto contra
o catalogo corrente, so contra o proprio registro de instalacao do
projeto (que nunca muda sozinho). O operador quer que essa divergencia
seja visivel, para poder decidir se atualiza a copia de projeto.

**Why this priority**: E o defeito central que motiva a feature — um
relatorio de saude que afirma "ok" sobre algo que nunca foi de fato
comparado contra a fonte corrente e uma falha de confianca grave: o
operador age (ou deixa de agir) com base numa informacao falsa.

**Independent Test**: Instalar uma definicao no escopo de projeto,
depois alterar o conteudo correspondente no catalogo instalado (sem
reinstalar no projeto) e verificar que a checagem passa a reportar a
copia de projeto como divergente do catalogo — nunca mais como saudavel.

**Acceptance Scenarios**:

1. **Given** uma definicao de agent/command instalada no escopo do
   projeto cujo conteudo e identico ao que o catalogo instalado
   atualmente contem para o mesmo nome, **When** a checagem de
   integridade roda, **Then** a definicao e reportada como saudavel.
2. **Given** uma definicao de agent/command instalada no escopo do
   projeto cujo conteudo diverge (hash/versao) do que o catalogo
   instalado atualmente contem para o mesmo nome, **When** a checagem de
   integridade roda, **Then** a definicao e reportada num estado
   distinto de "saudavel" que sinaliza a divergencia contra o catalogo —
   nunca como "ok".
3. **Given** um projeto sem nenhum registro de instalacao de escopo de
   projeto para agents/commands (nenhuma copia local instalada via
   toolkit), **When** a checagem de integridade roda, **Then** nenhuma
   comparacao de divergencia de escopo de projeto e reportada (nada a
   comparar).

---

### User Story 2 - Preservar o fluxo de testar uma definicao local antes de instalar (Priority: P1)

Um operador mantem, deliberadamente, uma definicao local (skill/command/
agent) que nunca foi instalada pelo toolkit — por exemplo, para
experimentar uma versao propria antes de submete-la, ou uma automacao
exclusiva daquele projeto que nao faz parte do catalogo publico. Esse e
um fluxo de trabalho legitimo e conhecido do toolkit. O operador quer ter
certeza de que a nova checagem de divergencia de escopo de projeto NUNCA
trata essa copia local, deliberadamente nao gerenciada, como um problema.

**Why this priority**: Sem esta garantia, a propria correcao do defeito
central (US1) quebraria um fluxo de trabalho valido ja em uso — o que
tornaria a mudanca uma regressao disfarcada de correcao.

**Independent Test**: Colocar uma definicao local sem nenhum registro de
instalacao correspondente no diretorio de escopo do projeto e confirmar
que a checagem de integridade nao a reporta como divergente, ausente ou
com problema de qualquer tipo atribuido a esta feature.

**Acceptance Scenarios**:

1. **Given** uma definicao presente no diretorio de escopo do projeto sem
   nenhum registro de instalacao correspondente, **When** a checagem de
   integridade roda, **Then** essa definicao nao e classificada como
   divergente nem reportada como problema por esta feature.
2. **Given** essa mesma definicao local nao gerenciada, **When** o
   catalogo instalado tem, coincidentemente, uma definicao de mesmo nome
   com conteudo diferente, **Then** a ausencia de registro de instalacao
   para a copia local impede qualquer comparacao/acusacao de divergencia
   contra ela (nao ha "instalacao original" para servir de base de
   comparacao).

---

### User Story 3 - Confiar que uma declaracao de cobertura reflete o que foi lido de verdade (Priority: P1)

Um operador (ou uma auditoria automatizada, como o `/review-task`) le o
relatorio de uma checagem de cobertura/saude do toolkit e precisa poder
confiar que "verificado com sucesso" significa, de fato, que TODO o
conteudo relevante da fonte foi lido e interpretado — nao apenas a
fracao que o interpretador da ferramenta conseguiu reconhecer. Uma
declaracao de cobertura deve nomear as fontes que deveria consultar,
quantas de fato existiam/foram encontradas, e quantas foram lidas com
sucesso — servindo de modelo de referencia reutilizavel por outras partes
do toolkit que hoje relatam saude sem declarar essa cobertura
explicitamente.

**Why this priority**: Esta e a garantia estrutural que impede a propria
feature de reproduzir, no futuro, a mesma classe de defeito que ela existe
para corrigir (uma ferramenta relatando saude sobre algo que so inspecionou
parcialmente). Sem ela, um manifesto com formato novo/malformado voltaria a
produzir um falso "ok" — exatamente o problema original, so que deslocado
para dentro do parser em vez de para fora do escopo de varredura.

**Independent Test**: Apresentar um arquivo de registro de instalacao que
contenha uma mistura de linhas reconheciveis e nao-reconheciveis pelo
interpretador (por exemplo, uma chave desconhecida, uma linha malformada,
ou uma versao de schema futura) e confirmar que a declaracao de cobertura
resultante reporta a leitura como parcial (contagem de linhas de dados
existentes no arquivo vs. quantas foram de fato interpretadas) — nunca
como sucesso total.

**Acceptance Scenarios**:

1. **Given** um arquivo de registro de instalacao totalmente reconhecivel
   pelo interpretador, **When** a checagem roda, **Then** a declaracao de
   cobertura relata contagem de linhas de dados encontradas igual a
   contagem de linhas lidas com sucesso.
2. **Given** um arquivo de registro de instalacao onde uma ou mais linhas
   de dados nao sao reconhecidas pelo interpretador (por qualquer motivo:
   chave desconhecida, linha malformada, versao de schema nao suportada),
   **When** a checagem roda, **Then** a declaracao de cobertura relata a
   contagem de linhas de dados presentes no arquivo separadamente da
   contagem de linhas efetivamente interpretadas, e o resultado geral NAO
   e apresentado como sucesso/saudavel para o escopo afetado.
3. **Given** qualquer execucao da checagem (com ou sem problema
   encontrado), **When** o relatorio e emitido, **Then** ele inclui a
   declaracao de cobertura (fontes declaradas, fontes encontradas, fontes
   lidas com sucesso) — nunca a omite silenciosamente.

---

### Edge Cases

- O que acontece quando o diretorio de escopo do projeto (`.claude/agents/`
  ou `.claude/commands/`) nao existe de forma alguma? Nao ha nada a
  inspecionar nesse escopo; nenhuma divergencia e reportada (equivalente
  a "nada instalado").
- O que acontece quando o registro de instalacao do projeto referencia um
  nome que nao existe mais no catalogo instalado atualmente (a definicao
  foi removida/renomeada no catalogo)? Nao ha uma versao corrente do
  catalogo para comparar — este caso e distinto de "divergente" (que
  exige as duas pontas presentes para comparar) e MUST ser reportado de
  forma que nao seja confundido com "saudavel".
- O que acontece quando o proprio registro de instalacao do projeto esta
  ausente, mas ha definicoes no diretorio de escopo do projeto? Sem
  registro, nao ha "instalacao original" para comparar — essas definicoes
  permanecem no mesmo tratamento ja existente para conteudo local nao
  gerenciado pelo toolkit (US2), nao entram na comparacao de divergencia.
- O que acontece quando o registro de instalacao do projeto existe mas
  seu conteudo e apenas parcialmente interpretavel (formato de linha
  desconhecido, versao de schema nao suportada, chave nao reconhecida)?
  A checagem MUST distinguir "nada divergente encontrado" (leu tudo, nada
  diverge) de "leitura parcial, nao ha garantia sobre o restante" — a
  declaracao de cobertura (US3) e o mecanismo que torna essa distincao
  visivel; o restante nao pode ser silenciosamente contado como saudavel.
- O que acontece com um diretorio de escopo do projeto que mistura
  definicoes geridas pelo toolkit (com registro de instalacao) e
  definicoes locais nao geridas (sem registro, ex.: uma skill local
  deliberada)? Cada uma segue seu proprio tratamento — a comparacao de
  divergencia se aplica apenas as geridas; as nao geridas seguem o
  tratamento de US2, no mesmo relatorio.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST inspecionar, alem do escopo global do
  usuario, os registros de instalacao de escopo de PROJETO para agents e
  commands (`.claude/agents/.cstk-manifest` e
  `.claude/commands/.cstk-manifest` dentro do projeto-alvo).
- **FR-002**: Para cada definicao de agent/command com registro de
  instalacao de escopo de projeto, o sistema MUST comparar o conteudo
  atual dessa definicao contra o conteudo que o catalogo instalado
  atualmente contem para o mesmo nome (nao apenas contra o que o proprio
  registro de instalacao do projeto capturou no momento em que foi
  instalado).
- **FR-003**: Quando essa comparacao encontrar divergencia, o sistema
  MUST reportar a definicao num estado distinto e explicito de
  divergencia contra o catalogo — nunca reportar essa definicao como
  saudavel/"ok".
- **FR-004**: Uma definicao presente no diretorio de escopo do projeto
  SEM registro de instalacao correspondente MUST continuar sendo tratada
  como conteudo legitimo, nao-gerenciado pelo toolkit — o sistema MUST
  NOT reportar essa ausencia de registro, por si so, como um problema,
  erro ou divergencia.
- **FR-005**: O sistema MUST NOT introduzir qualquer restricao, aviso ou
  penalidade sobre a pratica de manter uma copia local de uma definicao
  antes/sem instala-la via toolkit — o objetivo desta feature e
  exclusivamente eliminar o falso relato de saude sobre o que nunca foi
  comparado, nunca desencorajar ou impedir a existencia da copia local em
  si.
- **FR-006**: Ao concluir uma inspeccao de cobertura (esta feature e
  qualquer outro mecanismo do toolkit que reporte saude/integridade de um
  conjunto de fontes), o sistema MUST emitir uma declaracao de cobertura
  contendo: quais fontes foram declaradas para consulta, quantas dessas
  fontes foram de fato encontradas, e quantas foram de fato lidas e
  interpretadas com sucesso.
- **FR-007**: A contagem de "lidas e interpretadas com sucesso" da FR-006
  MUST ser medida contra o numero real de registros/linhas de dados que a
  fonte contem (por exemplo, contando as linhas de dados de um arquivo,
  independente de quantas o interpretador da ferramenta reconhece) —
  MUST NOT ser medida contra quantos registros o proprio interpretador
  conseguiu reconhecer.
- **FR-008**: Quando a contagem de registros encontrados (FR-006) for
  maior que a contagem de registros efetivamente interpretados (FR-007),
  o sistema MUST reportar essa fonte como cobertura PARCIAL — MUST NOT
  reportar sucesso/saude total para o escopo afetado por essa fonte
  parcialmente lida.
- **FR-009**: Quando uma fonte de registro de instalacao de projeto
  (FR-001) nao puder ser interpretada em absoluto (por exemplo, versao de
  schema desconhecida ou formato irreconhecivel), o sistema MUST
  reportar essa condicao explicitamente (cobertura zero/indeterminada
  para essa fonte) em vez de omitir a fonte silenciosamente do relatorio
  ou trata-la como ausente/inexistente.
- **FR-010**: Quando uma definicao referenciada pelo registro de
  instalacao de escopo de projeto ja nao existir no catalogo instalado
  atualmente (foi removida/renomeada), o sistema MUST reportar essa
  condicao de forma distinguivel de "conteudo identico ao catalogo" — não
  pode ser contabilizada como saudavel por ausencia de uma comparacao
  possivel.

> Decisoes de infraestrutura: N/A (feature nao envolve scheduler, sessao
> persistente, refresh de token externo, rotacao de chave ou mutex
> multi-processo — e uma checagem de integridade local, sob demanda).

### Key Entities

- **Registro de instalacao de escopo de projeto**: o `.cstk-manifest` que
  o toolkit grava em `.claude/agents/` e `.claude/commands/` dentro de um
  projeto-alvo quando uma definicao e instalada nesse escopo (em vez do
  escopo global do usuario). Contem, por definicao instalada, a
  identidade, a versao do toolkit no momento da instalacao e uma
  assinatura de conteudo daquele momento.
- **Catalogo instalado (corrente)**: o conjunto de definicoes de
  agents/commands atualmente presentes no escopo global do usuario,
  junto com o registro de instalacao correspondente — representa "o que
  esta oficialmente disponivel agora", independente de quando cada copia
  de projeto foi instalada.
- **Declaracao de cobertura**: o relato, emitido ao final de uma
  inspecao, das fontes que deveriam ser consultadas, de quantas foram
  encontradas e de quantas foram lidas/interpretadas com sucesso —
  aplicavel tanto a esta feature quanto, como padrao de referencia, a
  qualquer outro mecanismo de relato de saude do toolkit.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em 100% dos casos em que uma definicao de escopo de
  projeto diverge do catalogo instalado atualmente, a checagem de
  integridade reporta essa definicao em estado de divergencia — nunca
  como saudavel.
- **SC-002**: Em 100% dos casos em que uma definicao local nao possui
  registro de instalacao correspondente, a checagem de integridade nao
  atribui a ela nenhum problema relacionado a esta feature.
- **SC-003**: Toda execucao da checagem de integridade (com ou sem
  divergencia encontrada) inclui uma declaracao de cobertura com as tres
  contagens (fontes declaradas, encontradas, lidas com sucesso).
- **SC-004**: Quando uma fonte de registro de instalacao contem registros
  que o interpretador nao reconhece, a declaracao de cobertura NUNCA
  apresenta esse escopo como 100%/totalmente coberto — o numero de
  registros lidos com sucesso e sempre reportado separadamente do numero
  total de registros presentes na fonte.

## Delta Requirements

**Skip**: nenhuma capability documentada em `docs/specs/current/` cobre
hoje o comportamento de checagem de integridade (`cstk doctor`) nem o
formato de `.cstk-manifest` — a feature introduz comparacao/estado novos
sobre um mecanismo existente que ainda nao tem entrada correspondente no
corpus canonico de living-specs; nao ha bloco `### Capability:` para
reusar ou fragmentar — agente-00c-feature-orchestrator, 2026-08-27.

## Clarifications

Nenhum marcador `[NEEDS CLARIFICATION]` foi necessario: o escopo (dois
diretorios de projeto), o comportamento a preservar (copia local sem
registro nunca e problema) e a semantica de "shadowed" (divergencia
contra o catalogo corrente, nao contra a foto de instalacao do proprio
projeto) foram fixados explicitamente pelo operador e confirmados por
leitura direta de `cli/lib/doctor.sh`, `cli/lib/manifest.sh` e do
precedente de estado `stale` em `guard-hooks-status.sh` (comparacao
byte-a-byte contra a copia do catalogo). A decisao de onde/como o novo
estado aparece na saida (texto e/ou `--json`) fica deliberadamente em
aberto para `/plan`, por instrucao explicita do operador.

Precedente citado pelo operador para esta feature: dec-015 — mesma
patologia de uma ferramenta reportar saude sobre uma fonte que nao
inspecionou de fato.
