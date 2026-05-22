<!--
Sync Impact Report
- Version: (none) → 1.0.0  [initial ratification]
- Version: 1.0.0 → 1.1.0  [MINOR: optional-deps carve-out]
- Bump rationale: constituicao inexistente antes; criacao inicial versao 1.0.0.
  Amendment 1.1.0 adiciona subsecao no Principio II disciplinando "deps opcionais
  com fallback graceful" em tres condicoes cumulativas; nota complementar no
  Decision Framework item 4 reconhece subsecoes de carve-out como mecanismo valido
  de conformidade quando precedidas por amendment MINOR.
- Principios criados (1.0.0):
  I.   SDD como regra recursiva (NON-NEGOTIABLE)
  II.  POSIX sh puro para scripts (NON-NEGOTIABLE)
  III. Formato canonico de skill: progressive disclosure + gotchas + description-como-trigger
  IV.  Zero coleta remota (NON-NEGOTIABLE)
  V.   Profundidade sobre adocao
- Principios afetados por 1.1.0: II expandido (nao alterado); I/III/IV/V inalterados.
- Secoes adicionadas (1.0.0): Quality Standards, Decision Framework, Governance
- Secoes modificadas (1.1.0): Principio II recebe subsecao "Optional dependencies
  with graceful fallback"; Decision Framework item 4 recebe nota clarificadora.
- Artefatos que precisam atualizacao (resolver quando conveniente):
  * CLAUDE.md: adicionar secao curta "Principios" apontando para docs/constitution.md (NAO URGENTE — os principios ja sao seguidos de facto). Avaliado novamente em 2026-04-24 durante amendment 1.1.0: mantido nao-urgente; Principio V favorece profundidade sobre marketing; rastreabilidade essencial ja existe via spec↔plan↔constitution.
  * docs/specs/shell-scripts-tests/plan.md §Constitution Check: atualmente diz "Constitution nao presente"; re-rodar /analyze ou re-checar manualmente agora que existe
  * README.md: referenciar docs/constitution.md na secao de "Contribuindo" (opcional)
  * docs/specs/cstk-cli/plan.md §Complexity Tracking: RESOLVIDO em 2026-04-24
    — secao reescrita como "Optional-dep registry" referenciando o amendment
    1.1.0 e demonstrando conformidade com as tres condicoes (a)(b)(c).
- TODOs pendentes: nenhum bloqueante.
-->

# Claude Code Toolkit Constitution

Principios imutaveis que governam todas as decisoes de arquitetura, qualidade e processo
deste toolkit. Derivados do briefing em `docs/01-briefing-discovery/briefing.md` e
ratificados pelo autor/mantenedor. Violacoes sao bloqueantes em `/plan` e `/analyze`.

## Core Principles

### I. Spec-Driven Development Aplica-se Recursivamente (NON-NEGOTIABLE)

Este toolkit existe para promover SDD — e, portanto, **segue SDD a si proprio**. Toda
feature nao-trivial (nova skill, mudanca de formato de SKILL.md, refatoracao cross-skill,
infraestrutura como suite de testes, etc.) entra via pipeline completo:
`briefing` (se ausente) → `specify` → `clarify` (quando houver ambiguidade) → `plan` →
`create-tasks` → `analyze` → `execute-task`.

**MUST:**

- Nenhuma feature nao-trivial e implementada sem `spec.md` e `tasks.md` em
  `docs/specs/{feature}/`. Hotfixes de 1-5 linhas (tipografia, bug obvio localizado) sao
  a unica excecao; qualquer coisa maior exige artefato.
- Toda mudanca que altere o CONTRATO de uma skill (nome, trigger, output, paths de
  saida) exige `spec.md` + bump de versao no CHANGELOG + nota de BREAKING se aplicavel.

**Rationale:** o briefing define o proposito do projeto como "documentacao desde o d0,
correcoes como especificacoes validadas". Um toolkit de SDD que nao pratica SDA a si
mesmo e auto-contraditorio e perde legitimidade para usuarios que o aplicam nos proprios
projetos.

### II. Scripts POSIX sh Puros, Zero Dependencia Externa (NON-NEGOTIABLE)

Scripts auxiliares de skills (geradores de ID, validadores, metricas, scaffolding) sao
escritos em POSIX sh portavel e rodam em qualquer ambiente POSIX sem setup.

**MUST:**

- Shebang `#!/bin/sh` (nao `#!/bin/bash`).
- `set -eu` no inicio (fail-fast em erros e variaveis indefinidas).
- Sem Bash-isms: nenhum array, nenhum `[[ ]]`, nenhum `$'...'`, nenhum `<<<`, nenhum
  `local` (use subshell), nenhum `function` keyword.
- Zero dependencia externa alem de ferramentas POSIX canonicas: `find`, `grep`, `awk`,
  `sed`, `mktemp`, `sort`, `diff`, `cmp`. Ferramentas nao-POSIX (`jq`, `ripgrep`, `fd`,
  `bats`) estao banidas em scripts que acompanham skills.
- Mensagens de erro em stderr, saida de dados em stdout. Exit codes convencionais
  (0 sucesso, 1 erro geral, 2 uso incorreto).

#### Optional dependencies with graceful fallback (amendment 1.1.0)

Excecao disciplinada a regra geral de zero dependencia externa. Uma ferramenta
nao-POSIX PODE ser invocada por codigo do toolkit desde que as tres condicoes
abaixo sejam CUMULATIVAS (todas MUST ser satisfeitas):

(a) **Uso genuinamente opcional com fallback graceful documentado E verificavel.**
    A feature MUST funcionar sem a ferramenta; quando ausente, o fallback
    produz resultado correto (possivelmente com UX degradada) e MUST ser coberto
    por teste automatizado.
(b) **Codigo que referencia a dep confinado em UM unico arquivo identificavel.**
    A dep nao se espalha pela codebase — grep pelo nome do executavel localiza
    todas as mencoes em um unico arquivo fonte.
(c) **Dep declarada explicitamente na documentacao da feature que a introduz.**
    A dep aparece em `spec.md` ou `plan.md` da feature com justificativa, caminho
    do arquivo confinado (condicao b) e descricao do fallback (condicao a).

**O que NAO muda:**

- Bash-isms permanecem proibidos em qualquer script (opcional ou nao). A
  disciplina POSIX sh do bloco MUST acima continua integral.
- Ferramentas ja banidas nominalmente (`ripgrep`, `fd`, `bats`) permanecem
  vetadas inclusive como deps opcionais — este carve-out nao as reabilita.
- Dependencias obrigatorias (sem fallback) permanecem proibidas sob o bloco MUST
  do Principio II.

**Primeiro caso concreto sob esta regra**: dep opcional em `jq` em
`cli/lib/hooks.sh` da feature `cstk-cli`, introduzida em amendment 1.1.0. Ver
[specs/cstk-cli/spec.md](specs/_archived/cstk-cli/spec.md) §FR-009d e
[specs/cstk-cli/plan.md](specs/_archived/cstk-cli/plan.md) §Complexity Tracking.

**Rationale:** o briefing marca POSIX sh como restricao tecnica explicita. Bug recente
em `metrics.sh` (`grep -c` sem matches concatenando "0\n0" via fallback `|| printf '0'`)
mostrou que mesmo POSIX puro exige disciplina — introduzir Bash seria degradar o padrao,
nao proteger dele. Adicionar dependencia externa transforma "clone e uso" em "clone,
instale, configure", contrariando o modelo de distribuicao via `cp -r`.

### III. Formato Canonico de Skill: Progressive Disclosure, Gotchas, Description-como-Trigger

Toda skill segue a anatomia documentada no README secao "Anatomia de uma skill". O
contrato nao e opcional — e parte do valor que o usuario espera ao clonar o toolkit.

**MUST:**

- `SKILL.md` e o ponto de entrada enxuto — fluxo de execucao, regras de alto nivel,
  ponteiros para subpastas. Evitar colar templates, exemplos ou referencias inteiros no
  `SKILL.md`.
- Conteudo pesado vive em subpastas: `templates/` (preenchiveis), `references/`
  (catalogos/guias), `examples/` (good vs bad), `scripts/` (deterministicos POSIX),
  `config.json` (parametros por projeto). Carregados sob demanda.
- Secao **Gotchas** e obrigatoria em toda `SKILL.md`. Documenta armadilhas reais
  observadas, nao hipoteticas. Um SKILL.md sem Gotchas e incompleto.
- Campo `description` no frontmatter/cabecalho e escrito como **trigger condition**:
  "Use quando X, Y ou Z. Tambem quando mencionar A, B, C. NAO use quando W." Nao e
  resumo narrativo da skill.

**Rationale:** o briefing cita progressive disclosure como "anatomia de skill", gotchas
como "conteudo mais valioso", e o padrao description-como-trigger aparece no README
secao "Contribuindo" item 3. Skills que fogem do formato consomem mais contexto do
modelo (pior custo), sao menos invocaveis (pior discoverability), e perdem o saber
acumulado do autor (gotchas vazios = repeticao de erros).

### IV. Zero Coleta Remota de Uso ou Dados (NON-NEGOTIABLE)

Skills deste toolkit rodam no ambiente local do usuario e nao enviam nada para fora.

**MUST:**

- Nenhuma skill faz requisicao de rede para endpoint de telemetria, analytics,
  feature-flag remoto, ou servico de erro tipo Sentry.
- Fetches HTTP sao permitidos apenas quando o proposito da skill e inerentemente de
  rede (ex: skill que consulta documentacao externa sob demanda do usuario) e o fetch
  e do dominio-alvo da pergunta, nao de um endpoint do autor.
- Logs e artefatos gerados pelas skills permanecem no filesystem local do usuario.
  Nenhum upload automatico.

**Rationale:** o briefing marca "telemetria/observabilidade de uso das skills" como
explicitamente fora de escopo, com rationale de simplicidade e privacidade. O custo
aceito e cegueira operacional do autor sobre adocao e bugs silenciosos. Violar este
principio quebraria contrato com usuarios que clonam o repo e introduziria vetor de
confianca que nao foi pactuado.

### V. Profundidade e Reducao de Retrabalho Acima de Metricas de Adocao

Quando ha tensao entre (a) polir e aprofundar o que existe e (b) perseguir metricas
externas (stars, forks, mencoes, integracoes virais), prioriza-se (a).

**SHOULD:**

- Decisoes de escopo favorecem reducao mensuravel de retrabalho em projetos reais
  onde o toolkit e aplicado, nao geracao de visibilidade.
- Marketing, templates de issue/PR formais, CONTRIBUTING.md elaborado, badges e
  similares nao sao prioridade. O projeto aceita contribuicoes caso-a-caso.
- Features "legais de anunciar" com baixo valor de uso sao deprioritizadas em favor
  de refinamentos menos vistosos (ex: melhores gotchas, defaults mais afiados, novos
  cenarios de teste).

**Rationale:** o briefing, na pergunta 6, escolhe explicitamente profundidade (opcao B)
como ambicao de 12 meses sobre adocao (A), alcance (C) ou uso pessoal puro (D). A
metrica "reducao de retrabalho" esta marcada como Item a Definir — e ok nao ter a
metrica ainda; **nao** e ok deixar a prioridade se inverter silenciosamente.

## Quality Standards

Estes padroes operacionais implementam os principios acima. Sao verificaveis e
formam o quality gate em `/plan` (Constitution Check) e `/analyze`.

- **Toda skill tem SKILL.md + Gotchas** — verificavel via `find global/skills -name
  SKILL.md -exec grep -L '## Gotchas' {} +` (deve retornar vazio).
- **Scripts sao POSIX** — scripts que violam Principio II sao detectados por shellcheck
  com dialeto `sh` (ex: `shellcheck -s sh script.sh`). Zero warnings e meta; warnings
  justificaveis sao comentados em linha no script.
- **Scripts tem teste automatizado** — conforme suite `docs/specs/shell-scripts-tests/`
  (em construcao). Quando concluida, a regra se torna: adicionar `.sh` em
  `global/skills/**/scripts/` sem `tests/test_<nome>.sh` correspondente e detectavel via
  `tests/run.sh --check-coverage`.
- **Feature nao-trivial tem `docs/specs/{feature}/spec.md`** — verificavel observando
  se commits substantivos sao acompanhados de artefato. Principio I formaliza.
- **Versionamento SemVer com CHANGELOG** — mudancas que alteram contrato de skill
  (rename, remocao, mudanca de output) sao MAJOR e documentadas em `CHANGELOG.md`.
- **Nenhum secret em repo** — credenciais, tokens, endpoints privados jamais commitados.
  Skills que precisam de configuracao sensivel leem de variavel de ambiente ou
  `config.json` local (nao versionado).

## Decision Framework

Quando principios entram em tensao, a ordem de desempate e:

1. **NON-NEGOTIABLE vence SHOULD.** Principios I, II e IV sao MUST — nao cedem a
   Principio V. Se um refinamento de profundidade exigiria telemetria (IV) ou Bash
   (II), o refinamento e rejeitado ou redesenhado.

2. **Entre MUST e MUST, cita o briefing.** Se dois MUST aparentemente conflitam (ex:
   adicionar novo formato de skill conflita com formato canonico existente), o
   desempate e decidido pela intencao registrada no briefing. Se o briefing nao cobre,
   o caso merece emenda da constituicao (MINOR bump), nao decisao ad-hoc.

3. **Reversibilidade favorece exploracao; irreversibilidade favorece conservadorismo.**
   Decisao reversivel (nova skill experimental em `global/skills/`, novo template) pode
   ser tomada rapido. Decisao irreversivel ou de alto custo de reversao (renomear skill
   amplamente usada, mudar layout de diretorios) exige `spec.md` + discussao explicita.

4. **Excecao requer documentacao explicita.** Se um caso genuinamente precisa violar
   SHOULD (Principio V), registrar no `plan.md` da feature com secao `Constitution
   Exception` explicando o trade-off e o sunset da excecao. Excecao a MUST
   (Principios I, II, IV) exige amendment da constitution — nao ha opt-out tacito.
   Subsecoes de carve-out dentro de um Principio (como a subsecao "Optional
   dependencies with graceful fallback" sob Principio II, introduzida em amendment
   1.1.0) sao mecanismo valido de conformidade quando precedidas por amendment com
   MINOR bump — representam disciplina explicita do principio, nao opt-out.

## Governance

**Amendment process:**

- Mudancas na constitution sao propostas via `spec.md` em `docs/specs/constitution-amend-{topico}/`.
- Amendment que remove ou redefine principio incompativelmente = MAJOR bump.
- Amendment que adiciona novo principio ou expande materialmente uma secao = MINOR bump.
- Amendment que clarifica texto sem mudar semantica = PATCH bump.

**Propagacao obrigatoria em MAJOR/MINOR:**

- Atualizar Sync Impact Report no topo deste arquivo.
- Re-rodar `/analyze` em todas as features ativas (specs com tasks pendentes) e
  documentar violacoes introduzidas pela emenda.
- Atualizar CLAUDE.md se o novo principio afeta instrucoes gerais do projeto.

**Authority:**

- Autor/mantenedor (jot) aprova amendments. Contribuicoes externas a constitution
  seguem o processo de PR caso-a-caso ja descrito no briefing (nenhum processo formal).

**Versioning:**

- SemVer rigoroso: MAJOR.MINOR.PATCH.
- Datas em ISO YYYY-MM-DD.
- Versao inicial 1.0.0 — qualquer amendment futuro muda este rodape.

**Version**: 1.1.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-04-24
