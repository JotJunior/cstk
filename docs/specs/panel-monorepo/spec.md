# Feature Specification: Migração do painel para dentro do repositório único (monorepo)

**Feature**: `panel-monorepo`
**Created**: 2026-08-28
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Repositório único com histórico preservado (Priority: P1)

Como mantenedor do toolkit, quero que o projeto do painel (dashboard) passe a
viver dentro do mesmo repositório do toolkit, mantendo seu histórico de
commits completo e sua identidade de projeto autocontido (dependências,
documentação e governança próprias), para que mudanças que atravessam os dois
lados deixem de exigir duas pull requests, duas releases e uma ordem de merge
manual.

**Why this priority**: É o pré-requisito estrutural de tudo o mais — sem o
projeto do painel de fato incorporado ao repositório, nenhuma das demais
histórias tem o que testar. Sozinha, já entrega o valor central pedido
(coordenação em um lugar só) e é o MVP mínimo viável desta migração.

**Independent Test**: Clonar o repositório após a migração, confirmar que o
histórico de commits do painel (autoria, datas, mensagens) responde a
consultas de "por que esta linha existe", que o painel continua buildável e
testável como projeto autocontido, e que nenhum arquivo antes rastreado pelo
painel foi perdido no processo.

**Acceptance Scenarios**:

1. **Given** o repositório unificado após a migração, **When** um mantenedor
   consulta o histórico de qualquer arquivo do painel, **Then** a autoria,
   as datas e as mensagens de commit originais continuam disponíveis, sem
   perda de contexto.
2. **Given** o repositório unificado, **When** um mantenedor executa a suíte
   de testes própria do painel, **Then** ela roda e passa como projeto
   autocontido, sem depender de nenhuma configuração da raiz do repositório.
3. **Given** o repositório unificado, **When** um mantenedor executa a suíte
   de testes própria do restante do repositório, **Then** ela roda e passa
   sem nenhuma regressão introduzida pela presença do painel.
4. **Given** as duas governanças de projeto (a da raiz e a do painel)
   coexistindo no mesmo repositório, **When** o mecanismo de detecção de
   conflito de governança é executado, **Then** nenhum conflito falso é
   reportado — cada uma permanece válida no escopo do seu próprio projeto.
5. **Given** os arquivos de configuração do painel que estavam rastreados
   antes da migração, **When** a migração é concluída, **Then** o mesmo
   conjunto de arquivos permanece rastreado, mesmo que a raiz do repositório
   unificado normalmente não rastreie arquivos dessa categoria.

---

### User Story 2 - Distribuição correta do pacote do painel (Priority: P2)

Como operador que atualiza sua instalação do toolkit, quero que o comando que
baixa e inicia o painel sempre obtenha o pacote correto — mesmo quando a
mesma release publica mais de um pacote candidato — para que eu nunca receba
silenciosamente o componente errado com um carimbo de integridade que sugere
sucesso.

**Why this priority**: É o risco central desta migração. Hoje a lógica de
seleção de pacote é posicional ("o primeiro pacote completo encontrado"), e
passar a publicar dois pacotes na mesma release (o do restante do toolkit e o
do painel) faz essa lógica escolher o pacote errado, confirmar a integridade
dele com sucesso, e só falhar tarde — sem deixar rastro de que a verificação
recaiu sobre o pacote errado. Sem esta história corrigida, a User Story 1 cria
justamente as condições que disparam essa falha silenciosa.

**Independent Test**: Publicar uma release de teste contendo os dois pacotes
candidatos (o do restante do toolkit e o do painel) e confirmar que o comando
de atualização/serviço sempre seleciona e baixa o pacote do painel, com a
verificação de integridade recaindo sobre o pacote correto.

**Acceptance Scenarios**:

1. **Given** uma release que publica tanto o pacote do restante do toolkit
   quanto o pacote do painel, **When** o operador executa o comando de
   atualização/serviço do painel, **Then** o pacote efetivamente baixado,
   verificado e extraído é o do painel, nunca o do restante do toolkit.
2. **Given** uma release que publica apenas o pacote do restante do toolkit
   (sem pacote de painel, ex. uma correção pontual), **When** o operador
   executa o mesmo comando, **Then** o sistema reconhece a ausência do
   pacote do painel como tal, em vez de selecionar por engano o pacote
   errado.
3. **Given** um pacote do painel baixado e com checksum conferido, **When** a
   extração revela que o conteúdo esperado do painel não está presente,
   **Then** o sistema trata isso como falha de seleção/integridade — o
   sucesso anterior da conferência de checksum não é reportado como
   confirmação suficiente de que o pacote correto foi obtido.
4. **Given** o pacote do painel publicado na release, **When** ele é
   extraído seguindo a convenção padrão de extração de pacote único do
   sistema, **Then** os arquivos de manifesto de dependências e de trava de
   versões do painel ficam presentes na raiz da árvore extraída.
5. **Given** a suíte de testes automatizados que cobre a lógica de seleção
   de pacote, **When** ela é executada após esta migração, **Then** todos os
   cenários pré-existentes continuam passando sem alteração, e um cenário
   novo — release com os dois pacotes candidatos — confirma a seleção
   correta do pacote do painel.
6. **Given** a origem remota de onde o pacote do painel é buscado, **When**
   um operador precisa apontar para uma origem alternativa (ex. um fork ou
   ambiente de teste), **Then** existe um mecanismo de sobrescrita
   equivalente ao já disponível para as demais origens de atualização do
   sistema, e essa origem alternativa passa pela mesma validação de host
   confiável já aplicada às demais.

---

### User Story 3 - Versionamento unificado e documentação consistente (Priority: P3)

Como mantenedor, quero que o painel deixe de ter uma numeração de versão
independente e passe a acompanhar a mesma sequência de releases do restante
do repositório, com toda a documentação que hoje descreve a origem do painel
atualizada, para eliminar a duplicação de fatos entre os dois projetos e
qualquer referência desatualizada à distribuição antiga.

**Why this priority**: Consolida o valor da User Story 1 — sem versão e
documentação unificadas, o repositório único ainda se comportaria, aos olhos
de quem o consome, como dois projetos com ciclos de release e fontes de
verdade divergentes.

**Independent Test**: Após um ciclo de release completo, confirmar que a
versão publicada do painel corresponde à mesma versão do restante do
repositório, e que nenhum documento do sistema ainda descreve o painel como
distribuído a partir de um repositório separado.

**Acceptance Scenarios**:

1. **Given** um novo ciclo de release do repositório unificado, **When** a
   release é publicada, **Then** a versão do painel e a versão do restante
   do repositório avançam juntas, como uma única sequência.
2. **Given** o painel internamente organizado em mais de um módulo/pacote
   próprio, **When** uma release é publicada, **Then** todos esses módulos
   internos refletem a mesma versão da release, sem divergência entre eles.
3. **Given** a documentação do sistema que descreve de onde o painel é
   obtido, **When** revisada após a migração, **Then** nenhuma página ainda
   afirma que o painel vem de um repositório externo separado.

---

### User Story 4 - Transição segura para instalações existentes (Priority: P4)

Como operador com uma instalação existente do toolkit (painel na versão
anterior à migração), quero ser avisado explicitamente de que o painel mudou
de lugar e o que fazer a respeito, para que minha instalação não fique presa
silenciosamente na última versão do painel antes da migração.

**Why this priority**: É a história de menor risco técnico, mas protege
quem já usa o sistema hoje — sem ela, a migração das User Stories 1-3 teria
sucesso técnico às custas de instalações existentes ficarem congeladas sem
qualquer sinal de que isso aconteceu.

**Independent Test**: Simular uma instalação na versão anterior à migração,
executar o fluxo de atualização padrão contra o repositório original do
painel (ainda não arquivado, mas já com a release de transição publicada), e
confirmar que a instalação recebe um aviso explícito e visível sobre a
mudança de local e a ação necessária.

**Acceptance Scenarios**:

1. **Given** uma instalação na última versão do painel anterior à migração,
   **When** o operador executa o fluxo de atualização padrão contra o
   repositório original do painel, **Then** ele recebe uma comunicação
   explícita informando a mudança de local e a ação necessária para migrar.
2. **Given** a release de transição publicada no repositório original do
   painel, **When** o repositório unificado já publicou e teve verificada a
   distribuição do painel embutido (User Story 2), **Then** somente então o
   repositório original do painel é desativado/arquivado — nunca antes.
3. **Given** uma execução de pipeline iniciada a partir do subdiretório do
   painel após a migração, **When** o histórico de execuções é consultado,
   **Then** ele continua sendo resolvido e associado à identidade de projeto
   do painel usada nas 7 execuções anteriores à migração, sem órfãos nem
   duplicação de identidade.

---

### Edge Cases

- O que acontece quando uma release publica apenas o pacote do restante do
  toolkit, sem pacote de painel (ex. uma correção urgente que não toca o
  painel)? O sistema reconhece a ausência do pacote do painel como tal, sem
  selecionar por engano outro pacote em seu lugar (coberto pela Acceptance
  Scenario 2 da User Story 2).
- O que acontece com releases marcadas como pré-lançamento (prerelease)? O
  comportamento existente do sistema de não considerar pacotes de
  pré-lançamento como candidatos válidos é preservado sem alteração — uma
  eventual pré-lançamento do restante do toolkit não expõe, por
  consequência, um pacote de painel correspondente. Este é um comportamento
  aceito, não uma lacuna desta migração.
- O que acontece com uma instalação que executa o fluxo de atualização
  padrão durante a janela entre a migração ser concluída no repositório
  unificado e essa correção efetivamente chegar a ela? Até que a atualização
  seja aplicada, a instalação continua operando com a lógica de seleção
  anterior — risco aceito e mitigado pela obrigatoriedade da release de
  transição (User Story 4, Acceptance Scenario 1) antes do arquivamento do
  repositório original.
- O que acontece se alguém tenta executar uma feature deste pipeline a
  partir da raiz do repositório unificado esperando que a governança do
  painel se aplique (ou vice-versa)? Cada subárvore de projeto usa apenas a
  sua própria governança; nenhuma mistura ocorre (coberto pela Acceptance
  Scenario 4 da User Story 1).
- O que acontece se o repositório original do painel for arquivado antes de
  a distribuição do painel embutido no repositório unificado estar
  publicada e verificada? Esta ordem é um requisito explícito (User Story
  4, Acceptance Scenario 2) — o arquivamento nunca precede a verificação.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST preservar o histórico completo de commits do
  projeto do painel (autoria, datas, mensagens) ao incorporá-lo ao
  repositório unificado, de modo que consultas de histórico por arquivo
  continuem respondendo por que cada linha existe.
- **FR-002**: O sistema MUST manter o projeto do painel como um subdiretório
  autocontido do repositório unificado — com seu próprio manifesto de
  dependências, sua própria documentação de especificações e sua própria
  governança — em vez de fundi-lo à estrutura do projeto da raiz.
- **FR-003**: O sistema MUST preservar, após a migração, o mesmo conjunto de
  arquivos de configuração do painel que estava rastreado antes dela, mesmo
  quando a raiz do repositório unificado normalmente não rastreia arquivos
  dessa categoria.
- **FR-004**: O sistema MUST resolver qualquer colisão de nome entre
  arquivos/diretórios de topo dos dois projetos (documentação, changelog,
  guia de contribuição, scripts, automação de CI) de modo que os arquivos de
  cada projeto permaneçam associados a esse projeto após a migração, sem
  sobrescrita silenciosa de nenhum dos lados.
- **FR-005**: O sistema MUST desativar a automação de publicação de release
  independente do painel assim que o processo de release dele passar a ser
  absorvido pelo processo de release do repositório unificado, para evitar
  publicação duplicada ou conflitante.
- **FR-006**: O sistema MUST preservar o histórico de mudanças do painel
  anterior à migração como um registro histórico congelado dentro do seu
  próprio subdiretório, ao mesmo tempo em que estabelece um único histórico
  de mudanças contínuo para o repositório unificado a partir da migração.
- **FR-007**: O sistema MUST NOT reportar um conflito de governança entre os
  dois projetos — o mecanismo de detecção de conflito existente MUST
  reconhecer o subdiretório do painel como raiz de um projeto independente,
  não como um artefato de nível de feature.
- **FR-008**: Ao selecionar, dentro de uma release que publica mais de um
  pacote candidato, qual pacote corresponde ao componente do painel, o
  sistema MUST identificar o pacote correto por correspondência inequívoca
  de nome, e MUST NOT selecioná-lo apenas pela ordem em que aparece entre os
  pacotes disponíveis.
- **FR-009**: Quando um pacote do painel é baixado e tem sua integridade
  (checksum) confirmada, mas a extração revela que o conteúdo esperado do
  painel não está de fato presente, o sistema MUST tratar isso como falha de
  seleção/integridade — a confirmação de checksum anterior MUST NOT ser
  reportada como confirmação suficiente de que o pacote correto foi obtido.
- **FR-010**: O pacote do painel publicado em uma release MUST ser
  estruturado de forma que, seguindo a convenção padrão de extração de
  pacote único de topo do sistema, os arquivos de manifesto de dependências
  e de trava de versões do painel fiquem presentes na raiz da árvore
  extraída.
- **FR-011**: O sistema MUST publicar o pacote do painel como parte do mesmo
  processo de release (mesma release versionada) do restante do repositório
  unificado, em vez de por meio de um pipeline de publicação separado.
- **FR-012**: O sistema MUST oferecer um mecanismo de sobrescrita para a
  origem remota usada para buscar releases do painel, equivalente ao
  mecanismo de sobrescrita já disponível para as demais origens de
  atualização do sistema — eliminando a assimetria hoje existente entre
  diferentes fluxos de atualização.
- **FR-013**: Qualquer origem remota alternativa usada por meio do mecanismo
  de sobrescrita da FR-012 MUST passar pela mesma validação de host
  confiável já aplicada às demais origens remotas de download do sistema.
- **FR-014**: A suíte de testes automatizados que cobre a lógica de seleção
  de pacote MUST incluir um cenário em que uma release publica os dois
  pacotes candidatos (restante do toolkit e painel) e confirma a seleção
  correta do pacote do painel, e todos os cenários de seleção de pacote
  pré-existentes MUST continuar passando sem alteração de comportamento.
- **FR-015**: O sistema MUST fazer a numeração de versão de release do
  painel avançar em conjunto com a numeração de versão do restante do
  repositório unificado, substituindo a série de versão independente que o
  painel tinha antes da migração.
- **FR-016**: Quando o painel for internamente organizado em mais de um
  módulo/pacote próprio, o sistema MUST manter as versões desses módulos em
  lockstep com a versão da release do repositório unificado no momento de
  cada release.
- **FR-017**: Toda documentação do sistema que descreve o painel como
  distribuído a partir de um repositório externo separado MUST ser
  atualizada para refletir que ele passa a ser distribuído como parte das
  releases do próprio repositório unificado.
- **FR-018**: Antes de o repositório original do painel ser
  desativado/arquivado, o sistema MUST ter publicado nele uma release de
  transição comunicando explicitamente a mudança de local e a ação
  necessária (atualização) para o operador continuar recebendo versões
  atuais do painel.
- **FR-019**: O sistema MUST NOT desativar/arquivar o repositório original do
  painel antes de a distribuição do painel embutido no repositório unificado
  estar publicada e ter sua correta seleção/integridade verificada — para
  que nenhuma instalação fique, durante a transição, sem nenhum caminho de
  atualização funcional.
- **FR-020**: O sistema MUST preservar a identidade de projeto própria do
  painel no seu armazenamento de histórico/conhecimento entre execuções, de
  modo que uma execução de pipeline iniciada a partir do subdiretório do
  painel continue registrando e recuperando histórico sob essa identidade,
  distinta da identidade do projeto da raiz.
- **FR-021**: Para execuções de pipeline restritas ao subdiretório do painel,
  os arquivos de acompanhamento/estado de execução MUST permanecer isolados
  ao escopo desse subdiretório, e MUST NOT ser resolvidos como se
  pertencessem ao escopo do projeto da raiz (nem o inverso).

> Decisões de infraestrutura: N/A (esta feature é uma migração de
> repositório/pipeline de release; não introduz scheduler, criptografia de
> dados persistidos, refresh de token externo, ou lock multi-pod).

### Key Entities

- **Pacote de release**: arquivo baixável publicado dentro de uma release
  versionada; distinguido por a qual componente corresponde (restante do
  toolkit ou painel) e acompanhado de um checksum de integridade.
- **Identidade de projeto**: nome lógico sob o qual o histórico de execuções
  e as especificações de um projeto são rastreados, independente da
  localização desse projeto dentro do repositório unificado.
- **Aviso de transição**: comunicação publicada na release final do
  repositório original do painel, informando a mudança de local e a ação
  necessária ao operador.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Em 100% dos cenários de teste que exercitam uma release
  publicando os dois pacotes candidatos, o operador que executa o comando de
  atualização/serviço do painel recebe o pacote do painel — nunca o do
  restante do toolkit.
- **SC-002**: 100% do histórico de commits do painel anterior à migração
  (autoria, data, mensagem) permanece consultável após a migração.
- **SC-003**: Zero arquivos de configuração do painel antes rastreados são
  perdidos (deixam de estar rastreados) como resultado da migração.
- **SC-004**: A suíte de testes automatizados existente do repositório
  unificado (gate da automação de release) passa integralmente, sem nenhuma
  regressão introduzida pela migração.
- **SC-005**: A suíte de testes automatizados própria do painel passa
  integralmente, sem nenhuma regressão introduzida pela migração.
- **SC-006**: 100% das instalações que executam o fluxo de atualização
  contra o repositório original do painel após a publicação da release de
  transição recebem um aviso explícito e visível da mudança de local — nunca
  uma continuidade silenciosa sem sinal.
- **SC-007**: Uma execução de pipeline iniciada a partir do subdiretório do
  painel resolve corretamente seu histórico de execuções anterior à
  migração, com zero entradas órfãs ou duplicadas de identidade de projeto.
- **SC-008**: Zero documentos do sistema, após a migração, ainda descrevem o
  painel como distribuído a partir de um repositório externo separado.

## Delta Requirements

### Capability: serve-integrity

#### MODIFIED

- **FR-008**: Ao selecionar, dentro de uma release que publica mais de um
  pacote candidato, qual pacote corresponde ao componente do painel, o
  sistema MUST identificar o pacote correto por correspondência inequívoca
  de nome, e MUST NOT selecioná-lo apenas pela ordem em que aparece entre os
  pacotes disponíveis.
- **FR-009**: Quando um pacote do painel é baixado e tem sua integridade
  (checksum) confirmada, mas a extração revela que o conteúdo esperado do
  painel não está de fato presente, o sistema MUST tratar isso como falha de
  seleção/integridade — a confirmação de checksum anterior MUST NOT ser
  reportada como confirmação suficiente de que o pacote correto foi obtido.

### Capability: trusted-release-hosts

#### MODIFIED

- **FR-013**: Qualquer origem remota alternativa usada por meio do mecanismo
  de sobrescrita da FR-012 (busca de releases do painel) MUST passar pela
  mesma validação de host confiável já aplicada às demais origens remotas de
  download do sistema.
