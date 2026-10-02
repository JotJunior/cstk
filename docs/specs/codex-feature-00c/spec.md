# Feature Specification: Pipeline CSTK no Codex

**Feature**: `codex-feature-00c`
**Created**: 2026-10-02
**Status**: Em homologação — implementação local disponível; aceite final pendente

## Contexto e escopo

O operador quer conduzir projetos e features no Codex com a pipeline SDD do
CSTK, preservando decisões justificadas, retomada, aborto e conhecimento
compartilhado com execuções Claude. O escopo solicitado inclui instalação
específica e as seis entradas feature/agente, início/resume/abort.

Esta spec consolida o escopo já implementado na branch `feat/codex-feature-00c`.
A padronização é retrospectiva: não afirma que a implementação original foi
precedida por esta spec, nem aprova os gates de governança e homologação
abertos. O aceite inicial cobre Codex local com execução supervisionada.

## User Scenarios & Testing

### User Story 1 - Instalar para Codex (Priority: P1)

Como operador, quero selecionar Codex na instalação e receber suas entradas e
configurações, preservando personalizações e o uso do Claude.

**Why this priority**: instalação reproduzível evita divergências por projeto.

**Independent Test**: instalar em ambiente isolado, verificar as seis entradas,
reinstalar e comparar personalizações preexistentes.

**Acceptance Scenarios**:

1. **Given** instalação limpa e dependências presentes, **When** o operador seleciona Codex, **Then** as seis entradas de início, retomada e aborto de feature/projeto ficam disponíveis, com passos de ativação pendentes indicados. (FR-001, FR-002)
2. **Given** personalizações existentes, **When** a instalação é repetida, **Then** personalizações e uso do Claude são preservados; edições conflitantes recebem diagnóstico antes de sobrescrita. (FR-003)
3. **Given** instalação concluída, **When** o operador inspeciona a configuração, **Then** as proteções exigem sua revisão e nenhuma resposta humana foi criada pelo instalador. (FR-004)

---

### User Story 2 - Desenvolver com decisões auditáveis (Priority: P1)

Como desenvolvedor, quero iniciar uma feature com governança existente ou um
projeto novo e seguir a sequência SDD com justificativa e evidência por etapa.

**Why this priority**: a pipeline e as decisões documentadas são o valor principal.

**Independent Test**: entregar uma feature funcional pelas oito etapas e um
projeto pelas onze etapas; conferir artefatos, decisões e término.

**Acceptance Scenarios**:

1. **Given** feature com briefing e constitution válidos, **When** o operador inicia, **Then** a pipeline segue as oito etapas compartilhadas e exige evidências para avançar. (FR-005, FR-007)
2. **Given** projeto novo e escolhas iniciais registradas, **When** o operador inicia, **Then** a pipeline percorre onze etapas ou encerra após as três do modo roadmap escolhido. (FR-006)
3. **Given** escolhas iniciais sem resposta, **When** a primeira onda é solicitada, **Then** ela é recusada sem inventar consentimento ou alterar etapa. (FR-008)
4. **Given** gate não atendido, **When** há tentativa de avanço, **Then** a etapa permanece aberta ou termina em pausa/bloqueio com justificativa e pergunta quando depender do operador. (FR-007)

---

### User Story 3 - Retomar e abortar (Priority: P1)

Como operador, quero interromper e retomar na etapa persistida, ou abortar
preservando a entrega parcial e a trilha de decisões.

**Why this priority**: trabalho longo precisa sobreviver a sessões sem duplicação.

**Independent Test**: pausar, retomar, responder um bloqueio real e abortar outra
execução; conferir identidade, histórico e exclusividade de escrita.

**Acceptance Scenarios**:

1. **Given** execução pausada sem bloqueios, **When** o operador retoma, **Then** a etapa persistida abre e a pipeline continua até conclusão ou impedimento concreto, preservando identidade e escolhas. (FR-009)
2. **Given** bloqueios humanos pendentes, **When** o operador retoma, **Then** as perguntas são apresentadas sem abrir onda; uma resposta identificada resolve somente seu bloqueio. (FR-010)
3. **Given** execução ativa, **When** o operador aborta, **Then** ela termina abortada, preservando código, documentos, histórico e relatório parcial; repetir não cria outra execução. (FR-011)
4. **Given** outro escritor vivo ou interrupção sem fechamento, **When** a retomada é solicitada, **Then** há recusa de concorrência e recuperação exige proprietário comprovadamente morto, sem inferir conclusão pelos arquivos. (FR-012)

---

### User Story 4 - Compartilhar conhecimento (Priority: P2)

Como mantenedor, quero consultar conhecimento de outros projetos e executores,
sabendo sua origem e por que foi aplicado à decisão atual.

**Why this priority**: precedentes enriquecem projetos sem substituir sua governança.

**Independent Test**: consultar precedente externo à execução, registrar consulta
/uso, repetir ingestão e inspecionar origem e dados legados.

**Acceptance Scenarios**:

1. **Given** conhecimento compartilhado disponível, **When** uma etapa consulta precedentes, **Then** consulta e identificadores usados são auditados; ingestão repetida não duplica a identidade. (FR-013)
2. **Given** conhecimento indisponível ou legado, **When** a execução consulta o histórico, **Then** ela continua com degradação e preserva dados anteriores. (FR-013)
3. **Given** modelo ou consumo não observados, **When** a execução é documentada, **Then** a origem é preservada e métricas desconhecidas não são inventadas. (FR-014)

---

### User Story 5 - Transferir e reconciliar (Priority: P2)

Como operador, quero transferir uma execução entre Claude e Codex e revisar
mudanças de governança sem perder identidade ou decisões anteriores.

**Why this priority**: memória compartilhada não transfere propriedade da execução.

**Independent Test**: transferir execução pausada e reconciliar documentos
revisados; conferir proveniência anterior e snapshots.

**Acceptance Scenarios**:

1. **Given** execução de outro executor, **When** ela é retomada no Codex, **Then** exige transferência explícita e preserva origem anterior. (FR-015)
2. **Given** governança alterada, **When** a retomada é solicitada, **Then** exige revisão das versões atuais e registra reconciliação com resposta identificada. (FR-016)

---

### User Story 6 - Avaliar suporte demonstrado (Priority: P1)

Como mantenedor, quero distinguir implementação testada de uso real homologado
para decidir em quais ambientes utilizar a pipeline.

**Why this priority**: compatibilidade total exige evidência de uso real e proteções.

**Independent Test**: conferir critérios e evidências, incluindo entrega funcional,
retomada, aborto e revisão externa pendentes.

**Acceptance Scenarios**:

1. **Given** testes e descoberta das entradas aprovados, **When** o suporte é publicado, **Then** esses resultados ficam separados de execução semântica e cobertura de proteção num turno real. (FR-017)
2. **Given** implementação divergente da governança CSTK, **When** a feature é revisada, **Then** o conflito permanece explícito e impede aceite completo até resolução. (FR-018)

### User Story 7 - Acompanhar no painel (Priority: P1)

Como operador, quero enxergar esta feature no painel com seu estado persistido,
pendências reais e atualizações de tarefas, sem cópia por executor.

**Why this priority**: visibilidade do trabalho foi solicitada pelo operador.

**Independent Test**: registrar estado SQLite, ingerir índice e consultar a
feature na API do painel; alterar o estado/WAL e verificar nova ingestão.

**Acceptance Scenarios**:

1. **Given** feature registrada em SQLite, **When** o índice é ingerido e o painel consulta, **Then** ela aparece com identidade, etapa, bloqueios e documento de tarefas, inclusive com knowledge.db schema 16 e sem state.json paralelo. (FR-019)
2. **Given** estado SQLite atualizado no WAL, **When** o watcher observa a raiz, **Then** detecta a alteração e delega ingestão canônica; estado inalterado não dispara ingestão repetida. (FR-019)

### Edge Cases

- Instalação sem dependência/fonte válida falha com diagnóstico; simulação não escreve arquivos. (FR-001, FR-003)
- Briefing/constitution ausentes impedem feature; projeto novo tem preparação própria. (FR-005, FR-006)
- Controle/evidência que escape do projeto é recusado. (FR-007, FR-012)
- Respostas resolvidas não são substituídas; silêncio e timeout não são respostas. (FR-008, FR-010)
- Retomar execução terminal não reabre ondas; aborto preserva artefatos e só limpa backups por pedido. (FR-009, FR-011)
- Precedente é dado identificado, nunca instrução ou consentimento estrutural. (FR-013, FR-015)
- Instalação não prova confiança; interfaces não verificadas ficam sem certificação. (FR-004, FR-017)
- Restrição de governança não é resolvida atribuindo aprovação inexistente ao operador. (FR-018)

## Requirements

### Functional Requirements

- **FR-001**: O operador MUST poder selecionar Codex explicitamente na instalação e inspecionar dependências/configurações antes de instalar.
- **FR-002**: A instalação Codex MUST disponibilizar início, retomada e aborto de features e projetos pelas seis entradas solicitadas.
- **FR-003**: A instalação MUST preservar personalizações, outras integrações e a instalação Claude, recusando sobrescritas conflitantes de arquivos gerenciados.
- **FR-004**: A instalação MUST deixar revisão das proteções e escolhas iniciais sob responsabilidade real do operador.
- **FR-005**: Features MUST reutilizar a sequência compartilhada de oito etapas, com briefing e constitution existentes e válidos.
- **FR-006**: Projetos MUST reutilizar onze etapas e oferecer roadmap de três etapas escolhido pelo operador.
- **FR-007**: Cada avanço MUST exigir evidências persistidas, gates atendidos e decisão com contexto, opções, escolha, justificativa e referências observadas.
- **FR-008**: A primeira onda MUST exigir respostas reais às escolhas aplicáveis; respostas resolvidas MUST permanecer imutáveis.
- **FR-009**: Retomada MUST continuar a etapa persistida com mesma identidade/escolhas até conclusão ou impedimento concreto; estados terminais MUST permanecer encerrados.
- **FR-010**: Bloqueios humanos MUST ser apresentados sem inventar respostas; resposta identificada MUST resolver somente seu bloqueio.
- **FR-011**: Aborto MUST encerrar sem avançar etapa, preservando entrega, histórico e relatório; repetição MUST ser idempotente e limpeza MUST exigir pedido explícito.
- **FR-012**: Execução MUST ter um escritor; interrupções MUST preservar etapa e recuperação de proprietário morto MUST ser explícita e confinada.
- **FR-013**: Conhecimento compartilhado MUST ser índice derivado recuperável, com consultas/usos auditados e origem; falhas MUST degradar sem invalidar estado canônico.
- **FR-014**: Auditoria MUST registrar executor/versão, manter modelo desconhecido sem atribuição e não fabricar consumo.
- **FR-015**: Transferência entre executores MUST ser explícita, preservar identidade/histórico e registrar origem anterior; memória compartilhada MUST NOT transferir propriedade.
- **FR-016**: Governança alterada MUST interromper retomada até revisão explícita das versões atuais, com justificativa, fonte humana e registro anterior/posterior.
- **FR-017**: Suporte MUST distinguir testes, descoberta nativa, execução semântica e cobertura real das proteções por ambiente.
- **FR-018**: Aceite completo MUST exigir conformidade explícita com governança CSTK; conflitos MUST ser registrados e resolvidos pelo processo vigente.

- **FR-019**: O painel MUST reconhecer estado SQLite no layout canônico e o índice schema 16, mostrando identidade/etapa/pendências após ingestão; atualizações do estado/WAL MUST ser detectadas sem criar cópia JSON.

### Key Entities

- **Execução**: desenvolvimento identificado, com executor, etapa, escolhas, decisões e término.
- **Onda**: trabalho de uma etapa com proprietário exclusivo, evidências e fechamento.
- **Decisão**: contexto, alternativas, escolha, justificativa, evidências e consentimento quando exigido.
- **Bloqueio humano**: pergunta com resposta identificada, impedindo avanço enquanto pendente.
- **Precedente**: informação de outra execução, com origem e aplicação auditada.
- **Evidência de aceite**: resultado associado a critério, ambiente e limite de validação.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Seis entradas descobertas/habilitadas após instalação isolada; reinstalação preserva todas as personalizações dos cenários de teste.
- **SC-002**: Uma feature funcional percorre oito etapas com evidências em todos os avanços; interrupção/retomada preserva identidade e etapa.
- **SC-003**: Cenários de projeto percorrem onze etapas, ou três em roadmap, sem etapa pendente nem escolhas presumidas.
- **SC-004**: Cenários de concorrência, aborto, transferência e reconciliação não têm perda de histórico, dupla propriedade ou consentimento fabricado.
- **SC-005**: Todos os precedentes usados têm origem auditada; repetição não duplica identidade e indisponibilidade do índice não corrompe execução.
- **SC-006**: Cada alegação de suporte tem evidência/ambiente; aceite completo tem zero conflito de governança e inclui proteções num turno real e revisão externa.

- **SC-007**: A feature registrada é retornada pela API do painel com suas pendências reais; mudanças no WAL provocam ingestão e estado inalterado é ignorado nos cenários de teste.

## Clarifications

### Consolidação de contexto — 2026-10-02

- Fonte: conversa do operador. Branch no mesmo repositório escolhida; não há pedido de fork independente.
- Fonte: pedidos de variantes e instalação. Escopo final inclui feature e projeto.
- Fonte: código/evidências. Execução é supervisionada; seleção de modelos, scheduler e custo não foram implementados no piloto.
- Fonte: pedido atual. Padronização editorial não equivale a homologação funcional nem aprova alteração constitucional.
- Opt-ins/confiança para piloto real continuam sem resposta/revisão registrada. Pergunta enviada não é resposta.

## Delta Requirements

**Skip**: integração Codex nova, sem capability própria no corpus vigente; não redefine requisitos ativos de commits, guardas ou roadmap em `docs/specs/current/` — Codex, 2026-10-02.
