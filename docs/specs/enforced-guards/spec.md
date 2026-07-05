# Feature Specification: enforced-guards

**Feature**: `enforced-guards`
**Created**: 2026-07-05
**Status**: Implemented (aguardando publicação de release) — FASE 1-5 concluídas (tasks.md); ver CHANGELOG.md [Unreleased]

## Visao geral

O toolkit ja possui mecanismos de guarda para execucoes autonomas
(`agente-00c`/`feature-00c`): uma blocklist/whitelist de comandos Bash
perigosos e uma verificacao de checksum para pacotes baixados pelo painel
web. Hoje, porem, essas guardas sao **advisory**: dependem de a propria
prosa do orquestrador "lembrar" de invocar a checagem antes de rodar um
comando, e de o fluxo de download "avisar" quando nao consegue confirmar
integridade — mas prosseguir mesmo assim. Uma instrucao manipulada
(injecao de prompt), um lapso do modelo, ou simplesmente a ausencia do
aviso sendo notada a tempo, e suficiente para que a guarda nao produza
efeito nenhum, mesmo com o mecanismo de deteccao correto e funcionando.

Esta feature fecha essa lacuna tornando a protecao **enforced**: a
validacao passa a acontecer em um ponto que nao depende do orquestrador
lembrar de chama-la, e um download sem integridade confirmada deixa de
prosseguir silenciosamente. O escopo cobre tres frentes independentes:

1. Interceptacao automatica de comandos Bash executados por uma execucao
   autonoma, validados contra as mesmas regras ja existentes, antes de
   rodarem — nao depois, nao a criterio da prosa do orquestrador.
2. Verificacao de integridade obrigatoria (fail-closed) antes de o painel
   web local executar codigo baixado de um release.
3. Restricao dos hosts aceitos como origem de download tambem nos fluxos
   de instalacao/atualizacao do proprio CLI, hoje limitados apenas a uma
   checagem de esquema (https/file).

Fora do escopo desta feature: revisao do volume/"dieta" de tarefas dos
orquestradores autonomos, e assinatura criptografica de artefatos de
release (ambos citados na secao Out of Scope).

> Decisoes de infraestrutura: **N/A** — a feature nao introduz scheduling,
> sessao persistente, refresh de token externo, rotacao de chaves ou
> mutex multi-processo. E enforcement de seguranca local e sincrono
> (intercepta uma chamada, ou verifica um arquivo antes de usa-lo).

## Clarifications

### Session 2026-07-05

- Q: Quando o mecanismo de checagem (bash-guard.sh) falha internamente ao
  processar um comando (erro do proprio script, nao uma violacao de regra
  conhecida), o hook deve BLOQUEAR o comando (fail-closed) ou PERMITIR com
  aviso (fail-open)? → A: Fail-closed — o hook bloqueia o comando quando o
  mecanismo de checagem falha internamente, tratando a falha como
  equivalente a "comando nao autorizado"; o bloqueio expoe motivo
  distinguivel de um bloqueio por violacao de regra, para diagnostico
  rapido pelo operador (mesma logica de FR-009/FR-015 aplicada a US1;
  Principio VI da constitution).
- Q: Uma vez provisionado no projeto-alvo, o hook de interceptacao
  automatica (PreToolUse) deve validar TODO comando Bash rodado ali
  (inclusive sessoes interativas comuns do operador), ou apenas comandos
  originados de uma execucao ativa de agente-00c/feature-00c? (FR-006;
  bloqueio block-001, resolvido via decisao dec-012) → A: Opcao A — o hook
  valida Bash apenas quando ha execucao ativa de agente-00c/feature-00c
  (deteccao via presenca de state/lock); sessoes manuais/interativas do
  operador no mesmo projeto ficam fora do escopo desta feature.

## User Scenarios & Testing

### User Story 1 - Comando Bash perigoso e barrado mesmo sem a instrucao pedir a checagem (Priority: P1)

Como operador rodando `agente-00c` ou `feature-00c` de forma autonoma em
um projeto, eu quero que todo comando Bash disparado durante a execucao
seja validado contra as regras de seguranca conhecidas (comandos
destrutivos, rede fora de lista permitida, etc.) **antes** de rodar,
independentemente de a instrucao corrente do orquestrador ter pedido essa
validacao explicitamente, para que uma instrucao manipulada, um lapso do
modelo, ou uma condicao de borda nao resultem em um comando perigoso
executado de fato.

**Why this priority**: e o nucleo da feature. Hoje a mesma logica de
deteccao existe mas so produz efeito se a prosa do orquestrador decidir
invoca-la — ou seja, a garantia de seguranca depende do comportamento do
modelo em cada execucao, nao de um mecanismo. Sem esta story, as outras
duas seriam enforced apenas nominalmente.

**Independent Test**: configurar uma execucao autonoma cuja instrucao
corrente (deliberadamente, para teste) NAO menciona rodar a checagem
antes de um comando Bash que viola uma regra conhecida (ex: um `git push`
ou um `rm -rf` fora de area temporaria). Confirmar que o comando e barrado
mesmo assim, e que a tentativa fica registrada de forma revisavel. Este
teste passa independentemente de US2 ou US3 estarem implementadas.

**Acceptance Scenarios**:

1. **Given** uma execucao autonoma em andamento em um projeto onde a
   protecao foi instalada, **When** o orquestrador emite um comando Bash
   que viola uma regra ja conhecida de bloqueio, **Then** o comando NAO
   chega a executar, e o motivo do bloqueio fica visivel para o
   orquestrador continuar a execucao de outra forma.
2. **Given** a mesma execucao, **When** o orquestrador emite um comando
   Bash que nao viola nenhuma regra, **Then** o comando executa
   normalmente, sem atraso perceptivel nem passo manual adicional.
3. **Given** um projeto onde a instalacao da protecao ainda esta
   desatualizada (versao anterior a esta feature), **When** uma execucao
   autonoma roda um comando perigoso, **Then** o sistema continua
   contando apenas com a camada advisory ja existente (comportamento
   atual) ate que o projeto seja atualizado — sem regressao silenciosa,
   mas tambem sem alegar uma garantia que nao esta ativa.

---

### User Story 2 - Painel web local recusa executar pacote sem integridade confirmada (Priority: P1)

Como operador que roda o painel web local (`cstk serve`), eu quero que o
sistema jamais inicie a partir de um pacote baixado cuja integridade nao
foi confirmada, a menos que eu tenha decidido explicitamente aceitar o
risco para aquela execucao, para que um download comprometido ou
adulterado no meio do caminho nao seja executado silenciosamente so
porque a verificacao "nao tinha como confirmar".

**Why this priority**: hoje a ausência de dado de integridade e tratada
como "prosseguir com aviso" — ou seja, o caminho de falha (sem checksum
disponivel) e indistinguivel, no resultado pratico, do caminho de
sucesso (checksum conferido). Isso e uma janela de execucao de codigo nao
verificado por padrao.

**Independent Test**: simular uma atualizacao do painel em que o dado de
integridade nao esta disponivel para download. Confirmar que `cstk serve`
nao prossegue automaticamente; confirmar em seguida que existe um caminho
explicito para o operador aceitar o risco conscientemente, e que essa
decisao fica registrada. Testavel isoladamente de US1/US3.

**Acceptance Scenarios**:

1. **Given** um release do painel cujo dado de integridade esperado NAO
   esta disponivel para download, **When** o operador roda `cstk serve`
   (ou uma atualizacao do painel), **Then** o sistema NAO inicia a partir
   do pacote baixado por padrao, e apresenta ao operador uma decisao
   explicita a tomar (aceitar o risco ou abortar) em vez de um aviso que
   apenas passa por sozinho.
2. **Given** o mesmo cenario, **When** o operador decide explicitamente
   prosseguir mesmo sem verificacao, **Then** o sistema prossegue e essa
   decisao fica registrada de forma revisavel posteriormente.
3. **Given** um release cujo dado de integridade esperado ESTA disponivel
   mas nao confere com o pacote baixado, **When** `cstk serve` roda,
   **Then** o sistema recusa prosseguir, sem oferecer bypass silencioso
   (comportamento de bloqueio em caso de divergencia ja existe hoje e
   deve ser preservado).

---

### User Story 3 - Instalacao/atualizacao do CLI so aceita hosts confiaveis (Priority: P2)

Como operador que instala ou atualiza o `cstk` a partir de uma URL
remota, eu quero que o download de artefatos de release seja restrito a
uma lista de hosts conhecidos e confiaveis (nao apenas ao esquema
https/file), para que uma URL apontando para um host arbitrario nao seja
aceita so por nao usar `http://`.

**Why this priority**: fecha uma lacuna real mas de exposicao mais
estreita que US1/US2 — a checagem de esquema ja existente ja neutraliza o
vetor mais grosseiro (downgrade para `http://`); a lista de hosts
confiaveis e uma camada adicional contra um host https arbitrario nao
esperado.

**Independent Test**: tentar um `install`/`self-update` apontando para uma
URL https valida mas cujo host nao pertence a lista de hosts confiaveis
conhecidos do toolkit. Confirmar rejeicao antes de qualquer transferencia
de dado, com diagnostico claro. Confirmar separadamente que o fluxo de
desenvolvimento local via `file://` continua funcionando sem exigir
allowlist de host (nao ha host num caminho local). Testavel isoladamente
de US1/US2.

**Acceptance Scenarios**:

1. **Given** um operador executando `cstk install --from <URL https>` ou
   `cstk self-update --from <URL https>` apontando para um host fora da
   lista de hosts confiaveis, **When** o comando roda, **Then** o sistema
   rejeita antes de baixar qualquer dado, com mensagem clara indicando o
   motivo (host nao confiavel).
2. **Given** a mesma operacao apontando para um host da lista de
   confiaveis (fluxo padrao de release do proprio toolkit), **When** o
   comando roda, **Then** o download prossegue normalmente, sem exigir
   nenhuma acao manual nova do operador.
3. **Given** o fluxo de desenvolvimento local documentado (`--from
   file://...`), **When** o comando roda, **Then** o comportamento
   permanece identico ao atual — a checagem de host confiavel se aplica
   somente a URLs remotas, nunca a caminhos locais.

### Edge Cases

- O que acontece quando o proprio mecanismo de checagem falha
  internamente (erro, dependencia ausente) ao processar um comando Bash?
  O sistema bloqueia por seguranca (fail-closed), nunca permite por
  disponibilidade — ver FR-007.
- O que acontece quando a protecao via interceptacao automatica (US1)
  ainda nao foi instalada/atualizada em um projeto-alvo especifico? A
  camada advisory ja existente (chamada pela propria prosa do
  orquestrador) permanece como rede de seguranca secundaria — nao e
  removida por esta feature (ver FR de defesa em profundidade).
- O que acontece quando o operador roda um comando Bash fora do contexto
  de uma execucao autonoma (sessao interativa comum no mesmo projeto)? Ele
  nao e interceptado pela camada enforced desta feature — o escopo e
  restrito a comandos originados de uma execucao ativa de
  agente-00c/feature-00c (FR-006, resolvido via block-001/dec-012); o uso
  manual cotidiano do operador permanece inalterado.
- O que acontece se, apos esta feature, o repositorio de onde o painel
  web e baixado passar a publicar o dado de integridade que hoje nao
  publica? O sistema passa a verificar normalmente (caminho "verificado"
  de US2), sem exigir mudanca de comportamento adicional.
- O que acontece com instalacoes/atualizacoes que usam origem local
  (`file://`, fluxo de desenvolvimento) quanto a allowlist de hosts (US3)?
  Nao ha host para checar — o fluxo local continua funcionando sem
  restricao nova (ver Acceptance Scenario 3 de US3).

## Requirements

### Functional Requirements

#### Interceptacao enforced de Bash (US1)

- **FR-001**: O sistema MUST interceptar todo comando Bash emitido
  durante uma execucao autonoma (`agente-00c`/`feature-00c`) em um ponto
  anterior a execucao do comando, validando-o contra o mesmo conjunto de
  regras de bloqueio e de permissao de rede ja em vigor hoje.
- **FR-002**: Quando um comando viola as regras, o sistema MUST impedir
  sua execucao e MUST expor um motivo claro e acionavel, equivalente em
  qualidade ao que a checagem manual ja produz hoje.
- **FR-003**: Quando um comando nao viola nenhuma regra, o sistema MUST
  permitir sua execucao sem exigir passo manual adicional do operador ou
  do orquestrador, e sem atraso perceptivel no fluxo normal.
- **FR-004**: A interceptacao MUST ser provisionada automaticamente pelo
  fluxo normal de instalacao/atualizacao do toolkit em um projeto-alvo —
  o operador MUST NOT precisar de um passo manual nao-documentado para
  ativa-la depois de atualizar o toolkit.
- **FR-005**: As invocacoes advisory ja existentes (a propria prosa dos
  orquestradores chamando a checagem antes de comandos sensiveis) MUST
  permanecer em vigor apos esta feature — a interceptacao automatica e
  uma camada adicional de defesa em profundidade, nao uma substituicao
  que remove a camada atual.
- **FR-006**: A interceptacao automatica MUST validar comandos Bash
  apenas quando originados de uma execucao ativa de
  `agente-00c`/`feature-00c` (deteccao via presenca de state/lock da
  execucao) — sessoes interativas comuns do operador no mesmo
  projeto-alvo MUST NOT ser afetadas ou interceptadas por esta feature,
  mesmo apos a protecao estar provisionada (escopo restrito, opcao A;
  resolvido via bloqueio block-001/decisao dec-012).
- **FR-007**: Quando o proprio mecanismo de checagem falhar internamente
  ao processar um comando (erro inesperado do script de checagem,
  dependencia ausente, bug — distinto de uma violacao de regra
  conhecida), o sistema MUST BLOQUEAR o comando por padrao (fail-closed),
  tratando a falha do mecanismo como equivalente a "comando nao
  autorizado", nunca como passagem livre. O bloqueio MUST expor um motivo
  distinguivel de um bloqueio por violacao de regra (identificando que
  foi o proprio mecanismo de checagem que falhou), para diagnostico
  rapido pelo operador.

#### Verificacao de integridade fail-closed (US2)

- **FR-008**: O sistema MUST NOT iniciar a execucao de codigo do painel
  web local a partir de um pacote baixado cuja integridade nao foi
  confirmada, exceto quando o operador tiver optado explicitamente por
  prosseguir sem essa confirmacao para aquela execucao especifica.
- **FR-009**: Quando o dado necessario para confirmar integridade nao
  esta disponivel para download, o sistema MUST apresentar isso como uma
  decisao explicita a ser tomada (aceitar o risco ou interromper) — MUST
  NOT tratar a ausencia do dado como equivalente a uma verificacao
  bem-sucedida, nem prosseguir apenas com um aviso informativo como
  acontece hoje.
- **FR-010**: Quando a integridade confirmada diverge do pacote baixado,
  o sistema MUST recusar prosseguir, sem oferecer contorno silencioso
  (este comportamento ja existe hoje e MUST ser preservado pelo escopo
  desta feature — nenhum caminho de codigo pode tratar divergencia ou
  ausencia de verificacao como sucesso silencioso).
- **FR-011**: Uma decisao explicita do operador de prosseguir sem
  integridade confirmada MUST ficar registrada de forma revisavel
  posteriormente (o que foi executado sem verificacao e quando).

#### Allowlist de hosts em install/self-update (US3)

- **FR-012**: `install` e `self-update` MUST validar o host de origem de
  qualquer URL remota de download contra uma lista mantida de hosts
  confiaveis, adicionalmente a checagem de esquema (https/file) ja
  existente.
- **FR-013**: Uma tentativa de download cujo host nao pertence a lista de
  hosts confiaveis MUST ser rejeitada antes de qualquer transferencia de
  dado, com diagnostico claro (padrao de qualidade equivalente a
  rejeicao de `http://` ja existente).
- **FR-014**: A checagem de host confiavel MUST NOT se aplicar a origens
  locais (`file://`) — o fluxo de desenvolvimento local documentado do
  toolkit MUST continuar funcionando sem exigir presenca em allowlist de
  host.

#### Defesa em profundidade e degradacao (Principio V / auditabilidade)

- **FR-015**: Nenhuma das tres frentes desta feature MUST remover ou
  enfraquecer uma checagem de seguranca ja existente — todas sao camadas
  adicionadas sobre o comportamento atual (blocklist/whitelist,
  verificacao de checksum, rejeicao de `http://`).
- **FR-016**: Toda vez que a interceptacao enforced (US1) bloquear um
  comando, ou que uma verificacao de integridade (US2) resultar em
  bypass explicito, ou que um download for rejeitado por host fora da
  allowlist (US3), o evento MUST ficar registrado de forma auditavel e
  revisavel — nao apenas visivel momentaneamente em terminal (Principio
  I, Auditabilidade total).
- **FR-017**: A adocao desta feature por um projeto-alvo MUST ocorrer
  atraves do fluxo normal de instalacao/atualizacao do toolkit ja usado
  para outras capacidades (mesmo modelo de distribuicao existente) — MUST
  NOT introduzir um segundo mecanismo de distribuicao paralelo.

### Key Entities

- **GuardHookRegistration**: a configuracao de interceptacao provisionada
  em um projeto-alvo (ou globalmente) que liga a chamada de uma
  ferramenta Bash a validacao automatica das regras de bloqueio e de
  rede, antes da execucao.
- **EnforcementDecisionLog**: o registro auditavel de um comando Bash
  interceptado pela camada enforced (permitido ou bloqueado),
  distinguivel das invocacoes advisory ja existentes.
- **IntegrityVerificationOutcome**: o resultado de uma tentativa de
  confirmar a integridade de um pacote baixado pelo painel web —
  verificado, nao-verificavel (sem dado disponivel) ou divergente — e se
  um bypass explicito foi usado.
- **TrustedHostAllowlist**: o conjunto mantido de hosts aceitos como
  origem legitima de artefatos de release para `install`/`self-update`,
  distinto (mas com o mesmo espirito) da lista de hosts permitidos por
  execucao ja usada pelas execucoes autonomas.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um comando Bash que viola uma regra de seguranca conhecida,
  emitido durante uma execucao autonoma, e barrado antes de rodar em
  100% dos casos testados — inclusive quando a instrucao corrente do
  orquestrador nao pede a checagem explicitamente.
- **SC-002**: Zero execucoes do painel web local a partir de um pacote
  com integridade nao confirmada sem uma decisao explicita e registrada
  do operador — em 100% das execucoes onde o dado de integridade nao
  esta disponivel ou diverge.
- **SC-003**: 100% das tentativas de download por `install`/`self-update`
  apontando para um host fora da lista de confiaveis sao rejeitadas antes
  de qualquer transferencia de dado.
- **SC-004**: Os fluxos legitimos ja documentados do toolkit (instalacao
  local via `file://`, atualizacao via release oficial, uso normal de
  Bash por execucoes autonomas dentro das regras) continuam completando
  com sucesso em 100% das checagens de regressao, sem exigir passo manual
  novo do operador.
- **SC-005**: Todo comando bloqueado pela interceptacao enforced e toda
  decisao explicita de bypass de integridade ficam revisaveis pelo
  operador depois do fato, em 100% dos casos (nao apenas visiveis
  momentaneamente).
- **SC-006**: Apos uma unica instalacao/atualizacao do toolkit em um
  projeto-alvo, 100% das execucoes autonomas subsequentes nesse projeto
  tem a interceptacao ativa, sem acao manual adicional por execucao.

## Out of Scope

- Reducao do volume/"dieta" de tarefas ou de escopo operacional dos
  orquestradores autonomos (item D4, tratado como iniciativa separada).
- Assinatura criptografica de artefatos de release (code signing) — fica
  registrada como decisao a ser avaliada durante `/plan`, nao como
  requisito funcional desta spec.
- Definicao da lista concreta e inicial de hosts confiaveis (dominios
  exatos) — e um dado factual sobre infraestrutura externa que precisa
  vir de fonte verificavel (documentacao oficial do host de releases
  usado, ou observacao direta), a ser resolvido durante `/plan`/research,
  nao suposto aqui.
- Mudanca na logica interna de deteccao de comandos perigosos ou de
  verificacao de checksum ja existente — o que muda nesta feature e
  **quem garante que a checagem roda**, nao as regras de deteccao em si.
- Qualquer mudanca na interface ou funcionalidade do painel web
  (`cstk-panel`) alem do ponto de decisao sobre integridade antes de
  servir.

## Dependencies & Assumptions

- **Depende de** os mecanismos de deteccao ja existentes (blocklist de
  comandos perigosos, allowlist de rede por execucao, verificacao de
  checksum do pacote do painel) — esta feature muda como/quando eles sao
  acionados, nao a logica de deteccao em si.
- **Assume** que a plataforma que executa as ferramentas (incluindo Bash)
  em nome do orquestrador oferece um ponto de interceptacao capaz de
  validar e, se necessario, impedir uma chamada antes dela rodar. Sem
  essa capacidade, US1 nao e realizavel como enforced e o plan precisa
  registrar isso como constraint.
- **Assume** que o operador recebe esta capacidade atraves do mesmo fluxo
  de instalacao/atualizacao ja usado para outras partes do toolkit —
  projetos que nunca atualizam permanecem apenas com a protecao advisory
  atual (comportamento hoje), sem regressao mas tambem sem a nova
  garantia ate atualizar.
- **Assume** que o repositorio de onde o painel web e baixado hoje nao
  publica o dado de integridade esperado (estado observado no momento
  desta spec); US2 precisa contemplar esse estado atual como o caso
  comum, nao a excecao.
