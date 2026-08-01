# Feature Specification: Configuração de Backend do state.db (Cutover Fase 2)

**Feature**: `state-backend-config`
**Created**: 2026-08-01
**Status**: Draft

## Contexto

A `state-db-foundation` (Fase 1, released `v6.0.0-alpha.1` pre-release) entregou
o banco `state.db` (SQLite) como fonte de verdade transacional alternativa ao
`state.json`, mas com adoção **opt-in por projeto**: a seleção de backend hoje
é decidida apenas pela presença física de `<state-dir>/state.db` — sem esse
arquivo, tudo continua em `state.json` exatamente como antes, e a única forma
de um projeto migrar é rodar `cstk state migrate` manualmente. O próprio
`CHANGELOG.md` da `v6.0.0-alpha.1` já registra o que falta para fechar a linha
v6: *"o cutover (init em SQLite por default, config global e `cstk state
enable-sqlite`) fica para as próximas alphas da linha v6"*.

Esta feature é a **Fase 2 (cutover)** dessa linha de evolução: introduz uma
política **global** (uma única configuração por máquina, não por projeto) que
determina qual backend uma **nova** inicialização de execução 00c deve usar
por padrão, um comando explícito para ativar essa política com segurança, e um
diagnóstico para o operador decidir com informação antes de ativar.

**Ponto de atenção arquitetural**: quem de fato cria `state.json`/`state.db`
para uma execução é `state-rw.sh init`, um script do runtime instalado em
`~/.claude/skills/agente-00c-runtime/scripts/` (consumido pelos
orquestradores `agente-00c`/`feature-00c`) — não o binário `cstk`
(`~/.local/share/cstk/`). A configuração global só tem efeito real se **esse
runtime** também a ler; se apenas o binário `cstk` a consultasse, o comando de
ativação ligaria uma política que a criação de estado de fato ignoraria.

## User Scenarios & Testing

### User Story 1 - Ativar SQLite como backend padrão para novas execuções (Priority: P1)

Como operador do toolkit, quero rodar um único comando para declarar que
novas execuções 00c devem usar o backend `state.db` por padrão, sem precisar
editar cada projeto manualmente ou lembrar de rodar uma migração depois de
cada inicialização.

**Why this priority**: é a capacidade central desta fase — sem ela, o
cutover não avança e a linha v6 permanece presa em "opt-in por projeto"
indefinidamente. Sem essa política central, os demais itens (diagnóstico,
proteção contra versão insuficiente) não têm o que proteger nem o que
diagnosticar.

**Independent Test**: num ambiente com `sqlite3` na versão mínima suportada
ou acima, rodar o comando de ativação e, em seguida, inicializar uma
execução nova (sem `state.json`/`state.db` prévios) tanto pelo binário
`cstk` quanto por uma chamada direta ao script de inicialização do runtime —
confirmar que ambos os caminhos produzem `state.db` como fonte de verdade,
sem nenhuma ação manual adicional.

**Acceptance Scenarios**:

1. **Given** um ambiente com `sqlite3` na versão mínima suportada ou acima e
   nenhuma configuração global prévia, **When** o operador ativa o backend
   SQLite, **Then** o comando reporta sucesso e a configuração global passa a
   declarar SQLite como backend padrão para novas inicializações.
2. **Given** a configuração global já declara SQLite como padrão, **When**
   uma execução 00c é inicializada num projeto sem `state.json`/`state.db`
   prévios — seja pelo binário `cstk`, seja por uma chamada direta do
   runtime dos orquestradores —, **Then** o `state.db` é criado como fonte
   de verdade dessa execução, e os dois caminhos de inicialização produzem
   o mesmo resultado.
3. **Given** um projeto que já possui `state.json` não migrado, **When** a
   configuração global passa a declarar SQLite como padrão, **Then** esse
   projeto continua operando normalmente em `state.json` — a configuração
   global não força nem dispara migração automática de projetos existentes.

---

### User Story 2 - Falha segura ao tentar ativar sem suporte adequado (Priority: P1)

Como operador do toolkit, quero que a ativação do backend SQLite se recuse a
prosseguir quando o `sqlite3` disponível no ambiente não atende ao mínimo
exigido, para nunca acabar com uma política global apontando para um backend
que o ambiente não consegue sustentar de forma confiável.

**Why this priority**: sem essa proteção, a User Story 1 fica perigosa —
ativar a política em uma máquina/CI com uma versão antiga de `sqlite3`
poderia produzir falhas silenciosas ou dados inconsistentes em toda
inicialização futura, em vez de uma recusa clara no momento da ativação.

**Independent Test**: num ambiente com `sqlite3` ausente ou abaixo da versão
mínima suportada, rodar o comando de ativação e confirmar que ele falha com
diagnóstico claro e que a configuração global permanece exatamente como
estava antes da tentativa.

**Acceptance Scenarios**:

1. **Given** um ambiente onde `sqlite3` está ausente do sistema ou abaixo da
   versão mínima suportada, **When** o operador tenta ativar o backend
   SQLite, **Then** o comando falha (saída não-zero) com um diagnóstico que
   cita a versão mínima exigida e a versão efetivamente detectada (ou a
   ausência da dependência), e a configuração global permanece inalterada.
2. **Given** uma tentativa de ativação foi recusada por versão insuficiente,
   **When** o operador corrige o ambiente (instala/atualiza `sqlite3` para
   uma versão adequada) e tenta ativar novamente, **Then** a ativação é
   bem-sucedida normalmente — nenhum resíduo da tentativa recusada anterior
   bloqueia a nova tentativa.
3. **Given** o backend SQLite já está ativado e a dependência continua
   adequada, **When** o operador roda o comando de ativação novamente,
   **Then** o comando reporta sucesso (operação idempotente) sem duplicar
   nem corromper a configuração existente.

---

### User Story 3 - Diagnosticar dependências e backend efetivo antes de decidir (Priority: P2)

Como operador do toolkit, quero consultar, numa única checagem, quais
dependências relevantes para o backend de estado estão presentes no
ambiente e qual backend seria efetivamente usado numa nova inicialização
agora, para decidir com informação se e quando ativar o cutover — sem
precisar inspecionar arquivos internos manualmente.

**Why this priority**: é uma capacidade de apoio à decisão — tem valor por
si só (visibilidade), mas depende conceitualmente da política existir (User
Story 1) e da proteção de versão existir (User Story 2) para o relatório
fazer sentido; por isso vem depois na priorização, embora seja
independentemente testável.

**Independent Test**: rodar o diagnóstico num ambiente sem nenhuma
configuração prévia (backend padrão legado) e confirmar que o relatório
lista as dependências relevantes com presença/versão detectada e indica
corretamente qual backend seria usado numa nova inicialização — sem
depender de o operador já ter rodado qualquer comando de ativação.

**Acceptance Scenarios**:

1. **Given** qualquer ambiente (com ou sem a configuração global ativada),
   **When** o operador roda o diagnóstico de dependências, **Then** o
   relatório lista, no mínimo, `sqlite3` e `jq`, a presença/versão detectada
   de cada um, e qual backend seria efetivamente usado numa nova
   inicialização agora, junto com o motivo dessa escolha.
2. **Given** `sqlite3` está presente mas abaixo da versão mínima suportada,
   **When** o operador roda o diagnóstico, **Then** o relatório indica
   explicitamente que o backend efetivo permanece o legado (JSON) e cita a
   versão insuficiente como motivo, sem exigir que o operador vá investigar
   manualmente por que a ativação não seria possível.
3. **Given** a configuração global já declara SQLite como padrão e o
   ambiente atende à versão mínima, **When** o operador roda o diagnóstico,
   **Then** o relatório confirma que o backend efetivo é SQLite pela
   combinação "configurado + dependência adequada".

---

### Edge Cases

- O que acontece quando a configuração global está ausente (nunca foi
  ativada)? Tratado exatamente como "nenhum backend configurado" — as novas
  inicializações continuam usando o backend legado (JSON), sem qualquer erro
  ou aviso disruptivo.
- O que acontece quando a configuração global existe mas está malformada ou
  corrompida (não é um `key=value` válido)? O sistema degrada com segurança:
  trata como se a configuração estivesse ausente (volta ao backend legado)
  em vez de falhar a inicialização ou o diagnóstico — mas o diagnóstico
  (`doctor --deps`) sinaliza a anomalia para o operador corrigir.
- O que acontece quando um projeto já possui `state.db` (já migrado) e a
  configuração global muda de SQLite para nunca-configurada ou o contrário?
  Nenhum efeito — a presença de `state.db` já migrado continua sempre
  vencendo como fonte de verdade daquele projeto especificamente; a
  configuração global só governa a escolha para inicializações **novas**.
- O que acontece quando `sqlite3` está completamente ausente do `PATH` (não
  é apenas uma questão de versão)? Tratado da mesma forma que versão
  insuficiente — ativação recusada com diagnóstico claro, e o diagnóstico de
  dependências reporta a ausência explicitamente.
- Reverter uma ativação (desativar o backend SQLite como padrão depois de
  ativado) está fora do escopo desta feature — não há comando de
  desativação especificado aqui.

## Requirements

### Functional Requirements

- **FR-001**: System MUST expor uma configuração global (arquivo único por
  máquina, fora de qualquer projeto específico) que declara qual backend de
  estado deve ser usado por padrão para novas inicializações de execução
  00c.
- **FR-002**: O formato da configuração global MUST ser texto plano
  `key=value` (uma atribuição por linha), parseável sem depender de um
  parser YAML ou JSON — consistente com a base POSIX-pura do toolkit; um
  parser YAML nunca MUST ser introduzido para esta finalidade.
- **FR-003**: System MUST prover um comando explícito de ativação que, quando
  a versão de `sqlite3` detectada no ambiente atende ao mínimo suportado
  (3.45.1 — piso já formalizado no amendment 1.3.0 da constitution do
  projeto, herdado da Fase 1), atualiza a configuração global para declarar
  SQLite como backend padrão.
- **FR-004**: O comando de ativação MUST se recusar (saída não-zero,
  diagnóstico claro citando a versão mínima exigida e a versão efetivamente
  detectada, ou a ausência da dependência) a ativar o backend SQLite quando
  `sqlite3` estiver ausente do ambiente ou abaixo da versão mínima
  suportada — e MUST deixar a configuração global exatamente como estava
  antes da tentativa nesse caso.
- **FR-005**: A decisão de qual backend usar para uma inicialização **nova**
  (nenhum `state.json` nem `state.db` presente ainda para aquela execução)
  MUST ser regida pela configuração global e MUST produzir o mesmo resultado
  independentemente de a inicialização ser disparada pelo binário `cstk` ou
  diretamente pelo script de runtime que efetivamente cria o estado — nenhum
  caminho de inicialização pode ignorar silenciosamente a configuração.
- **FR-006**: Um projeto que já possui `state.json` não migrado, ou já
  possui `state.db` (migrado), MUST continuar se comportando exatamente
  como hoje — a configuração global nunca dispara ou força uma migração de
  projeto existente; ela só determina o padrão para inicializações novas.
- **FR-007**: System MUST prover um diagnóstico de dependências que reporte,
  no mínimo: presença e versão detectada de cada dependência relevante para
  a decisão de backend (ao menos `sqlite3` e `jq`), e qual backend seria
  efetivamente usado numa nova inicialização agora, incluindo o motivo dessa
  escolha (ex.: configurado e dependência adequada; configurado mas
  dependência abaixo do mínimo; nunca configurado).
- **FR-008**: Se a configuração global estiver ausente ou não puder ser
  interpretada (formato inválido), System MUST tratar isso como equivalente
  a "nenhum backend configurado" (fallback para o backend legado) em vez de
  falhar a inicialização ou o comando de diagnóstico.

**Decisões de infraestrutura auditáveis:**

- **FR-009-INFRA-IDEMP**: O comando de ativação MUST ser idempotente —
  rodá-lo novamente quando o backend já está ativado e a dependência
  continua adequada MUST resultar em sucesso silencioso (no-op), sem
  duplicar entradas na configuração nem reportar erro.

> Demais categorias do checklist de infraestrutura: N/A explícito.
> Scheduling — feature não introduz job periódico novo. Rotação de chave —
> a configuração global não armazena segredo nem dado criptografado.
> Refresh de token externo — não há integração com IdP/OAuth nesta feature.
> Mutex multi-réplica — a configuração é um arquivo local de máquina, lido
> por processos locais sequenciais do próprio operador; não há cenário de
> múltiplas réplicas concorrentes disputando essa configuração nesta
> feature. Backup/restore — a configuração é um arquivo mínimo,
> integralmente re-derivável rodando o comando de ativação novamente; não
> justifica mecanismo de backup dedicado nesta fase.

### Key Entities

- **BackendConfig (Configuração de Backend)**: o registro global (um por
  máquina) que declara qual backend de estado (JSON legado ou SQLite) deve
  ser usado por padrão para novas inicializações de execução 00c.
- **DependencyDiagnosticReport (Relatório de Diagnóstico de Dependências)**:
  a saída do diagnóstico de dependências — lista de dependências relevantes,
  presença/versão detectada de cada uma, e o backend efetivo resultante com
  o motivo.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Após uma ativação bem-sucedida do backend SQLite, 100% das
  novas inicializações de execução (sem `state.json`/`state.db` prévios) no
  mesmo ambiente passam a usar o backend SQLite, sem nenhuma ação manual
  adicional do operador além da ativação em si.
- **SC-002**: Uma tentativa de ativar o backend SQLite com uma versão de
  dependência abaixo do mínimo suportado (ou dependência ausente) é
  recusada em 100% dos casos, sem alterar a configuração global vigente.
- **SC-003**: Um operador consegue determinar, numa única consulta de
  diagnóstico, quais dependências relevantes estão presentes/ausentes e
  qual backend será efetivamente usado, sem precisar inspecionar arquivos
  internos manualmente.
- **SC-004**: A decisão de backend para uma nova inicialização é idêntica
  entre os dois caminhos de leitura da configuração (binário `cstk` e
  chamada direta ao runtime dos orquestradores) — 0% de divergência entre
  os dois caminhos, medido em teste automatizado.
- **SC-005**: Projetos que já possuíam uma execução migrada (`state.db`) ou
  não-migrada (`state.json`) antes da ativação continuam se comportando
  exatamente como antes — 0 regressões na suíte de testes existente do
  toolkit atribuíveis a esta feature.

## Delta Requirements

**Skip**: nenhuma capability documentada em `docs/specs/current/`
(`atomic-commit-staging`, `bash-guard-enforcement`, `delta-archive-gate`,
`guards-defense-in-depth`, `serve-integrity`, `spec-corpus`,
`spec-delta-requirements`, `trusted-release-hosts`) descreve seleção de
backend de estado ou configuração global do `cstk` — o comportamento
relacionado mais próximo (seleção de backend por presença de `state.db`)
foi introduzido pela `state-db-foundation`, que ainda não foi arquivada e
portanto ainda não tem capability correspondente no corpus vivo. Nada a
alterar no corpus nesta fase; uma capability nova (`state-backend-config` ou
equivalente, possivelmente absorvida na mesma capability futura de
`state-db-foundation`) poderá ser declarada quando esta feature for
arquivada, seguindo o processo padrão de `delta-merge`. —
agente-00c-feature-orchestrator, 2026-08-01
