# Quickstart: cstk CLI

Cenarios end-to-end que validam a implementacao. Um cenario por fluxo critico
(happy path + pelo menos um error case). Cada cenario e executavel manualmente
contra a CLI real ou serve de base para teste automatizado.

## Scenario 1: Primeira instalacao em escopo global (happy path, P1)

**Pre-condicoes:** maquina sem `~/.claude/skills/`, `cstk` instalado via one-liner.

1. Usuario executa `cstk install` (sem args — default profile `sdd`)
2. CLI baixa tarball da ultima release, valida checksum
3. CLI extrai skills do perfil `sdd` para `~/.claude/skills/`
4. CLI escreve `~/.claude/skills/.cstk-manifest` com 10 linhas (uma por skill SDD)
5. **Expected**:
   - Exit 0
   - `~/.claude/skills/specify/SKILL.md` existe
   - `~/.claude/skills/.cstk-manifest` contem header + 10 linhas, todas com mesma
     `toolkit_version`
   - Stderr contem summary `installed: 10 ... scope: global`

## Scenario 2: Update incremental com zero mudancas (idempotencia, SC-002)

**Pre-condicoes:** cenario 1 ja executado; ultima release do toolkit nao mudou.

1. Usuario executa `cstk update`
2. CLI compara manifest local com release atual
3. Nenhuma divergencia detectada
4. **Expected**:
   - Exit 0
   - Stderr: `already up-to-date: 10`
   - mtime dos arquivos em `~/.claude/skills/` INALTERADO (checar com `stat -f
     %m` antes e depois — devem ser iguais)
   - Manifest inalterado

## Scenario 3: Update com edicao local (politica de conflito, FR-008)

**Pre-condicoes:** cenario 1 ja executado; usuario editou `~/.claude/skills/specify/SKILL.md`
adicionando uma linha; release nova publicada com mudanca diferente em specify.

1. Usuario executa `cstk update`
2. CLI detecta hash mismatch em `specify`
3. CLI atualiza outras 9 skills normalmente
4. CLI skippa `specify`
5. **Expected**:
   - Exit 4
   - Stderr:
     ```
     ==> cstk update summary
       updated: 9
       skipped (local edits): 1
         - specify (use --force to overwrite, --keep to silence)
     ```
   - `~/.claude/skills/specify/SKILL.md` inalterado (linha do usuario preservada)
6. Usuario executa `cstk update specify --force`
7. **Expected**:
   - Exit 0
   - `specify` agora corresponde a release nova
   - Edicao do usuario perdida (documentado no help)

## Scenario 4: Instalacao em escopo de projeto com hook (FR-009c, FR-009d)

**Pre-condicoes:** projeto em `/tmp/foo`, sem `.claude/`, `jq` instalado.

1. Usuario entra em `/tmp/foo` e executa `cstk install --scope project --profile language-go`
2. CLI cria `./.claude/skills/`
3. CLI instala skills Go em `./.claude/skills/`
4. CLI detecta `jq` disponivel
5. CLI cria `./.claude/settings.json` (nao existia) copiando o settings.json da linguagem
6. **Expected**:
   - Exit 0
   - `./.claude/skills/.cstk-manifest` populado
   - `./.claude/settings.json` contem hooks da linguagem Go
   - `~/.claude/skills/` NAO foi tocado (verifica mtime do dir)

## Scenario 5: Instalacao em escopo de projeto sem jq (fallback FR-009d)

**Pre-condicoes:** projeto em `/tmp/bar`, `jq` NAO instalado, `./.claude/settings.json`
ja existe com outras configs.

1. Usuario executa `cstk install --scope project --profile language-dotnet`
2. CLI detecta `jq` ausente
3. CLI instala skills normalmente
4. CLI NAO modifica `./.claude/settings.json`
5. CLI imprime na stderr o bloco JSON exato que o usuario deve mergear manualmente +
   caminho alvo
6. **Expected**:
   - Exit 0 (instalacao de skills bem-sucedida)
   - `./.claude/settings.json` intocado
   - Stderr contem bloco comecando com `# Hooks to merge manually into ./.claude/settings.json:`

## Scenario 6: Self-update atomico (FR-005, FR-006)

**Pre-condicoes:** `cstk` instalado na versao 3.2.0; release 3.3.0 disponivel.

1. Usuario executa `cstk self-update`
2. CLI baixa tarball 3.3.0 + checksum
3. Checksum OK
4. CLI copia novos arquivos para tempdir adjacente
5. Atomic mv do binario + lib
6. **Expected**:
   - Exit 0
   - `cstk --version` imprime `cstk 3.3.0`
   - `~/.local/bin/cstk` tem mtime atualizado
   - Skills em `~/.claude/skills/` INTACTAS (self-update nao toca skills)
   - Stderr: `from: 3.2.0 → 3.3.0 ... next: cstk update`

## Scenario 7: Self-update com queda de rede (atomicidade, FR-006, SC-004)

**Pre-condicoes:** cstk 3.2.0 instalado; conexao de rede derrubada apos inicio do download.

1. Usuario executa `cstk self-update`
2. CLI inicia download do tarball
3. Rede cai no meio
4. CLI detecta erro no `curl` (exit != 0)
5. CLI aborta SEM tocar `~/.local/bin/cstk` nem `~/.local/share/cstk/`
6. **Expected**:
   - Exit 1
   - `cstk --version` continua imprimindo `cstk 3.2.0`
   - Comandos subsequentes (`cstk list`, `cstk update`) funcionam normalmente
   - `~/.local/bin/cstk` com mtime INALTERADO

## Scenario 7b: Kill no self-update em cada ponto critico (atomicidade FR-006)

**Pre-condicoes:** cstk 3.2.0 instalado; release 3.3.0 disponivel. Teste parametrizado
simula kill em 4 pontos da sequencia stage-and-rename (research Decision 4).

Para cada ponto de kill, o cenario completa assim:

- **Kill apos download + checksum (pre-stage)**: `$CSTK_BIN` e `$CSTK_LIB` inalterados;
  `cstk --version` = 3.2.0; lockfile limpo via trap.
- **Kill apos stage de `.new/` mas antes do rename de lib**: idem — stages nao afetam
  o observavel; lockfile limpo.
- **Kill entre rename de lib (`$CSTK_LIB.old` ↔ `$CSTK_LIB.new` ↔ `$CSTK_LIB`) e rename
  do bin**: janela critica. Proxima invocacao do bin antigo detecta mismatch
  bin-lib via boot-check (tasks 5.1.6c) e aborta com `error: self-update in progress,
  please retry`. Operador executa `cstk self-update` novamente (passa lockfile ou
  limpa stale) — rollback restaura `$CSTK_LIB.old/` e sistema volta a 3.2.0. Em
  nenhum momento `cstk --version` retorna 3.3.0 com lib 3.2.0 ou vice-versa.
- **Kill apos rename do bin (commit point ja passou, antes do cleanup de `.old/`)**:
  sistema esta 100% em 3.3.0. `cstk --version` = 3.3.0. Diretorio `$CSTK_LIB.old/`
  remanesce como lixo; `cstk doctor` reporta e pode limpar. Estado e funcional.

**Expected em todos os 4 kills**:
- `cstk --version` retorna 3.2.0 OU 3.3.0 consistentemente (nunca output misto,
  nunca shebang invalido, nunca erro de modulo lib faltando)
- Todos os comandos anteriormente funcionais permanecem funcionais
- Lockfile limpo apos retry bem-sucedido
- Manifest de skills (`~/.claude/skills/.cstk-manifest`) com mtime INALTERADO em
  todos os 4 casos (FR-006a)

## Scenario 8: Lock concorrente (FR-015)

**Pre-condicoes:** cenario 1 executado.

1. Usuario abre terminal A e executa `cstk update` (processo longo — simular com
   pausa artificial em `--dry-run` ou rede lenta)
2. Enquanto roda, usuario abre terminal B e executa `cstk update` no mesmo escopo
3. **Expected (terminal B):**
   - Exit 3
   - Stderr: `error: lock held by another cstk process (~/.claude/skills/.cstk.lock).
     If no other cstk is running, remove the directory manually.`
4. Terminal A completa normalmente (exit 0)
5. Lock e liberado

## Scenario 9: Dry-run fiel a execucao real (SC-006)

**Pre-condicoes:** release 3.3.0 disponivel, manifest em 3.2.0, nenhuma edicao local.

1. Usuario executa `cstk update --dry-run`
2. CLI imprime plano de acao na stderr (por skill: "would update X", "already up-to-date
   Y")
3. CLI NAO baixa nem escreve nada alem de tempfiles limpos no fim
4. Usuario captura essa saida em arquivo A
5. Usuario executa `cstk update` para real
6. Usuario captura saida em arquivo B
7. **Expected**: todas as skills listadas em A estao em B e vice-versa — uniao simetrica
   vazia. Todas as acoes descritas como "would X" em A estao descritas como "X" em B.

## Scenario 10: Doctor detecta drift (SC-007)

**Pre-condicoes:** cenario 1 executado. Usuario manualmente:
- Deletou `~/.claude/skills/checklist/`
- Editou `~/.claude/skills/plan/SKILL.md`
- Criou `~/.claude/skills/my-custom/SKILL.md` (skill de terceiro)

1. Usuario executa `cstk doctor`
2. **Expected**:
   - Exit 1
   - Output:
     ```
     [OK]        <7 other skills>
     [MISSING]   checklist   in manifest, not on disk
     [EDITED]    plan        local edits detected
     [ORPHAN]    my-custom   on disk, not in manifest (third-party)
     [DRIFT]     3 issues found.
     ```
3. Usuario executa `cstk doctor --fix`
4. **Expected**:
   - Entry `checklist` removida do manifest
   - `plan` e `my-custom` permanecem inalterados (fix e manifest-only)
   - Exit 0

## Scenario 11: Modo interativo

**Pre-condicoes:** TTY presente, cenario 1 NAO executado (dir vazio).

1. Usuario executa `cstk install --interactive`
2. CLI lista perfis numerados + todas as skills numeradas
3. Usuario digita `1 3 5 12` (seleciona perfil sdd + 3 skills extra)
4. CLI mostra set resolvido final e pede confirmacao `[y/N]`
5. Usuario digita `y`
6. **Expected**: skills selecionadas instaladas; manifest escrito

## Scenario 12: Modo interativo sem TTY (pipe)

**Pre-condicoes:** CLI invocada via pipe/redirecionamento (nao-TTY).

1. Usuario executa `echo "" | cstk install --interactive`
2. **Expected**:
   - Exit 2
   - Stderr: `error: --interactive requires a TTY. Use --profile or explicit skill
     names instead.`

## Scenario 13: `cstk 00c` happy path (FASE 12, US-5 AS-1, SC-008)

**Pre-condicoes:** `claude`, `jq` no PATH; `~/.claude/commands/agente-00c.md`
instalado; TTY interativo; `<path>` (`./test-poc`) NAO existe.

1. Operador executa `cstk 00c ./test-poc`
2. cstk valida path (FR-016b), cria diretorio, faz `mkdir
   ./test-poc/.cstk-00c.lock/` atomico (FR-016h)
3. cstk verifica `claude`, `jq` e `agente-00c.md` — todos presentes (FR-016d)
4. cstk pergunta `Descricao curta do POC/MVP (10-500 chars):` →
   operador digita "POC de chatbot com OAuth"
5. cstk pergunta `Stack-sugerida em JSON (Enter para pular):` → operador
   digita `{"runtime":"node20","ui":"react"}` (validado via `jq -e .`)
6. cstk pergunta `Whitelist de URLs externas (Enter para pular):` →
   operador digita `https://api.openai.com` + linha vazia para terminar
7. cstk imprime resumo dry-run (path, descricao, stack, whitelist count,
   linha exata da `/agente-00c`) e pergunta `Confirmar? [Y/n]` → Enter (=Y)
8. cstk persiste `./test-poc/.agente-00c-whitelist.txt` (chmod 600), libera
   lock per-path, faz `cd ./test-poc` e `exec claude "/agente-00c '...' ..."`
9. **Expected**:
   - Diretorio `./test-poc/` criado
   - Arquivo `./test-poc/.agente-00c-whitelist.txt` com `https://api.openai.com`
     e mode 600
   - `./test-poc/.cstk-00c.lock/` removido (lock liberado)
   - `claude` rodando interativamente, primeiro turno auto-submetido com a
     slash command `/agente-00c "POC de chatbot com OAuth" --stack
     '{"runtime":"node20","ui":"react"}' --whitelist
     /abs/path/test-poc/.agente-00c-whitelist.txt --projeto-alvo-path
     /abs/path/test-poc`
   - Tempo total medido (timestamp invocacao -> primeira saida do claude no
     TTY) **< 60 segundos** com toolkit ja instalado (SC-008)

## Scenario 14: `cstk 00c` em path nao-vazio (FASE 12, US-5 AS-2, SC-009)

**Pre-condicoes:** `<path>` (`./projeto-existente`) ja existe e contem
arquivos.

1. Operador executa `cstk 00c ./projeto-existente`
2. **Expected**:
   - Exit 1 IMEDIATAMENTE (sem prompt)
   - Stderr: `error: ./projeto-existente ja existe e nao esta vazio. Use
     'cstk 00c' apenas em paths novos ou vazios; para retomar uma execucao
     existente do agente-00C use '/agente-00c-resume --projeto-alvo-path
     ./projeto-existente' diretamente no claude`
   - Filesystem inalterado: nenhum byte escrito, nenhum inode novo, lock
     `./projeto-existente/.cstk-00c.lock/` NAO criado (validacao precede o
     lock)

## Scenario 15: `cstk 00c` sem TTY (FASE 12, US-5 AS-3)

**Pre-condicoes:** stdin redirecionada (CI ou pipe).

1. Operador executa `cstk 00c ./x < /dev/null`
2. **Expected**:
   - Exit 2
   - Stderr: `error: cstk 00c requer TTY interativo — fluxo nao automatizavel
     via pipe. Rode em terminal interativo`
   - Filesystem inalterado (nenhum mkdir, lock ou whitelist criado — TTY
     check precede tudo, FR-016a)

## Scenario 16: `cstk 00c` com `agente-00c.md` ausente, prompt Y instala (FASE 12, US-5 AS-5)

**Pre-condicoes:** `claude` e `jq` no PATH; `~/.claude/commands/agente-00c.md`
NAO instalado; `~/.claude/skills/.cstk.lock` LIVRE; `<path>` novo.

1. Operador executa `cstk 00c ./novo-projeto`
2. cstk valida path, cria dir + lock
3. cstk verifica `claude` (OK), `jq` (OK), depois `agente-00c.md` — ausente
4. cstk pergunta `Comando agente-00c nao instalado. Instalar agora via
   'cstk install'? [Y/n]` → operador responde `Y`
5. cstk executa `cstk install` em foreground, mostrando progresso normal
   (download tarball, sha verify, copy commands/agents/skills, manifest
   upsert)
6. `cstk install` termina com exit 0; `agente-00c.md` agora presente
7. cstk prossegue para os prompts da FASE 12 (descricao, stack, whitelist),
   dry-run, confirmacao, exec claude — fluxo identico ao Scenario 13
8. **Expected**:
   - `~/.claude/commands/agente-00c.md` instalado pelo install aninhado
   - Manifest `~/.claude/commands/.cstk-manifest` atualizado
   - `claude` rodando como no Scenario 13

**Variante 16b — operador responde `n`:**

1. Mesmo state inicial; operador responde `n` no prompt da etapa 4
2. **Expected**:
   - cstk libera lock per-path via trap
   - Exit 1
   - Stderr: `error: cstk 00c requer comando agente-00c instalado. Rode
     'cstk install' manualmente e tente novamente`
   - Diretorio `./novo-projeto/` PERMANECE no disco (sem rollback)

**Variante 16c — `cstk install` aninhado falha por rede:**

1. Mesmo state inicial; operador responde `Y`; mock de `cstk install` falha
   com exit 1 e stderr `error: download failed: connection refused`
2. **Expected**:
   - cstk captura exit code != 0
   - Lock per-path liberado via trap
   - Exit 1 propagando o motivo
   - Stderr: `error: cstk install falhou (exit code 1): download failed:
     connection refused. Tente 'cstk install --force' manualmente`
   - Diretorio `./novo-projeto/` PERMANECE (sem rollback automatico)

**Variante 16d — `cstk install` aninhado bloqueado por lock global:**

1. Outro `cstk install` ja rodando em paralelo (`~/.claude/skills/.cstk.lock`
   tomado, FR-015)
2. Operador responde `Y`; nested install detecta lock e falha imediatamente
3. **Expected**:
   - Exit 1
   - Stderr: `error: outro cstk install em andamento. Aguarde, depois rode
     'cstk 00c ./novo-projeto' novamente`
   - Lock per-path liberado
   - Diretorio `./novo-projeto/` PERMANECE
