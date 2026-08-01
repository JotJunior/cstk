# Research: Configuração de Backend do state.db (Cutover Fase 2)

Documento produzido no Phase 0 do `/plan`. Resolve todos os `NEEDS CLARIFICATION`
do Technical Context antes do design.

> **Aterramento (Constitution VI)**: cada afirmação sobre o código existente abaixo
> cita arquivo + linha verificados na árvore do repositório em 2026-08-01. Nenhum
> caminho, assinatura ou comportamento foi suposto. Onde a decisão projeta algo
> **ainda inexistente**, está marcado como `[PROPOSTA]`.

---

## Decision 1: Localização e formato do arquivo de configuração global

**Decision**: arquivo único `~/.claude/cstk/config`, texto plano `key=value`
(uma atribuição por linha), com a chave `state_backend` assumindo os valores
`sqlite` ou `json`. Comentários com `#` no início da linha e linhas em branco
são ignorados.

**Rationale**:

- O diretório `~/.claude/cstk/` **já existe** na instalação corrente — verificado:
  abriga `knowledge.db`, `knowledge.db-shm`, `knowledge.db-wal` e `plugins/`.
  Não é um caminho novo inventado para esta feature; é o diretório que o toolkit
  já usa para estado global por-usuário fora de qualquer projeto.
- FR-001 exige configuração **por-usuário do SO**, nunca system-wide. `$HOME/.claude/`
  satisfaz isso por construção.
- FR-002 proíbe parser YAML/JSON. `key=value` é parseável em POSIX sh puro sem
  dependência externa nenhuma — inclusive sem `jq`. Isso importa porque o
  diagnóstico (FR-007) precisa reportar a **ausência de `jq`** como anomalia; um
  leitor de config que dependesse de `jq` não conseguiria rodar exatamente no
  cenário que precisa diagnosticar.

**Alternatives considered**:

- **YAML** (`~/.claude/cstk/config.yaml`): rejeitado explicitamente por FR-002 e
  pelo Princípio II (POSIX sh puro, zero dependência). Não existe parser YAML no
  toolkit e introduzir um violaria o bloco MUST do Princípio II sem carve-out
  aplicável (o carve-out 1.3.0 cobre a camada de estado transacional, não parsing
  de configuração).
- **JSON via `jq`**: rejeitado pelo argumento de bootstrap acima — a config precisa
  ser legível quando `jq` está ausente, já que a ausência de `jq` é uma das anomalias
  que o diagnóstico FR-007 deve reportar.
- **Variável de ambiente** (`CSTK_STATE_BACKEND`): rejeitada como mecanismo
  primário — não persiste entre sessões, e FR-005 exige que os dois caminhos de
  inicialização (binário e runtime) cheguem ao mesmo resultado sem que o operador
  precise exportar nada. Permanece viável como override de teste, mas não é a
  fonte da verdade.

---

## Decision 2: Fonte única de leitura da config (o ponto crítico de SC-004)

**Decision**: a leitura da configuração é implementada **uma única vez**, num
script novo do runtime `agente-00c-runtime` — `[PROPOSTA]`
`global/skills/agente-00c-runtime/scripts/state-backend.sh`. O binário `cstk`
**não reimplementa** a leitura: `cli/lib/config.sh` resolve o caminho desse script
e o invoca, exatamente como `cli/lib/state.sh` já faz com `state-db-migrate.sh`.

**Rationale**:

- FR-005 e SC-004 exigem **0% de divergência** entre o caminho do binário `cstk`
  e o caminho do runtime que efetivamente cria o estado. Duas implementações do
  mesmo parser divergem com o tempo — é uma questão de quando, não de se. Uma
  única implementação torna SC-004 verdadeiro **por construção**, não por teste.
- O padrão de delegação já existe e está documentado no repositório:
  `cli/lib/state.sh:43-61` (`_state_migrate_script_path`) resolve o script do
  runtime em três camadas — (1) `PATH`, (2) layout de repo relativo a `CSTK_LIB`
  (`$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/`), (3) layout
  instalado em `$HOME/.claude/skills/agente-00c-runtime/scripts/`. O comentário
  imediatamente acima da função (`cli/lib/state.sh:42`) registra a lição de campo
  que motiva a camada (2): *"resolver SO via ~/.claude passa local e quebra no CI
  fresh-checkout"* (mesma licão de `recall_secrets_filter_path` em
  `cli/lib/recall.sh`). Reusar esse resolvedor evita repetir um bug já pago.
- Quem **precisa** da config é o runtime (é `state-rw.sh init` que cria o estado).
  Colocar a fonte da verdade no runtime e delegar do CLI é a direção correta da
  dependência; o inverso obrigaria o runtime a depender de `cli/lib/`, que não é
  instalado junto com as skills (`cstk install` toca só o catálogo; o runtime do
  CLI vai por `cstk self-update` — GOTCHA registrado no `CLAUDE.md`).

**Alternatives considered**:

- **Parser duplicado** (um em `cli/lib/config.sh`, outro em `_state-config.sh`):
  rejeitado — é exatamente o risco que SC-004 mede. Divergência silenciosa entre
  os dois caminhos é o modo de falha mais caro desta feature.
- **Config lida só pelo binário `cstk`, que passa `--backend` ao runtime**:
  rejeitado por FR-005, que exige que a inicialização disparada **diretamente pelo
  script de runtime** também honre a config. Um flag repassado só funciona quando
  o binário é o ponto de entrada.

---

## Decision 3: Como `init` passa a criar `state.db` (e por que não via `migrate`)

**Decision**: quando a config resolve para `sqlite` e as dependências estão
adequadas, `state-rw.sh init` cria o `state.db` **nativamente** — aplicando o
schema via `state-db-schema.sh create --db <state-dir>/state.db` e populando a
execução — em vez de criar `state.json` e migrar em seguida.

**Rationale (fato bloqueante verificado)**:

- `state-db-migrate.sh:202-204` **recusa** a migração quando
  `.execution.status = em_andamento`:

  ```
  _sdm_status=$(jq -r '.execution.status // ""' "$_SDM_SRC")
  [ "$_sdm_status" != "em_andamento" ] || _sdm_refuse \
    "execucao ativa (.execution.status = em_andamento) — conclua, aborte ..."
  ```

- `state-rw.sh` init escreve `status: "em_andamento"` no template `jq -n` da
  criação (bloco a partir de L408; campo verificado na região L419-470).

  Logo, um `state.json` recém-criado por `init` está **sempre** em
  `em_andamento` e a migração o recusaria com exit 3. O caminho
  "init → migrate" é estruturalmente impossível sem afrouxar a pré-condição M1
  da migração — afrouxamento que reintroduziria o risco que M1 existe para
  prevenir (migrar estado sob execução ativa).

- `state-db-schema.sh create --db PATH` já existe e é o criador canônico do
  schema (verificado L51-79): aplica o DDL, aplica `PRAGMA journal_mode=WAL`
  (idempotente) e chama `_state_db_secure_perms`. `init` reusa esse verbo em vez
  de duplicar DDL.

- A guarda existente de `init` em `state-rw.sh:390-395` (recusa se `state.db` já
  existe) **permanece intacta e continua correta**: ela protege contra criar um
  `state.json` paralelo num projeto já migrado. A mudança desta feature é sobre
  **qual arquivo `init` cria quando não existe nenhum**, não sobre relaxar a
  guarda.

**Alternatives considered**:

- **`init` cria `state.json` e chama `state-db-migrate.sh` logo em seguida**:
  rejeitado pelo fato acima — a migração recusa `em_andamento` (exit 3). Seria
  necessário ou criar o JSON com status falso e corrigir depois (estado
  transitório mentiroso, e uma janela onde o status persistido não descreve a
  realidade), ou adicionar um bypass da M1 (enfraquece a pré-condição para todos
  os callers). Ambos pioram a fonte de verdade transacional.
- **Manter `init` sempre em JSON e migrar manualmente depois**: é o
  comportamento **atual**, e falha SC-001, que exige que após a ativação as novas
  inicializações usem SQLite "sem nenhuma ação manual adicional do operador além
  da ativação em si".

---

## Decision 4: Comparação de versão do `sqlite3` em POSIX sh

**Decision**: comparação numérica campo-a-campo (`major`/`minor`/`patch`) usando
`IFS='.'` e expansão de parâmetro, sem `sort -V`, sem `awk`, sem aritmética de
string. Versão mínima exigida: **3.45.1**, declarada como constante única no
script que a consome.

**Rationale**:

- `sort -V` não é POSIX. É uma extensão GNU; o BSD `sort` do macOS (plataforma de
  desenvolvimento corrente) não a oferece de forma garantida. O `CLAUDE.md` global
  do operador registra a regra: *"não dependa de GNU-only (`timeout`, `sed -i`
  estilo GNU)"*. `sort -V` cai na mesma categoria.
- Comparação lexicográfica de string está **errada** para versões: `"3.9.0"` >
  `"3.45.1"` lexicograficamente, mas é uma versão anterior. O bug seria silencioso
  e permitiria ativar o backend com uma versão insuficiente — exatamente o que
  FR-004 e SC-002 existem para impedir.
- O formato de saída de `sqlite3 --version` foi observado por execução direta
  **nesta máquina de desenvolvimento** (macOS, 2026-08-01):
  `3.51.0 2025-06-12 13:14:41 f0ca7bba1c5e232e5d279fad6338121ab55af0c8c68c84cdfb18ba5114dcaapl (64-bit)`.
  O que a implementação pode assumir é apenas o **formato** — primeiro campo
  separado por espaço é a versão semântica; a extração é `cut -d' ' -f1` ou
  expansão de parâmetro, ambos POSIX. O número `3.51.0` é **específico deste
  ambiente** e não deve ser embutido em nenhum teste como valor esperado.
- O piso 3.45.1 **não é novo desta feature**. Sua fonte real é
  `docs/specs/state-db-foundation/research.md:320-336` (Fase 1), onde foi
  derivado empiricamente como a **menor** das duas versões reais dos ambientes
  suportados: macOS local (`3.51.0`) e o runner `ubuntu-latest` do CI
  (`3.45.1`, pacote `sqlite3 | 3.45.1-1ubuntu2.6`).

  > **Correção de atribuição (Princípio VI)**: `spec.md` FR-003 atribui o piso ao
  > *"amendment 1.3.0 da constitution"*. Isso está **incorreto** — verificado que
  > `docs/constitution.md` **não contém a string `3.45`** em nenhum ponto. O
  > amendment 1.3.0 autoriza `sqlite3` como dependência obrigatória da camada de
  > estado transacional, mas **não fixa versão mínima alguma**. A atribuição
  > correta é a Fase 1, citada acima. Registrado aqui em vez de propagado.

- Esta feature é a primeira a **verificar o piso em código**. Hoje o valor
  `3.45.1` aparece no repositório apenas como texto documental — em
  `cli/lib/recall.sh:2002` (comentário sobre o piso do JSON1), em
  `docs/specs/state-db-foundation/` (Fase 1) e no `CHANGELOG.md:53` — sem nenhuma
  checagem executável.

**Alternatives considered**:

- **`sort -V` / `sort -t. -k1,1n -k2,2n -k3,3n`**: o primeiro não é POSIX; o
  segundo é POSIX mas exige montar e ordenar uma lista de duas linhas e depois
  inspecionar qual saiu primeiro — mais indireto e menos legível que a comparação
  direta, sem ganho.
- **`awk`**: `awk` é POSIX, mas a comparação em sh puro é curta o bastante para
  não justificar sair do shell; manter em sh reduz a superfície de citação/quoting.

---

## Decision 5: Checagem ativa de capability do runtime instalado (FR-004A)

**Decision**: `[PROPOSTA]` o script `state-backend.sh` do runtime expõe um
subcomando `capability`, que imprime um token de capability versionado em stdout
e sai 0. O comando de ativação resolve o caminho do script instalado (mesmo
resolvedor de três camadas da Decision 2), o invoca e exige sucesso **antes** de
escrever qualquer coisa na config.

A checagem falha — e a ativação é recusada com exit não-zero — em qualquer um
destes casos, todos ativos e observáveis:

1. o script não é encontrado em nenhuma das três camadas (runtime antigo, anterior
   a esta feature: o arquivo simplesmente não existe);
2. o script existe mas não reconhece o subcomando `capability` (sai não-zero);
3. o token/versão reportado é anterior ao mínimo exigido.

**Rationale**:

- FR-004A exige checagem **ATIVA executada pelo próprio comando**, não uma
  precondição documentada. Invocar o script instalado e observar o resultado é
  ativo; ler um número de versão de um manifesto seria uma afirmação sobre o
  runtime, não uma observação dele.
- Foi verificado que **não existe hoje nenhum marcador de versão ou capability**
  no runtime (`grep` por `RUNTIME_VERSION|_RUNTIME_VER|CAPABILITY|capability` nos
  scripts do `agente-00c-runtime` não retorna nada). Portanto o marcador é
  necessariamente novo — e a **ausência do arquivo** já é, por si só, o sinal
  correto e inequívoco de "runtime antigo demais", sem precisar de nenhum
  retrocompatível.
- O cenário que FR-004A previne é real e documentado no `CLAUDE.md` do projeto:
  `cstk install`/`cstk update` atualizam **só o catálogo** (`~/.claude/`), enquanto
  o runtime do CLI vai por `cstk self-update`. Um operador pode ter o binário novo
  (que conhece `enable-sqlite`) e o catálogo antigo (cujo `state-rw.sh init` ignora
  a config). Sem a checagem ativa, a ativação "teria sucesso" e as novas execuções
  continuariam silenciosamente em JSON — violando SC-001 sem nenhum sinal ao
  operador.

**Alternatives considered**:

- **Comparar a versão do manifesto do catálogo** (`~/.claude/.cstk-manifest*`):
  rejeitado — mede o que o gerenciador de pacotes *acha* que instalou, não o que
  o script instalado *sabe fazer*. Um catálogo com edição local ou drift
  (situação que o próprio `cstk doctor` existe para detectar) enganaria a
  checagem.
- **`grep` por um nome de função dentro do `state-rw.sh` instalado**: rejeitado —
  acopla a checagem ao texto interno de outro arquivo, quebra em qualquer refactor
  e não é um contrato declarado.

---

## Decision 6: Semântica de exit code do diagnóstico (`--deps`)

**Decision**: o diagnóstico sai **0 apenas quando nenhuma anomalia é detectada** e
**não-zero quando há qualquer anomalia** (dependência ausente ou abaixo do mínimo).
O relatório legível vai para stdout nos dois casos — o exit code é o canal de
máquina, o texto é o canal humano.

**Rationale**:

- FR-007 e SC-003 pedem explicitamente que o exit code seja usável "diretamente
  como gate em pipelines de CI, sem parsing adicional da saída".
- Emitir o relatório mesmo no caminho de falha é o que torna o diagnóstico útil:
  um gate de CI que falha precisa dizer *o que* falhou na mesma execução.
- "Nunca configurado" **não** é anomalia: é o estado default legítimo de qualquer
  instalação que não optou pelo SQLite. FR-008 trata config ausente como
  equivalente a "nenhum backend configurado" com fallback ao legado — um caminho
  normal, não um erro. Tratá-lo como anomalia faria o gate falhar em toda
  instalação padrão, tornando-o inútil.

**Alternatives considered**:

- **Sempre exit 0, sinalizando anomalia só no texto**: rejeitado por SC-003 —
  obrigaria parsing da saída, exatamente o que o critério proíbe.
- **Exit codes distintos por tipo de anomalia** (2 = ausente, 3 = versão baixa):
  rejeitado nesta fase por YAGNI. SC-003 pede apenas a distinção binária
  zero/não-zero. Granularidade adicional pode ser introduzida depois sem quebrar
  contrato (qualquer não-zero continua sendo anomalia).

---

## Decision 7: Escrita idempotente e atômica da config (FR-009-INFRA-IDEMP, FR-004)

**Decision**: a escrita da config usa o padrão *write-temp-then-rename*
(`mktemp` no mesmo diretório + `mv`), e a atualização de uma chave já presente
**reescreve a linha existente** em vez de acrescentar uma segunda.

**Rationale**:

- FR-004 e SC-002 exigem que uma ativação recusada deixe a config **exatamente
  como estava**. A ordem correta — validar tudo primeiro, escrever só no fim — já
  garante isso; o rename atômico protege adicionalmente contra interrupção no meio
  da escrita (que deixaria um arquivo truncado).
- FR-009-INFRA-IDEMP exige que reativar quando já ativado seja no-op silencioso e
  **sem duplicar entradas**. Um `>>` ingênuo acumularia `state_backend=sqlite` a
  cada invocação; o leitor teria que definir uma regra de desempate (primeira ou
  última linha vence) que é pura complexidade acidental.
- `mktemp` + `mv` no mesmo diretório é o padrão **já usado no repositório** —
  `state-rw.sh:407` faz exatamente `_tmp=$(mktemp -- "${_sr_sf}.XXXXXX")` antes de
  escrever o estado. Seguir o padrão local em vez de inventar outro.

**Alternatives considered**:

- **Append simples (`>>`)**: rejeitado por duplicar entradas (viola
  FR-009-INFRA-IDEMP).
- **Reescrita in-place com `sed -i`**: rejeitado — `sed -i` tem sintaxe
  incompatível entre GNU e BSD (regra do `CLAUDE.md` global), e in-place não é
  atômico.

---

## Decision 8: GOTCHAs herdados da Fase 1 que restringem o design

Não são decisões novas, e sim restrições verificadas que o design MUST respeitar.
Registradas aqui porque cada uma já custou um ciclo de depuração na Fase 1.

| GOTCHA | Impacto no design desta feature |
|--------|---------------------------------|
| Sob `set -e`, `x=$(cmd); rc=$?` **mata o shell** antes de `rc` ser lido | Toda captura de saída de `sqlite3 --version`, do resolvedor de path e do `capability` MUST usar a forma `if x=$(cmd); then ... else ... fi` |
| `PRAGMA busy_timeout` **ecoa o valor** no stdout do `sqlite3` CLI | Só afeta o caminho de criação do `state.db` no `init`; qualquer captura de stdout de `sqlite3` nesse caminho MUST usar `.output` ou descartar, sob pena de contaminar o valor lido |
| Testes de permissão usam `stat` **GNU-first** com fallback BSD | Os testes novos que verificarem permissão da config (se houver) MUST seguir o mesmo padrão já estabelecido na suíte |

**Fonte**: registrados como gotchas da feature `state-db-foundation` (Fase 1) e
repassados no contexto de retomada desta onda.
