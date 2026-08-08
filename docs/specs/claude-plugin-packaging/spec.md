# Feature Specification: Empacotamento do cstk como Plugin do Claude Code

**Feature**: `claude-plugin-packaging`
**Created**: 2026-08-08
**Status**: Draft

## Clarifications

### Session 2026-08-08

- Q: Marketplace listing deve seguir tags SemVer (lockstep) ou HEAD continuo
  de main? → A: lockstep-tags-semver — atualizacoes do marketplace amarradas
  a tags SemVer publicadas (nao a HEAD continuo), alinhado ao versionamento
  SemVer + CHANGELOG ja praticado pelo toolkit.
- Q: Versao instalada via plugin (FR-008) e determinada por metadado do
  harness ou por checksum de conteudo do catalogo? → A:
  checksum-conteudo-catalogo — a comparacao de alinhamento usa checksum do
  conteudo do catalogo (mesma abordagem hash_dir ja usada por `cstk doctor`
  hoje), nao um metadado de versao exposto pelo harness (nao confirmado em
  doc oficial).
- Q: O plugin cstk deve empacotar o catalogo completo (core + todos os
  perfis de linguagem) num unico bundle, ou espelhar a selecao por perfil da
  instalacao classica? → A: marketplace com 2 entradas — `cstk` (catalogo
  default: 22 skills, 6 commands, agents, hooks) e `cstk-language-go`
  (perfil go, ja fora do manifest default desde v6.0.0), espelhando a
  separacao de profiles existente na instalacao classica.
- Q: Quando um projeto tem hooks classicos (`cstk hooks install --scope
  project`) E o plugin habilitado ao mesmo tempo, como evitar duplicacao de
  efeito? → A: dedup em tempo de instalacao, PLUGIN VENCE — `cstk hooks
  install` e `cstk setup` detectam o plugin cstk habilitado e nao registram
  o snippet classico no `settings.json` do projeto (orientando remocao de
  registro pre-existente); `cstk doctor` reporta duplicacao com remediacao;
  nenhum guard adicional em tempo de execucao nos scripts de hook.
- Q: Habilitar o plugin cstk ja e suficiente para os hooks de guarda
  ficarem ativos automaticamente, sem nenhum passo de confianca adicional
  especifico para hooks? → A: [ASSUMPTION a validar empiricamente] — a doc
  oficial (discover-plugins/plugins-reference) confirma a tela "Will
  install" (lista hooks/MCP antes de instalar) + aviso geral de confianca,
  mas NAO confirma nem nega um gate de consentimento separado especifico
  para hooks, nem o timing exato de ativacao (pode exigir `/reload-plugins`
  apos habilitar). A spec assume, defensivamente, que basta habilitar o
  plugin — sem inventar um comportamento de plataforma nao documentado
  (Constitution VI); o backlog (`create-tasks`) MUST incluir uma task de
  validacao empirica dessa premissa antes de FR-004 ser dado como
  encerrado.

## User Scenarios & Testing

### User Story 1 - Catalogo completo disponivel sem copia manual (Priority: P1)

Como operador que quer usar o toolkit cstk num projeto, eu habilito o
catalogo completo (skills, commands, agents) atraves do mecanismo nativo de
plugins do Claude Code, sem precisar clonar o repositorio e rodar um passo
de copia/instalacao separado — e sem correr o risco de ficar com uma copia
desatualizada em relacao ao repositorio fonte.

**Why this priority**: e o problema historico documentado do projeto — a
distribuicao por copia manual (`cstk install`/`cstk update`) exige que o
operador lembre de rodar `cstk update`/`cstk doctor` periodicamente; drift
entre a copia instalada e o repositorio fonte ja causou bugs de producao
(catalogo desatualizado, hooks stale). Sem esta story nao ha feature.

**Independent Test**: habilitar o plugin num projeto novo (sem nenhuma
instalacao classica previa do cstk) e confirmar que as skills, commands e
agents do toolkit ficam disponiveis e invocaveis, sem nenhum comando manual
de copia/instalacao de catalogo.

**Acceptance Scenarios**:

1. **Given** um projeto sem qualquer instalacao previa do cstk, **When** o
   operador habilita o plugin cstk atraves do mecanismo nativo do Claude
   Code, **Then** todas as skills, commands e agents do toolkit ficam
   disponiveis para invocacao nessa sessao, sem passo de copia manual.
2. **Given** o plugin ja habilitado, **When** o repositorio fonte do cstk
   publica uma nova versao do catalogo, **Then** o operador tem um caminho
   documentado (nativo do mecanismo de plugins) para atualizar o catalogo
   habilitado, sem depender de `cstk update`.

---

### User Story 2 - Hooks de guarda ativos sem provisionamento manual por projeto (Priority: P1)

Como operador que roda execucoes autonomas (`agente-00c`/`feature-00c`) em
varios projetos-alvo, eu quero que os hooks de guarda (interceptacao de
comandos perigosos, contagem de tool calls, captura de consumo avulso)
fiquem ativos automaticamente em qualquer projeto onde o plugin esta
habilitado, sem precisar rodar um comando de provisionamento
projeto-a-projeto.

**Why this priority**: hoje so o proprio repositorio do cstk tem os hooks
provisionados; todo outro projeto-alvo depende do operador lembrar de rodar
o provisionamento com escopo de projeto apos cada atualizacao que toque os
hooks — omissao ja causou o bug de contagem de tool calls zerada em
producao. Resolver isso e o segundo maior motivador da feature (empatado em
prioridade com US1: sem hooks confiaveis, a US1 sozinha nao fecha o
problema histerico completo).

**Independent Test**: habilitar o plugin num projeto-alvo novo, iniciar uma
execucao autonoma nele e confirmar (via artefato auditavel da execucao) que
os hooks de guarda dispararam durante a execucao, sem que o operador tenha
rodado nenhum comando de provisionamento de hooks nesse projeto.

**Acceptance Scenarios**:

1. **Given** um projeto-alvo com o plugin cstk habilitado e nenhum
   provisionamento manual de hooks ja realizado, **When** uma execucao
   autonoma (`agente-00c`/`feature-00c`) roda um comando que viola uma regra
   de bloqueio, **Then** o comando e interceptado e impedido, com o mesmo
   comportamento (motivo claro e acionavel) que a interceptacao provisionada
   manualmente ja produz hoje.
2. **Given** o mesmo projeto-alvo, **When** a execucao autonoma roda
   normalmente sem violar regras, **Then** as metricas de contagem de tool
   calls da onda refletem a atividade real (nao ficam zeradas por ausencia
   de hook).

---

### User Story 3 - Binario cstk continua disponivel independente do plugin (Priority: P2)

Como operador, eu continuo tendo acesso as capacidades de linha de comando
do cstk (`cstk recall`, `cstk usage`, `cstk mcp`, `cstk session`, `cstk
doctor`, etc.) atraves do fluxo de instalacao ja existente, mesmo que eu
adote (ou nao adote) o plugin do Claude Code para o catalogo de skills.

**Why this priority**: o formato de plugin do Claude Code nao substitui um
binario persistente no PATH do sistema (a superficie `bin/` de um plugin e
sessional, valida apenas durante a sessao). O binario cstk e a fonte de
capacidades que operam fora do escopo de uma sessao (ex: consultas
historicas via `cstk recall`, gerenciamento de sessoes paralelas via `cstk
session`). Sem esta story, adotar o plugin quebraria funcionalidade hoje
essencial.

**Independent Test**: instalar o binario cstk via o fluxo classico
(install.sh/self-update) num ambiente sem o plugin habilitado e confirmar
que todos os subcomandos do binario funcionam normalmente; depois habilitar
o plugin no mesmo ambiente e confirmar que o binario continua funcionando
sem nenhuma mudanca de comportamento.

**Acceptance Scenarios**:

1. **Given** um operador que so instalou o binario cstk (sem habilitar o
   plugin), **When** ele roda um subcomando do binario, **Then** o
   subcomando funciona identicamente ao comportamento hoje documentado.
2. **Given** um operador que habilita o plugin do Claude Code, **When** ele
   roda o mesmo subcomando do binario, **Then** o resultado e identico ao
   cenario sem o plugin — a presenca do plugin nao altera o comportamento do
   binario.

---

### User Story 4 - Convivencia sem drift entre os dois caminhos de instalacao (Priority: P2)

Como operador que pode ter, no mesmo ambiente, tanto a instalacao classica
do catalogo (`cstk install`/`cstk update` em `~/.claude/skills` etc.) quanto
o plugin do Claude Code habilitado, eu quero um jeito de saber se as duas
formas estao divergindo (versoes diferentes do catalogo, conteudo
duplicado) para nao acabar com comportamento inconsistente e dificil de
diagnosticar (skill de um caminho executando com uma versao, hook de outro
caminho executando com outra).

**Why this priority**: e a consequencia direta de introduzir um segundo
caminho de instalacao — sem visibilidade sobre a convivencia dos dois, o
ganho da US1/US2 (eliminar drift) pode ser substituido por uma nova forma de
drift (drift ENTRE os dois caminhos, em vez de entre repo e copia unica).
Prioridade P2 porque so se manifesta para quem efetivamente usa os dois
caminhos ao mesmo tempo — nao bloqueia quem escolhe um unico caminho.

**Independent Test**: com as duas formas de instalacao presentes e
propositalmente desalinhadas (uma em versao mais nova que a outra), rodar a
checagem de diagnostico do toolkit e confirmar que ela relata a divergencia
de forma explicita, em vez de silenciosamente favorecer uma das duas sem
aviso.

**Acceptance Scenarios**:

1. **Given** um ambiente com instalacao classica E plugin habilitados,
   ambos na mesma versao, **When** o operador roda a checagem de
   diagnostico do toolkit, **Then** o relatorio confirma que os dois
   caminhos estao alinhados, sem falso-positivo de divergencia.
2. **Given** o mesmo ambiente, agora com as duas instalacoes em versoes
   diferentes, **When** o operador roda a mesma checagem, **Then** o
   relatorio aponta explicitamente a divergencia (quais caminhos, quais
   versoes) em vez de mascarar o problema ou escolher um caminho
   silenciosamente.

---

### Edge Cases

- O que acontece quando um projeto-alvo tem o plugin habilitado E ja tinha
  hooks de guarda provisionados manualmente (`cstk hooks install --scope
  project`) de uma instalacao classica anterior? A interceptacao MUST
  continuar se comportando como uma unica camada efetiva — sem disparar
  duas vezes o mesmo bloqueio nem contar tool calls em dobro. Resolvido via
  dedup em tempo de instalacao (plugin vence — ver FR-005): `cstk hooks
  install`/`cstk setup` detectam o plugin habilitado e nao registram o
  snippet classico; `cstk doctor` reporta duplicacao residual com
  remediacao.
- O que acontece quando `${CLAUDE_PLUGIN_ROOT}` nao esta definida (harness
  mais antigo, ou script invocado fora do contexto de um plugin)? O sistema
  MUST cair no comportamento classico (resolver a partir de `~/.claude`)
  sem falhar.
- O que acontece quando o operador desabilita/remove o plugin depois de tê-lo
  usado? Qualquer configuracao ou artefato de projeto que dependia
  exclusivamente do plugin (hooks vindos so por ele) MUST deixar de ter
  efeito de forma limpa — sem deixar o projeto num estado quebrado
  (ex: referencias a scripts que nao existem mais).
- O que acontece quando a listagem do marketplace (`.claude-plugin/
  marketplace.json`) fica temporariamente fora de sincronia com uma tag de
  release publicada (ex: release em andamento)? O sistema MUST deixar claro
  qual e a versao efetivamente instalada pelo plugin, para o operador nao
  supor que esta na ultima versao quando nao esta.
- O que acontece quando um script de runtime hoje com caminho hardcoded a
  `~/.claude/skills/...` e invocado a partir do caminho plugin sem ter sido
  migrado ainda (feature em rollout incremental)? O comportamento MUST ser
  uma falha diagnostica clara (script nao encontrado, mensagem acionavel) —
  nunca uma falha silenciosa ou um caminho errado sendo lido sem aviso.

## Requirements

### Functional Requirements

- **FR-001**: O sistema MUST disponibilizar o catalogo completo do toolkit
  (as skills, commands e agents hoje mantidos no projeto) atraves do
  mecanismo nativo de plugins do Claude Code, de forma que um operador
  possa habilitar o catalogo inteiro sem executar nenhum passo manual de
  copia de arquivos.
- **FR-002**: O sistema MUST publicar um manifesto de plugin valido segundo
  o formato oficial de plugins do Claude Code, identificando o toolkit, sua
  versao corrente e os pontos de entrada do catalogo (skills, commands,
  agents).
- **FR-003**: O sistema MUST publicar uma listagem de marketplace (formato
  oficial, hospedada no proprio repositorio git do toolkit) que permita a
  um operador descobrir e habilitar o plugin atraves do mecanismo nativo de
  instalacao de plugins, sem depender de nenhum servico de terceiros
  operado pelo autor do toolkit. A listagem MUST conter exatamente 2
  entradas, espelhando a separacao de profiles ja existente na instalacao
  classica: `cstk` (catalogo default — 22 skills, 6 commands, agents,
  hooks) e `cstk-language-go` (perfil go, ja fora do manifest default desde
  v6.0.0). Atualizacoes da listagem MUST seguir tags SemVer publicadas
  (lockstep) — nunca refletir HEAD continuo de `main` — consistente com o
  versionamento SemVer + CHANGELOG ja praticado pelo toolkit.
- **FR-004**: O sistema MUST disponibilizar os hooks de guarda hoje
  existentes (interceptacao de comandos, contagem de tool calls, captura de
  consumo avulso) empacotados junto do plugin, de forma que fiquem ativos
  automaticamente em qualquer projeto onde o plugin esteja habilitado — sem
  exigir do operador um passo de provisionamento manual adicional por
  projeto. [ASSUMPTION a validar empiricamente — ver secao Clarifications]:
  esta spec assume que habilitar o plugin basta para os hooks ficarem
  ativos, sem gate de consentimento extra especifico para hooks alem do
  trust dialog padrao de habilitacao do plugin; a doc oficial confirma a
  tela "Will install" + aviso geral de confianca, mas nao confirma nem nega
  um gate adicional nem o timing exato de ativacao. O backlog (`create-tasks`)
  MUST incluir task de validacao empirica dessa premissa.
- **FR-005**: Quando um projeto-alvo tiver tanto o plugin habilitado quanto
  hooks provisionados pelo caminho classico, o sistema MUST evitar
  duplicacao de efeito (bloqueio disparado duas vezes, contagem de tool
  calls em dobro) — o comportamento efetivo MUST ser equivalente a uma
  unica camada de interceptacao. Mecanismo: dedup em tempo de instalacao,
  plugin vence — `cstk hooks install` e `cstk setup` MUST detectar o plugin
  cstk habilitado e, quando detectado, MUST NOT registrar o snippet
  classico no `settings.json` do projeto (orientando o operador a remover
  qualquer registro classico pre-existente); `cstk doctor` MUST reportar a
  duplicacao (quando ambos os registros coexistirem) com remediacao
  acionavel. Nenhum guard adicional em tempo de execucao MUST ser
  introduzido nos scripts de hook para este fim.
- **FR-006**: O binario cstk (CLI real usado por subcomandos como `recall`,
  `usage`, `mcp`, `session`, `doctor`) MUST continuar sendo distribuido e
  atualizado pelo fluxo hoje existente (install.sh/self-update),
  independentemente de o operador ter ou nao habilitado o plugin do Claude
  Code — o formato de plugin nao instala um binario persistente no PATH do
  sistema.
- **FR-007**: O sistema MUST comunicar claramente ao operador, na
  documentacao e na saida dos comandos relevantes (`cstk update`, `cstk
  doctor`), qual parte da instalacao cada mecanismo gerencia — o binario
  cstk continua sob `cstk update`/`self-update`; o catalogo habilitado via
  plugin passa a ser gerenciado pelo mecanismo nativo de atualizacao de
  plugins do Claude Code — para o operador nunca supor que um comando
  atualizou algo que na verdade pertence ao outro mecanismo.
- **FR-008**: O sistema MUST oferecer ao operador um jeito de verificar se
  a instalacao classica do catalogo (`cstk install`/`cstk update`) e a
  instalacao via plugin, quando ambas presentes no mesmo ambiente, estao
  alinhadas (mesma versao de conteudo) ou divergentes — reportando
  explicitamente qual das duas (se alguma) esta desatualizada. O criterio de
  alinhamento MUST ser checksum do conteudo do catalogo (mesma abordagem
  `hash_dir` ja usada por `cstk doctor` hoje), nao um metadado de versao
  exposto pelo harness do Claude Code — a doc oficial consultada nao
  documenta tal metadado.
- **FR-009**: Os scripts de runtime hoje referenciados por caminho fixo
  (`~/.claude/skills/...`) MUST resolver corretamente sua propria
  localizacao tanto quando invocados a partir da instalacao classica quanto
  quando invocados a partir do plugin, sem exigir a manutencao de duas
  copias divergentes da mesma logica.
- **FR-010**: Um projeto-alvo que nao adota o plugin do Claude Code (segue
  exclusivamente pela instalacao classica) MUST continuar funcionando
  exatamente como funciona hoje — a introducao do caminho plugin MUST ser
  aditiva e opt-in, nunca uma migracao forcada.
- **FR-011**: A distribuicao via plugin (manifesto, marketplace, download do
  conteudo do catalogo pelo mecanismo nativo do Claude Code) MUST continuar
  operando exclusivamente a partir do proprio repositorio do toolkit — MUST
  NOT introduzir nenhum endpoint de telemetria, analytics ou coleta remota
  administrado pelo autor do toolkit.
- **FR-012**: Quando um script de runtime nao consegue resolver sua propria
  localizacao em nenhum dos dois caminhos suportados (nem `${CLAUDE_PLUGIN_
  ROOT}`, nem o layout classico em `~/.claude`), o sistema MUST falhar de
  forma diagnostica e acionavel — nunca silenciosamente, nem lendo um
  caminho incorreto sem aviso.
- **FR-013**: A documentacao do projeto (README, CLAUDE.md, guias de
  instalacao) MUST descrever os dois caminhos de instalacao disponiveis
  (classico e plugin) e o criterio para um operador escolher entre eles ou
  usar ambos, evitando que a existencia de dois caminhos vire confusao para
  quem esta comecando.

> Decisoes de infraestrutura: N/A (feature de empacotamento/distribuicao;
> nao introduz scheduling, criptografia de dados persistentes, refresh de
> token externo, lock multi-pod nem backup — os mecanismos de auditoria e
> lock ja existentes no runtime dos orquestradores nao mudam de politica
> aqui, apenas de forma como sao localizados em disco).

### Key Entities

- **Plugin Manifest**: descritor do toolkit no formato oficial de plugins
  do Claude Code (`.claude-plugin/plugin.json`) — nome, versao, pontos de
  entrada do catalogo (skills/commands/agents) e dos hooks de guarda.
- **Marketplace Listing**: entrada publicada (`.claude-plugin/
  marketplace.json`) que permite a descoberta e habilitacao do plugin
  atraves do mecanismo nativo `/plugin install`, hospedada no proprio
  repositorio git do toolkit. Contem exatamente 2 entradas (`cstk` catalogo
  default, `cstk-language-go` perfil go) e e atualizada em lockstep com
  tags SemVer publicadas (nunca refletindo HEAD continuo de `main`).
- **Distribution Path**: um dos dois caminhos pelos quais um operador pode
  obter o catalogo do toolkit num ambiente — classico (`cstk install`/
  `cstk update` copiando para `~/.claude`) ou plugin (habilitado atraves do
  mecanismo nativo do Claude Code). Um mesmo ambiente pode ter os dois
  ativos simultaneamente.
- **Installation Alignment Report**: a informacao (reportada ao operador
  via checagem de diagnostico do toolkit) sobre se os Distribution Paths
  presentes num ambiente estao na mesma versao de conteudo ou divergentes.
  O criterio de comparacao e checksum de conteudo do catalogo (`hash_dir`),
  nao metadado de versao exposto pelo harness.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Um operador habilita o catalogo completo do toolkit (skills,
  commands, agents) num projeto novo, atraves do mecanismo nativo de
  plugins, sem executar nenhum comando de copia manual — tempo do processo
  comparavel ao de habilitar qualquer outro plugin do Claude Code.
- **SC-002**: Apos o plugin estar habilitado num projeto-alvo, zero passos
  manuais adicionais sao necessarios para os hooks de guarda ficarem
  ativos nesse projeto — elimina por completo a etapa hoje obrigatoria de
  provisionamento com escopo de projeto, que e a causa historica documentada
  do bug de contagem de tool calls zerada.
- **SC-003**: 100% dos subcomandos do binario cstk continuam funcionando
  sem alteracao de comportamento, com ou sem o plugin habilitado no mesmo
  ambiente.
- **SC-004**: Um operador com os dois caminhos de instalacao presentes no
  mesmo ambiente consegue, atraves de uma unica checagem de diagnostico,
  saber se ha divergencia de versao entre eles — sem precisar comparar
  arquivos manualmente.
- **SC-005**: 100% dos scripts de runtime que hoje dependem de caminho fixo
  a `~/.claude/skills/` continuam passando na suite de testes automatizada
  do projeto apos a migracao, nos dois caminhos de instalacao (classico e
  plugin).
- **SC-006**: Um projeto-alvo que opta por nao adotar o plugin do Claude
  Code nao percebe nenhuma mudanca de comportamento em relacao ao estado
  anterior a esta feature.

## Delta Requirements

### Capability: bash-guard-enforcement

#### MODIFIED

- **FR-004**: A interceptacao MUST ser provisionada automaticamente pelo
  fluxo normal de instalacao/atualizacao do toolkit em um projeto-alvo —
  seja pelo caminho classico (instalacao/atualizacao via `cstk install`/
  `cstk update` com hooks provisionados por projeto) seja pelo caminho de
  plugin do Claude Code (hooks empacotados no plugin, ativos automaticamente
  em qualquer projeto onde o plugin esteja habilitado, sem passo de
  provisionamento por projeto). Em ambos os casos, o operador MUST NOT
  precisar de um passo manual nao-documentado para ativa-la depois de
  atualizar o toolkit; quando os dois caminhos estiverem presentes no mesmo
  projeto, o efeito MUST permanecer equivalente a uma unica camada de
  interceptacao (ver FR-005 desta feature).

### Capability: guards-defense-in-depth

#### MODIFIED

- **FR-017**: A adocao das guardas por um projeto-alvo MUST ocorrer atraves
  de um dos fluxos de distribuicao oficiais do toolkit ja documentados —
  o classico (`cstk install`/`cstk update`) e, a partir desta feature,
  tambem o plugin nativo do Claude Code — MUST NOT introduzir um terceiro
  mecanismo de distribuicao paralelo fora desses dois, nem um caminho que
  contorne a auditabilidade/consistencia de qualquer um dos dois. A adicao
  do caminho plugin nao e um mecanismo concorrente nao-governado: e uma
  segunda forma OFICIAL de entregar o mesmo conteudo auditavel, com o
  mesmo conjunto de garantias de seguranca (FR-015/FR-016 desta capability
  permanecem intactas nos dois caminhos).
