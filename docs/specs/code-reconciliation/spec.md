# Feature Specification: Code Reconciliation (reconciliar documentacao de feature com o codebase)

**Feature**: `code-reconciliation`
**Created**: 2026-09-30
**Status**: Draft

## Contexto e motivacao

Com frequencia o codigo recebe acertos pontuais (correcoes, ajustes de comportamento,
renomeacoes, remocoes) sem que a documentacao da feature que originou aquele codigo seja
atualizada. Com o tempo, `spec.md`, `plan.md` e demais artefatos da feature passam a
descrever um sistema que ja nao existe, e deixam de servir como fonte confiavel de
"o que a feature e hoje".

O toolkit ja possui a skill `converge`, que compara a intencao documentada com o codigo e
**acrescenta tarefas** para fechar as lacunas (o codigo e que e trazido para a spec). Esta
feature cobre o sentido inverso, hoje sem cobertura: quando o codigo e a realidade aceita,
**a documentacao e que deve ser trazida para o codigo**. A skill nova atua exclusivamente
sobre documentacao — jamais altera codigo.

## Clarifications

### Session 2026-09-30

- Q: Onde vive o registro de reconciliacao (FR-018) e o que acontece quando nao ha divergencias? → A: Arquivo proprio na feature (`reconciliation.md`), log append-only, atualizado somente quando ha alteracao real; execucao sem divergencia nao grava nada (preserva FR-012/SC-003).
- Q: Qual o escopo de busca no codigo para confrontar uma feature (FR-004/FR-009)? → A: Somente o codigo alcancavel a partir de caminhos, simbolos, comandos e contratos citados na documentacao (git apenas como atalho de priorizacao, FR-016); comportamento fora dessa ancora nao e detectado e, quando relevante, e reportado como nao verificavel.
- Q: Que contradicoes codigo x documentacao viram "possivel regressao" (FR-007)? → A: Apenas contradicao de requisitos MUST/MUST NOT da feature e de principios da constitution; SHOULD e texto descritivo sao reescritos para refletir o codigo.
- Q: Como marcar trechos obsoletos/removidos e acrescimos documentados (FR-005/FR-009)? → A: Marcadores inline padronizados, com data e referencia a evidencia, mantendo o identificador FR-NNN; acrescimos usam novo FR-NNN sequencial; os tokens exatos dos marcadores sao fixados no plan.
- Q: Qual a politica de escrita em features arquivadas e no corpus canonico `docs/specs/current/` (FR-017)? → A: Editar diretamente a documentacao de features arquivadas (mesma politica da ativa) e NUNCA editar o corpus `docs/specs/current/`, preservando o fluxo delta-merge (decisao humana, block-001).
- Q: Como a skill se comporta quando `docs/constitution.md` do projeto e inexistente ou ilegivel (FR-007)? → A: Segue sem falhar, usando como criterio de "possivel regressao" apenas os requisitos MUST/MUST NOT da propria feature, e emite o aviso `constitution-unavailable` no relatorio; nenhum principio e presumido (Constitution VI). Decisao operacional dec-027 (execute-task 1.1).
- Q: O que e "divergencia por acerto pontual" (denominador de SC-005)? → A: Divergencia dos tipos `stale`, `removed` ou `undocumented` (data-model) que a skill consegue resolver com evidencia observavel; `possible-regression` e `unverifiable` ficam fora do denominador por exigirem decisao humana ou fonte inexistente. Nenhum limiar numerico (linhas, tamanho) e usado. Decisao operacional dec-028 (execute-task 1.2).
- Q: A skill pode reproduzir valores sensiveis do codigo ao citar evidencia? → A: Nao; evidencia e sempre por referencia `arquivo:linha` (ou `absent:<caminho>`), nunca reproduzindo chaves, tokens ou credenciais em documentos, marcadores ou relatorio (FR-019). O cumprimento e regra da skill (`references/` + Gotcha), sem detector deterministico novo. Decisao operacional dec-029 (execute-task 1.3).

## User Scenarios & Testing

### User Story 1 - Reconciliar UMA feature com o codigo atual (Priority: P1)

Uma pessoa mantenedora sabe que fez acertos no codigo de uma feature (ativa ou ja
arquivada) e quer que a documentacao dessa feature volte a refletir a realidade. Ela invoca
a skill informando o nome da feature; a skill localiza a feature, compara o que a
documentacao afirma com o que o codigo faz hoje, atualiza os documentos divergentes e
entrega um relatorio do que mudou e por que.

**Why this priority**: e o nucleo do pedido e entrega valor sozinho — documentacao
confiavel de uma feature — sem depender do modo em lote nem de nenhum outro recurso.

**Independent Test**: escolher uma feature cujo codigo foi alterado apos a ultima edicao da
sua spec, invocar a skill com o nome dela e verificar (a) que a spec e os demais documentos
divergentes foram atualizados para refletir o codigo, (b) que nenhum arquivo fora da
documentacao mudou e (c) que o relatorio lista cada alteracao com a evidencia no codigo.

**Acceptance Scenarios**:

1. **Given** uma feature ativa em `docs/specs/<feature>/` cujo codigo passou a se comportar
   diferente do que a spec afirma, **When** a pessoa invoca a skill com o nome da feature,
   **Then** a spec e reescrita nos pontos divergentes para descrever o comportamento
   atual, e o relatorio cita, para cada ponto, o trecho de codigo que serve de evidencia.
2. **Given** uma feature cuja documentacao ja esta coerente com o codigo, **When** a skill
   e invocada, **Then** nenhum documento e alterado e o relatorio informa "nenhuma
   divergencia encontrada".
3. **Given** uma feature arquivada (sob `docs/specs/_archived/`), **When** a pessoa invoca a
   skill apenas com o nome da feature (sem o prefixo de data do diretorio), **Then** a
   skill localiza o diretorio arquivado e o reconcilia.
4. **Given** um nome de feature que nao existe nem em `docs/specs/` nem em
   `docs/specs/_archived/`, **When** a skill e invocada, **Then** ela encerra sem alterar
   nada, informa que a feature nao foi encontrada e lista as features disponiveis com
   nomes proximos.

---

### User Story 2 - Reconciliar TODAS as features de uma vez (Priority: P2)

A pessoa mantenedora quer varrer o portfolio inteiro apos um periodo de acertos dispersos.
Ela invoca a skill com a opcao `--all` e a skill reconcilia cada feature ativa e arquivada,
entregando um relatorio consolidado.

**Why this priority**: multiplica o valor da P1 para o portfolio inteiro, mas so faz
sentido depois de a reconciliacao de uma feature funcionar; e independente da P1 no teste,
pois basta haver duas ou mais features.

**Independent Test**: em um projeto com pelo menos uma feature ativa e uma arquivada, ambas
com divergencias conhecidas, invocar a skill com `--all` e verificar que as duas foram
reconciliadas e que o relatorio consolidado traz uma linha por feature.

**Acceptance Scenarios**:

1. **Given** um projeto com features ativas e arquivadas, **When** a skill e invocada com
   `--all`, **Then** cada feature encontrada nos dois locais e reconciliada e o relatorio
   consolidado traz, por feature, o resultado (reconciliada, sem divergencia, ignorada ou
   com erro).
2. **Given** uma execucao `--all` em que a reconciliacao de uma feature falha (por exemplo,
   documento ilegivel), **When** a varredura continua, **Then** as demais features ainda
   sao processadas e a falha aparece no relatorio consolidado sem interromper o lote.
3. **Given** um projeto sem nenhuma feature em `docs/specs/`, **When** a skill e invocada
   com `--all`, **Then** ela informa que nao ha features a reconciliar e nao altera nada.

---

### User Story 3 - Garantia de que so a documentacao e alterada (Priority: P1)

A pessoa mantenedora precisa ter certeza de que rodar a skill nunca muda codigo, testes,
scripts, configuracoes ou qualquer artefato que nao seja documentacao de feature.

**Why this priority**: e a restricao central do pedido ("exclusivamente atualizar
documentacao, nunca alterar codigo"). Sem essa garantia a skill nao e segura de usar em
lote, entao tem a mesma prioridade do nucleo.

**Independent Test**: rodar a skill (uma feature e `--all`) em um repositorio versionado e
comparar o conjunto de arquivos modificados ao final: todos devem estar em documentacao de
feature.

**Acceptance Scenarios**:

1. **Given** uma execucao qualquer da skill, **When** ela termina, **Then** o conjunto de
   arquivos modificados contem apenas documentos de feature (ativa ou arquivada) dentro de
   `docs/specs/`, nenhum arquivo do corpus `docs/specs/current/` e nenhum arquivo de codigo,
   teste, script ou configuracao.
2. **Given** uma divergencia cuja "correcao" natural seria mudar o codigo (o codigo
   contradiz um requisito MUST da feature ou um principio da constitution do projeto),
   **When** a skill a encontra, **Then** ela NAO reescreve o requisito para acomodar o
   codigo e NAO altera o codigo: registra a divergencia como "possivel regressao — requer
   decisao humana" no relatorio.

---

### User Story 4 - Revisar antes de gravar (Priority: P3)

Antes de aceitar alteracoes em documentos, a pessoa quer ver o que a skill pretende mudar,
principalmente em `--all`.

**Why this priority**: reduz o risco de adocao e da confianca, mas a skill ja entrega valor
gravando direto (P1) e o resultado e revertivel pelo controle de versao.

**Independent Test**: invocar a skill em modo de pre-visualizacao e verificar que o
relatorio mostra as alteracoes propostas e que nenhum arquivo foi modificado.

**Acceptance Scenarios**:

1. **Given** a opcao de pre-visualizacao (`--dry-run`), **When** a skill e invocada para uma
   feature ou com `--all`, **Then** o relatorio descreve cada alteracao que seria feita
   (documento, trecho, evidencia) e nenhum arquivo do projeto e modificado.

---

### Edge Cases

- **Feature presente em dois locais**: o mesmo nome existe ativa e arquivada (ex.: feature
  reaberta). A skill reconcilia a versao ativa e informa a existencia da arquivada; nunca
  mescla as duas nem reconcilia a arquivada silenciosamente.
- **Codigo de referencia removido**: um caminho de codigo citado pela documentacao nao
  existe mais. A skill marca o trecho como obsoleto/removido no documento (com a evidencia
  da ausencia) em vez de apagar o requisito sem rastro.
- **Codigo novo nao documentado**: comportamento presente no codigo que a documentacao nao
  menciona. A skill o registra como acrescimo documentado, distinguindo-o do que a feature
  originalmente pediu.
- **Feature sem `spec.md`** (diretorio incompleto): a skill nao inventa a spec; informa o
  documento ausente e reconcilia apenas os documentos existentes, ou ignora a feature com
  aviso se nenhum documento reconciliavel existir.
- **Nome ambiguo**: o nome informado casa com mais de uma feature (prefixo comum). A skill
  nao escolhe sozinha: lista os candidatos e encerra sem alterar nada.
- **Sem controle de versao** (projeto fora de repositorio versionado): a skill funciona,
  mas sem o atalho de identificar mudancas recentes por historico; a reconciliacao passa a
  depender apenas da leitura do codigo atual.
- **Reexecucao**: rodar a skill duas vezes seguidas sobre a mesma feature nao produz
  alteracoes na segunda execucao (idempotencia).
- **Documento com edicoes manuais recentes**: trechos ja coerentes com o codigo nao sao
  reescritos apenas por estilo; so muda o que diverge do codigo.
- **Constitution ausente ou ilegivel**: `docs/constitution.md` nao existe ou nao pode ser
  lido. A skill nao falha nem presume principios: classifica "possivel regressao" apenas por
  requisitos MUST/MUST NOT da propria feature e informa o aviso `constitution-unavailable`
  no relatorio (FR-007).
- **Segredo no codigo citado como evidencia**: o trecho de codigo que serve de evidencia
  contem valor sensivel (chave, token, credencial). A skill cita somente `arquivo:linha` e
  nao reproduz o valor em documento, marcador ou relatorio (FR-019).
- **Dado factual sem fonte**: se a skill nao encontra no codigo a fonte de um valor,
  nome de campo, caminho ou endpoint que precisaria escrever, ela nao o escreve; marca o
  ponto como "nao verificavel" no relatorio.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST oferecer uma skill invocavel como `/reconcile-docs <feature>`
  que reconcilia a documentacao de uma unica feature com o estado atual do codigo do
  projeto.
- **FR-002**: O sistema MUST localizar a feature informada tanto em `docs/specs/<feature>/`
  quanto em `docs/specs/_archived/`, aceitando o nome da feature com ou sem o prefixo de
  data usado nos diretorios arquivados.
- **FR-003**: O sistema MUST aceitar a opcao `--all`, que reconcilia todas as features
  encontradas em `docs/specs/` e `docs/specs/_archived/` e produz um relatorio consolidado
  com uma entrada por feature.
- **FR-004**: Para cada feature, o sistema MUST comparar as afirmacoes verificaveis da
  documentacao (comportamentos, requisitos, caminhos de codigo, contratos, estruturas de
  dados, comandos e opcoes citados) com o que o codigo atual de fato faz, e classificar cada
  divergencia encontrada. O escopo de busca no codigo MUST ser o alcancavel a partir dos
  caminhos, simbolos, comandos e contratos citados na documentacao; comportamento fora dessa
  ancora nao e detectado e, quando relevante, MUST ser reportado como nao verificavel.
- **FR-005**: O sistema MUST atualizar os documentos divergentes da feature — `spec.md`,
  `plan.md`, `data-model.md`, `contracts/` e `quickstart.md` quando existirem — para que
  passem a descrever o comportamento atual, alterando somente os trechos que divergem e
  preservando o restante do texto, a estrutura e os identificadores existentes (FR-NNN,
  SC-NNN).
- **FR-006**: O sistema MUST NEVER alterar codigo-fonte, testes, scripts, configuracoes ou
  qualquer arquivo que nao seja documentacao de feature (ativa ou arquivada) dentro de
  `docs/specs/`, excluido o corpus `docs/specs/current/` (FR-017); toda escrita fora desse
  escopo e proibida por regra da skill, nao apenas por convencao.
- **FR-007**: O sistema MUST usar o codigo atual como fonte de verdade da reconciliacao,
  exceto quando a divergencia contradiz um requisito MUST/MUST NOT da propria feature ou um
  principio da constitution do projeto (requisitos SHOULD e texto descritivo sao reescritos
  para refletir o codigo): nesse caso MUST reportar a divergencia como
  "possivel regressao — requer decisao humana", sem reescrever o requisito nem alterar o
  codigo.
- **FR-008**: O sistema MUST fundamentar cada alteracao de documento em evidencia
  observavel no codigo (arquivo e trecho) e MUST NOT escrever nomes de campos, valores,
  caminhos, endpoints ou assinaturas que nao possam ser verificados no codigo; pontos nao
  verificaveis MUST ser reportados como tal (Constitution VI).
- **FR-009**: O sistema MUST tratar a documentacao referente a codigo removido marcando o
  trecho como obsoleto/removido com a evidencia, e MUST registrar como acrescimo
  documentado o comportamento novo do codigo que a documentacao nao cobre, sem apagar
  requisitos sem rastro. As marcas MUST ser marcadores inline padronizados, com data e
  referencia a evidencia, preservando o identificador FR-NNN do requisito afetado; acrescimos
  MUST usar novo FR-NNN sequencial (tokens exatos definidos no plan).
- **FR-010**: O sistema MUST produzir, ao final de cada execucao, um relatorio que liste,
  por feature, cada divergencia (tipo, documento e trecho afetados, evidencia no codigo) e
  a acao tomada (atualizado, reportado para decisao humana, nao verificavel, ignorado).
- **FR-011**: O sistema MUST oferecer a opcao `--dry-run`, que produz o mesmo relatorio
  descrevendo as alteracoes propostas sem modificar nenhum arquivo.
- **FR-012**: O sistema MUST ser idempotente: uma segunda execucao sobre a mesma feature,
  sem novas mudancas no codigo, MUST NOT produzir alteracoes em documentos.
- **FR-013**: Na opcao `--all`, uma falha ao reconciliar uma feature MUST NOT interromper o
  processamento das demais; a falha MUST aparecer no relatorio consolidado.
- **FR-014**: Quando o nome informado nao corresponder a nenhuma feature, ou corresponder a
  mais de uma de forma ambigua, o sistema MUST encerrar sem alterar nada, informando os
  candidatos ou as features disponiveis.
- **FR-015**: Quando a mesma feature existir ativa e arquivada, o sistema MUST reconciliar
  a versao ativa por padrao e informar a existencia da arquivada, sem mescla-las.
- **FR-016**: O sistema MUST funcionar em projeto sem historico de controle de versao,
  usando-o apenas como atalho opcional para priorizar o que mudou; a verificacao MUST
  sempre se basear na leitura do codigo atual.
- **FR-017**: O sistema MUST aplicar a features arquivadas (`docs/specs/_archived/`) a mesma
  politica de escrita das features ativas (FR-005 a FR-009), editando diretamente a
  documentacao delas, e MUST NEVER escrever no corpus canonico de comportamento atual
  (`docs/specs/current/`), que e gerado por merge de deltas e nao e editado a mao; a
  proibicao preserva o fluxo delta-merge. Divergencias que afetariam o corpus canonico, se
  relevantes, MUST aparecer apenas no relatorio.
- **FR-018**: O sistema MUST deixar cada feature reconciliada com um registro rastreavel da
  reconciliacao (data e resumo das alteracoes) dentro do proprio diretorio da feature, sem
  duplicar o relatorio completo, para que uma leitura futura saiba quando a documentacao
  foi confrontada com o codigo pela ultima vez. O registro MUST viver em arquivo proprio da
  feature (`reconciliation.md`), em formato append-only, e MUST ser atualizado somente
  quando a execucao alterar algum documento; execucao sem divergencia MUST NOT gravar nada
  (preserva FR-012/SC-003).
- **FR-019**: Ao citar codigo como evidencia (FR-008, FR-010), o sistema MUST NOT
  reproduzir valores sensiveis (chaves, tokens, senhas, credenciais) em documentos da
  feature, marcadores inline ou relatorio; a evidencia MUST ser referenciada apenas por
  `arquivo:linha` (ou `absent:<caminho>`), sem copiar o conteudo da linha quando ele
  contiver valor sensivel.

### Key Entities

- **Feature reconciliavel**: diretorio de documentacao de uma feature (ativa ou arquivada)
  com seus documentos (spec, plan, modelo de dados, contratos, quickstart, tasks).
- **Divergencia**: diferenca entre uma afirmacao verificavel da documentacao e o codigo
  atual; possui tipo (desatualizada, removida, nao documentada, possivel regressao, nao
  verificavel), documento e trecho afetados e evidencia no codigo.
- **Relatorio de reconciliacao**: resultado da execucao, por feature e consolidado, com as
  divergencias e a acao tomada em cada uma.
- **Registro de reconciliacao**: marca datada, dentro da feature, de quando ela foi
  confrontada com o codigo e do que mudou.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em 100% das execucoes, o conjunto de arquivos modificados contem apenas
  documentacao de feature (ativa ou arquivada) sob `docs/specs/`, com zero arquivos em
  `docs/specs/current/` e zero arquivos de codigo, teste, script ou configuracao alterados.
- **SC-002**: Ao reconciliar uma feature com divergencias conhecidas, 100% das divergencias
  plantadas em um projeto de teste sao detectadas e tratadas (atualizadas ou reportadas
  para decisao humana) e 0% dos trechos ja coerentes sao reescritos.
- **SC-003**: Uma segunda execucao sobre a mesma feature, sem novas mudancas no codigo,
  produz zero alteracoes em documentos.
- **SC-004**: Em 100% das alteracoes gravadas, o relatorio cita a evidencia no codigo
  (arquivo e trecho) que a justifica.
- **SC-005**: Uma pessoa mantenedora reconcilia uma feature em uma unica invocacao, sem
  precisar editar nenhum documento manualmente para concluir a reconciliacao, em pelo menos
  90% dos casos de divergencia por acerto pontual. "Acerto pontual" = divergencia dos tipos
  `stale`, `removed` ou `undocumented` (data-model) resolvivel com evidencia observavel;
  `possible-regression` e `unverifiable` nao entram no denominador, pois exigem decisao
  humana ou fonte inexistente por desenho (FR-007, FR-008).
- **SC-006**: Uma execucao `--all` sobre o portfolio processa 100% das features localizadas
  mesmo quando algumas falham, e o relatorio consolidado contabiliza todas.
- **SC-007**: Com `--dry-run`, zero arquivos do projeto sao modificados e o relatorio
  permite decidir sobre as alteracoes sem abrir nenhum documento.

## Assumptions

- **Nome da skill**: `reconcile-docs` (recomendado — o verbo "reconcile" ja aparece na
  descricao da skill vizinha `converge`, entao o sufixo `-docs` explicita o sentido
  inverso: documentacao segue o codigo). Alternativa: `sync-spec`.
- **Diferenca para `converge`**: `converge` adiciona tarefas para o codigo alcancar a spec;
  `reconcile-docs` atualiza a documentacao para acompanhar o codigo. As duas nao se
  substituem e podem ser usadas em sequencia (primeiro decidir o que e regressao, depois
  reconciliar o que e evolucao aceita).
- **Escopo de documentos**: `spec.md`, `plan.md`, `data-model.md`, `contracts/` e
  `quickstart.md` sao reconciliados. `research.md` e `checklists/` sao registro historico
  de decisoes e nao sao reescritos. `tasks.md` nao e reescrito; divergencias com tarefas
  marcadas como concluidas cujo codigo foi removido aparecem apenas no relatorio. O corpus
  `docs/specs/current/` nunca e reescrito (FR-017).
- **Modo padrao grava direto**: sem `--dry-run` as alteracoes sao gravadas na hora; o
  controle de versao do projeto e a rede de seguranca para reverter. Nenhuma confirmacao
  interativa por alteracao.
- **Identidade da feature**: o nome da feature e o do diretorio; diretorios arquivados
  ignoram o prefixo `AAAA-MM-DD-` na comparacao. Diretorios de arquivo sem prefixo
  (legados) tambem sao aceitos.
- **Modo standalone**: a skill funciona sem execucao autonoma (`/agente-00c`,
  `/feature-00c`) ativa e nao grava estado de orquestrador, como a skill `converge`.
- **Constitution do projeto opcional**: `docs/constitution.md` do projeto-alvo e insumo de
  FR-007, nao pre-requisito; sem ela a skill segue com aviso (ver Edge Cases).
- **Compreensao do codigo e semantica, nao mecanica**: a comparacao entre documentacao e
  codigo depende de leitura e julgamento; por isso o relatorio sempre expoe a evidencia
  para que a pessoa possa auditar.
- **Local de entrega**: nova skill no catalogo de skills do toolkit; por alterar a
  superficie publica do toolkit, exige entrada no CHANGELOG (Constitution I).

> Decisoes de infraestrutura: N/A (skill stateless, sem scheduling, sem rotacao de chaves,
> sem refresh de tokens, sem multi-replica, sem persistencia critica, sem aceite de retry).

## Delta Requirements

**Skip**: nova skill de documentacao, capacidade puramente nova que nao altera comportamento ativo do corpus canonico — feature-00c orchestrator, 2026-09-30
