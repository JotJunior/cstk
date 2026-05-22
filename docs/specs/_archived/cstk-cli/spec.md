# Feature Specification: CSTK — Claude Specs Toolkit CLI

**Feature**: `cstk-cli`
**CLI name**: `cstk` (canonico — ver Clarifications 2026-04-22)
**Created**: 2026-04-22
**Status**: Draft

## Resumo

Hoje as skills deste toolkit sao distribuidas via `cp -r global/skills/ ~/.claude/skills/`
(documentado no `CLAUDE.md`). Esse fluxo tem dois problemas cronicos: (a) drift entre o
repositorio fonte e a copia instalada, que o proprio CLAUDE.md ja reconhece como recorrente;
(b) nenhuma forma de saber qual versao esta instalada nem de aplicar apenas as mudancas
novas. Esta feature adiciona uma CLI dedicada (`cstk`) que instala skills no escopo global
(`~/.claude/skills/`) ou de projeto (`./.claude/skills/`), detecta e aplica atualizacoes
sem sobrescrever edicoes locais cegamente, e sabe atualizar a si propria.

## Clarifications

### Session 2026-04-22

- Q: Fonte de distribuicao canonica das skills e do CLI? → A: Tarballs de releases
  versionadas publicadas no GitHub (tags SemVer). Cliente precisa apenas de `curl`/`tar`;
  versao alvo = tag. Skills e CLI podem ter releases separadas ou conjuntas; nao exige
  clone git do repositorio nem infra propria do mantenedor.
- Q: Politica de conflito no update quando skill instalada tem edicoes locais? → A:
  Abortar a skill afetada com mensagem clara. Usuario deve passar `--force` para
  sobrescrever ou `--keep` para manter a cozinha local intocada nessa skill. Outras
  skills continuam atualizando normalmente. Nenhum backup automatico, nenhuma mesclagem
  automatica.
- Q: Granularidade de selecao no install? → A: Perfis nomeados (`all`, `sdd`,
  `complementary`, `language-go`, `language-dotnet`) + cherry-pick por nome tambem
  suportado. Default = `sdd` (pipeline SDD tende a ser o uso global mais comum;
  language-* faz sentido principalmente em escopo de projeto onde a linguagem e
  conhecida). Adicionalmente, modo interativo disponivel via flag, onde a CLI lista
  perfis e skills e permite selecao manual sem exigir que o usuario decore nomes.
- Q: Catalogo da CLI inclui hooks de `language-related/*/hooks/`? → A: Sim, mas
  com restricoes: (a) hooks sao instalaveis APENAS em escopo de projeto, nunca global
  — perfis `language-*` em escopo global instalam apenas skills e ignoram hooks; (b)
  merge do `settings.json` da linguagem em `./.claude/settings.json` do projeto segue
  deteccao de ambiente: se `jq` estiver disponivel, CLI faz merge automatico; se nao,
  CLI imprime na saida o bloco JSON exato que o usuario precisa colar manualmente no
  arquivo e referencia a documentacao local. CLI nao tenta merge POSIX puro de JSON
  para evitar risco de corromper o arquivo.
- Q: Nome definitivo do binario/comando da CLI? → A: `cstk` (Claude Specs Toolkit).
  Confirmado como nome final e canonico. Qualquer rename futuro e BREAKING e exige
  bump MAJOR conforme politica documentada em CLAUDE.md.

### Session 2026-04-22 (follow-up — gap CHK023)

- Q: Como o usuario dispara o self-update? → A: Exclusivamente via comando explicito
  `cstk self-update`. NAO ha auto-check passivo em nenhum outro comando da CLI (list,
  install, update, doctor) — zero trafego de rede sem demanda explicita do usuario,
  alinhado com Principio IV da constitution (Zero coleta remota). Para verificar sem
  aplicar, o usuario invoca `cstk self-update --check`, que tambem e explicito.
- Q: Como e a primeira instalacao (bootstrap) quando ainda nao ha `cstk` na maquina?
  → A: Via one-liner documentado no README (`curl <url-asset-install.sh> | sh`) que
  baixa o `install.sh` bootstrap da ultima release, que por sua vez baixa o tarball,
  valida checksum e instala `cstk` + `cli/lib/`. Bootstrap e self-update sao fluxos
  DISTINTOS: self-update pressupoe CLI ja instalado e falha com mensagem clara
  instruindo o one-liner caso o binario nao exista.
- Q: Integridade de tarballs baixados e requisito explicito? → A: Sim. Verificacao
  SHA-256 e OBRIGATORIA em todo download de tarball feito pela CLI (bootstrap,
  install, update, self-update). Mismatch aborta a operacao sem realizar qualquer
  escrita no filesystem de destino. O checksum canonico vem de um asset `.sha256`
  publicado na mesma release que o tarball.
- Q: Self-update pode tocar o manifest de skills? → A: Nao. Self-update e estritamente
  sobre o binario `cstk` e a biblioteca `cli/lib/`. Invariante explicita: self-update
  NUNCA le, escreve, nem modifica de qualquer forma o manifest de skills (global ou
  projeto). Verificavel: mtime dos manifests antes e depois do self-update e
  identico. Trava a porta contra regressoes que corromperiam estado de instalacao.
- Q: Semantica operacional de "atomico" em FR-006 (unidade, estado nao-funcional,
  substituicao parcial)? → A: Atomicidade estrita do par binario+biblioteca. Apos
  qualquer interrupcao, o sistema MUST estar 100% na versao antiga OU 100% na nova,
  nunca em estado misto. "Estado nao-funcional" e operacionalizado como qualquer
  situacao em que um comando previamente funcional (pre self-update) falhe, retorne
  exit code diferente, ou produza output inconsistente com a versao reportada por
  `cstk --version`. Substituicao parcial (bin novo + lib antiga, ou inverso) e
  VIOLACAO de FR-006. A implementacao fica livre (stage-and-rename, symlink flip,
  outras), desde que o observavel acima seja preservado.

### Session 2026-04-24

- Q: Estado transiente entre rename de lib e rename de bin (quando kill dura
  impede trap rodar rollback) e observavel pela proxima invocacao — esse terceiro
  estado viola FR-006? → A: Nao. FR-006 passa a reconhecer explicitamente um
  terceiro estado observavel "retry-required": a CLI detecta divergencia bin/lib
  no boot-check e aborta imediatamente com mensagem instrutiva. Nenhum comando
  opera, mas tambem nenhum retorna output incorreto. Proxima invocacao de
  `cstk self-update` completa o rollback. Trade-off aceito: a alternativa
  (rollback automatico no boot) teria surface de bug maior e menos transparencia
  para o usuario.

### Session 2026-05-09 (FASE 12 — `cstk 00c`)

- Q: Apos confirmacao do dry-run em `cstk 00c <path>`, como a slash command
  montada chega ao `claude` spawnado? → A: Auto-submit. `exec claude
  "/agente-00c '<desc>' ..."` envia a slash command como primeiro turno
  automaticamente; o `claude` inicia ja processando o pedido sem exigir Enter
  adicional do operador. O dry-run de FR-016e e a unica confirmacao final.
  Pre-typed (aguardando Enter) e print+paste foram rejeitados por adicionarem
  passo manual redundante apos o dry-run.
- Q: Como `cstk 00c` deve reagir quando `~/.claude/commands/agente-00c.md`
  ausente? → A: Prompt + auto-install. Detecta ausencia e pergunta `Comando
  agente-00c nao instalado. Instalar agora via 'cstk install'? [Y/n]`. Default
  Y roda `cstk install` em foreground (progresso visivel) e prossegue para os
  prompts; N aborta com exit 1 e instrucao manual. Auto-install silencioso
  (sem prompt) foi rejeitado por quebrar o principio de explicit operations
  do cstk; instruct-only puro foi rejeitado por friccao desnecessaria.
- Q: Como `cstk 00c` deve reagir quando `jq` esta ausente do PATH? → A: Hard
  fail upfront. `jq` entra no dep check de FR-016d como requisito ao lado de
  `claude` e `agente-00c.md`; ausencia aborta com exit 1 e mensagem de
  instalacao por OS (`brew install jq` no macOS, `apt install jq` no Linux).
  Justificativa: `jq` ja e dependencia de runtime do `agente-00c-runtime`
  (operacoes em `state.json`); sem ele, o orquestrador falha na primeira
  onda — falha cedo e em local explicito e melhor UX que erro tardio dentro
  da sessao do `claude`. Skip-com-warning e accept-raw foram rejeitados por
  apenas adiarem o erro.
- Q: Como tratar symlinks em `<path>` durante validacao? → A: Resolver via
  `realpath -m` (que aceita paths inexistentes) e checar o destino resolvido
  contra a lista de zonas proibidas. Mesma postura defensiva do `path-guard.sh`
  no `agente-00c-runtime` (defesa contra T2 — symlinks adversariais). Symlinks
  legitimos que apontam para outros locais do `$HOME` continuam funcionando;
  symlinks que apontam para `/etc`, `~/.ssh`, etc. sao rejeitados. Reject-any
  (mesmo legitimos) e trust-operator foram rejeitados por excesso/insuficiencia
  de proteção respectivamente.
- Q: Em re-execucao com `<path>` ja existente e contendo arquivos, como
  tratar? E como tratar `.agente-00c-whitelist.txt` colidindo? → A: Recusar
  diretamente (sem prompt). A finalidade do `cstk 00c` e ser **atalho para
  criar projeto NOVO**, nao retomar/reusar existente. Dir nao-vazio aborta
  com exit 1 e mensagem `<path> ja existe e nao esta vazio. Use 'cstk 00c'
  apenas em paths novos ou vazios; para retomar uma execucao existente do
  agente-00C use '/agente-00c-resume --projeto-alvo-path <path>' diretamente
  no claude`. Como consequencia, a questao "como tratar
  `.agente-00c-whitelist.txt` ja existente" torna-se moot — o fluxo nunca
  alcanca a etapa de persistencia se o dir tem conteudo. Prompt-com-confirmacao,
  append-com-dedup e skip-com-reuso foram rejeitados por contradizerem a
  finalidade do subcomando.

### Session 2026-05-09 (FASE 12 — round 2: gaps de prioridade ALTA)

- Q: Como `cstk 00c` deve obter logica de path-guard / sanitize /
  whitelist-validate (ja existentes no `agente-00c-runtime`)? → A:
  Reimplementar em `cli/lib/` com referencia cruzada. `cstk` e o instalador
  (camada inferior) e `agente-00c-runtime` e algo que ele distribui (camada
  superior). Validacao de path precisa rodar ANTES do dep check de FR-016d
  — depender do runtime para validar criaria chicken-and-egg. Cada bloco
  reimplementado em `cli/lib/` MUST conter comentario apontando o canonico
  em `global/skills/agente-00c-runtime/scripts/<script>.sh`; divergencias
  futuras precisam ser refletidas em ambos por PR review (gate manual). A
  cobertura esperada e: zonas proibidas (espelha `path-guard.sh`), escape
  de single-quotes/path-traversal/comprimento (espelha `sanitize.sh`),
  regex de URL e patterns overly-broad (espelha `whitelist-validate.sh`).
  Shell-out e hibrido foram rejeitados por acoplamento e complexidade.
- Q: A lista de 14 zonas proibidas em FR-016b deve ser extensivel pelo
  operador (env var, arquivo de config) ou fechada na FASE 12? → A: Fechada.
  cstk e ferramenta pessoal/experimental, sem casos de uso corporativos
  conhecidos. Operadores que precisam de zonas adicionais abrem issue ou
  fork. Extensibilidade pode ser adicionada em fase futura se demanda real
  aparecer. Env var e config file foram rejeitados por adicionar codigo
  (parser, defaults, doc) sem ROI atual.
- Q: Como tratar invocacoes concorrentes de `cstk 00c <path>` no mesmo
  path? → A: Lockfile per-path. Logo apos validar `<path>` (e antes de
  qualquer prompt), criar `<path>/.cstk-00c.lock/` via `mkdir` atomico. Se
  mkdir falha (lock ja existe), abortar com exit 1 e mensagem `outra
  instancia de cstk 00c em andamento neste path` (sem mexer no estado
  existente). Lock liberado no `exec claude` final ou via `trap` on exit
  (Ctrl+C, falha de prompt). Cobre race entre prompts e exec sem complicar.
  Sem-lock e lock-global foram rejeitados por trade-off insuficiente
  e restricao excessiva, respectivamente.
- Q: Como tratar `cstk install` aninhado em FR-016d (c) quando outro
  `cstk install` ja esta rodando paralelamente (FR-015 lockfile)? → A:
  Respeitar o lock + aborto explicito. Nested install usa o mesmo lockfile
  de FR-015; se lock esta tomado, nested install falha imediatamente; `cstk
  00c` captura o exit, libera seu proprio lock per-path (FR-016h), e aborta
  com exit 1 e mensagem `outro cstk install em andamento. Aguarde, depois
  rode 'cstk 00c <path>' novamente`. Sem retry automatico nem bypass.
  Operador escolhe quando tentar de novo. Wait-com-timeout e bypass foram
  rejeitados.
- Q: Quando `cstk install` aninhado falha por outro motivo (rede, sha
  mismatch, disco cheio), como `cstk 00c` deve reagir? → A: Abort sem
  rollback. Capturar exit code do install (qualquer != 0) e abortar com
  exit 1 proxiando o motivo (`cstk install falhou (exit code N): <razao
  stderr>`). Diretorio criado em FR-016b/12.2.1 PERMANECE no disco — sem
  rollback automatico, alinhado com regra geral do edge case Ctrl+C.
  Operador decide se remove o dir vazio antes de tentar de novo. Mensagem
  aponta `cstk install --force` para retry manual fora do `cstk 00c`.
  Lock per-path liberado via trap on exit. Cleanup-de-diretorio e
  retry-interativo foram rejeitados por quebrar simetria com regra Ctrl+C
  e por pouco ROI, respectivamente.

## User Scenarios & Testing

### User Story 1 - Instalacao inicial de skills no escopo global (Priority: P1)

Desenvolvedor recem-clonou o toolkit em uma maquina nova e precisa que todas as skills
fiquem disponiveis para o Claude Code. Ele executa a CLI uma unica vez apontando para o
escopo global e passa a ter todas as skills do toolkit acessiveis em qualquer projeto.

**Why this priority**: sem instalacao inicial nao ha nada. Esta story e o MVP — entrega
o valor principal (parar de fazer `cp -r` manual e passar a ter uma acao atomica e
rastreavel), mesmo que update, project-scope e self-update ainda nao existam.

**Independent Test**: em uma maquina/ambiente sem `~/.claude/skills/` povoado, rodar o
comando de instalacao global, verificar que todas as skills do toolkit aparecem no
diretorio destino, e que o Claude Code consegue invoca-las por nome.

**Acceptance Scenarios**:

1. **Given** `~/.claude/skills/` vazio ou inexistente, **When** o usuario executa o
   comando de instalacao em escopo global, **Then** todas as skills listadas no
   toolkit ficam disponiveis em `~/.claude/skills/{nome}/` com estrutura identica a
   `global/skills/{nome}/`.
2. **Given** uma maquina recem-configurada sem conexao previa com o toolkit, **When**
   o usuario executa o comando, **Then** a CLI reporta quantas skills foram instaladas
   e grava um registro do que foi instalado e em qual versao.
3. **Given** `~/.claude/skills/foo/` ja existe porque o usuario tem skills de terceiros,
   **When** o comando de instalacao roda, **Then** skills de terceiros (fora do catalogo
   do toolkit) sao preservadas intactas e apenas as skills do toolkit sao instaladas.

---

### User Story 2 - Atualizacao das skills ja instaladas (Priority: P2)

Depois de instalar, o toolkit evolui — skills ganham conteudo novo, bugs de scripts POSIX
sao corrigidos, novas skills sao adicionadas. O usuario precisa trazer essas mudancas para
a copia instalada sem perder edicoes locais que ele tenha feito deliberadamente.

**Why this priority**: endereca diretamente a dor documentada no CLAUDE.md sobre "drift
entre installed e source". Sem atualizacao nao ha razao para o registro de versao existir.
P2 porque so faz sentido depois de ter algo instalado (P1).

**Independent Test**: com uma instalacao existente apontando para uma versao antiga,
rodar o comando de atualizacao e verificar que (a) skills desatualizadas foram atualizadas,
(b) skills ja em dia foram puladas sem escrita desnecessaria, (c) edicoes locais foram
tratadas segundo a politica definida (ver [NEEDS CLARIFICATION] abaixo).

**Acceptance Scenarios**:

1. **Given** instalacao existente com skill `foo` na versao antiga e fonte com `foo` na
   versao nova, **When** o usuario executa o comando de atualizacao, **Then** `foo`
   passa a refletir o conteudo da versao nova e o registro de versao e atualizado.
2. **Given** instalacao existente onde todas as skills ja estao na versao mais recente,
   **When** o usuario executa o comando de atualizacao, **Then** a CLI reporta que nada
   mudou e nao realiza escritas.
3. **Given** uma skill que deixou de existir no toolkit fonte, **When** o usuario executa
   o comando de atualizacao, **Then** a CLI sinaliza essa skill como removida no fonte
   e pede confirmacao antes de apagar a copia instalada.
4. **Given** instalacao com edicoes locais em `~/.claude/skills/foo/SKILL.md` feitas
   manualmente pelo usuario, **When** o usuario executa o comando de atualizacao e `foo`
   tem versao nova disponivel, **Then** o comportamento segue a politica definida em
   FR-008 (abaixo).

---

### User Story 3 - Instalacao em escopo de projeto (Priority: P3)

Um projeto especifico precisa de um conjunto curado de skills (por exemplo, apenas as
do pipeline SDD, mais uma skill `bugfix` customizada) ou de versao travada diferente da
global. O usuario executa a CLI dentro do diretorio do projeto com a flag de escopo de
projeto, e a instalacao acontece em `./.claude/skills/` isoladamente.

**Why this priority**: escopo de projeto e explicitamente pedido. E util para casos em
que o projeto quer travar versao ou subconjunto de skills, mas nao bloqueia o fluxo
principal de um unico desenvolvedor. Funciona de forma analoga ao escopo global — a
unica diferenca e o diretorio destino e o registro de versao.

**Independent Test**: em um diretorio de projeto sem `.claude/skills/`, rodar o comando
com flag de escopo de projeto, verificar que a instalacao ocorreu em `./.claude/skills/`
e nao tocou `~/.claude/skills/`, e que o Claude Code rodando dentro do projeto ve ambas
as copias (a global e a do projeto, com a do projeto tendo prioridade conforme o
comportamento padrao do Claude Code).

**Acceptance Scenarios**:

1. **Given** CWD em um diretorio de projeto sem `.claude/skills/`, **When** o usuario
   executa instalacao em escopo de projeto, **Then** skills sao instaladas em
   `./.claude/skills/` e `~/.claude/skills/` nao e modificada.
2. **Given** instalacao global e de projeto coexistindo, **When** o usuario executa
   atualizacao em escopo de projeto, **Then** apenas a copia do projeto e atualizada e
   a global permanece intacta.

---

### User Story 4 - Self-update da propria CLI (Priority: P4)

A CLI evolui (novos comandos, correcoes de bugs, suporte a novas estruturas de skill).
O usuario executa um comando `self-update` e a CLI se atualiza para a versao mais recente,
sem que ele precise reinstalar manualmente via clonagem do repositorio.

**Why this priority**: util mas nao bloqueante para o MVP. Nos primeiros dias a CLI pode
ser distribuida junto do toolkit via `make install` ou `git pull`; self-update e
conveniencia que paga o proprio custo so quando a base de usuarios cresce ou quando a
CLI passa a ter ciclo de release independente.

**Independent Test**: com uma versao antiga da CLI instalada e uma versao nova disponivel
no canal de distribuicao, rodar o comando de self-update e verificar que apos a execucao
`cstk --version` reporta a nova versao e todos os comandos continuam funcionais.

**Acceptance Scenarios**:

1. **Given** CLI instalada em versao antiga e canal de distribuicao com versao nova,
   **When** o usuario executa `self-update`, **Then** a CLI e substituida pela versao
   nova e subsequentes invocacoes usam a nova versao.
2. **Given** CLI ja na versao mais recente, **When** o usuario executa `self-update`,
   **Then** a CLI informa que ja esta atualizada e nao realiza escritas.
3. **Given** self-update disparado e falha de rede durante o download, **When** o
   download falha, **Then** a CLI antiga permanece funcional e a falha e reportada —
   nenhuma substituicao parcial pode deixar a CLI quebrada.

---

### User Story 5 - Bootstrap interativo de projeto-alvo do agente-00C (Priority: P5)

Como operador querendo iniciar um POC/MVP guiado pelo `/agente-00c`, eu quero rodar
`cstk 00c <path>` em uma unica passada e ter o diretorio criado, os parametros do
slash command coletados e o `claude` invocado ja na sessao do agente-00C — sem
precisar lembrar a sintaxe do `/agente-00c` nem fazer `mkdir`/`cd` manualmente.

**Why this priority**: complementar ao MVP — quem ja conhece a CLI consegue rodar
`/agente-00c` direto. Ganho real e onboarding de novos usuarios e reducao de friccao
para uso recorrente. Depende das fases 1-11 (CLI base) e do agente-00C ja entregues.

**Independent Test**: com `claude` no PATH e o agente-00C instalado via `cstk install`,
rodar `cstk 00c ./projeto-x`, responder a descricao curta e confirmar — verificar
que o `claude` inicia ja com `/agente-00c "<descricao>" --projeto-alvo-path .`
montado, sem o operador precisar digitar a slash command.

**Acceptance Scenarios**:

1. **Given** `<path>` que nao existe e `claude` no PATH, **When** o operador roda
   `cstk 00c ./novo-projeto` e responde a descricao curta, **Then** o diretorio e
   criado, o CWD e ajustado e `claude` inicia ja com `/agente-00c` auto-submetido
   como primeiro turno (sem exigir Enter adicional do operador).
2. **Given** `<path>` ja existe e contem arquivos, **When** o operador roda
   `cstk 00c ./projeto-existente`, **Then** a CLI aborta com exit 1 e mensagem
   apontando `/agente-00c-resume` como caminho para retomada — NAO ha prompt
   de overwrite porque `cstk 00c` so opera em paths novos ou vazios.
3. **Given** ambiente sem TTY (entrada redirecionada via pipe ou `< /dev/null`),
   **When** `cstk 00c ./x` e invocado, **Then** a CLI aborta com exit 2 e mensagem
   indicando que o subcomando exige TTY interativo.
4. **Given** `claude` ou `jq` ausentes do PATH, **When** o operador roda
   `cstk 00c ./x`, **Then** a CLI aborta com exit 1 e mensagem apontando
   ponteiro de instalacao por OS (sem auto-install — Claude Code e `jq`
   estao fora do escopo do cstk).
5. **Given** `claude` e `jq` presentes mas `~/.claude/commands/agente-00c.md`
   ausente, **When** o operador roda `cstk 00c ./x` e responde `Y` ao prompt
   `Instalar agora via 'cstk install'?`, **Then** `cstk install` executa em
   foreground, completa com exit 0, e o fluxo prossegue para coletar
   descricao/stack/whitelist; resposta `n` aborta com exit 1.

---

### Edge Cases

- Instalacao invocada sem permissao de escrita em `~/.claude/skills/` — CLI deve abortar
  cedo com mensagem clara, sem deixar estado parcial.
- Atualizacao disparada enquanto outra instancia da CLI ja esta rodando — CLI deve
  detectar lock e abortar em vez de produzir corrupcao.
- Self-update em uma maquina offline — CLI deve falhar cedo e preservar a versao atual.
- Registro de versao corrompido ou ausente — CLI deve reconstruir o registro inspecionando
  o estado atual dos diretorios antes de decidir o que atualizar.
- Skill renomeada no fonte (caso ja documentado no CLAUDE.md como BREAKING MAJOR) — o
  update precisa tratar como remocao + adicao, nao tentar mesclar.
- Usuario executa comando em diretorio que parece projeto mas nao tem `.claude/` — CLI
  deve pedir confirmacao antes de criar `.claude/skills/` do zero, para evitar
  poluicao acidental de um diretorio arbitrario.
- `cstk 00c <path>` invocado em diretorio nao-vazio — CLI aborta diretamente
  com exit 1 (sem prompt). Finalidade do subcomando e criar projeto novo;
  retomada de execucao existente e via `/agente-00c-resume`.
- `cstk 00c <path>` em ambiente nao-TTY (CI, pipe, `< /dev/null`) — abortar com
  exit 2; o fluxo e estritamente interativo.
- `cstk 00c <path>` quando `claude` CLI ou `jq` nao esta no PATH — CLI deve
  detectar antes de coletar prompts, abortar com exit 1 e ponteiro de
  instalacao por OS.
- `cstk 00c <path>` quando `~/.claude/commands/agente-00c.md` ausente — CLI
  deve oferecer prompt explicito para rodar `cstk install` automaticamente
  (default Y); apenas N aborta com exit 1.
- `cstk 00c <path>` quando `cstk install` aninhado falha (rede, sha
  mismatch, disco cheio, ou outro `cstk install` paralelo): aborta com
  exit 1 propagando exit code e razao do install. Diretorio criado em
  FR-016b PERMANECE (sem rollback). Operador decide se remove e retenta.
- Operador interrompe (Ctrl+C) durante prompts — abortar limpamente; se diretorio
  ja foi criado, deixar como esta sem rollback automatico (operador decide remover).

## Requirements

### Functional Requirements

- **FR-001**: A CLI MUST oferecer um comando para instalar skills do toolkit em escopo
  global (`~/.claude/skills/`).
- **FR-002**: A CLI MUST oferecer um comando para instalar skills do toolkit em escopo
  de projeto (`./.claude/skills/` relativo ao CWD).
- **FR-003**: A CLI MUST oferecer um comando para atualizar skills ja instaladas,
  detectando quais estao desatualizadas e aplicando apenas as mudancas necessarias.
- **FR-004**: A CLI MUST manter um registro (manifest) por escopo de instalacao,
  informando cada skill instalada e sua versao/identificador correspondente.
- **FR-005**: A CLI MUST suportar self-update — substituir seu proprio binario/executavel
  por uma versao mais nova sem exigir reinstalacao manual. O self-update MUST ser
  disparado exclusivamente por comando explicito do usuario (`cstk self-update`); a
  CLI NAO MUST realizar verificacoes passivas de versao em nenhum outro comando (list,
  install, update, doctor nao falam com a rede para checar novas versoes). Verificacao
  sem instalacao tambem e explicita (`cstk self-update --check`).
- **FR-005a**: A distribuicao MUST disponibilizar um script de bootstrap (`install.sh`)
  publicado junto com cada release, acessivel via URL estavel da ultima release, que
  realize a primeira instalacao via one-liner `curl <url> | sh`. O bootstrap MUST:
  baixar o tarball da ultima release, validar seu checksum, copiar `cstk` para
  `~/.local/bin/` e `cli/lib/` para `~/.local/share/cstk/lib/`, sem exigir sudo nem
  toolchain de build. Bootstrap e self-update sao fluxos DISTINTOS: quando self-update
  e invocado sem o binario existir na maquina, a CLI MUST falhar com mensagem clara
  apontando o one-liner de bootstrap.
- **FR-006**: O self-update MUST ser atomico no par `binario + biblioteca` tratado
  como unidade indivisivel. Apos qualquer interrupcao (rede, kill, falha de disco),
  o sistema MUST ficar em um de tres estados observaveis:
  (a) **100% na versao antiga** — `cstk --version` reporta a versao antiga E todos
      os comandos que funcionavam continuam funcionando com o comportamento antigo;
  (b) **100% na versao nova** — `cstk --version` reporta a versao nova E todos os
      comandos operam com o comportamento novo;
  (c) **transiente "retry-required"** — quando o processo e morto exatamente na
      janela curta entre o commit parcial da biblioteca e o commit do binario, a
      proxima invocacao de `cstk` MUST detectar a divergencia via boot-check e
      abortar imediatamente com mensagem clara instruindo o usuario a re-executar
      `cstk self-update` (que completa o rollback para o estado (a)). Neste estado
      NENHUM outro comando funciona, mas nenhum comando retorna output incorreto —
      a CLI se recusa a agir ate recuperar.

  Substituicao parcial com output incorreto (bin novo rodando com lib antiga que
  responde comandos, ou vice-versa) MUST ser impossivel como estado observavel.
  "Estado nao-funcional" proibido e definido como qualquer estado em que um comando
  retorne exit code zero com output inconsistente com a versao reportada por
  `cstk --version`. O estado (c) acima nao viola a proibicao porque a CLI se recusa
  a operar — um erro claro e aceitavel; output silenciosamente incorreto nao.

  A implementacao (stage-and-rename, symlink flip, co-existencia versionada, etc.)
  fica a cargo do plan tecnico; o FR fixa apenas os estados observaveis.
- **FR-006a**: Self-update MUST NOT ler, escrever ou modificar manifests de skills
  em qualquer escopo (global ou projeto). Self-update opera exclusivamente sobre o
  proprio binario `cstk` e sobre a biblioteca `cli/lib/`, preservando intocado todo
  estado de skills instaladas. Esta invariante MUST ser verificavel no teste: mtime
  dos arquivos `.cstk-manifest` antes e depois de um self-update bem-sucedido MUST
  permanecer identico.
- **FR-007**: A CLI MUST preservar skills de terceiros (fora do catalogo do toolkit)
  presentes no mesmo diretorio destino — instalacao e atualizacao so tocam skills
  cuja origem e o toolkit.
- **FR-008**: Quando uma skill instalada tiver sido editada localmente (conteudo difere
  do manifest registrado), a CLI MUST, durante update, pular essa skill e reportar que
  ela foi preservada, nao realizando nenhuma escrita nela. O usuario MUST poder invocar
  novamente com `--force` para sobrescrever as edicoes locais ou com `--keep` para
  silenciar o aviso e manter a cozinha local. Skills nao afetadas continuam sendo
  atualizadas normalmente no mesmo run — uma skill com edicao local nao interrompe o
  update das demais.
- **FR-009**: A CLI MUST suportar selecao de skills via perfis nomeados (minimo:
  `all`, `sdd`, `complementary`, `language-go`, `language-dotnet`) E via cherry-pick
  por nome explicito de skill. Quando nenhuma selecao e informada, o perfil padrao
  e `sdd` (independente de escopo). A CLI MUST tambem oferecer um modo interativo
  (flag dedicada) que lista perfis e skills disponiveis e permite selecao manual,
  servindo como alternativa ergonomica quando o usuario nao memorizou nomes.
- **FR-009a**: O mesmo mecanismo de selecao (perfis, cherry-pick, interativo) MUST
  valer para update e para install — update em escopo ja instalado opera, por default,
  sobre o que esta instalado naquele escopo (registrado no manifest), e nao sobre o
  perfil default global.
- **FR-009b**: O catalogo que a CLI gerencia MUST incluir: (a) todas as skills de
  `global/skills/` do toolkit; (b) todas as skills de `language-related/{linguagem}/skills/`;
  (c) hooks de `language-related/{linguagem}/hooks/` junto com seu `settings.json` de
  referencia. Hooks sao sempre considerados parte do perfil `language-{linguagem}`.
- **FR-009c**: Hooks e respectivo `settings.json` MUST ser instalaveis APENAS em
  escopo de projeto. Quando um perfil `language-*` e acionado em escopo global, a CLI
  instala apenas as skills desse perfil e omite/ignora os hooks, reportando essa
  omissao no resumo final.
- **FR-009d**: Para mesclar o `settings.json` da linguagem no `./.claude/settings.json`
  do projeto, a CLI MUST: (a) detectar se `jq` esta disponivel no PATH; (b) se sim,
  realizar merge automatico preservando chaves existentes nao conflitantes; (c) se
  nao, imprimir na saida o bloco JSON exato a ser mesclado manualmente e instrucoes
  claras de onde cola-lo. A CLI NUNCA faz merge de JSON sem `jq` nem sobrescreve um
  `./.claude/settings.json` existente.
- **FR-010**: A CLI MUST obter skills e suas atualizacoes a partir de tarballs
  publicados como GitHub Releases do repositorio do toolkit, identificados por tag
  SemVer. A CLI MUST funcionar usando apenas ferramentas POSIX tipicas (`curl`/`tar`)
  sem exigir `git` instalado na maquina do usuario. A CLI MUST falhar com mensagem
  clara quando offline ou quando a release alvo nao existir.
- **FR-010a**: Toda operacao que baixa um tarball do GitHub Releases (bootstrap,
  install, update, self-update) MUST verificar o checksum SHA-256 do tarball contra
  o asset `.sha256` publicado na mesma release ANTES de qualquer escrita no
  filesystem de destino. Em caso de mismatch, a CLI MUST abortar a operacao e
  reportar erro claro, sem ter tocado binario, biblioteca, catalog ou manifest.
  Este requisito se aplica uniformemente a todos os fluxos de download — nao ha
  caminho "rapido" que pule a verificacao.
- **FR-011**: A CLI MUST reportar, em todos os comandos de escrita (install, update,
  self-update), um resumo final com contagem de skills afetadas (instaladas, atualizadas,
  puladas, removidas) e nome/versao da CLI em uso.
- **FR-012**: A CLI MUST aceitar uma flag de dry-run que mostra o que seria feito sem
  executar escritas reais, valido tanto para install quanto update quanto self-update.
- **FR-013**: A CLI MUST ser observavel — o usuario precisa conseguir inspecionar a
  qualquer momento o estado de uma instalacao (quais skills estao presentes, em que
  versao, se ha drift entre manifest e arquivos reais).
- **FR-014**: A CLI MUST detectar quando uma skill foi removida da fonte e sinalizar
  isso ao usuario durante update, exigindo confirmacao antes de apagar.
- **FR-015**: A CLI MUST prevenir execucoes concorrentes no mesmo escopo via lockfile
  para evitar corrupcao quando dois comandos rodam em paralelo.
- **FR-016**: A CLI MUST oferecer um subcomando `cstk 00c <path>` que faz bootstrap
  interativo de um projeto-alvo do agente-00C: validar/criar diretorio em `<path>`,
  coletar parametros do `/agente-00c` via prompts e invocar `claude` ja com a
  slash command montada a partir das respostas.
- **FR-016a**: O subcomando `cstk 00c` MUST recusar execucao em ambiente nao-TTY
  (stdin OU stdout nao-TTY) com exit 2 e mensagem explicita. E fluxo estritamente
  interativo — nao ha modo nao-interativo.
- **FR-016b**: O subcomando `cstk 00c` MUST validar `<path>` antes de qualquer
  escrita: rejeitar vazio, rejeitar componentes de path traversal `..`, e
  resolver o path (incluindo symlinks em qualquer ancestral) via `realpath -m`
  (modo que aceita paths inexistentes) ANTES de checar contra a lista de zonas
  proibidas. A lista canonica e: `/`, `/etc`, `/usr`, `/var`, `/bin`, `/sbin`,
  `/boot`, `/proc`, `/sys`, `~`, `~/.ssh`, `~/.gnupg`, `~/.aws`,
  `~/.config/claude`. A checagem MUST resolver tambem cada zona proibida antes
  de comparar (defesa contra symlinks adversariais — alinhado com
  `path-guard.sh` do `agente-00c-runtime`). Se `<path>` resolvido ja existe e
  contem qualquer arquivo, abortar com exit 1 SEM prompt (finalidade do
  subcomando e criar projeto novo, nao retomar existente — mensagem deve
  apontar `/agente-00c-resume` como caminho para retomada).
- **FR-016c**: O subcomando `cstk 00c` MUST coletar interativamente, em ordem:
  (a) descricao curta do POC/MVP (>=10 chars, <=500 chars; rejeitar
  newlines/`$`/`` ` ``); (b) stack-sugerida em JSON (opcional, validado via `jq`
  quando presente); (c) whitelist de URLs externas (opcional, uma URL por linha
  ate linha vazia, cada linha precisa comecar com `http://` ou `https://`).
- **FR-016d**: O subcomando `cstk 00c` MUST verificar dependencias antes de
  invocar o agente, em ordem:
  (a) binario `claude` no PATH — ausencia aborta com exit 1 e mensagem com
      ponteiro de instalacao do Claude Code (sem auto-install — instalacao do
      Claude Code esta fora do escopo do cstk);
  (b) binario `jq` no PATH — ausencia aborta com exit 1 e mensagem de
      instalacao por OS (`brew install jq` em macOS, `apt install jq` em
      Linux). `jq` e dependencia de runtime do `agente-00c-runtime` (operacoes
      em `state.json`) — falha cedo aqui evita erro tardio dentro da sessao
      do `claude`;
  (c) arquivo `~/.claude/commands/agente-00c.md` presente — ausencia dispara
      prompt explicito `Comando agente-00c nao instalado. Instalar agora via
      'cstk install'? [Y/n]`. Default Y executa `cstk install` em foreground
      (progresso visivel no terminal) e prossegue para coletar prompts apenas
      se a instalacao terminou com exit 0; N aborta com exit 1 e instrucao
      manual. Flag `--yes` aceita o prompt automaticamente. O `cstk install`
      aninhado MUST respeitar o lockfile global de FR-015 — se outro
      `cstk install` ja esta rodando, o nested falha imediatamente e
      `cstk 00c` aborta com exit 1, libera seu lock per-path (FR-016h) e
      mensagem instrutiva `outro cstk install em andamento. Aguarde, depois
      rode 'cstk 00c <path>' novamente`.
- **FR-016e**: O subcomando `cstk 00c` MUST imprimir resumo dry-run antes de
  invocar `claude` (path final, descricao, stack, whitelist e linha exata da
  `/agente-00c` que sera disparada) e exigir confirmacao final `[Y/n]`
  (default Y). Flag `--yes` pula apenas o prompt final (nao pula validacoes
  de FR-016a, FR-016b, FR-016d, nem o prompt de dir nao-vazio).
- **FR-016f**: O subcomando `cstk 00c` MUST fazer `cd` para `<path>` e em seguida
  invocar `claude` via `exec` (substituindo o processo cstk) passando a slash
  command `/agente-00c <args>` como **primeiro turno auto-submetido** — i.e.,
  ao operador NAO e exigido pressionar Enter adicional dentro do `claude`; a
  sessao do agente-00C inicia processando o pedido imediatamente. O dry-run de
  FR-016e e a unica confirmacao final. A whitelist coletada MUST ser persistida
  em `<path>/.agente-00c-whitelist.txt` antes do `exec` e referenciada via
  `--whitelist` (nao inline) para evitar argv overflow e quote-escape.
- **FR-016g**: O subcomando `cstk 00c` MUST sanitizar todas as respostas antes de
  montar a linha de comando: descricao escapada para shell single-quotes
  (`'` -> `'\''`); stack JSON reproduzida via `jq -c` para garantir uma linha;
  nenhum caractere de controle inserido na argv final. A logica de validacao e
  sanitizacao MUST ser reimplementada em `cli/lib/` (espelhando `path-guard.sh`,
  `sanitize.sh`, `whitelist-validate.sh` do `agente-00c-runtime`) e NAO obtida
  via shell-out para os scripts da skill — `cstk` e camada inferior ao runtime.
  Cada bloco reimplementado MUST conter comentario apontando o canonico (path
  exato em `global/skills/agente-00c-runtime/scripts/<script>.sh`); divergencias
  futuras passam por PR review explicito.
- **FR-016h**: O subcomando `cstk 00c` MUST prevenir invocacoes concorrentes no
  mesmo `<path>` via lockfile per-path. Logo apos validacao do `<path>` por
  FR-016b e ANTES de qualquer prompt, MUST tentar `mkdir <path>/.cstk-00c.lock`
  atomicamente; falha do mkdir (lock pre-existente) aborta com exit 1 e
  mensagem `outra instancia de cstk 00c em andamento em <path>` sem alterar
  qualquer outro arquivo. O lock MUST ser liberado tanto no `exec claude`
  final quanto via trap on exit (Ctrl+C, abort de prompt, falha em qualquer
  etapa). FR-015 (lock por escopo skills/commands/agents) NAO se aplica aqui
  — `cstk 00c` opera em diretorio arbitrario fora dos escopos canonicos.

### Key Entities

- **Skill**: unidade de capacidade instalavel. Identificada por nome (ex: `specify`),
  possui um conjunto de arquivos (`SKILL.md` + subpastas opcionais) e uma versao
  derivada da fonte.
- **Installation Scope**: contexto onde skills ficam instaladas. Dois valores: `global`
  (`~/.claude/skills/`) e `project` (`./.claude/skills/` no CWD).
- **Manifest**: registro persistido por escopo que descreve quais skills foram
  instaladas via CLI, em que versao, e quando. E a fonte de verdade para detectar
  drift e decidir o que atualizar.
- **CLI Release**: versao distribuida da propria CLI `cstk`. Consumida pelo comando
  self-update.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Instalacao inicial em escopo global completa em menos de 30 segundos em
  uma maquina padrao de desenvolvimento com conexao de banda larga residencial tipica.
- **SC-002**: Durante um comando de atualizacao onde zero skills tiveram mudanca na
  fonte, a CLI realiza zero escritas em disco no destino (idempotencia observavel via
  timestamps dos arquivos).
- **SC-003**: Apos execucao bem-sucedida de install ou update, 100% das skills
  instaladas correspondem ao conteudo da versao registrada no manifest (verificavel
  via comparacao byte-a-byte entre fonte e destino para skills sem edicao local).
- **SC-004**: Self-update interrompido no meio (kill de processo, queda de rede) deixa
  a CLI anterior 100% funcional em todas as ocorrencias de teste — zero casos de CLI
  quebrada por atualizacao parcial. O conjunto de teste canonico desse SC e o
  Scenario 7b documentado em `quickstart.md`, que enumera 4 pontos de kill ao longo
  da sequencia stage-and-rename: (1) pos-download pre-stage, (2) pos-stage pre-rename,
  (3) entre rename de lib e rename de bin (janela transiente), e (4) pos-commit
  antes do cleanup.
- **SC-005**: Um usuario novo consegue, lendo apenas o `--help` da CLI e o README, fazer
  a instalacao inicial e uma atualizacao subsequente em menos de 5 minutos sem assistencia
  externa.
- **SC-006**: Dry-run produz saida que descreve com precisao 100% das acoes que a
  execucao real faria (nenhuma acao executada em real ausente do dry-run; nenhuma acao
  listada no dry-run ausente da execucao real).
- **SC-007**: A CLI detecta 100% dos casos de drift entre manifest e estado real do
  filesystem. O conjunto de teste canonico e fechado e contem exatamente quatro
  casos: (1) arquivo deletado manualmente, (2) arquivo editado localmente, (3) skill
  renomeada na fonte, (4) skill removida da fonte. Casos adicionais (ex: permissoes
  alteradas, symlinks introduzidos) sao fora do escopo deste SC e podem ser
  adicionados em specs futuras.
- **SC-008**: Rodando `cstk 00c <path>` em maquina com toolkit instalado e `claude`
  no PATH, o operador consegue iniciar uma sessao do agente-00C em <60 segundos,
  contando da invocacao do subcomando ate o `claude` aparecer ja com `/agente-00c`
  montado como primeiro turno.
- **SC-009**: Em 100% das tentativas com `<path>` invalido (path traversal, zona
  de sistema, vazio, ou dir existente nao-vazio), o subcomando `cstk 00c`
  aborta ANTES de qualquer escrita em disco e ANTES de invocar `claude`.
  Verificavel via comparacao de inode/timestamp do filesystem antes/depois,
  e via ausencia de `<path>/.agente-00c-whitelist.txt` no caso de aborto.