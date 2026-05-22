# Research: shell-scripts-tests

Phase 0 do `/plan`. Resolve decisoes de stack antes do design.

## Decision 1: Framework de teste

**Decision**: Harness proprio em POSIX sh (zero dependencias externas), vivendo
em `tests/lib/` com ~150 linhas de helpers de assercao.

**Rationale**:

- O projeto inteiro (scripts sob teste + skills que os invocam) ja se compromete
  com POSIX sh puro. Introduzir `bats-core` (Bash-only, exige instalacao via
  brew/apt) ou `shunit2` (Bash-first tambem) contradiz essa disciplina e
  adiciona uma dependencia que o mantenedor precisa justificar em cada novo
  clone.
- Volume e pequeno: 5 scripts, ~20-30 cenarios totais. Nao ha massa critica
  que justifique a ergonomia de um framework externo.
- Harness proprio da controle total sobre o "check de orfaos" (FR-009) — seria
  um hack colado por fora se usassemos bats.
- Entry point unico e trivial: um `tests/run.sh` que faz `find tests -name
  'test_*.sh'`, executa cada um em subshell isolada com tmpdir dedicado, e
  acumula PASS/FAIL.

**Alternatives considered**:

- **bats-core**: ergonomia superior (sintaxe `@test`, TAP output, integracao
  com editores). Rejeitado: exige install (`brew install bats-core`), nao e
  POSIX sh (usa Bash), adiciona passo de setup que FR-002 proibe.
- **shunit2**: single-file, sem install global. Rejeitado: ainda requer Bash,
  xUnit-style e verboso demais para 5 scripts, e a comunidade nao e tao viva
  (ultimos releases sao espacados).
- **Harness em Go ou Python**: rejeitado porque introduz toolchain que o
  projeto hoje nao usa para nada. Shell testando shell mantem o loop de feedback
  local (editar script → rodar teste, mesmo processo).

## Decision 2: Isolamento de execucao

**Decision**: Cada arquivo `test_*.sh` exporta uma variavel `TMPDIR_TEST`
criada via `mktemp -d`, e registra `trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM`
logo no inicio. Todas as fixtures sao copiadas para dentro desse tmpdir antes
de invocar o script sob teste.

**Rationale**:

- FR-005 exige zero efeito colateral fora do diretorio do teste. `mktemp -d`
  da um diretorio unico por execucao, eliminando colisao mesmo se um dia
  quisermos paralelizar.
- `trap ... EXIT INT TERM` garante limpeza inclusive em falha ou Ctrl+C
  (edge case listado na spec).
- Copiar fixtures (nao symlink-ar) evita que o teste modifique o fixture
  fonte por engano — determinismo (FR-007).
- `TMPDIR_TEST` e separado do `TMPDIR` do sistema para nao confundir com
  outros processos do usuario.

**Alternatives considered**:

- **Usar diretorio fixo `tests/tmp/`**: simples, mas colide em paralelo e
  exige limpeza manual se um teste crasha — viola FR-005 em caso de falha.
- **Git worktree descartavel por teste**: exagero de overhead (cada teste
  ~2s de cold start). Nao justificado para scripts que rodam em ms.
- **Container Docker por teste**: mata o requisito de "roda offline, sem
  setup alem do padrao local" (FR-002).

## Decision 3: Shell sob o qual os scripts sao executados

**Decision**: Rodar scripts explicitamente via `sh script.sh args` no runner,
NAO confiar no shebang. Na primeira iteracao, apenas o `sh` apontado por
`/bin/sh` e exercitado. Matriz bash/dash/zsh fica documentada como extensao
futura, nao bloqueante.

**Rationale**:

- O shebang dos scripts ja e `#!/bin/sh` — o contrato e POSIX. Invocar via
  `sh` no runner valida exatamente esse contrato, mesmo que o sistema tenha
  bash como `/bin/sh` (caso comum em macOS onde `/bin/sh` e bash em modo
  POSIX, e em Debian onde e dash).
- Matriz multi-shell (bash/dash/zsh) multiplica tempo de execucao por 3 e
  complica setup — violaria SC-003 (<30s) sem beneficio imediato ja que hoje
  o alvo de instalacao e uma maquina dev local onde `/bin/sh` e o unico shell
  de execucao de scripts do projeto.
- Se no futuro surgir bug especifico de shell, adicionamos variavel
  `TEST_SHELLS="sh bash dash"` no runner e iteramos. API ja suporta essa
  extensao sem rewrite.

**Alternatives considered**:

- **Matrix completa (bash + dash + zsh) desde o dia 1**: rejeitado por custo
  de tempo e complexidade sem bug conhecido cross-shell para justificar.
- **Confiar no shebang (rodar `./script.sh`)**: rejeitado porque mascara
  bug em sistemas onde `/bin/sh` difere do shell do desenvolvedor.

## Decision 4: Formato do relatorio de falha

**Decision**: Cada teste emite linhas TAP-like (`ok N - titulo` / `not ok N -
titulo`) seguidas, em caso de falha, de um bloco YAML-ish com `command:`,
`stdout:`, `stderr:`, `exit_code:`, `expected:`. O runner consolida em
sumario final: `PASS: X / FAIL: Y / skipped orphans: Z / total time: Ns`.

**Rationale**:

- FR-011 exige que a mensagem de falha seja suficiente para reproduzir sem
  debugger. Capturar exatamente `command` + `stdout` + `stderr` + `exit_code`
  permite ao mantenedor copiar e colar o comando e ver o mesmo problema.
- TAP e familiar e parsavel por humanos e maquinas — se um dia um CI ou
  editor quiser consumir, o formato esta la.
- Bloco YAML-ish (nao YAML estrito) evita dependencia de parser; e legivel
  mesmo em terminal cru.

**Alternatives considered**:

- **JUnit XML**: overkill, so faz sentido com CI que o consome.
- **Apenas `echo "FAIL: foo"`**: nao atende FR-011 (falta contexto para
  reproduzir).

## Decision 5: Deteccao de scripts orfaos (FR-009)

**Decision**: O runner tem um comando auxiliar `tests/run.sh --check-coverage`
que: (1) lista todos os `*.sh` em `global/skills/**/scripts/`, (2) cruza com a
lista de `test_*.sh` em `tests/`, (3) reporta qualquer script sem teste
associado. A convencao de nome e `tests/test_<nome-do-script>.sh` (ex:
`test_metrics.sh` cobre `metrics.sh`).

**Rationale**:

- SC-006 pede deteccao em <1min. Um simples `find + comm` resolve em
  milissegundos.
- Convencao de nome por arquivo-alvo e auto-explicativa e facilita code review
  (PR que adiciona `foo.sh` sem `test_foo.sh` e visivel).
- Mantem o runner e o check no mesmo entry-point, sem um script separado
  que pode se perder.

**Alternatives considered**:

- **Manter lista explicita em `tests/REGISTRY.txt`**: duplicacao desnecessaria
  quando a convencao de nome ja carrega a informacao.
- **Falhar a suite inteira se houver orfao**: rejeitado porque transforma
  trabalho em progresso (script novo ainda sem teste) em bloqueio. Preferivel
  emitir warning visivel e manter exit code 0 quando apenas orfaos ocorrem.
