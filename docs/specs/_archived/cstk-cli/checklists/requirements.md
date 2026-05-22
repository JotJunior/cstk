# Requirements Checklist: cstk CLI

**Purpose**: valida qualidade dos requisitos com foco em (a) testabilidade dos
Success Criteria e (b) clareza dos FRs relacionados a self-update. "Unit tests
for English" — cada item testa qualidade do REQUISITO escrito, nao da implementacao.
**Created**: 2026-04-22
**Feature**: [spec.md](../spec.md)

## Testabilidade dos Success Criteria

### SC-001 (instalacao < 30s em banda larga tipica)

- [ ] CHK001 - "Banda larga tipica" e quantificado com intervalo de Mbps ou referencia
  a um benchmark publico (ex: 100 Mbps FTTH, sera medio brasileiro 2026)? [Clareza, Spec §SC-001]
- [ ] CHK002 - "Maquina padrao de desenvolvimento" e caracterizado por especificacoes
  minimas (CPU class, SSD vs HDD, RAM) para o teste ser reproduzivel? [Clareza, Spec §SC-001]
- [ ] CHK003 - O cronometro de 30 segundos comeca e termina em pontos observaveis
  bem definidos (ex: invocacao do comando ate exit 0)? [Mensurabilidade, Spec §SC-001]
- [ ] CHK004 - O requisito especifica o tamanho aproximado do catalog base contra o
  qual os 30s valem? (Com 100 skills vs 20, o mesmo 30s pode ser inatingivel.) [Gap, Spec §SC-001]

### SC-002 (zero escritas quando nada mudou)

- [ ] CHK005 - "Zero escritas" e definido precisamente — mtime inalterado? inode
  inalterado? ausencia total de `open(2)` em write mode? [Clareza, Spec §SC-002]
- [ ] CHK006 - O criterio contempla que o manifest em si pode ser re-escrito com
  conteudo identico (escrita ocorre mas byte-a-byte igual)? O requisito deveria
  proibir isso ou aceitar? [Ambiguity, Spec §SC-002]
- [ ] CHK007 - O criterio vale tambem para re-escrita do lockfile (criado+removido
  a cada run)? Se sim, lock-via-`mkdir` tecnicamente escreve no filesystem. [Ambiguity, Spec §SC-002]

### SC-003 (100% match byte-a-byte pos install)

- [ ] CHK008 - O requisito define explicitamente como "skill sem edicao local" e
  identificada para ser incluida no conjunto verificado? [Clareza, Spec §SC-003]
- [ ] CHK009 - Arquivos binarios (se existirem em skills futuras) sao tratados da
  mesma forma que texto? Newline endings sao normalizados? [Gap, Spec §SC-003]
- [ ] CHK010 - Files de metadados (timestamps, attributos extendidos xattr) sao
  parte do "byte-a-byte" ou excluidos? [Ambiguity, Spec §SC-003]

### SC-004 (self-update interrompido = CLI antigo funcional em 100% dos testes)

- [x] CHK011 - O "conjunto de teste" e definido em tamanho e composicao (ex: N
  cenarios cobrindo kill em cada etapa do self-update)? [Gap, Spec §SC-004]
  → Resolvido: SC-004 agora ancora explicitamente no Scenario 7b de
  `quickstart.md`, que enumera 4 pontos de kill ao longo da sequencia
  stage-and-rename (pos-download, pos-stage, janela transiente, pos-commit).
- [ ] CHK012 - "CLI anterior 100% funcional" e verificavel — lista de comandos que
  devem funcionar pos-interrupcao esta especificada? [Clareza, Spec §SC-004]
- [x] CHK013 - O requisito especifica em qual momento do self-update a interrupcao
  pode ocorrer (antes do download, durante, apos checksum, durante mv)? Todos os
  momentos? [Gap, Spec §SC-004]
  → Resolvido: SC-004 lista os 4 pontos canonicos de kill — (1) pos-download
  pre-stage, (2) pos-stage pre-rename, (3) entre rename de lib e rename de bin
  (janela transiente, agora coberta pelo estado retry-required de FR-006), e
  (4) pos-commit antes do cleanup.
- [ ] CHK014 - "100% das ocorrencias de teste" e mensuravel — ha definicao de
  quantas execucoes constituem o conjunto estatistico valido? [Mensurabilidade, Spec §SC-004]

### SC-005 (novo usuario completa install+update em <5min)

- [ ] CHK015 - "Novo usuario" e caracterizado com persona especifica (ja usa Claude
  Code? sabe shell? tem `curl` instalado?) para o teste ser replicavel? [Clareza, Spec §SC-005]
- [x] CHK016 - "Sem assistencia externa" inclui acesso ao stack-overflow/LLM ou exige
  apenas README + --help? [Ambiguity, Spec §SC-005]
  → Resolvido: SC-005 ja restringe explicitamente a "lendo apenas o `--help`
  da CLI e o README", o que exclui assistencia externa (StackOverflow/LLM).
- [ ] CHK017 - A metrica de 5 minutos comeca do zero absoluto (ainda sem cstk
  instalado) ou apos o CLI ja estar instalado? [Clareza, Spec §SC-005]

### SC-006 (dry-run = execucao real)

- [ ] CHK018 - "Uniao simetrica vazia" e operacionalmente mensuravel — formato de
  saida comparavel esta especificado (ex: cada linha de acao em formato fixo)?
  [Mensurabilidade, Spec §SC-006]
- [ ] CHK019 - Mensagens humanas (stderr "Downloading...") que so fazem sentido em
  execucao real sao excluidas da comparacao? [Ambiguity, Spec §SC-006]

### SC-007 (doctor detecta 100% em conjunto de teste)

- [x] CHK020 - O "conjunto de teste" esta enumerado exaustivamente — os 4 casos
  listados (deletado/editado/renomeado/removido) sao a unica cobertura obrigatoria
  ou ha mais? [Clareza, Spec §SC-007]
  → Resolvido: SC-007 declara explicitamente que o conjunto canonico e
  "fechado e contem exatamente quatro casos" — cobertura obrigatoria.
- [ ] CHK021 - O requisito define o que constitui "detectar" — apenas flagear? ou
  propor fix correto? (contratos mencionam --fix.) [Clareza, Spec §SC-007]
- [x] CHK022 - O criterio cobre ordem/interacao de drifts (ex: skill editada E
  removida do catalog simultaneamente) ou apenas casos isolados? [Cobertura, Spec §SC-007]
  → Resolvido: SC-007 declara casos compostos/adicionais (permissoes,
  symlinks, interacoes) como "fora do escopo deste SC" — apenas casos
  isolados sao obrigatorios. Ambiguidade fechada por exclusao explicita.

## Clareza dos FRs relacionados a self-update

### FR-005 (self-update existe)

- [x] CHK023 - O FR define como o usuario dispara o self-update (comando explicito
  vs auto-check no boot de todo invoke)? A spec nao diz. [Gap, Spec §FR-005]
  → Resolvido em Clarifications 2026-04-22 (follow-up): exclusivamente comando
  explicito; zero auto-check. FR-005 atualizado.
- [x] CHK024 - O FR especifica onde a CLI esta instalada para que saiba o que
  atualizar? (Spec silencia; detalhe esta em research, nao em FR.) [Gap, Spec §FR-005]
  → Resolvido via FR-005a (adicionado na mesma session): paths `~/.local/bin/cstk`
  e `~/.local/share/cstk/lib/` agora sao requisito explicito.
- [x] CHK025 - O FR cobre a transicao da primeira release (quando nao ha versao
  anterior) — instalacao inicial e self-update sao o mesmo fluxo? [Gap, Spec §FR-005]
  → Resolvido em Clarifications 2026-04-22 (follow-up): bootstrap one-liner via
  `install.sh` publicado na release; fluxos distintos. FR-005a adicionado.

### FR-006 (self-update atomico)

- [x] CHK026 - "Atomico" e operacionalizado — o FR define qual transicao deve ser
  atomica (binario? biblioteca? ambos conjuntos)? [Clareza, Spec §FR-006]
  → Resolvido via reescrita de FR-006: atomicidade estrita do par bin+lib tratado
  como unidade indivisivel.
- [x] CHK027 - "Estado nao-funcional" e especificado — o que conta como nao-funcional?
  Binario corrompido? Shebang invalido? Faltando um modulo de lib? [Clareza, Spec §FR-006]
  → Resolvido via reescrita de FR-006: comando previamente funcional falha OU exit
  code diferente OU output inconsistente com `cstk --version`.
- [x] CHK028 - O FR contempla cenario onde o bin e atualizado com sucesso mas o
  lib/ falha depois (ou vice-versa) — essa divergencia e aceitavel ou viola
  "atomicidade"? [Ambiguity, Spec §FR-006]
  → Resolvido via reescrita de FR-006: substituicao parcial e VIOLACAO;
  sistema so pode estar 100% antigo ou 100% novo como estado observavel.
- [x] CHK029 - O FR especifica que o CLI-em-execucao atual nao pode ser afetado
  por self-update disparado por outro processo (caso teorico de dois self-update
  simultaneos)? [Gap, Spec §FR-006]
  → Resolvido junto com CHK033: lock exclusivo de self-update em
  `$CSTK_LIB/../.self-update.lock` (research Decision 4, contracts self-update
  passo 1, tasks 5.1.4) impede dois self-update simultaneos.

### FRs correlatos que impactam self-update

- [x] CHK030 - FR-010 define a fonte como GitHub Releases, mas nao explicita se
  self-update valida assinatura/checksum do tarball baixado. Ha requisito explicito
  para isso? [Gap, Spec §FR-010, §FR-006]
  → Resolvido em Clarifications 2026-04-22 (follow-up): SHA-256 obrigatorio em todo
  download de tarball; mismatch = abort sem escrita. FR-010a adicionado.
- [ ] CHK031 - FR-011 exige summary com "nome/versao da CLI em uso" — vale para
  self-update reportar versao ANTIGA ou NOVA no summary? Ambiguidade podera gerar
  confusao operacional. [Ambiguity, Spec §FR-011]
- [ ] CHK032 - FR-012 exige dry-run em self-update. O FR cobre como dry-run reporta
  a versao alvo e o plano de arquivos tocados sem realmente tocar? [Clareza, Spec §FR-012]
- [x] CHK033 - FR-015 previne execucoes concorrentes por escopo de skills. Self-update
  nao e ligado a escopo — ha requisito paralelo impedindo dois self-update
  simultaneos ou esse caso esta nao-especificado? [Gap, Spec §FR-015, §FR-005]
  → Resolvido como parte do ajuste cirurgico pos-clarify FR-006: lock exclusivo de
  self-update em `$CSTK_LIB/../.self-update.lock` documentado em research Decision 4,
  tasks 5.1.4 e contracts self-update passo 1.

## Consistencia cross-requirement

- [x] CHK034 - SC-004 (self-update interrompido = CLI antigo funcional) e consistente
  com a politica de FR-006 (atomico)? Se atomico, interrompido deveria significar
  "NADA foi substituido" — e isso esta escrito inequivocamente? [Consistencia, Spec §SC-004, §FR-006]
  → Resolvido: FR-006 reescrito enumera 3 estados observaveis pos-interrupcao
  (100% antigo, 100% novo, retry-required) e proibe substituicao parcial com
  output incorreto. SC-004 ancora no Scenario 7b (4 kill points) e o estado
  retry-required cobre exatamente a janela transiente em que "NADA foi
  substituido" nao e literalmente verdade — alinhamento explicito.
- [x] CHK035 - SC-005 (novo usuario em 5min) depende da existencia de install
  via one-liner/bootstrap. Esse bootstrap e requisito funcional explicito ou apenas
  detalhe do plan? [Gap, Spec §SC-005]
  → Resolvido via FR-005a: bootstrap via one-liner `curl <url-install.sh> | sh`
  publicado junto com cada release e agora requisito funcional formal.
- [ ] CHK036 - FR-005 diz "suportar self-update" mas nao referencia explicitamente
  que a versao alvo e sempre a ULTIMA release. Usuario pode quer self-update para
  versao arbitraria (downgrade, pin). Esse caso esta coberto ou fora de escopo?
  [Gap, Spec §FR-005]
- [ ] CHK037 - A politica de `--force`/`--keep` em update (FR-008) tem analogo
  para self-update (ex: se a nova versao do CLI seria incompativel com o manifest
  v1 atual)? Requisito silente. [Gap, Spec §FR-008, §FR-005]

## Ambiguidades e lacunas adicionais (self-update especifico)

- [x] CHK038 - Ha requisito exigindo que self-update preserve o manifest das skills
  instaladas? (Obvio, mas nao esta escrito — e uma regressao seria desastrosa.)
  [Gap, Spec §FR-005]
  → Resolvido em Clarifications 2026-04-22 (follow-up): self-update NUNCA toca
  manifests; invariante verificada por mtime inalterado. FR-006a adicionado.
- [x] CHK039 - Self-update exige conexao com GitHub. Ha requisito explicito sobre
  comportamento offline alem do Edge Case listado? [Gap, Spec §FR-005, §Edge Cases]
  → Resolvido via FR-010: "A CLI MUST falhar com mensagem clara quando offline
  ou quando a release alvo nao existir" — aplica-se a todos os fluxos de
  download, inclusive self-update.
- [ ] CHK040 - Ha requisito de observabilidade minima para self-update (log em
  arquivo, rollback trace) ou toda informacao vive apenas em stderr daquele run?
  [Gap, Spec §FR-005]

## FASE 12 — `cstk 00c <path>` (US-5, FR-016, SC-008/009)

### Testabilidade dos novos Success Criteria

- [x] CHK041 - SC-008 mede "<60 segundos da invocacao do subcomando ate o claude
  aparecer ja com `/agente-00c` montado". Os pontos de inicio e fim do cronometro
  sao observaveis externamente (timestamp na invocacao do `cstk 00c` vs primeira
  saida do `claude` no TTY)? [Mensurabilidade, Spec §SC-008]
  → Resolvido. SC-008 cravou os endpoints: "contando da invocacao do subcomando
  ate o `claude` aparecer ja com `/agente-00c` montado como primeiro turno".
  Inicio = timestamp do shell ao invocar `cstk 00c`; fim = primeira saida do
  `claude` no TTY com a slash command processada (auto-submit confirmado em
  Clarifications 2026-05-09 via FR-016f).
- [ ] CHK042 - SC-008 assume `toolkit instalado e claude no PATH` mas o tempo de
  resposta dos prompts interativos depende do operador. O SC esta cravado em
  tempo de cstk-side ou tempo total de UX? [Clareza, Spec §SC-008]
- [ ] CHK043 - SC-009 exige verificacao "via comparacao de inode/timestamp do
  filesystem antes/depois". O conjunto de paths a inspecionar esta enumerado
  (apenas `<path>` resolvido? `<path>/.agente-00c-whitelist.txt`? cwd anterior?
  `~/.claude/state-history`)? [Mensurabilidade, Spec §SC-009]
- [ ] CHK044 - SC-009 lista 4 cenarios de path invalido (traversal, zona, vazio,
  dir nao-vazio). O conjunto e fechado e exaustivo, ou ha gap (ex: path com
  symlink que resolve para zona — coberto por FR-016b mas nao explicito em
  SC-009)? [Cobertura, Spec §SC-009 vs §FR-016b]

### Clareza dos FR-016*

- [ ] CHK045 - FR-016a recusa "stdin OU stdout nao-TTY". E stderr? Algumas
  ferramentas redirecionam stderr para arquivo mantendo stdout no TTY — o
  requisito cobre/permite/proibe esse caso? [Clareza, Spec §FR-016a]
- [x] CHK046 - FR-016b lista 14 zonas proibidas. A lista e exaustiva ou
  exemplificativa? Como o operador adiciona zonas custom (ex: politicas
  corporativas que proibem `/opt`, `~/Documents`)? [Gap, Spec §FR-016b]
  → Resolvido em Clarifications 2026-05-09 (round 2): lista FECHADA na
  FASE 12. Operadores que precisam de extensao abrem issue ou fork.
  Extensibilidade pode ser adicionada em fase futura. cstk e ferramenta
  pessoal sem caso de uso corporativo conhecido.
- [ ] CHK047 - FR-016b exige `realpath -m` para resolver symlinks e tambem
  resolver "cada zona proibida antes de comparar". Esta especificado o
  comportamento quando uma zona proibida da lista canonica nao existe no host
  (ex: `/proc` em macOS)? [Ambiguity, Spec §FR-016b]
- [ ] CHK048 - FR-016c exige descricao "10-500 chars; rejeitar newlines/`$`/`` ` ``".
  Caracteres unicode (acentos, emojis) sao permitidos? E controles invisiveis
  (zero-width space, `\t`)? [Clareza, Spec §FR-016c]
- [ ] CHK049 - FR-016c valida URL na whitelist via regex
  `^https?://[A-Za-z0-9._/*?-]+$` (em tasks.md 12.3.3) — esta inconsistente
  com `whitelist-validate.sh` do agente-00c-runtime, que rejeita
  patterns "overly broad" como `**` puro, `*://*`, `https://*`. Os dois
  validators concordam ou ha drift? [Consistencia, Spec §FR-016c vs
  agente-00c-runtime]
- [ ] CHK050 - FR-016d (b) exige `jq` no PATH. O requisito cobre versao minima
  de `jq`? Algumas distros embarcam versoes muito antigas; `jq -e .` para
  validacao precisa de feature de exit code que existe ha tempo, mas vale
  cravar para evitar surpresa. [Clareza, Spec §FR-016d]
- [ ] CHK051 - FR-016e exige confirmacao final `[Y/n]`. Aceita-se `s/S` (em
  pt-BR) e `yes/no` por extenso? Comportamento de Enter (default) e Ctrl+D?
  [Clareza, Spec §FR-016e]
- [x] CHK052 - FR-016f diz "auto-submetido". Existe um cenario onde o `claude`
  nao processa o primeiro turno auto-submetido (ex: claude exige session
  resume ou abre TUI ao inves de processar argv)? Ha requisito de testar essa
  premissa antes do release? [Premissa, Spec §FR-016f]
  → Resolvido. tasks.md 12.7.3 cravou "Smoke manual em maquina limpa: ...
  `cstk 00c ./test-poc` -> verificar que claude inicia com slash command
  montada (SC-008)" como gate antes do release. tasks.md 12.5.5 cobre via
  mock no CI; 12.7.3 cobre claude real. Validacao premissa esta planejada.

### Consistencia cross-requirement

- [x] CHK053 - FR-016b lista zonas proibidas e tasks.md 12.1.3 menciona
  "compartilhada com path-guard.sh". As listas devem permanecer sincronizadas
  ao longo do tempo (mudanca em uma exige mudanca na outra) ou cada uma evolui
  independente? Ha requisito sobre isso? [Consistencia, Spec §FR-016b]
  → Resolvido em Clarifications 2026-05-09 (round 2): cstk reimplementa em
  `cli/lib/` com comentario apontando o canonico em
  `global/skills/agente-00c-runtime/scripts/path-guard.sh`. Politica
  explicita: divergencias futuras precisam ser refletidas em ambos por
  PR review (gate manual). Reflexionado em FR-016g.
- [x] CHK054 - FR-016g exige sanitizacao com escape de single-quotes mas
  `sanitize.sh` do agente-00c-runtime tem subcomandos especializados
  (`escape-commit-msg`, `escape-issue-body`, `escape-path`). cstk 00c reusa
  essas primitivas (via shelling para o script da skill instalada) ou
  reimplementa em `cli/lib/`? [Consistencia, Spec §FR-016g]
  → Resolvido em Clarifications 2026-05-09 (round 2): cstk reimplementa em
  `cli/lib/`. cstk e camada inferior ao runtime (instalador vs instalado);
  shell-out criaria chicken-and-egg porque path validation precisa rodar
  ANTES do dep check de FR-016d. FR-016g atualizado para crava a
  reimplementacao + comentario cross-reference + PR review como gate.
- [x] CHK055 - FR-015 ja cobre "lockfile por escopo". `cstk 00c` cria um
  diretorio fora dos escopos `~/.claude/skills/` ou `./.claude/skills/`,
  entao o lock atual nao se aplica. Ha requisito sobre concorrencia entre
  duas invocacoes simultaneas de `cstk 00c <path>` no mesmo `<path>`? [Gap,
  Spec §FR-015 vs §FR-016]
  → Resolvido em Clarifications 2026-05-09 (round 2): novo FR-016h cravou
  lockfile per-path via `mkdir <path>/.cstk-00c.lock` atomico, com release
  via trap on exit. Aborto explicito se lock pre-existente. tasks.md
  12.1.6/12.1.7 cobrem implementacao e testes.
- [x] CHK056 - FR-016d (c) dispara `cstk install` em foreground. Esse `cstk
  install` aninhado interage com FR-015 (lockfile)? Se outro `cstk install`
  ja esta rodando paralelamente, o nested install bloqueia ou aborta?
  [Gap, Spec §FR-016d vs §FR-015]
  → Resolvido em Clarifications 2026-05-09 (round 2): nested install
  RESPEITA o lockfile global de FR-015. Se lock tomado, nested falha
  imediatamente; cstk 00c captura, libera lock per-path (FR-016h) e aborta
  com mensagem `outro cstk install em andamento. Aguarde, depois rode
  'cstk 00c <path>' novamente`. Sem retry automatico nem bypass. FR-016d (c)
  e tasks.md 12.2.8 cravam o comportamento.

### Cobertura de cenarios e edge cases

- [ ] CHK057 - US-5 tem 5 acceptance scenarios. Ha cenario para Ctrl+C no
  meio dos prompts (mencionado em Edge Cases mas sem AS dedicado)?
  [Cobertura, Spec §US-5]
- [x] CHK058 - Ha cenario para boundary da descricao: exatamente 9 chars
  (rejeitar), exatamente 10 chars (aceitar), exatamente 500 chars (aceitar),
  exatamente 501 chars (rejeitar)? [Cobertura, Spec §FR-016c]
  → Resolvido. tasks.md 12.3.5 lista "descricao com 9 chars, descricao com 501
  chars" cobrindo boundary-1 e boundary+1. Aceitacao em 10 e 500 e implicada
  por exclusao (se 9 e 501 sao rejeitados, 10 e 500 sao aceitos pela politica
  >=10 && <=500). Cenarios reforcaveis em test_00c-bootstrap durante a
  implementacao se vier necessidade.
- [x] CHK059 - Edge case `Operador interrompe (Ctrl+C) durante prompts`
  diz "deixar como esta sem rollback automatico". Cobre o caso onde o
  diretorio foi criado mas a interrupcao aconteceu APOS escrever
  `.agente-00c-whitelist.txt` — esse arquivo persiste? [Cobertura,
  Spec §Edge Cases]
  → Resolvido implicitamente pela regra "deixar como esta sem rollback
  automatico". Como FR-016f persiste a whitelist ANTES do `exec claude`, e
  Ctrl+C entre persistencia e exec deixa o arquivo no disco — comportamento
  esperado e operador remove manualmente se quiser. Sem necessidade de
  cleanup automatico (pode mascarar bugs).
- [ ] CHK060 - SC-009 cita `<path>/.agente-00c-whitelist.txt` mas nao cobre
  outros artefatos potenciais (ex: lockfile, log temporario do prompt do
  cstk install). Ha cenario testando que NENHUM byte e escrito em caso de
  abort precoce? [Cobertura, Spec §SC-009]
- [x] CHK061 - Edge case "agente-00c.md ausente -> prompt + auto-install"
  cobre o caminho feliz (Y -> install completa). Cobre o caso onde `cstk
  install` falha (rede, sha mismatch) durante o prompt — abort com erro
  claro ou estado intermediario? [Gap, Spec §FR-016d]
  → Resolvido em Clarifications 2026-05-09 (round 2): falha do nested
  install (qualquer exit code != 0 que nao seja conflito de lock — esse
  ja e tratado em CHK056) faz cstk 00c abortar com exit 1 proxiando o
  motivo. Diretorio criado em FR-016b PERMANECE (sem rollback automatico,
  alinhado com edge case Ctrl+C). Mensagem aponta `cstk install --force`
  para retry manual. tasks.md 12.2.7 cobre.

### Ambiguidades e premissas explicitas

- [x] CHK062 - Premissa nao validada: `claude "<prompt>"` aceita uma slash
  command como prompt e a executa como primeiro turno auto-submetido. Ha
  requisito de validacao dessa premissa antes da implementacao da FASE 12
  (tasks.md 12.5.5 cobre via mock, mas falta gate manual com claude real)?
  [Premissa, Spec §FR-016f]
  → Resolvido. tasks.md 12.7.3 cravou smoke manual em maquina limpa como
  gate de release. Se a premissa nao se confirmar com `claude` real, FASE
  12 abre nova clarify para revisar FR-016f (ex: trocar auto-submit por
  pre-typed se nao for tecnicamente possivel via argv).
- [x] CHK063 - Existe requisito sobre o que acontece quando o operador
  fornece descricao com aspas simples literais? FR-016g escapa para
  single-quotes mas o conteudo da descricao em si vai para dentro de
  single-quotes shell — apostrofos no texto precisam ser escapados como
  `'\''`. [Ambiguity, Spec §FR-016g]
  → Resolvido. FR-016g cravou "descricao escapada para shell single-quotes"
  — esse escape canonico SUBSTITUI cada `'` por `'\''` exatamente para
  preservar apostrofos no conteudo. tasks.md 12.3.4 reforca a regra. Caso
  tipico ("don't") fica corretamente escapado e chega ao orquestrador como
  string ASCII original.
- [x] CHK064 - O acceptance scenario 5 (cstk install via prompt Y) assume
  que `cstk install` e idempotente. Ha requisito explicito de idempotencia
  para o caso onde `agente-00c.md` foi recem-instalado mas em versao
  incorreta (FR-008 cobre `--force`, mas o auto-install em FASE 12 nao usa
  `--force`)? [Gap, Spec §FR-016d]
  → Resolvido. SC-002 ja cobre idempotencia geral do `cstk install`. Para
  o caso "agente-00c.md ausente -> install novo": e o caminho feliz, a
  ausencia exclui conflito de versao. Para "agente-00c.md presente": a
  verificacao em FR-016d (c) detecta arquivo presente e SKIPA o prompt
  (nao reinstala). Politica de `--force` permanece responsabilidade do
  operador via `cstk install --force` rodado fora do `cstk 00c`.
- [ ] CHK065 - O subcomando `cstk 00c` e exposto no `--help` (tasks 12.6.1,
  12.6.2). Ha requisito sobre como `cstk --help` documenta o pre-requisito
  TTY (FR-016a) — para o operador descobrir antes de tentar usar em script?
  [Gap, Spec §FR-016a]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente (CHK001 a CHK065)
- Items com `[Gap]` indicam que a spec precisa ser AMPLIADA
- Items com `[Ambiguity]` indicam que existe requisito mas interpretacao dupla
- Items com `[Clareza]` indicam que requisito existe mas termos vagos precisam
  quantificacao
- Items com `[Consistencia]` indicam conflito potencial entre dois requisitos
- Items com `[Mensurabilidade]` indicam criterios nao diretamente observaveis
- Items com `[Cobertura]` indicam cenario/AS ausente para um requisito existente
- Items com `[Premissa]` indicam suposicao implicita que precisa validacao antes
  da implementacao
- Rodar `/clarify` nos items `[Ambiguity]` / `[Gap]` de maior impacto antes de
  `/create-tasks`
