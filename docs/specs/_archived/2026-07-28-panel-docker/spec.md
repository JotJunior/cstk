# Feature Specification: panel-docker

**Feature**: `panel-docker`
**Created**: 2026-07-11
**Status**: Draft

## Visao geral

Hoje `cstk serve` inicia o painel web (`cstk-panel`) diretamente no host: na
primeira execucao baixa a release mais recente do GitHub, verifica sua
integridade, roda `npm run build` e depois `npm run start` — exigindo `curl`
e `npm` instalados e disponiveis no PATH da maquina do usuario. Isso
funciona bem quando o usuario ja tem esse ecossistema de pacotes
configurado, mas cria atrito real para quem nao tem (ou nao quer poluir o
ambiente global com mais uma instalacao de dependencias) e acopla o
processo do painel diretamente aos recursos do host, sem nenhum
isolamento.

Esta feature adiciona um modo alternativo de execucao — ativado
explicitamente pelo usuario — que sobe o mesmo painel dentro de um
container, em vez de executa-lo nativamente. O comportamento hoje existente
(execucao nativa) permanece o padrao inalterado; o novo modo e estritamente
opt-in.

> Decisoes de infraestrutura: aplica-se apenas o item de **Idempotencia**
> (ver FR-012-INFRA-IDEMP) — o sistema precisa reconciliar um container
> remanescente de uma execucao anterior do modo Docker. As demais categorias
> do checklist de infraestrutura NAO se aplicam: **N/A** para politica de
> scheduling (o comando roda em primeiro plano, sob demanda do usuario, sem
> disparo periodico), rotacao de chave de criptografia (a feature nao
> criptografa nem persiste segredo novo), refresh policy de token externo (a
> unica chamada de rede e a checagem de release do GitHub ja existente,
> nao-autenticada) e mutex multi-pod (execucao local single-host, sem
> replica compartilhando estado).

## Clarifications

### Session 2026-07-11

- Q: A alcancabilidade do painel dentro do container (FR-005) depende de
  coordenar uma mudanca no repositorio externo `cstk-panel` antes do
  lancamento, ou pode ser resolvida inteiramente do lado cstk/Docker? → A:
  Resolvida inteiramente do lado cstk/Docker, sem depender de nenhuma
  mudanca no `cstk-panel`. Bind em loopback (`127.0.0.1`) dentro de um
  container so aceita conexoes originadas do proprio namespace de rede —
  publicar a porta do container nao e suficiente para torna-lo alcancavel a
  partir do host. A resolucao adotada roda um processo leve de
  encaminhamento de rede dentro do proprio container, escutando em todas as
  interfaces e repassando para o processo do painel no endereco de loopback
  interno (mesmo namespace) — pratica padrao de containerizacao para
  processos que nao suportam bind configuravel. Modo de rede compartilhado
  com o host foi considerado e descartado por nao ter suporte uniforme
  entre sistemas operacionais de desktop, o que quebraria a promessa de
  "mesma convencao local" da FR-005 em parte das maquinas dos usuarios.
  Patchear o `cstk-panel` para aceitar o endereco de bind via configuracao
  nativamente fica registrado como melhoria futura opcional — simplificaria
  a imagem removendo a necessidade do encaminhamento — mas NAO e
  pre-requisito desta feature nem bloqueia o lancamento.

## User Scenarios & Testing

### User Story 1 - Rodar o painel sem instalar npm no host (Priority: P1)

Como usuario do `cstk` que nao tem `npm` instalado na maquina (ou nao quer
que o `cstk` instale dependencias diretamente no ambiente global), eu quero
poder subir o painel dentro de um container isolado usando o mesmo comando
que ja conheco, para acessar a mesma interface no navegador sem precisar
preparar esse ambiente de pacotes local.

**Why this priority**: e o motivador central da feature — sem esta
capacidade, o modo Docker nao entrega nenhum valor novo em relacao ao modo
nativo ja existente. Um usuario sem `npm` hoje simplesmente nao consegue
usar `cstk serve`.

**Independent Test**: numa maquina sem `npm` instalado (mas com o runtime
de container disponivel), executar o comando com a opcao de modo Docker e
verificar que o painel fica acessivel no navegador no endereco local
esperado, sem que o sistema jamais tente localizar ou exigir `npm` no
host.

**Acceptance Scenarios**:

1. **Given** o runtime de container esta instalado e em execucao, **When**
   o usuario roda o comando com a opcao de modo Docker, **Then** o painel
   fica acessivel no navegador no endereco local padrao, sem que `npm` ou
   `node` precisem existir no host.
2. **Given** o usuario ja tem uma instalacao nativa em cache (de uma
   execucao anterior sem o modo Docker), **When** ele roda o comando com a
   opcao de modo Docker pela primeira vez, **Then** o sistema sobe o painel
   containerizado normalmente, sem exigir remocao ou interferir na
   instalacao nativa existente.
3. **Given** o modo Docker foi solicitado, **When** o runtime de container
   nao esta instalado no host, **Then** o sistema recusa a operacao com uma
   mensagem acionavel, sem tentar nenhuma chamada de rede antes de checar o
   pre-requisito.

---

### User Story 2 - Painel containerizado mostra os mesmos dados que o painel nativo (Priority: P1)

Como usuario que ja tem execucoes anteriores dos orquestradores registradas
localmente, eu quero que o painel rodando em modo Docker exiba exatamente
os mesmos dados (decisoes, execucoes, alertas, tarefas) que o painel nativo
exibiria, para que trocar de modo de execucao nao signifique perder
visibilidade sobre o meu historico.

**Why this priority**: um painel que sobe mas nao mostra dado nenhum (ou
mostra dados incompletos) e uma casca vazia — tecnicamente "funciona" mas
nao entrega o proposito do painel, que e observabilidade sobre as execucoes
dos orquestradores. Sem paridade de dados, a User Story 1 sozinha nao
produz um MVP util.

**Independent Test**: com um indice de conhecimento local ja populado por
execucoes anteriores dos orquestradores, subir o painel em modo Docker e
comparar o conteudo exibido (contadores, listas, detalhes de execucao) com
o que o mesmo indice produziria no modo nativo — devem ser identicos.

**Acceptance Scenarios**:

1. **Given** existe um indice de conhecimento local com execucoes
   registradas, **When** o painel sobe em modo Docker, **Then** os dados
   exibidos (contadores, listas, buscas) sao identicos aos que o modo
   nativo exibiria para o mesmo indice.
2. **Given** o indice de conhecimento local ainda nao existe (instalacao
   nova, nenhuma execucao anterior dos orquestradores), **When** o painel
   sobe em modo Docker, **Then** o painel inicia normalmente e apresenta o
   mesmo estado "sem dados" que o modo nativo ja apresenta hoje — nunca uma
   falha de inicializacao.
3. **Given** o painel esta rodando em modo Docker, **When** uma nova onda de
   um orquestrador atualiza o indice de conhecimento local, **Then** essa
   atualizacao fica visivel no painel containerizado da mesma forma que
   ficaria no painel nativo.

---

### User Story 3 - Ergonomia de linha de comando familiar no modo Docker (Priority: P2)

Como usuario que ja conhece as opcoes existentes do comando de subir o
painel (porta, host, atualizar, reinstalar), eu quero que essas mesmas
opcoes continuem funcionando quando eu ativo o modo Docker, para nao
precisar aprender um novo conjunto de comandos so porque troquei o modo de
execucao.

**Why this priority**: reduz atrito de adocao — o valor da User Story 1 e
maior se o usuario nao precisar decorar uma segunda "API" de linha de
comando so para o modo Docker. E, no entanto, deprioritizavel frente as
duas primeiras: o modo Docker ja e util mesmo que, por exemplo,
`--update` ainda nao esteja implementado para ele no primeiro incremento.

**Independent Test**: repetir, com o modo Docker ativado, os mesmos
cenarios de porta customizada, atualizacao e reinstalacao ja cobertos pelo
modo nativo, e confirmar comportamento equivalente do ponto de vista do
usuario.

**Acceptance Scenarios**:

1. **Given** o usuario informa uma porta customizada, **When** o modo
   Docker esta ativo, **Then** o painel fica acessivel nessa porta, do
   mesmo jeito que ficaria no modo nativo.
2. **Given** existe uma instalacao containerizada anterior, **When** o
   usuario pede para verificar/aplicar atualizacao, **Then** o sistema
   segue a mesma logica ja existente no modo nativo (so reinstala se
   houver release mais nova; falha de rede/API mantem a versao instalada
   sem abortar a subida do painel).
3. **Given** o usuario pede reinstalacao explicita, **When** o modo Docker
   esta ativo, **Then** o sistema remove a instalacao containerizada
   existente e reconstroi do zero, de forma incondicional — assim como o
   modo nativo ja faz hoje para a instalacao no host.
4. **Given** o painel esta rodando em modo Docker, **When** o usuario
   interrompe o processo (Ctrl+C), **Then** o painel encerra de forma
   graciosa, sem deixar processo ou container orfao rodando em segundo
   plano.

---

### User Story 4 - Reexecucao segura sem limpeza manual (Priority: P3)

Como usuario que roda o modo Docker repetidamente (por exemplo, em dias
diferentes de trabalho), eu quero poder simplesmente repetir o mesmo
comando sem precisar descobrir e remover manualmente vestigios de uma
execucao anterior, para que o modo Docker seja tao previsivel quanto
rodar qualquer outro comando do dia a dia.

**Why this priority**: e um refinamento de robustez sobre as tres stories
anteriores — o cenario feliz (subir, usar, encerrar com Ctrl+C) ja cobre a
maior parte do uso real; esta story protege contra o caso em que uma
execucao anterior nao foi encerrada de forma limpa (queda de energia,
`kill -9`, etc.).

**Independent Test**: simular uma execucao anterior do modo Docker que nao
foi encerrada corretamente (deixando um container remanescente) e verificar
que uma nova execucao do comando resolve a situacao automaticamente, sem
exigir que o usuario rode comandos de limpeza manuais nem apresentar um
erro tecnico de baixo nivel do runtime de container.

**Acceptance Scenarios**:

1. **Given** existe um container remanescente de uma execucao anterior do
   modo Docker (parado ou ainda em execucao), **When** o usuario roda o
   comando novamente, **Then** o sistema reconcilia automaticamente essa
   situacao (reaproveitando ou substituindo o container remanescente) e
   sobe o painel normalmente.
2. **Given** a reconciliacao automatica nao e possivel por algum motivo,
   **When** o usuario roda o comando, **Then** o sistema apresenta uma
   mensagem acionavel especifica do `cstk`, nunca um erro cru do runtime de
   container.

---

### Edge Cases

- O que acontece quando o runtime de container nao esta instalado no host?
- O que acontece quando o runtime de container esta instalado mas o
  daemon/servico correspondente nao esta em execucao (ou o usuario nao tem
  permissao para acessa-lo)?
- Como o sistema se comporta quando a porta escolhida ja esta em uso por
  outro processo, seja ele nativo ou containerizado?
- O que acontece quando ja existe um container remanescente de uma
  execucao anterior do modo Docker (parado ou ainda em execucao) ocupando
  o mesmo nome ou porta?
- Como o sistema se comporta quando o indice de conhecimento local ainda
  nao existe (instalacao nova, nenhuma execucao anterior dos
  orquestradores)?
- O que acontece quando a verificacao de integridade do pacote do painel
  falha (checksum ausente ou divergente) com o modo Docker ativo?
- Como o sistema se comporta quando o usuario combina o modo Docker com as
  opcoes de atualizar e reinstalar ao mesmo tempo?
- O que acontece se o usuario interromper o processo (Ctrl+C) enquanto o
  container ainda esta sendo construido/iniciado, antes de ficar pronto
  para uso?

## Requirements

### Functional Requirements

- **FR-001**: System MUST oferecer uma opcao explicita e opt-in no comando
  existente de subir o painel que, quando informada, executa o painel
  dentro de um ambiente de container isolado em vez de diretamente no
  host.
- **FR-002**: Quando a opcao de modo Docker NAO for informada, System MUST
  preservar integralmente o comportamento nativo ja existente hoje, sem
  nenhuma mudanca de default.
- **FR-003**: System MUST verificar que um runtime de container esta
  disponivel no host ANTES de realizar qualquer operacao de rede; se o
  runtime de container nao estiver instalado, System MUST falhar
  imediatamente com uma mensagem de erro especifica e acionavel (no mesmo
  padrao ja adotado hoje para os demais pre-requisitos de ferramenta do
  comando).
- **FR-004**: System MUST distinguir a condicao "runtime de container nao
  instalado" da condicao "runtime de container instalado mas indisponivel
  (servico parado ou inacessivel)", relatando cada uma com uma mensagem
  acionavel distinta.
- **FR-005**: Quando o modo Docker sobe com sucesso, System MUST tornar o
  painel acessivel no navegador do usuario na mesma convencao local de
  host/porta ja oferecida pelas opcoes existentes de porta/host, sem exigir
  que o usuario entenda conceitos de rede de container. O processo do
  painel (mantido no repositorio externo `cstk-panel`) hoje faz bind fixo
  em `127.0.0.1` dentro do proprio processo, sem opcao de configuracao via
  variavel de ambiente ou flag — uma restricao que, isoladamente, impediria
  conexoes originadas fora do container mesmo com a porta publicada. System
  MUST resolver essa alcancabilidade inteiramente do lado cstk/Docker (ver
  Clarifications), sem depender de nenhuma mudanca no repositorio externo
  `cstk-panel`.
- **FR-006**: System MUST NOT exigir `npm` instalado no host quando o modo
  Docker for usado — o ambiente containerizado fornece seu proprio runtime
  de linguagem, embutido na imagem.
- **FR-007**: System MUST aplicar, no modo Docker, as mesmas garantias de
  integridade de artefato ja aplicadas hoje no modo nativo: bloqueio por
  padrao quando a integridade nao pode ser verificada, o mesmo mecanismo de
  bypass explicito ja existente, e uma divergencia de checksum confirmada
  MUST continuar sendo um bloqueio absoluto, sem nenhum caminho de bypass.
- **FR-008**: System MUST dar ao painel containerizado o mesmo acesso de
  leitura ao indice de conhecimento local que ele teria no modo nativo
  (hoje, o arquivo local `~/.claude/cstk/knowledge.db`, ou o local indicado
  pela variavel de configuracao ja existente para essa finalidade), para
  que a paridade de dados do painel (User Story 2) nao se perca somente
  por o modo Docker estar em uso.
- **FR-009**: Qualquer dado do host disponibilizado ao container conforme
  FR-008 MUST ser exposto somente leitura e restrito apenas ao que o
  painel efetivamente precisa — nunca um acesso mais amplo ao sistema de
  arquivos do host — de forma consistente com o proprio desenho
  somente-leitura do painel e com os principios de confinamento do
  toolkit.
- **FR-010**: System MUST suportar, no modo Docker, as opcoes existentes de
  verificar/aplicar atualizacao e de forcar reinstalacao, com semantica
  equivalente a ja oferecida hoje pelo modo nativo.
- **FR-011**: System MUST encerrar o painel containerizado de forma
  graciosa quando o usuario interromper o processo (Ctrl+C ou sinal de
  termino), sem deixar nenhum container orfao em execucao — o mesmo
  compromisso de encerramento gracioso que o modo nativo ja oferece hoje.
- **FR-012-INFRA-IDEMP**: System MUST detectar um container remanescente de
  uma execucao anterior do modo Docker e reconcilia-lo automaticamente
  (reaproveitando-o ou substituindo-o) em vez de expor ao usuario um erro
  bruto de baixo nivel do runtime de container. Chave de idempotencia:
  instalacao do modo Docker por host (uma unica instancia esperada por
  maquina); sem TTL — a reconciliacao acontece a cada nova invocacao do
  comando, nao por expiracao temporal.
- **FR-013**: System MUST NOT publicar nem enviar (`push`) nenhuma imagem
  de container construida para um registry remoto — o uso de container
  desta feature permanece inteiramente local ao host, de forma consistente
  com o confinamento de raio de acao ja praticado pelo restante do
  toolkit.
- **FR-014**: Users MUST conseguir descobrir a opcao de modo Docker e seu
  comportamento consultando a ajuda ja existente do comando.

### Key Entities

- **Instancia Containerizada do Painel**: a execucao do painel dentro do
  container, iniciada por uma invocacao do modo Docker. Seu ciclo de vida
  esta atrelado a essa invocacao — comeca quando o comando sobe o painel e
  termina quando o usuario interrompe o processo — e pode deixar um
  vestigio reconciliavel entre execucoes (ver FR-012-INFRA-IDEMP).
- **Instalacao Verificada do Painel**: a mesma arvore de instalacao/artefato
  ja obtida e verificada pelo fluxo de instalacao existente (download +
  checagem de integridade), reaproveitada como base do modo Docker — nao e
  uma fonte de instalacao nem um mecanismo de verificacao separados do que
  ja existe hoje.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um usuario sem `npm` instalado consegue deixar o painel
  acessivel no navegador executando um unico comando, sem nenhuma
  instalacao manual adicional alem do proprio runtime de container.
- **SC-002**: O painel em modo Docker exibe exatamente os mesmos dados
  (decisoes, execucoes, alertas, tarefas) que o painel nativo exibiria para
  o mesmo indice de conhecimento local — zero divergencia de conteudo
  observada entre os dois modos.
- **SC-003**: Encerrar o painel (Ctrl+C) no modo Docker nao deixa nenhum
  container ou processo orfao em execucao, em 100% das execucoes
  verificadas.
- **SC-004**: Um usuario que ja conhece as opcoes atuais do comando (porta,
  host, atualizar, reinstalar) consegue usar o modo Docker sem precisar
  aprender nenhum conceito novo alem da propria opcao que ativa o modo.
- **SC-005**: Repetir o comando do modo Docker logo apos uma execucao
  anterior bem-sucedida funciona sem exigir nenhuma limpeza manual do
  usuario, em 100% das tentativas.
- **SC-006**: Quando o runtime de container esta ausente ou inacessivel, o
  usuario recebe um diagnostico acionavel em menos de 5 segundos, sem que o
  sistema tenha tentado nenhuma operacao de rede antes dessa checagem.

## Delta Requirements

**Skip**: corpus docs/specs/current/ inexistente no momento do arquivamento (primeiro ciclo pos living-specs); backfill de capabilities historicas deferido pelo operador (living-specs 6.4.1/6.4.2); comportamento corrente documentado em CLAUDE.md/README — operador via review-features, 2026-07-28
