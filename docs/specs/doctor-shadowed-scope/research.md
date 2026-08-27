# Research: Doctor Shadowed Scope

**Feature**: `doctor-shadowed-scope` | **Date**: 2026-08-27 | **Phase**: 0

> **Regra deste documento (Constitution VI)**: tudo afirmado como
> EXISTENTE foi lido de `cli/lib/doctor.sh`, `cli/lib/manifest.sh`,
> `cli/lib/hash.sh`, `plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh`
> ou medido em execucao real (marcado **MEDIDO**). Tudo que e desenho novo
> esta marcado `[PROPOSTA — a validar na implementacao]`.

---

## Decision 1 — Onde vive o codigo novo

**Decision**: duas metades.

1. **Lib nova `cli/lib/manifest-coverage.sh`** `[PROPOSTA — a validar na
   implementacao]`: validador de registro + contadores + montagem da
   declaracao de cobertura. Nao depende de `doctor.sh`.
2. **Secao nova em `cli/lib/doctor.sh`**: `_doctor_shadowed_scope`
   `[PROPOSTA]`, que consome a lib e faz a comparacao cross-scope.

Consequencia obrigatoria: `tests/cstk/test_manifest-coverage.sh`
`[PROPOSTA]`. `CLAUDE.md` §"Como testar scripts shell" e literal — todo
`.sh` novo em `cli/lib/` exige `tests/cstk/test_<nome>.sh`, e
`./tests/run.sh --check-coverage` sai com exit 1 em orfao.

**Rationale**:

- A spec (US3, FR-006) pede que a declaracao de cobertura sirva de
  **padrao de referencia reutilizavel** por outros mecanismos de saude do
  toolkit. Codigo enterrado dentro de `_doctor_*` (funcoes privadas,
  dependentes das variaveis globais `_doctor_count_*`) nao e reutilizavel
  por construcao.
- A Clarification de 2026-08-27 na spec limita o **retrofit** a zero, mas
  nao proibe deixar o mecanismo pronto para reuso — ao contrario, e o
  proposito declarado.

**Alternatives considered**:

- *Tudo dentro de `doctor.sh`*: rejeitado — mata o requisito de reuso
  (FR-006) e engorda um arquivo que ja tem 674 linhas (MEDIDO: `wc -l`).
- *Estender `cli/lib/manifest.sh`*: **rejeitado, e este e o ponto
  delicado**. `manifest.sh` esta no caminho de ESCRITA de `install`/
  `update` (`write_manifest`, `upsert_entry`, `remove_entry`). Seu
  `read_manifest` deliberadamente **nao valida campos** — MEDIDO na linha
  do filtro: `awk '/^[[:space:]]*$/ {next} /^#/ {next} {print}'`, que
  imprime qualquer linha nao-vazia e nao-comentario inteira. Endurecer
  esse leitor mudaria o comportamento de todos os chamadores existentes
  (install/update/doctor/plugin-detect), o que e mudanca de escopo e
  risco de regressao fora desta feature. A lib nova e **puramente
  aditiva**: `manifest.sh` fica intocado.

---

## Decision 2 — Qual e a "verdade" do catalogo corrente: conteudo ou registro?

**Decision**: **conteudo em disco**. A comparacao cross-scope compara o
hash do artefato de projeto contra o hash do artefato correspondente no
catalogo global (`$HOME/.claude/<kind>/<name>.md`), calculado na hora com
`hash_file`. O `source-sha256` gravado no manifesto **global** NAO e a
base da comparacao. `[PROPOSTA — a validar na implementacao]` quanto a
funcao/assinatura; a escolha de "conteudo, nao registro" e derivada de
fonte (abaixo).

**Rationale**:

- FR-002 da spec e literal: "comparar o **conteudo atual** dessa
  definicao contra o **conteudo** que o catalogo instalado atualmente
  contem". Conteudo contra conteudo.
- Um manifesto e uma *afirmacao sobre* conteudo, feita no passado. Usar a
  afirmacao como base seria repetir, um nivel acima, exatamente o defeito
  que a feature corrige (confiar num registro que nunca e reconferido).
- **Precedente existente no toolkit**: `guard-hooks-status.sh` resolve
  `current|stale|unknown` por comparacao byte-a-byte da copia do projeto
  contra a copia do catalogo. MEDIDO, linha 354 do arquivo:
  `if cmp -s -- "$_gh_fr_proj" "$_gh_fr_cat"; then` ... senao
  `printf 'stale'`. E, linha 352, sem `cmp` no PATH o veredito e
  `unknown`, **nunca** `stale` — nunca inventa um veredito que nao pode
  sustentar. Esta feature herda os dois comportamentos.

**Alternatives considered**:

- *Comparar `source-sha256` do manifesto de projeto contra
  `source-sha256` do manifesto global*: rejeitado — compara duas
  afirmacoes, nenhuma delas reconferida contra o disco. Um catalogo
  global `EDITED` (estado que o proprio doctor ja detecta) passaria como
  alinhado.
- *Comparar `toolkit-version` (campo 2) apenas*: rejeitado como
  criterio PRIMARIO — versoes iguais nao garantem conteudo igual (edicao
  local no catalogo global nao bumpa versao). As duas versoes sao
  **reportadas como contexto** para o operador, porque sao a informacao
  acionavel ("sua copia e da 5.26.0, o catalogo esta na 9.0.0"), mas o
  veredito nasce do hash.

---

## Decision 3 — Nomes dos estados da secao nova

**Decision** `[PROPOSTA — a validar na implementacao]`:

| Estado | Significado |
|--------|-------------|
| `shadowed` | copia de projeto **existe**, catalogo global **existe**, hashes **diferem** |
| `shadow-current` | copia de projeto existe e e byte-identica ao catalogo global |
| `unmanaged-upstream` | nome consta no manifesto de projeto, mas **nao ha** artefato correspondente no catalogo global (removido/renomeado) — FR-010 |
| `indeterminate` | veredito **por registro**: uma das duas pontas nao pode ser hasheada, e symlink, ou o `name` reprovou na validacao de forma |

Estados de **fonte** (cobertura) sao um eixo SEPARADO e vivem em
`coverage_state` — `absent` / `unreadable` / `full` / `partial` /
`inconsistent` (data-model.md). Nao confundir: `indeterminate` qualifica
UM registro; `unreadable` qualifica UM ARQUIVO inteiro que nem chegou a
ser lido.

**Rationale**:

- `shadowed` foi o termo fixado pelo operador e da nome a feature.
- `shadow-current` existe para satisfazer FR-006/SC-003: a declaracao de
  cobertura sai em TODA execucao, logo os registros saudaveis tambem
  precisam de um rotulo — o silencio nao pode ser o unico sinal de saude
  (silencio e indistinguivel de "nao olhei", que e o defeito original).
- `unmanaged-upstream` e nomeado a parte porque FR-010 e explicito: nao
  ha as duas pontas, logo **nao houve comparacao**; chamar isso de
  `shadowed` afirmaria uma divergencia medida que nao foi medida
  (violacao do Principio VI), e chamar de saudavel e exatamente o falso
  OK proibido.
- `indeterminate` reusa a palavra ja empregada por
  `_doctor_distribution_paths` (MEDIDO: estado `undetermined` no
  cabecalho e nos ramos daquela funcao) para a mesma classe semantica:
  "nao consegui, e digo que nao consegui".

**Alternatives considered**:

- *Reusar `EDITED`*: rejeitado — `EDITED` ja significa, na saida atual
  (MEDIDO: `[EDITED]   %s    local edits detected`), "diverge do que o
  MEU proprio manifesto registrou". Sobrecarregar o rotulo com uma
  segunda semantica cross-scope quebraria a saida historica que os
  cenarios de `tests/cstk/test_doctor.sh` afirmam.
- *`stale`*: considerado (e o termo do `guard-hooks-status.sh`), mas
  descartado porque "stale" implica direcao temporal (quem esta atrasado)
  — e a Decision 5 abaixo mostra que essa direcao nao e determinavel com
  fonte.

---

## Decision 4 — A secao roda sempre, ou so com `--scope project`?

**Decision**: **sempre**, independente de `--scope` e de `--fix`.
`[PROPOSTA — a validar na implementacao]`

**Rationale**:

- MEDIDO: `_doctor_reset_state` fixa `_doctor_scope=global` como default.
  Se a secao nova exigisse `--scope project`, o operador que roda
  `cstk doctor` puro continuaria vendo o mesmo falso OK de hoje — a
  feature entregaria zero para o caso majoritario.
- A secao e **inerentemente cross-scope** (le o lado projeto E o lado
  global no mesmo veredito). `--scope` seleciona qual lado a varredura
  CLASSICA inspeciona; nao ha valor de `--scope` que descreva a nova
  comparacao. Aplicar `--scope` a ela seria sobrecarregar a flag.
- Precedente direto: `_doctor_distribution_paths` ja roda incondicional a
  `--scope`/`--fix`. MEDIDO no comentario de `doctor_main`: "independente
  de --scope/--fix — nao ha acao de --fix para divergencia entre catalogo
  classico e plugin... Por isso o resultado NUNCA e suprimido pelo ramo
  --fix".
- Mesma logica se aplica aqui: `--fix` so sabe reparar manifesto
  (`remove_entry` de MISSING, refresh de hash de OK — MEDIDO em
  `_doctor_apply_fix`). Nao ha reparo automatico seguro para `shadowed`:
  sobrescrever a copia de projeto destruiria exatamente o trabalho local
  que US2/FR-005 mandam preservar. Secao read-only, remediacao manual.

**Alternatives considered**:

- *So com `--scope project`*: rejeitado (acima).
- *Flag nova `--shadowed`*: rejeitado — opt-in reproduz o falso OK por
  default, que e o defeito.

---

## Decision 5 — Efeito no exit code

**Decision** `[PROPOSTA — a validar na implementacao]`:

| Condicao | Contribui para exit 1? | Justificativa |
|----------|------------------------|---------------|
| `shadowed` (>=1) | **Sim** | divergencia real e acionavel; simetrico a `diverged` do Distribution Paths (MEDIDO: `return 1`) |
| cobertura **parcial** (denominador > numerador) | **Sim** | FR-008: o escopo afetado MUST NOT ser apresentado como sucesso. Para um gate de CI (`cstk doctor \|\| exit 1`), exit 0 **e** a apresentacao de sucesso |
| fonte **ininterpretavel** (FR-009) | **Sim** | mesma razao; "nao consegui ler" nunca pode sair como 0 |
| inconsistencia interna (numerador > denominador) | **Sim** | bug do proprio contador (ver Decision 7) — sair 0 seria o contador mentindo sobre si mesmo |
| `indeterminate` por registro (>=1) | **Sim** | "nao consegui comparar" nunca pode sair como sucesso; e o mesmo raciocinio de cobertura parcial, aplicado a granularidade de registro |
| `unmanaged-upstream` (>=1) | **Nao** | ver rationale abaixo |
| `shadow-current` apenas | **Nao** | tudo comparado, tudo igual |
| nenhuma fonte encontrada | **Nao** | nada a comparar; declaracao sai com 0/0/0 |

**Rationale para `unmanaged-upstream` NAO gatear**: precedente literal e
recente do proprio arquivo. MEDIDO, comentario de `_doctor_record` sobre
ORPHAN: "Enquanto ORPHAN gateava, `cstk doctor || exit 1` virava falso
positivo assim que qualquer skill de terceiro aparecia no disco, e o
operador nao tinha acao nenhuma a tomar". `unmanaged-upstream` tem a
mesma forma: pode ser apenas um rename legitimo upstream, e nao ha acao
obrigatoria. Ele e **reportado** (FR-010 satisfeito: distinguivel de
saudavel), mas nao gateia.

**Rationale para cobertura parcial GATEAR**: esta e a decisao central da
feature. Se cobertura parcial saisse com 0, o comando teria dito
"cheguei ao fim sem problema" sobre um arquivo que leu pela metade —
literalmente a classe de defeito que a feature existe para matar,
reintroduzida no seu proprio mecanismo de honestidade.

**Precedentes de exit consultados (MEDIDOS)**: `cstk doctor --deps`
retorna 1 em anomalia (a Decisao registrada na execucao
`state-backend-config` escolheu "exit nao-zero em anomalia (gate)" sobre
"sempre exit 0 (informativo)"); `_doctor_distribution_paths` retorna 1 em
`diverged` e `duplicated-hooks`, e 0 em `undetermined`. **Divergimos
deliberadamente** do `undetermined`→0 daquela funcao no nosso
`indeterminate`, porque la o indeterminado e sobre um plugin opcional,
e aqui e sobre a fonte que a feature promete ter lido.

---

## Decision 6 — Como medir cobertura sem o contador herdar a gramatica do parser

**Decision** `[PROPOSTA — a validar na implementacao]`: dois caminhos com
**granularidades diferentes**, nunca duas passadas do mesmo criterio.

- **Denominador — `manifest_count_data_lines <path>`**: criterio
  puramente de LINHA (nao vazia, nao iniciada por `#`). Nao olha campos,
  nao conhece TAB, nao conhece o schema. Nao chama `read_manifest`.
- **Numerador — contagem por USO**: incrementado como efeito colateral do
  laco que de fato classifica; um registro so conta quando foi
  decomposto em `(name, version, sha)` validos **e** produziu um veredito
  (`shadowed`/`shadow-current`/`unmanaged-upstream`/`indeterminate`).

**Rationale — por que numerador e denominador nao colapsam**:

1. **Granularidade diferente**: o denominador opera sobre linhas; o
   numerador sobre registros decompostos em campos. Nenhuma regra e
   compartilhada alem de "isto e uma linha de dados".
2. **`read_manifest` nao serve de numerador** — este e o ponto que o
   aterramento tornou visivel. MEDIDO: seu filtro e
   `awk '/^[[:space:]]*$/ {next} /^#/ {next} {print}'`, ou seja, ele
   **imprime toda linha nao-comentario nao-vazia sem olhar campo nenhum**.
   Um numerador construido sobre `read_manifest` daria sempre
   numerador == denominador, isto e, **100% de cobertura por
   construcao** — o contador auto-congratulatorio que a spec proibe.
   Logo o discriminador "reconhecido vs nao interpretado" precisa nascer
   de um validador de registro **novo**, que hoje nao existe em lugar
   nenhum do repo.
3. **Contar por uso, e nao por uma segunda passada de validacao**, e o
   que impede a divergencia silenciosa: se amanha o classificador
   passar a rejeitar um caso que o validador aceitava, o numerador cai
   sozinho e a cobertura acusa. Duas passadas independentes poderiam
   discordar sem ninguem perceber.

**MEDIDO — armadilha descartada, e por que importa**: a primeira escolha
obvia de denominador seria `grep -cv -e '^[[:space:]]*$' -e '^#'`
(ferramenta diferente do `awk` do parser, aparentemente "mais
independente"). Medicao real num arquivo **sem newline final**:

```
$ printf 'a\tb\tc\td' > m2.tsv          # 1 registro, sem \n final
$ grep -cv -e '^[[:space:]]*$' -e '^#' m2.tsv
0
$ awk '/^[[:space:]]*$/ {next} /^#/ {next} {c++} END{print c+0}' m2.tsv
1
```

O denominador via `grep` diria **0** onde o parser enxerga **1** —
produzindo numerador (1) > denominador (0), ou seja, **mais de 100% de
cobertura**: o mecanismo de honestidade mentindo a favor da ferramenta.
Por isso o denominador MUST ser robusto a ausencia de newline final
(forma `awk`), e MUST existir a guarda da Decision 7.

**MEDIDO — validador funcionando sobre fixture com lixo**:

```
# arquivo: header + schema + 1 registro valido + linha em branco
#          + "bar baz malformada" (sem TAB) + registro com 5 campos
denominador (linhas de dados)         : 3
numerador (NF==4 e campos nao vazios) : 1
=> nao interpretados                  : 2
```

---

## Decision 7 — Guarda de sanidade do proprio contador

**Decision** `[PROPOSTA — a validar na implementacao]`: se
`numerador > denominador`, a fonte e reportada com `coverage_state =
inconsistent` (nome unico usado tambem em plan.md, data-model.md e no
contrato — `indeterminate` fica reservado ao eixo de REGISTRO, ver D3),
com motivo explicito de **inconsistencia interna do contador**, e
contribui para exit 1. Nunca normalizar (nunca `min(num, den)`), nunca silenciar.

**Rationale**: e a unica forma de a feature nao virar a proxima instancia
da classe que ela mata. Um contador que se corrige sozinho para caber na
narrativa e um contador que mente. A condicao e, por construcao,
impossivel se ambos os caminhos estiverem corretos — logo sua ocorrencia
e evidencia de bug, e evidencia de bug se reporta.

---

## Decision 8 — Copia local sem registro nunca vira problema (US2/FR-004/FR-005)

**Decision**: a secao nova **so** itera nomes presentes no manifesto de
PROJETO. Nao varre o diretorio. Uma definicao local sem entrada no
manifesto e literalmente inalcancavel por este codigo.

**Rationale**: a garantia vira estrutural, nao comportamental — nao
depende de um `if` que alguem possa inverter num refactor.

**Precisao sobre o tratamento existente (corrigido apos o gate
doc-quality)**: e tentador dizer que essas definicoes "continuam sendo
listadas como `ORPHAN`". Isso so e verdade sob `cstk doctor --scope
project`. No `cstk doctor` **puro** (default `--scope global`, MEDIDO em
`_doctor_reset_state`), `_doctor_walk_kind` resolve
`_doctor_scope_dir="${HOME}/.claude/$_dwk_kind"` e **nunca varre
`./.claude/`** — logo `release-wave` nao recebe rotulo nenhum, nem
`ORPHAN`. A afirmacao correta e a mais fraca e a que importa: **a secao
nova nao lhe atribui problema algum, em nenhum modo de invocacao**, o que
e exatamente o que FR-004/FR-005 exigem.

**Caso de teste nomeado**: `.claude/skills/release-wave` neste repo.
MEDIDO: `.claude/skills/` contem exatamente um item, `release-wave`; e o
`.claude/skills/.cstk-manifest` local tem uma unica linha de dados,
`agente-00c-runtime  5.26.0  11d6139a...  2026-07-26T16:05:20Z` — que
nao e `release-wave`. Ou seja, `release-wave` nao tem registro nenhum, e
qualquer regra que a acuse esta errada por definicao.

---

## Decision 9 — Dependencia de CWD, declarada e nao contornada

**Decision**: a secao resolve as fontes de projeto via
`manifest_default_path project <kind>`, que MEDIDO retorna
`./.claude/<kind>/.cstk-manifest` — **relativo ao CWD**. Nao ha
descoberta de raiz de repositorio.

**Rationale**: (a) `.claude/` e gitignored e o desenho nao pode depender
de git para detectar nada (restricao do operador); (b) inventar uma
heuristica de "subir ate achar `.git`" contradiz (a) e adiciona
comportamento nao especificado; (c) precedente literal — o
`_doctor_distribution_paths` ja le `./.claude/settings.json` e
`./.claude/settings.local.json` relativos ao CWD (MEDIDO). A limitacao e
**documentada no contrato**, nao escondida: rodar `cstk doctor` fora da
raiz do projeto encontra 0 fontes, e a declaracao de cobertura dira
exatamente isso (fontes declaradas: 2, encontradas: 0), em vez de
silenciar.

---

## Decision 10 — Tolerancias de formato (CRLF, campos extras)

**Decision** `[PROPOSTA — a validar na implementacao]`: remover `\r`
terminal de cada linha antes de validar; exigir exatamente 4 campos
separados por TAB; campos 1-3 nao vazios; campo 3 com forma de sha256
(64 caracteres em `[0-9a-f]`).

**Rationale/MEDIDO**: numa linha CRLF, `awk -F'\t'` reporta `NF==4`
normalmente, mas o ultimo campo carrega o `\r`:

```
$ printf 'a\tb\tc\td\r\n' > m3.tsv
$ awk -F'\t' '{print "campo4=["$4"]"}' m3.tsv | cat -v
campo4=[d^M]
```

Isso e a mesma armadilha ja registrada no repo ("`$()` nao remove `\r`").
Como so usamos os campos 1-3, um CRLF nao corromperia o veredito hoje —
mas deixar passar sem normalizar cria uma bomba-relogio para o dia em
que o campo 4 for usado. Normalizar e barato e determinista.

Campo extra (5 campos) e tratado como **nao interpretado**, nao como
tolerado: um registro com forma desconhecida e exatamente o caso que a
declaracao de cobertura existe para expor.

---

## Decision 11 — Sem `jq`, sem GNU-only, sem `--json`

**Decision**: caminho novo usa apenas `awk`, `printf`, `cmp`/`hash_file`,
`[`/`case`. Nenhuma saida JSON e adicionada nesta feature.

**Rationale**: MEDIDO — `_doctor_parse_args` aceita exatamente
`--help|-h`, `--fix`, `--deps`, `--scope <v>`, `--scope=<v>` e `--`.
**Nao existe `--json` no `cstk doctor`**. A Clarification da spec deixou
"onde/como o novo estado aparece na saida (texto e/ou `--json`)" em
aberto para o `/plan`; a decisao e **texto em stderr apenas**, pelo
precedente unanime das duas secoes existentes (`_doctor_emit_report` e
`_doctor_distribution_paths` escrevem tudo em stderr — MEDIDO). Adicionar
uma superficie `--json` seria feature nova, nao coberta pelos FRs, e
ampliaria o escopo. Fica registrado como candidato futuro, nao entregue.
`jq` continua confinado a `plugin-detect.sh` (Constitution II, amendment
1.1.0).

---

## Decision 12 — Fronteira de confianca: o manifesto de projeto e entrada nao confiavel

**Origem**: gate `owasp-security` sobre o Phase 1 (1 HIGH, 4 MEDIUM, 2 LOW).
As Decisoes 1-11 tratavam `./.claude/<kind>/.cstk-manifest` como dado
proprio do toolkit. Isso estava **errado** e a D9 so o discutia como
ergonomia de CWD, nunca como superficie de ataque.

**Decision** `[PROPOSTA — a validar na implementacao]`: declarar
formalmente o manifesto de escopo de projeto como **entrada nao
confiavel** e aplicar as 6 regras normativas do contrato §7 (R1..R6):
validacao de forma do `name` antes de compor path; recusa de symlink;
sanitizacao + `printf '%s'` em texto untrusted; `set -f` no laco; teto de
consumo; hash impresso so para path validado.

**Rationale**:

- O vetor e banal e nao exige nada exotico: `.claude/` e gitignored **no
  cstk**, mas nada impede um repositorio de terceiro de **versionar** um
  `.claude/agents/.cstk-manifest`. O operador clona e roda `cstk doctor`
  dentro — e o CWD-relativo da D9 vira o canal.
- O achado HIGH e real e verificavel no proprio desenho anterior: o
  validador exigia forma dos campos 2 e 3, mas **nao do campo 1** — que e
  justamente o unico usado para compor path. `name=../../../.ssh/known_hosts`
  escaparia do catalogo e a secao viraria oraculo de existencia mais 12
  caracteres de hash de qualquer `.md` do host.
- O achado de injecao de terminal e o mais ironico e por isso o mais
  importante de fechar: bytes de controle num campo untrusted permitem
  **forjar visualmente** a linha `[OK] ... lidas integralmente` e apagar
  `[DRIFT]`. O exit code permaneceria correto (o gate de CI sobrevive),
  mas o relato ao humano seria falsificavel — isto e, a feature de
  honestidade seria forjavel pelo proprio arquivo que ela audita.
- O achado de glob (`set -f`) ataca especificamente o mecanismo da D6: uma
  linha de dados contendo `*` sofre pathname expansion no laco
  `for _line in $(...)` com `IFS=<newline>`, inflando o numerador "por
  uso" acima do denominador e disparando `inconsistent` a partir de input
  externo. Precedente literal de mitigacao ja no repo: `cli/lib/recall.sh`,
  `fts_query_escape()`, isola `set -f` num subshell pelo mesmo motivo.

**Encaixe deliberado com a D6**: `name` reprovado **nao** e silenciado nem
vira divergencia — vira `unrecognized`, entrando no denominador e nao no
numerador. A defesa de seguranca e a declaracao de cobertura passam a usar
o **mesmo** mecanismo, em vez de competirem por quem decide o veredito.

**Alternatives considered**:

- *Recusar ler manifesto de projeto fora de uma allowlist de repositorios*:
  rejeitado como desenho unilateral — muda o escopo da feature (US1 quer
  justamente ver a copia de projeto) e e uma decisao de produto do
  operador, nao do agente. **Registrada como bloqueio humano** desta onda.
- *Confiar no manifesto porque `.claude/` e gitignored*: rejeitado —
  gitignore e do cstk, nao do repo clonado; e um `.gitignore` alheio nao
  e mecanismo de seguranca.
- *So sanitizar na impressao, sem validar o path*: rejeitado — fecharia o
  achado de terminal e deixaria o traversal aberto, que e o de maior
  impacto (leitura fora do escopo declarado).

**TOCTOU**: avaliado e **descartado** como achado — secao read-only, sem
`--fix`, sem decisao de privilegio; a janela so pode produzir
`indeterminate`, ja fail-closed.
