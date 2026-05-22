# Research: cstk CLI

Documento produzido no Phase 0 do `/plan`. Resolve unknowns tecnicos antes do design
de modelo de dados e contratos.

## Decision 1: Linguagem de implementacao do CLI

**Decision**: POSIX sh (`#!/bin/sh`, `set -eu`, sem bash-isms), distribuido como um
unico arquivo executavel `cstk` + diretorio `cli/lib/` com subcomandos modulares
(tambem POSIX sh).

**Rationale**:
- Constitution Principio II (NON-NEGOTIABLE) exige POSIX sh para scripts do toolkit.
  O CLI e, na pratica, o maior "script" do toolkit — violar II aqui seria degradar o
  padrao que as skills do toolkit ensinam a manter.
- Todos os workflows do CLI sao orchestration de `curl`, `tar`, `sha256sum`, `mv`,
  `find`, `grep`, `awk`. Nenhum deles exige linguagem mais expressiva.
- Distribuicao e trivial: tarball GitHub Release contem `cstk` + `cli/lib/*`. Instalacao
  e `cp` + `chmod +x`. Self-update e atomic-mv de tarball novo.
- Zero toolchain de build — nao precisamos de compilador Go/Rust nem runtime
  Node/Python. Cara que clona o repositorio roda direto.

**Alternatives considered**:
- **Go** — binario estatico autocontido, typing, testes nativos. Rejeitado: violaria
  Principio II; introduz toolchain de build; 3MB+ de binario vs ~20KB de scripts sh;
  usuario precisa de cross-compile para mac arm64/intel/linux.
- **Node.js** — ecossistema rico. Rejeitado: runtime deps (Node >= X), npm lock-in,
  usuarios sem Node instalado ficam de fora, violaria clone-e-usa.
- **Python** — ubiquo. Rejeitado: fragmentacao 2/3, venv, pip install, ambiguidade do
  `python` vs `python3`. Perde "zero setup".
- **Rust** — binario nativo. Mesmas rejeicoes de Go + toolchain ainda mais pesado.

## Decision 2: Formato do manifest

**Decision**: Arquivo texto plain com uma linha por skill instalada, 4 colunas
separadas por TAB: `<skill-name>\t<version>\t<source-sha>\t<installed-at-iso>`.
Localizacao: `~/.claude/skills/.cstk-manifest` (global) e `./.claude/skills/.cstk-manifest`
(projeto). Linha inicial e comentario `# cstk manifest v1` para versionamento de schema.

**Rationale**:
- POSIX-grepavel com `awk -F'\t'`, `grep`, `sort`. Nao precisa de `jq`.
- Append/update com `awk` + `mv` (atomic replace) e trivial em shell puro.
- Formato auto-documentado quando o usuario abre o arquivo.
- Schema version na primeira linha permite evoluir sem quebrar clientes antigos.

**Alternatives considered**:
- **JSON** — exigiria `jq` como dep hard. Rejeitado por Principio II (so `jq`
  opcional para hooks e aceitavel; manifest nao pode depender dele).
- **YAML** — nao e POSIX canonico; sem parser sem deps.
- **Diretorio `.cstk/` com um arquivo por skill** — mais granular mas inflaciona
  I/O (N skills = N reads) sem beneficio claro; plain text single-file e mais simples.

## Decision 3: Deteccao de edicoes locais (hash_dir via manifest canonico)

**Decision**: Hash SHA-256 de um **manifest canonico ordenado** da arvore da skill:
para cada arquivo regular sob o diretorio, calcula-se SHA-256 individual, produz-se
uma linha `<sha256>  <relpath>`, ordena-se por path, e o SHA-256 desse manifest e
o hash final. Armazenado no manifest da CLI. Update compara hash atual com hash
registrado; divergencia = edicao local OU drift.

**Rationale**:
- SHA-256 disponivel via `sha256sum` (linux) ou `shasum -a 256` (macOS) — CLI detecta
  qual existe e usa (cli/lib/compat.sh).
- Manifest canonico ordenado garante determinismo 100% portavel: `find -type f` +
  `sort` existem em qualquer sistema POSIX, sem depender de flags que variam.
- Mesmas propriedades desejadas: mesmo conteudo + mesmo path = mesmo hash;
  insensivel a mtime/permissoes/ordem de criacao.
- Hash e forma mais confiavel que mtime (que muda com `cp -p`, `rsync`, etc.).
- Skills sao pequenas (KB a baixas dezenas de KB) — overhead de hashing e desprezivel.

**Alternatives considered**:
- **`tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0`** (plano
  original) — REJEITADO apos implementacao: essas flags sao GNU-only; BSD tar do
  macOS nao suporta `--sort`. Testar em mac revelou incompatibilidade. Manifest
  canonico entrega o mesmo observavel sem depender de nenhuma feature especifica
  de tar.
- **mtime comparison** — simples mas facil de quebrar (touch, rsync sem -a, checkout
  git). Rejeitado como fragil demais para decisao de `--force` vs abort.
- **Hash por arquivo em vez de por skill** — mais granular, permitiria mergeflows
  avancados. Rejeitado: complexidade alta, usuario casual nao precisa dessa
  granularidade, e politica definida no spec e "skill-level abort/force/keep".
- **git diff** — depende de `git` instalado no dir destino. Violaria "curl+tar only".

## Decision 4: Self-update atomico (par bin + lib como unidade indivisivel)

**Decision**: Self-update usa **stage-and-rename coordenado** com ponto de commit
unico no ultimo `mv`. Sequencia exata:

1. Download do tarball para `mktemp -d`; extracao; validacao SHA-256.
2. Montar arvore nova de lib em `$CSTK_LIB.new/` (diretorio irmao, mesmo filesystem).
3. Montar novo `cstk` em `$CSTK_BIN.new` (mesmo dir do bin atual, mesmo filesystem).
4. Mover lib atual para `$CSTK_LIB.old/` (renomeacao atomica). A partir daqui, se
   falhar, rollback = renomear `$CSTK_LIB.old/` de volta para `$CSTK_LIB/` e abortar.
5. Renomear `$CSTK_LIB.new/` → `$CSTK_LIB/` (atomic rename). Agora lib nova esta no
   lugar, mas bin ainda e o antigo. Uma nova invocacao neste instante resultaria em
   bin-antigo + lib-nova — ESTADO PROIBIDO POR FR-006.
6. **Ponto de commit**: `mv -f $CSTK_BIN.new $CSTK_BIN` — atomic rename no mesmo
   diretorio. Este e o unico ponto onde bin muda. Apos este passo, sistema esta
   100% na versao nova.
7. Cleanup: `rm -rf $CSTK_LIB.old/`. Falha de cleanup nao quebra correcao — o
   sistema ja esta consistente na versao nova; apenas deixa lixo que `cstk doctor`
   pode reportar.

**Janela de inconsistencia entre passos 5 e 6**: o design compensa com um **lock de
self-update exclusivo** (`$CSTK_LIB/../.self-update.lock`) adquirido no passo 1 e
liberado apos passo 7. Adicionalmente, o bootstrap da CLI (source-once das libs) le
tudo de uma vez no inicio — invocacoes que iniciam entre passos 5 e 6 e conseguem
ler lib nova antes do bin ser trocado simplesmente carregam lib nova; o dispatch
subsequente usa `$CSTK_BIN` corrente, que ainda pode ser o antigo. Para blindar
esse caso, o proprio `cstk` bin (velho) verifica no boot se `cli/lib/VERSION` bate
com seu proprio VERSION embutido, e aborta com mensagem de "self-update em progresso,
tente novamente" se nao bate. Isso garante que **nenhuma invocacao observa par
bin+lib divergente** — requisito de FR-006.

**Rollback explicito**: se qualquer passo 2-6 falhar, a CLI tenta restaurar o
estado anterior:
- Se passo 4 completo mas passo 5 falha: restaurar `$CSTK_LIB.old/` para
  `$CSTK_LIB/`.
- Se passo 5 completo mas passo 6 falha: mover `$CSTK_LIB/` para `$CSTK_LIB.new/`
  (garantindo que o novo nao se perde), restaurar `$CSTK_LIB.old/` para
  `$CSTK_LIB/`. Abortar.

**Rationale**:
- `rename(2)` e atomico em POSIX dentro do mesmo filesystem — kernel garante que
  observadores veem antes ou depois, nunca estado intermediario. Esse e o primitivo
  que sustenta toda a sequencia.
- Commit point unico (passo 6) garante que o observavel "versao" (dada por
  `cstk --version` que le `$CSTK_LIB/../VERSION`, via o bin) seja monotonicamente
  consistente — se bin diz 3.3.0, lib tambem e 3.3.0.
- Check bin-lib-match no boot da CLI e ultimo-recurso contra a janela curta. Custa
  uma comparacao de string ao boot, ganho e eliminar o estado proibido por FR-006.
- Lock de self-update previne dois self-updates concorrentes — inclusive self-update
  paralelo a outro (FR-015 cobre operacoes de skills; self-update exige seu proprio
  lock por opera em artefatos distintos).

**Alternatives considered**:
- **Sequencia antiga** (bin mv primeiro, depois `rm -rf lib && mv new-lib lib`) —
  REJEITADA apos reescrita de FR-006: permite janela observavel com bin novo e lib
  antiga, explicitamente proibida.
- **Symlink flip** — usar symlinks para versoes instaladas e flipar o symlink como
  commit point unico. Tecnicamente mais simples de provar atomico, mas exige
  repensar layout (`$CSTK_LIB` vira symlink para `lib-3.2.0/` e self-update cria
  `lib-3.3.0/`). Rejeitado por inflar footprint em disco e exigir garbage collection
  de versoes antigas; stage-and-rename coordenado entrega o mesmo observavel sem
  esse overhead.
- **Co-existencia versionada permanente** — cada versao vive em seu dir; self-update
  soh adiciona nova versao e flipa pointer. Rejeitado: storage cresce indefinidamente
  ate GC explicito, complexidade de saber "qual versao rodar quando" aumenta.
- **GPG signing** — assinar releases com GPG. Rejeitado por ora: GitHub Releases
  checksums + HTTPS do proprio GitHub sao nivel de seguranca aceitavel para o threat
  model deste projeto (single-maintainer toolkit). Adicionavel depois sem breaking.
- **In-process replace** — parar, substituir, re-exec. Rejeitado por ser mais fragil
  que stage-and-rename + boot-check.

## Decision 5: Versionamento de skills e CLI

**Decision**: Versionamento UNIFICADO. Toda release do toolkit (tag SemVer, ex:
`v3.2.0`) empacota como assets GitHub Release:
1. `cstk-<version>.tar.gz` — contem o CLI (`cstk` + `cli/lib/`) + todos os skills do
   toolkit naquela versao + `CHANGELOG.md` + `manifest-catalog.txt` (catalogo dos
   nomes de skills/perfis daquela versao).
2. `cstk-<version>.tar.gz.sha256` — checksum.

O CLI armazena no manifest `version` = tag da release de onde a skill veio. Update
compara ultima release com versao no manifest global/projeto, e re-instala as skills
do perfil/selecao com a nova.

**Rationale**:
- Simpler mental model: "todo toolkit versiona junto". Atualizar e "puxar o toolkit
  inteiro da release X". Nao ha matrix de compatibilidade entre versao-X-do-CLI e
  versao-Y-da-skill.
- Alinha com o CHANGELOG.md unico que ja existe no repo.
- Uma release = um artefato = uma fonte de verdade para reproducibilidade.

**Alternatives considered**:
- **Versao por skill** — cada skill com sua propria versao/tag. Rejeitado: explode
  complexidade para usuario e mantenedor; nao ha hoje indicio de que uma skill evolui
  numa cadencia materialmente diferente do resto.
- **CLI versionado separado de skills** — dois channels. Rejeitado: sem ganho claro,
  mais superficie para bug de compatibilidade (CLI vX espera manifest schema Y).

## Decision 6: Layout dos assets dentro do tarball

**Decision**: O tarball da release preserva a estrutura do repo mas sem arquivos de
desenvolvimento (docs/, tests/, .git/, CLAUDE.md, README.md). Layout:

```
cstk-v3.2.0/
├── cstk                        # executavel principal (chmod +x)
├── cli/
│   └── lib/
│       ├── install.sh
│       ├── update.sh
│       ├── self-update.sh
│       ├── doctor.sh
│       ├── list.sh
│       ├── manifest.sh         # helpers de leitura/escrita do manifest
│       ├── hash.sh             # helpers de hashing
│       ├── profiles.sh         # definicao de perfis
│       └── ui.sh               # modo interativo
├── catalog/
│   ├── VERSION                 # "3.2.0"
│   ├── profiles.txt            # definicao dos perfis
│   ├── skills/                 # espelho de global/skills/ da release
│   │   ├── specify/...
│   │   └── ...
│   └── language/               # espelho de language-related/
│       ├── go/
│       └── dotnet/
└── CHANGELOG.md
```

**Rationale**:
- Separar `cli/` (codigo do CLI) de `catalog/` (payload de skills) deixa claro o que
  e ferramenta vs conteudo. CLI precisa ser atualizado em self-update; catalog nao —
  catalog e sempre baixado fresh a cada install/update, nao mantido na maquina.
- `VERSION` e `profiles.txt` como arquivos declarativos permite CLI listar perfis
  sem hardcode no codigo do CLI.
- Arquivos de dev do repo ficam fora da release, reduzindo tamanho e ruido.

**Alternatives considered**:
- **Tarball = snapshot do repo inteiro** — simples mas carrega `docs/`, `tests/`, etc.
  que o usuario nao precisa.
- **Dois tarballs separados (CLI e catalog)** — mais modular mas exige duas
  download/valida/extrai operations por comando.

## Decision 7: Mecanismo de lock para execucoes concorrentes

**Decision**: Lockfile via `mkdir` em `~/.claude/skills/.cstk.lock` (ou
`./.claude/skills/.cstk.lock`). `mkdir` e atomico em POSIX — se ja existe, falha e
CLI aborta com mensagem clara. Lock e limpo via `trap` em EXIT/INT/TERM.

**Rationale**:
- `mkdir` e a primitiva POSIX canonica para lock atomico (mais simples que flock,
  que nao e POSIX).
- Crash deixa lock stale — documentar na ajuda que `rmdir` manual do lockfile
  resolve, com mensagem de erro instrutiva.

**Alternatives considered**:
- **flock** — nao e POSIX padrao; varia em macOS vs linux.
- **PID file** — inseguro (pid pode ser reciclado, corrida entre check e write).
- **Sem lock** — ja descartado por FR-015.

## Decision 8: Modo interativo

**Decision**: Implementado via loop `read` + numeracao de opcoes. Sem `fzf`, sem
`dialog`, sem `whiptail`. Fluxo: CLI lista perfis e skills numerados, usuario digita
numeros separados por espaco ou vazio para default. Toggle por re-digitar numero
(conjunto simétrico). Confirmacao final mostra seleção resolvida antes de executar.

**Rationale**:
- POSIX `read` + aritmetica com `expr` resolvem sem deps. Suficiente para o caso
  de uso (lista de ~20 items).
- Sem `fzf`/`dialog` = funciona em qualquer terminal, inclusive em CI/SSH sem pty
  quirks.
- Usuario sem TTY (pipe) recebe erro claro instruindo a usar flags ao inves do modo
  interativo.

**Alternatives considered**:
- **`fzf`** — UX superior mas dep externa. Rejeitado.
- **`dialog`/`whiptail`** — verbose, rare em setups mac default. Rejeitado.

## Decision 9: Local de instalacao do proprio CLI

**Decision**: `~/.local/bin/cstk` por default (segue XDG_BIN_HOME spec-like).
Instalacao inicial (one-liner do README) baixa ultima release, extrai, copia
`cstk` para `~/.local/bin/cstk`, extrai `cli/lib/` para `~/.local/share/cstk/lib/`.
Self-update opera nesses paths.

**Rationale**:
- `~/.local/bin/` e convencao user-space amplamente aceita. Nao exige sudo.
- Separar executavel (`~/.local/bin/`) de biblioteca (`~/.local/share/cstk/`) e
  convencao filesystem hierarchy standard.
- Variaveis `CSTK_BIN` e `CSTK_LIB` opcionais permitem override para testes ou
  setups nao-padrao.

**Alternatives considered**:
- **`/usr/local/bin/`** — exigiria sudo em instalacao inicial. Rejeitado.
- **Homebrew tap** — caminho mais ergonomico para macOS mas exclui linux. Pode ser
  fornecido depois como opcao adicional; nao e o default.

## Decision 10: Integridade do tarball baixado

**Decision**: Verificar SHA-256 do tarball baixado contra asset `.sha256` da mesma
release. Se mismatch, abortar com mensagem clara sem tocar nada local. HTTPS do
GitHub ja garante transport integrity; o checksum cobre corrupcao acidental ou
race condition de asset trocado.

**Rationale**:
- Custo baixo (um comando `sha256sum` adicional).
- GitHub Releases mostra checksums no proprio release note — usuario pode verificar
  manualmente se suspeitar.

**Alternatives considered**:
- **GPG signatures** — mais forte mas exige gpg + gestao de chaves publicas.
  Nao justificado para o threat model atual. Podera ser adicionado sem breaking.
- **Sem checksum** — HTTPS e suficiente na maioria dos casos, mas checksum protege
  contra cenario raro de asset corrompido no proprio GitHub (ja aconteceu
  historicamente durante incidentes).

## Decision 11: Modelo de spawn do `claude` no `cstk 00c` (FASE 12)

**Decision**: invocar `claude` via `exec` com a slash command `/agente-00c <args>`
como argumento posicional, contando que a CLI do Claude Code interpreta o argumento
como **primeiro turno auto-submetido** na sessao interativa.

**Rationale**:
- A documentacao publica do Claude Code CLI descreve `claude "<prompt>"` como o modo
  one-shot/interativo onde o argumento e tratado como mensagem inicial; a UX padrao
  e que a mensagem seja processada imediatamente, sem exigir Enter manual.
- Clarifications 2026-05-09 Q1 cravou auto-submit como o comportamento esperado pelo
  operador (ele ja teve dry-run em FR-016e como confirmacao final).
- `exec` substitui o processo `cstk` pelo `claude`, evitando proxy desnecessario e
  preservando o TTY para o operador (fork+wait introduziria buffering e quebraria a
  ergonomia). Padrao tradicional de wrappers shell.
- Testabilidade: tasks.md 12.5.5 cobre via mock (`claude` substituido por script que
  loga argv); tasks.md 12.7.3 cravou smoke manual em maquina limpa como GATE
  obrigatorio antes do release — se a premissa nao se confirmar com claude real, a
  spec volta para clarify e FR-016f e revisado.

**Alternatives considered**:
- **Pre-typed (claude abre com slash digitada mas aguarda Enter)**: requer suporte
  do claude CLI a este modo (tipo flag `--prefill`); nao confirmado existir.
  Adicionaria atrito redundante apos o dry-run.
- **Print + paste manual**: maxima transparencia mas zero automacao — derrota o
  proposito do `cstk 00c` como atalho.
- **`claude --print "<prompt>"`**: modo nao-interativo (one-shot). Nao serve porque
  o agente-00C precisa rodar interativamente em multiplas ondas com pause-or-decide.

## Decision 12: Resolucao portavel de paths com symlinks no `cstk 00c` (FASE 12)

**Decision**: usar `realpath -m` quando disponivel (GNU coreutils — Linux,
macOS com `brew install coreutils` simbolizado como `grealpath`); fallback
POSIX puro via `cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd -P)"
"$(basename "$p")"` que resolve symlinks de ancestrais via `cd -P`. Implementar
wrapper `_00c_realpath` em `cli/lib/00c-bootstrap.sh` que tenta `realpath -m`
e cai no fallback POSIX se nao disponivel.

**Rationale**:
- macOS (BSD) tem `realpath` nativo desde Catalina mas SEM flag `-m` (que aceita
  paths inexistentes, necessario porque `<path>` ainda nao existe quando validamos).
- Linux (GNU coreutils) tem `realpath -m`.
- Workaround POSIX (`cd -P`) funciona em ambos OS porem so resolve ancestrais
  existentes — para o componente final inexistente, usamos `dirname` + concat.
- Alinha com padrao do `path-guard.sh` no agente-00c-runtime que ja usa fallback
  similar.

**Alternatives considered**:
- **Exigir GNU coreutils como dep**: rejeitado — adiciona pre-requisito ao
  one-liner de bootstrap (`brew install coreutils`).
- **Python como fallback**: rejeitado — adiciona dep nao-shell para um
  edge case de portabilidade.
- **Sem resolucao de symlinks**: rejeitado — Clarifications 2026-05-09 Q4
  cravou validacao defensiva contra symlinks adversariais.

## Decision 13: Detecao de TTY em POSIX (FASE 12)

**Decision**: usar `[ -t 0 ] && [ -t 1 ]` (POSIX `test -t fd`) para verificar
que stdin e stdout sao TTY. Stderr explicitamente NAO incluido — operador
pode redirecionar stderr para arquivo de log sem violar a semantica interativa.

**Rationale**:
- `test -t fd` e POSIX e funciona em sh/bash/zsh/dash sem deps extra.
- Excluir stderr e padrao em CLIs interativos (ex: `vim`, `git rebase -i`) —
  permite ao operador `cstk 00c ./x 2>cstk.log` para debug sem perder
  interatividade.
- Resolve CHK045 (stderr nao-TTY): explicitamente permitido e nao bloqueia.

**Alternatives considered**:
- **Tambem checar stderr**: rejeitado — quebra padrao Unix de stderr-redirect-OK.
- **Detectar stdin via `tty -s`**: rejeitado — `test -t` e mais portavel
  e nao depende do binario `tty`.

## Decision 14: Lock e cleanup via trap para o `cstk 00c` (FASE 12)

**Decision**: usar `trap '_00c_release_lock' EXIT INT TERM` no inicio do
`00c_bootstrap_main`, registrado APOS o `mkdir <path>/.cstk-00c.lock/`
atomico. `_00c_release_lock` faz `rmdir "$_00c_lock_dir" 2>/dev/null || :`
(idempotente; nao falha se ja foi removido). No caminho feliz, chamar
`_00c_release_lock` explicitamente ANTES do `exec claude` para nao depender
do trap herdado.

**Rationale**:
- POSIX `trap` em EXIT cobre exit normal, abort precoce, e maior parte dos
  caminhos de saida sem requerer codigo replicado.
- INT (Ctrl+C) e TERM cobrem interrupcoes externas — POSIX dispara o trap
  no shell antes da terminacao do processo.
- `rmdir` falha se diretorio nao-vazio, entao usamos `2>/dev/null || :` para
  ser idempotente. Lock e diretorio vazio (`mkdir` puro), entao `rmdir`
  funciona.
- Release explicito antes do `exec` documenta a intencao e evita ambiguidade
  sobre comportamento do trap heredado pelo `claude`.

**Alternatives considered**:
- **Sem trap, release explicito em cada exit point**: rejeitado — espalha
  cleanup pelo codigo, fragil a refactor.
- **Lockfile com PID e auto-stale-detection**: overkill para o uso; lock e
  curto (segundos a minutos). Stale lock requer intervencao manual
  (`rmdir <path>/.cstk-00c.lock`) — aceitavel como trade-off.
