# Contract: saida da secao "Shadowed Scope" do `cstk doctor`

**Feature**: `doctor-shadowed-scope` | **Date**: 2026-08-27

> **Status deste contrato**: `[PROPOSTA — a validar na implementacao]` em
> sua integralidade. Nada aqui existe hoje no `cstk doctor`. As secoes
> "Contexto existente" citam comportamento REAL lido de
> `cli/lib/doctor.sh` e servem de fronteira que este contrato nao pode
> violar (Constitution VI: nao afirmar como real o que e desenho).

---

## 1. Contexto existente (REAL — nao muda)

Lido de `cli/lib/doctor.sh`:

- Superficie de flags de `cstk doctor`: `--help|-h`, `--fix`, `--deps`,
  `--scope global|project`, `--scope=<v>`, `--`. **Nao existe `--json`.**
  Esta feature **nao adiciona flag alguma**.
- O relatorio de diagnostico vai para **stderr**. **Excecao real**: o modo
  `--deps` escreve em **stdout** (`printf '==> cstk doctor --deps\n'` sem
  redirect), por contrato de gate de CI. A secao desta feature nao e
  emitida em `--deps` (§2), logo usa stderr.
- Cabecalho do relatorio classico: `==> cstk doctor (scope: %s)`.
- Linhas de achado classicas (preservadas byte-a-byte):
  ```
    [OK]       <label>
    [EDITED]   <label>    local edits detected
    [MISSING]  <label>    in manifest, not on disk
    [ORPHAN]   <label>    nao gerenciada pelo cstk (informativo)
  ```
  `<label>` = `<name>` para `skills`; `<kind>/<name>` para
  `commands`/`agents`.
- Sumario classico (padding literal, incluindo os espacos de alinhamento):
  ```
    ---
    ok:      %d
    edited:  %d
    missing: %d
    orphan:  %d
  ```
  A linha `orphan` ganha o sufixo `  (nao gerenciadas pelo cstk — informativo, nao e drift)`
  quando a contagem e `> 0`. Havendo drift, sai
  `  [DRIFT] %d issue(s). Run with --fix to reconcile manifest.` — ou, sob
  `--fix`, `  --fix executado: entries MISSING removidas; EDITED/ORPHAN preservados.`
- Exit codes atuais: `2` uso incorreto; `1` drift sem `--fix`, `--deps` com
  anomalia, ou Distribution Paths `diverged`/`duplicated-hooks`; `0` caso
  contrario. **Precisao**: `--fix` **nao** garante `0` — o ramo de `--fix`
  ainda devolve `1` quando `_doctor_dp_rc != 0`
  (`[ "$_doctor_dp_rc" = 0 ] || return 1`). Esta feature herda a mesma
  disciplina: `--fix` nao suprime o rc da secao nova.
- Padrao de secao condicional ja existente (modelo de forma seguido
  aqui): `_doctor_distribution_paths` emite
  `\n==> Distribution Paths (plugin cstk)\n  [<estado>] ...` em stderr e
  devolve 0/1 lido por `doctor_main` via `$?`.

**Compatibilidade exigida**: nenhuma linha, contagem ou rotulo do bloco
acima muda. Os cenarios existentes de `tests/cstk/test_doctor.sh`
(`scenario_doctor_4_tipos_drift`, `_apenas_orphan_nao_gateia`,
`_fix_preserva_orphan`, `_tudo_ok_exit0`, `_fix_remove_missing`,
`_apos_fix_menos_drift`, `_manifest_ausente`, `_help`,
`_arg_posicional_invalido`, `_scope_invalido`, `_deps_*`,
`_distribution_paths_*`) MUST continuar passando sem edicao.

---

## 2. Quando a secao e emitida `[PROPOSTA]`

**Sempre.** Em toda invocacao de `cstk doctor` que nao seja `--help` nem
`--deps`, independente de `--scope` e de `--fix`.

- `--deps` e modo distinto e read-only (lido: "ignora --fix/--scope") —
  a secao **nao** e emitida nele.
- `--help` nao roda diagnostico.
- `--fix` **nao suprime** o resultado da secao nem repara nada dela
  (mesma politica de `_doctor_distribution_paths`, e por motivo mais
  forte: sobrescrever a copia de projeto destruiria o trabalho local que
  FR-005 manda preservar).

Posicao na saida: **apos** o sumario classico (`  ---` ... `orphan: %d`)
e **antes** da secao `Distribution Paths`.

---

## 3. Formato de saida `[PROPOSTA]`

Tudo em **stderr**. Duas partes, nesta ordem: achados, depois cobertura.

### 3.1 Cabecalho

```
\n==> Shadowed Scope (escopo de projeto vs catalogo)
```

### 3.2 Linhas de achado — uma por registro `recognized`

```
  [shadowed]           <kind>/<name>    projeto <pver> (<phash12>...) != catalogo <cver> (<chash12>...)
  [shadow-current]     <kind>/<name>    identico ao catalogo (<chash12>...)
  [unmanaged-upstream] <kind>/<name>    sem correspondente no catalogo atual (removido/renomeado upstream)
  [indeterminate]      <kind>/<name>    comparacao impossivel: <motivo>
```

- `<phash12>` / `<chash12>`: primeiros 12 caracteres do hash. Segue o
  precedente literal do `Distribution Paths`, que ja trunca com
  `cut -c1-12` e sufixa `...`.
- `<cver>` sai vazio como `?` quando o manifesto global nao tem entrada
  para `<name>` — **nunca** inferido.
- `<motivo>` ∈ { `projeto-ausente`, `hash-indisponivel`, `symlink`,
  `nome-invalido` }.

**Normativo — todo campo lido do manifesto e UNTRUSTED** (§7): antes de
impressao, `name` e `toolkit_version` MUST ser sanitizados (remocao de
bytes de controle C0/DEL, truncamento a 64 caracteres) e emitidos SEMPRE
via `printf '%s'` com o valor como argumento — nunca concatenados no
formato, nunca interpolados no proprio `printf` de formato. A mesma regra
vale para o texto de erro devolvido por `detect_schema_version` (que ecoa
o header lido do arquivo em `  obtido:   %s`).

**Proibicao explicita (Principio VI)**: a saida MUST NOT afirmar qual
lado esta desatualizado. Nao ha fonte para isso — mtime nao e evidencia,
e o operador pode nem ter o repo do cstk. Mesma postura ja documentada no
cabecalho de `_doctor_distribution_paths`. Mostram-se os dois lados e as
remediacoes possiveis; quem decide e o operador.

### 3.3 Bloco de remediacao (so quando ha `shadowed >= 1`)

```
  remediacao: para realinhar a copia de projeto ao catalogo, reinstale no
              escopo do projeto; para manter a copia local divergente de
              proposito, nenhuma acao e necessaria — este relato e
              informativo sobre a divergencia, nao uma exigencia.
```

> Esta redacao e normativa por FR-005: a secao **nao** pode sugerir que
> manter a copia divergente e erro. Sombrear e fluxo legitimo (testar uma
> definicao antes de instalar); o defeito corrigido e o falso OK, nunca a
> existencia da copia.

### 3.4 Declaracao de cobertura — SEMPRE emitida (FR-006 / SC-003)

```
  --- cobertura
  fontes declaradas: ./.claude/agents/.cstk-manifest, ./.claude/commands/.cstk-manifest
  fontes encontradas: <F> de 2
  fontes lidas com sucesso: <R> de 2
    ./.claude/agents/.cstk-manifest    [<coverage_state>]  registros no arquivo: <D>  interpretados: <N>  nao interpretados: <U>
    ./.claude/commands/.cstk-manifest  [<coverage_state>]  registros no arquivo: <D>  interpretados: <N>  nao interpretados: <U>
```

- As **tres** contagens exigidas por FR-006 tem cada uma sua propria linha
  rotulada: `fontes declaradas`, `fontes encontradas: <F> de 2` e
  `fontes lidas com sucesso: <R> de 2`. `R` conta as fontes cujo
  `coverage_state` e `full` — uma fonte `partial`, `unreadable`,
  `inconsistent` ou `absent` **nao** conta como lida com sucesso. As tres
  contagens MUST NOT depender do texto da linha de veredito (§3.5) para
  serem legiveis.
- Emitida mesmo com `F = 0` e com zero achados. Fonte ausente sai como
  `[absent]  registros no arquivo: 0  interpretados: 0  nao interpretados: 0`.
  Ausencia declarada, nunca omitida.
- `<D>` = **denominador** (linhas de dados no arquivo, contagem de
  granularidade de linha). `<N>` = **numerador** (registros que
  produziram veredito). `<U> = <D> - <N>`, exceto em `inconsistent`.
- Em `unreadable` (FR-009), a linha sai com `<D>` e `<N>` como `?`:
  ```
    ./.claude/agents/.cstk-manifest    [unreadable]  registros no arquivo: ?  interpretados: ?  motivo: <msg de detect_schema_version>
  ```
  A fonte MUST aparecer. Omiti-la ou trata-la como `absent` e violacao de
  FR-009.
- Em `inconsistent` (numerador > denominador — bug do proprio contador):
  ```
    <path>  [inconsistent]  registros no arquivo: <D>  interpretados: <N>  (N > D: inconsistencia interna do contador — reporte este caso)
  ```
  Os numeros brutos MUST ser exibidos como medidos. Normalizar (`min`),
  arredondar ou silenciar e proibido.

### 3.5 Linha de veredito da secao

```
  [PARCIAL] cobertura incompleta: <n> de 2 fontes lidas apenas em parte — nada nesta secao pode ser lido como saude total.
```
ou, quando **nenhuma** fonte foi encontrada (`F = 0`):
```
  [SEM-FONTE] nenhum manifesto de escopo de projeto encontrado no CWD; nada foi comparado.
```
ou, e **somente** quando `F = R = 2`:
```
  [OK] 2 de 2 fontes lidas integralmente; <n> divergencia(s).
```

> `[OK]` MUST NOT ser impresso quando `R < F`, quando `F < 2`, ou quando
> qualquer fonte estiver em `partial`, `unreadable` ou `inconsistent` —
> **mesmo que zero divergencias tenham sido encontradas**. Em particular,
> `F = 0` MUST usar `[SEM-FONTE]`, nunca `[OK] 0 de 2`: imprimir `[OK]`
> sobre um escopo onde nada foi lido e literalmente o falso OK que esta
> feature existe para matar. "Nao encontrei divergencia" e
> "li tudo e nao ha divergencia" sao afirmacoes diferentes, e so a
> segunda e saude (FR-008).

---

## 4. Exit code `[PROPOSTA]`

A secao devolve `0` ou `1`, consumido por `doctor_main` via `$?` e
combinado com os demais (`_doctor_count_drift`, `_doctor_dp_rc`) por OU
logico. Nao ha exit code novo — `2` continua exclusivo de uso incorreto.

| Condicao na secao | rc |
|---|---|
| `count_shadowed >= 1` | 1 |
| qualquer fonte em `partial` | 1 |
| qualquer fonte em `unreadable` | 1 |
| qualquer fonte em `inconsistent` | 1 |
| `count_indeterminate >= 1` | 1 |
| `count_unmanaged_upstream >= 1` (e nada acima) | **0** |
| so `shadow-current`, ou nenhuma fonte encontrada | 0 |

Justificativa de `unmanaged-upstream` = 0: precedente literal do proprio
arquivo sobre ORPHAN — "Enquanto ORPHAN gateava, `cstk doctor || exit 1`
virava falso positivo assim que qualquer skill de terceiro aparecia no
disco, e o operador nao tinha acao nenhuma a tomar". Rename upstream tem
a mesma forma. E **reportado** (FR-010), nao gateado.

Justificativa de cobertura parcial = 1: para um gate de CI
(`cstk doctor || exit 1`), **exit 0 e a apresentacao de sucesso**. FR-008
proibe apresentar como sucesso um escopo lido pela metade.

---

## 5. Interface interna consumida `[PROPOSTA]`

Funcoes da lib nova `cli/lib/manifest-coverage.sh`. Assinaturas
propostas, a validar na implementacao:

| Funcao | Entrada | Saida | Notas |
|--------|---------|-------|-------|
| `manifest_count_data_lines <path>` | caminho | inteiro em stdout | denominador. Granularidade de LINHA. Arquivo ausente ⇒ `0`, exit 0. MUST ser robusto a ausencia de newline final |
| `manifest_record_is_valid <line>` | uma linha | exit 0 valido / 1 invalido | 4 campos TAB, 1-3 nao vazios, campo 3 casa `^[0-9a-f]{64}$`, campo 1 aprovado por `manifest_name_is_safe`, `\r` terminal removido antes de validar |
| `manifest_name_is_safe <name>` | campo 1 | exit 0 seguro / 1 inseguro | casa `^[A-Za-z0-9._-]+$`; rejeita `..`, `/`, `\`, `-` inicial, vazio, e comprimento > 64. **Gate obrigatorio antes de qualquer uso do valor como componente de path** |
| `manifest_scrub_text <valor>` | texto untrusted | texto em stdout | remove bytes de controle C0/DEL, trunca a 64 chars; usado antes de imprimir `name`/`toolkit_version` |
| `manifest_coverage_line <path> <D> <N> <state>` | | linha formatada em stdout | formatador puro |

O **numerador nao tem funcao propria**: e um contador incrementado pelo
laco de classificacao em `doctor.sh`, ao produzir cada veredito. Isso e
deliberado (research.md D6) — contar por uso, e nao por uma segunda
passada de validacao, e o que impede numerador e denominador de
convergirem para a mesma regra.

---

## 6. Nao-objetivos deste contrato

- Nenhuma saida JSON (`--json` nao existe no `cstk doctor`; adicionar
  seria feature nova, fora dos FRs).
- Nenhum `--fix` para os estados novos.
- Nenhum retrofit de outras secoes do doctor nem de
  `guard-hooks-status.sh` (Clarification de 2026-08-27 na spec).
- Nenhuma cobertura do kind `skills` no escopo de projeto — FR-001 cita
  `agents` e `commands`. A lib nova e generica o bastante para incluir
  `skills` depois, mas esta feature nao o faz.

---

## 7. Fronteira de confianca — o manifesto de projeto e UNTRUSTED (normativo)

> Adicionado apos o gate `owasp-security` sobre o Phase 1 (achado HIGH de
> path traversal + 4 MEDIUM). Ver research.md D12.

`./.claude/<kind>/.cstk-manifest` e resolvido **relativo ao CWD** e
`.claude/` e gitignored — mas nada impede que um repositorio de terceiro
**versione** um `.claude/agents/.cstk-manifest` proprio. O vetor real e
banal: o operador clona um repo e roda `cstk doctor` dentro dele. Logo,
**todo campo lido desse arquivo e entrada nao confiavel**, e nao dado
proprio do toolkit. Regras normativas:

| # | Regra | Motivo |
|---|-------|--------|
| R1 | `name` MUST passar por `manifest_name_is_safe` **antes** de compor qualquer path. Reprovado ⇒ registro `unrecognized` (entra no denominador, nunca no numerador) | `name` e o unico campo usado para montar `$HOME/.claude/<kind>/<name>.md` e `./.claude/<kind>/<name>.md`. Sem validacao, `name=../../../.ssh/known_hosts` escapa do catalogo e transforma a secao num oraculo de existencia + prefixo de hash de qualquer arquivo do host |
| R2 | Antes de hashear, MUST testar `[ -h "$path" ]`. Symlink ⇒ `indeterminate` com `<motivo> = symlink`; **nunca** hashear o alvo | `[ -f ]` e `hash_file` seguem symlink. `./.claude/agents/x.md -> ~/.ssh/id_rsa` faria a secao hashear um segredo e imprimir seu prefixo |
| R3 | `name` e `toolkit_version` MUST passar por `manifest_scrub_text` antes de impressao, e serem emitidos via `printf '%s'` com o valor como **argumento** | ESC/`\r`/`\b` em campo untrusted forjam visualmente a linha `[OK] ... lidas integralmente` e apagam `[DRIFT]`. O exit code permanece correto (o gate de CI sobrevive), mas o relato humano e forjavel — a falsa saude que a feature existe para matar |
| R4 | O laco que itera linhas do manifesto MUST rodar sob `set -f` (desabilitando pathname expansion), restaurado ao sair | Com `IFS=<newline>` mas sem `set -f`, uma linha de dados contendo `*` sofre glob e vira N iteracoes — inflando o numerador "por uso" acima do denominador e disparando `inconsistent` a partir de input externo. Precedente literal no repo: `cli/lib/recall.sh`, `fts_query_escape()`, que isola `set -f` num subshell pelo mesmo motivo |
| R5 | Teto explicito de consumo: no maximo 10.000 linhas de dados por fonte e 4.096 bytes por linha. Excedido ⇒ fonte reportada como `unreadable` com motivo `teto-excedido` | Sem teto, um manifesto de 100k linhas gera 2 `awk` + 1 `hash_file` por registro e trava o comando num repo hostil (A04 / CWE-400) |
| R6 | Hash so pode ser **impresso** para paths que passaram em R1 e R2 | O prefixo de 12 caracteres so e inocuo enquanto o path e comprovadamente confinado ao catalogo; sem R1/R2 ele vira oraculo de confirmacao de conteudo |

**Consequencia desejada de R1 no modelo de cobertura**: um `name` fora de
forma nao e silenciosamente ignorado nem tratado como divergencia — ele e
**contado como nao interpretado**, e a declaracao de cobertura ja o expoe
como `partial`. A defesa de seguranca e a declaracao de honestidade usam
o mesmo mecanismo, em vez de competirem.

**TOCTOU (CWE-367) — avaliado e NAO e achado**: a secao e read-only, nao
tem `--fix` associado (§6) e nao toma decisao de privilegio. A janela
entre ler o manifesto e hashear so pode produzir `indeterminate`, que ja
e fail-closed e gateia exit 1.
