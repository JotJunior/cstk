# Requirements Checklist: roadmap-mode

**Purpose**: validar a QUALIDADE dos requisitos da feature `roadmap-mode`
(spec + plan + contratos) antes de decompor em backlog. Dominio
`requirements` — escolhido por escopo: CLI/pipeline de documentacao POSIX,
sem UI, sem rede, sem authN/Z (dominios `ux`/`api`/`security`/`performance`
nao se aplicam; a superficie de seguranca real — artefato gerado por LLM e
re-consumido — entra como cluster proprio abaixo).
**Created**: 2026-08-14
**Feature**: [spec.md](../spec.md)
**Artefatos avaliados**: `spec.md`, `plan.md`, `research.md`,
`data-model.md`, `contracts/roadmap-artifact.md`,
`contracts/cli-roadmap-mode.md`, `quickstart.md`

## Completude de Requisitos

- [x] CHK001 - Sao os requisitos do opt-in (posicao, default, afirmativas
  aceitas, comportamento nao-interativo, retomada) definidos para o modo?
  [Completude, Spec §FR-001] {auto}
  — Evidencia: `contracts/cli-roadmap-mode.md` §7 define posicao ("antes de
  inicializar o estado"), default seguro ("qualquer resposta que nao seja
  afirmativa, inclusive Enter ⇒ false"), conjunto de afirmativas
  (`s,S,y,Y,sim,yes`), nao-interativo ("cai no default sem bloquear") e
  retomada ("`/agente-00c-resume` nunca re-pergunta").
- [x] CHK002 - Sao as etapas que MUST NOT executar no modo enumeradas
  exaustivamente, e nao apenas por exclusao implicita? [Completude,
  Spec §FR-002] {auto}
  — Evidencia: FR-002 lista nominalmente specify, clarify, plan, checklist,
  create-tasks, execute-task, review-task.
- [x] CHK003 - Sao os campos obrigatorios de uma entrada de roadmap
  definidos com tipo e regra de validacao? [Completude, Spec §FR-003] {auto}
  — Evidencia: `data-model.md` §EntradaDeRoadmap tabela de 5 campos +
  bloco Validacoes; gramatica literal em `contracts/roadmap-artifact.md` §3.
- [x] CHK004 - Sao os campos de estado exigidos pelo encerramento terminal
  especificados individualmente? [Completude, Spec §FR-004] {auto}
  — Evidencia: `contracts/cli-roadmap-mode.md` §5 enumera os 5 campos
  (`status`, `termination_reason`, `finished_at`, `current_stage`,
  `next_instruction`) e declara por que 3 nao bastam.
- [x] CHK005 - Sao as condicoes de derivacao dos 3 status de portfolio
  definidas de forma mutuamente exclusiva e exaustiva? [Completude,
  Spec §FR-006] {auto}
  — Evidencia: `data-model.md` §Enum `status` — `nao-iniciada` (dir
  ausente), `em-andamento` (dir existe, `tasks.md` ausente ou com
  pendentes), `concluida` (`tasks.md` sem pendentes).
- [ ] CHK006 - Existe requisito que atribua a PRODUCAO do artefato (quem
  gera `docs/roadmap.md`, com que gramatica e sob que gatilho)? [Gap,
  Spec §FR-003] {auto}
  — Gap: `plan.md` §Abordagem de implementacao (passos 1-11) atribui dono a
  estado, pipeline, validador, cruzamento, prosa de command/orquestrador e
  relatorio — nenhum passo atribui a geracao/escrita do artefato. O
  `plan.md:52` chega a tratar a hipotese ("se a geracao do roadmap vier a
  ser extraida para skill propria"), confirmando que hoje ela nao tem dono
  declarado. Sem dono, as regras normativas de §3 (gramatica), §8 (merge) e
  §9.4 (filtragem) nao tem onde ser implementadas.
- [ ] CHK007 - Existe requisito que atribua a filtragem de segredos ANTES
  da escrita do artefato versionado? [Gap, Contract §9.4] {auto}
  — Gap: `contracts/roadmap-artifact.md` §9.4 declara MUST fail-closed, mas
  nenhum FR da spec o exige e nenhum passo do plan o implementa (o passo 11
  cobre o relatorio, que §9.4 explicita ser caminho DISTINTO do arquivo
  versionado em git).
- [x] CHK008 - Sao os requisitos de retro-compatibilidade do campo de modo
  (ausencia = default) definidos? [Completude, Spec §SC-003] {auto}
  — Evidencia: `data-model.md` §ModoDeExecucao invariante "ausencia do campo
  e lida como `false`"; `contracts/cli-roadmap-mode.md` §8 (matriz de
  compatibilidade, linha 1).

## Clareza e Mensurabilidade

- [ ] CHK009 - E SC-001 ("menos ondas que a pipeline completa atual do mesmo
  projeto") mensuravel sem exigir uma execucao de baseline que pode nao
  existir? [Ambiguity, Spec §SC-001] {auto}
  — Ambiguidade: o criterio compara contra uma execucao completa do MESMO
  projeto, que num projeto novo nunca ocorrera. O contrato §5.2 resolve
  metade do problema (distinguir as duas execucoes por `termination_reason`),
  mas nao define a baseline nem um limiar absoluto. Reformular como criterio
  observavel (ex.: "a execucao nunca registra etapa posterior a `roadmap`").
- [x] CHK010 - E "descricao acionavel" quantificado com criterio
  verificavel, em vez de adjetivo? [Clareza, Spec §FR-003] {auto}
  — Evidencia: `contracts/roadmap-artifact.md` §3.4 fixa "texto acionavel,
  1-4 frases"; §7 fecha o criterio operacional ("aceito sem edicao pelo
  `/feature-00c`"), que e o teste de SC-002.
- [x] CHK011 - E o formato de `short-name` expresso como regra verificavel
  por maquina, com fonte da convencao? [Clareza, Spec §FR-005] {auto}
  — Evidencia: `^[a-z][a-z0-9-]*$`, com fonte citada
  (`plugins/cstk/commands/feature-00c.md:93`) em `data-model.md` §Validacoes
  e `contracts/roadmap-artifact.md` §7.
- [ ] CHK012 - E o valor de `termination_reason` do modo normativo, ou
  apenas exemplificativo? [Ambiguity, Contract §5.2] {auto}
  — Ambiguidade: §5.2 grafa `concluido_roadmap` precedido de "ex.:". Como o
  proprio requisito existe para tornar as execucoes distinguiveis por
  consumidores derivados (painel, `knowledge.db`, `recall`), um valor
  exemplificativo nao serve — o consumidor precisa casar string exata.
- [x] CHK013 - Sao os exit codes e o contrato de stdout dos helpers novos
  especificados por caso (incluindo estado ausente/ilegivel)? [Clareza,
  Contract §2] {auto}
  — Evidencia: `contracts/cli-roadmap-mode.md` §2 tabela — stdout
  `true|false` exato, "exit 0 sempre", campo ausente/nao-booleano/estado
  ilegivel ⇒ `false`, com a justificativa (`if` sob `set -e`).
- [ ] CHK014 - E SC-004 ("nunca perdem status de features ja iniciadas")
  consistente com o modelo, onde `status` nunca e persistido? [Ambiguity,
  Spec §SC-004] {auto}
  — Ambiguidade terminologica: `contracts/roadmap-artifact.md` §2.2 e
  `data-model.md` declaram que status e derivado na leitura e por isso "nao
  existe status a sobrescrever ou perder". O que uma re-execucao pode de
  fato perder e a IDENTIDADE/prosa da entrada, nao o status. Redigir SC-004
  em termos de entradas preservadas torna o criterio testavel.

## Consistencia entre Artefatos

- [x] CHK015 - Sao os requisitos de nao-regressao consistentes entre spec,
  plan e cenarios de teste? [Consistencia, Spec §SC-003] {auto}
  — Evidencia: FR-001 (default = pipeline atual) ↔ `plan.md` §Riscos
  ("`_PL_STAGES_LIST` intocada + assercao existente das 10 etapas preservada
  sem edicao") ↔ `quickstart.md` Cenario 1 `[CRITICO]`.
- [x] CHK016 - E a decisao de nao alargar a lista global de etapas
  consistente entre research, plan e contrato? [Consistencia, Research §D2]
  {auto}
  — Evidencia: `research.md` D2 (lista escopada por modo) ↔ `plan.md` passo
  3 (`_PL_STAGES_LIST` inalterada) ↔ `contracts/cli-roadmap-mode.md` §3.1
  ("a correcao MUST ser tornar a validacao ciente do modo, e nao alargar a
  lista global") + assercao de regressao obrigatoria.
- [x] CHK017 - E o encerramento terminal descrito de forma consistente
  (nunca via `--advance --terminal-phase`)? [Consistencia, Research §D3]
  {auto}
  — Evidencia: `research.md` D3 ↔ `plan.md` §Summary (c) ↔
  `contracts/cli-roadmap-mode.md` §4.1 e §5 (precedente do `reconcile-wave`).
- [ ] CHK018 - Sao as regras de merge de FR-007 consistentes com a gramatica
  do artefato, que nao possui campo de marcacao? [Conflict, Spec §FR-007]
  {auto}
  — Conflito: `contracts/roadmap-artifact.md` §8 exige, para entrada
  considerada desnecessaria, "nao apagar; **marcar** e reportar ao operador"
  — mas §2.2 declara a ausencia deliberada de campo de status no artefato e
  §3 nao define nenhum campo de marcacao/obsolescencia. Como marcar sem
  campo nao esta definido.
- [ ] CHK019 - Existe requisito que defina COMO detectar alteracao
  deliberada de descricao/justificativa para reporta-la? [Gap,
  Contract §8] {auto}
  — Gap: §8 proibe sobrescrita silenciosa e exige que alteracao deliberada
  "MUST ser reportada no relatorio final", mas nada define a fonte de
  comparacao (o artefato nao versiona conteudo anterior; a deteccao
  dependeria de diff do git, nao contratado).
- [x] CHK020 - Sao os requisitos de FR-002 (reuso de briefing/constitution)
  consistentes com o mecanismo ja existente, sem exigir logica nova?
  [Consistencia, Spec §FR-002] {auto}
  — Evidencia: `contracts/cli-roadmap-mode.md` §3.2 contrata explicitamente
  o comportamento emergente e adverte que "o que seria erro e supor que o
  modo precisa forcar re-execucao dessas etapas"; `plan.md` §nota de reuso
  confirma "nenhum passo e necessario".

## Cobertura de Cenarios e Edge Cases

- [x] CHK021 - Tem cada requisito funcional ao menos um cenario associado?
  [Cobertura, Spec §Requirements] {auto}
  — Evidencia: gate deterministico
  `plugins/cstk/skills/checklist/scripts/requirement-coverage.sh
  docs/specs/roadmap-mode/spec.md` ⇒
  `RESULT|...|requirements=8|covered=8|errors=0`, exit 0.
- [x] CHK022 - Sao os edge cases de re-execucao (roadmap preexistente,
  colisao de nome, entrada unica) definidos como requisito e nao so como
  narrativa? [Cobertura, Spec §Edge Cases] {auto}
  — Evidencia: FR-007 normatiza os tres; `contracts/roadmap-artifact.md` §8
  tabela de merge por situacao; `quickstart.md` Cenarios 7 `[CRITICO]` e 9.
- [x] CHK023 - E o comportamento definido para roadmap de 0 entradas, com a
  assimetria produtor/leitor explicitada? [Cobertura, Data-model
  §Invariantes] {auto}
  — Evidencia: `data-model.md` §Roadmap — produtor reprova (etapa nao
  conclui), leitor de portfolio trata como sucesso com aviso; a assimetria e
  declarada deliberada ("rigor na escrita, tolerancia na leitura").
- [x] CHK024 - Sao os cenarios de nao-regressao marcados como criticos e
  ligados a um criterio de sucesso? [Cobertura, Spec §SC-003] {auto}
  — Evidencia: `quickstart.md` Cenarios 1, 7, 11 e 12 marcados `[CRITICO]`;
  Cenario 1 declarado gate de nao-regressao em `plan.md` Fase D passo 13.
- [ ] CHK025 - Cobre a validacao estrutural (gate de conclusao) TODAS as
  invariantes declaradas como MUST no modelo? [Gap, Contract §6] {auto}
  — Gap: as 8 regras de §6 nao cobrem (a) aciclicidade do grafo de
  `depende-de`, (b) compatibilidade `ordem(B) < ordem(A)` quando A depende
  de B, (c) unicidade de `ordem`, (d) limite de 200 entradas, (e) limite de
  64 caracteres de `short-name` — todas declaradas MUST em `data-model.md`
  §Validacoes, `contracts/roadmap-artifact.md` §3.3 e §9.3. O item 7 de §6
  valida apenas EXISTENCIA da dependencia. Consequencia: o produtor pode
  emitir artefato que o consumidor fail-closed (§9.2) rejeitara.
- [ ] CHK026 - Valida o gate de conclusao as secoes obrigatorias de
  proveniencia? [Gap, Contract §2.1] {auto}
  — Gap: §2.1 marca `**Gerado por**:` / `**Atualizado em**:` como
  obrigatorias, mas as 8 regras de §6 checam apenas o H1 `Roadmap`, a secao
  `## Features` e as entradas — nem a proveniencia nem `## Ordem sugerida`
  sao verificadas.
- [x] CHK027 - E o comportamento definido para projeto-alvo sem
  `docs/roadmap.md` no consumidor de portfolio? [Cobertura, Contract §8]
  {auto}
  — Evidencia: `contracts/cli-roadmap-mode.md` §8 (matriz: "review-features
  inalterado"); `plan.md` passo 10 exige invocacao best-effort;
  `quickstart.md` Cenario 8.2 cobre feature sem `tasks.md`.

## Requisitos Nao-Funcionais (seguranca do artefato, portabilidade)

- [x] CHK028 - Sao os requisitos de tratamento do artefato re-lido como
  UNTRUSTED definidos, com a distincao face ao Principio VI? [Completude,
  Contract §9.1] {auto}
  — Evidencia: §9.1 exige o cerco UNTRUSTED no merge e no relatorio de
  portfolio, com regra normativa citavel e a nota de ortogonalidade ("VI
  protege contra inventar; §9.1 protege contra obedecer").
- [x] CHK029 - Sao os requisitos de validacao fail-closed NO CONSUMIDOR
  especificados campo a campo, com acao definida em caso de falha?
  [Completude, Contract §9.2] {auto}
  — Evidencia: §9.2 tabela por campo (`short-name`, comprimento,
  `depende-de`, `ordem`) com acao ("descartar a entrada/token + avisar"),
  mais a justificativa de por que `depende-de` e o unico campo que exige
  validacao explicita; `quickstart.md` Cenario 11 `[CRITICO]`.
- [x] CHK030 - Sao os limites de tamanho declarados com valor numerico e
  motivo? [Clareza, Contract §9.3] {auto}
  — Evidencia: §9.3 — `short-name` <= 64, entradas <= 200, motivo declarado
  (exaustao de recurso em consumidores POSIX que varrem diretorio por
  entrada). Ressalva: nao sao exigiveis pelo gate do produtor (ver CHK025).
- [x] CHK031 - E o requisito de ordem `finalize` antes da promocao terminal
  justificado por consequencia observavel, e nao por estilo? [Clareza,
  Contract §5.1] {auto}
  — Evidencia: §5.1 — o hook `PreToolUse` so age com execucao ativa; apos a
  promocao a execucao e inativa e o `git push` do finalize rodaria com a
  guarda desligada. Sequencia de 4 passos numerada; `quickstart.md`
  Cenario 12 `[CRITICO]`.
- [x] CHK032 - Sao as restricoes de portabilidade e de dependencia
  declaradas como requisito verificavel? [Completude, Plan §Technical
  Context] {auto}
  — Evidencia: `plan.md` §Technical Context ("sem GNU-ismos", "Dependencias
  novas: Nenhuma") + §Constitution Check II (2 scripts novos sem `jq`,
  precedente `aggregate.sh`) + §Re-check ("foi o requisito de parse POSIX
  que ditou o formato do artefato").
- [x] CHK033 - E o requisito de veracidade aplicado ao CONTEUDO gerado, com
  criterio de separacao entre proposta e afirmacao factual? [Completude,
  Spec §FR-008] {auto}
  — Evidencia: `contracts/roadmap-artifact.md` §3.4 fixa a regra com exemplo
  contrastante ("permitir que o usuario autentique" vs "consome `POST
  /api/v2/auth/token`"); `plan.md` §Aplicacao do Principio VI, frente 2.

## Decisoes de Produto em Aberto

- [x] CHK034 - A priorizacao P1/P2/P3 (modo > consumo > acompanhamento)
  reflete o apetite do dono do produto para a primeira entrega? [Risco,
  Spec §User Scenarios] {humano}
  — RESOLVIDO (operador, 2026-08-14): manter P1 > P2 > P3 como esta.
- [x] CHK035 - O limite de 200 entradas por roadmap e adequado ao maior
  projeto-alvo previsto, ou e conservador/permissivo demais? [Risco,
  Contract §9.3] {humano}
  — RESOLVIDO (operador, 2026-08-14): REDUZIR para 50 entradas. Atualizar
  Contract §9.3 e o gate estrutural (tarefa de CHK025, FASE 1) para o
  teto 50; roadmap maior que 50 indica decomposicao errada do projeto.
- [x] CHK036 - Entrada obsoleta deve permanecer visivel no artefato
  indefinidamente, ou o operador prefere um mecanismo de arquivamento?
  [Risco, Contract §8] {humano}
  — RESOLVIDO (operador, 2026-08-14): marcacao EXPLICITA e visivel no
  proprio artefato (campo de marcacao com motivo — historico auditavel).
  Resolve a direcao do conflito CHK018: definir o campo de marcacao em
  Contract §3/§2.2 (tarefa de CHK018, FASE 1).
- [x] CHK037 - A relacao com a feature irma `delivery-tier` (tier influencia
  o tamanho do roadmap) deve ser requisito nesta entrega, ou fica como
  integracao futura? [Assumption, Spec §Contexto] {humano}
  — RESOLVIDO (operador, 2026-08-14): integracao FUTURA; features seguem
  independentes nesta entrega, como a spec declara.
  — A spec declara as duas features independentes ("nenhuma depende da outra
  para entregar valor"), mas nao ha FR cobrindo a interacao quando ambas
  existirem.

## Notes

- Items `{auto}` vem resolvidos: `[x]` cita a evidencia que prova; `[ ]`
  carrega marcador `[Gap]`/`[Ambiguity]`/`[Conflict]` com o que falta.
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Rastreabilidade: 37/37 items com referencia (`[Spec §...]`,
  `[Contract §...]`, `[Gap]`, `[Ambiguity]`, `[Conflict]`, `[Assumption]`).
</content>
