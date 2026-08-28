# Quickstart: Doctor Shadowed Scope

**Feature**: `doctor-shadowed-scope` | **Date**: 2026-08-27 | **Phase**: 1

Cenarios de validacao. Todos rodam contra um `HOME` e um CWD de teste
(mesma tecnica ja usada por `tests/cstk/test_doctor.sh`), nunca contra o
`~/.claude` real do operador.

> **Criterio binario que governa TODOS os cenarios de cobertura**:
> o doctor **PODE** falhar em interpretar um manifesto; o que ele **NAO
> PODE** e reportar OK sobre um que leu pela metade.
> Cobertura parcial reportada como parcial = **sucesso**.
> Cobertura parcial reportada como sucesso = **falha da feature**.

> **Segundo criterio, que governa TODOS os cenarios quanto ao exit code**
> (postura report-only — research.md D13, `dec-020`/`block-001`; contrato
> §4): **a secao Shadowed Scope NUNCA contribui para o exit code**. Em
> todos os cenarios abaixo o exit esperado e determinado exclusivamente
> pela varredura CLASSICA e pelo Distribution Paths. Como os fixtures
> destes cenarios montam um escopo classico limpo, **o exit esperado e `0`
> em todos eles** — inclusive naqueles com `[shadowed]`, `[partial]`,
> `[unreadable]`, `[inconsistent]` ou `[indeterminate]`.
>
> O que cada cenario de fato verifica e o **texto**: o rotulo de cobertura,
> o rotulo de veredito e as linhas de achado. Um teste que afirme exit `1`
> por causa desta secao esta verificando o desenho **antigo** (D5, agora
> supersedida) — ver Cenario 19, que e o teste de invariante dessa
> propriedade.

---

## Cenario 1 — Copia de projeto divergente do catalogo (US1, FR-002/FR-003)

1. Instalar `agents/foo.md` no escopo do projeto (entrada em
   `./.claude/agents/.cstk-manifest` + arquivo em `./.claude/agents/foo.md`).
2. Alterar o conteudo de `$HOME/.claude/agents/foo.md` (catalogo evoluiu),
   sem tocar na copia de projeto nem no manifesto de projeto.
3. Rodar `cstk doctor`.

**Expected**: linha `[shadowed] agents/foo` mostrando os dois hashes
truncados e as duas versoes; veredito da secao
`[ACHADOS] 2 de 2 fontes lidas integralmente; 1 divergencia(s), 0 nao comparado(s) — informativo, nao altera o exit code.`;
bloco de remediacao (§3.3) emitido; **exit `0`** — a secao e report-only
(contrato §4) e o escopo classico esta limpo.

**Verificacao explicita do rotulo**: o veredito MUST ser `[ACHADOS]`, nunca
`[OK]`. Com o exit code fora de jogo, o rotulo e o unico sinal que resta;
um `[OK]` aqui seria um falso OK produzido pela propria feature.

**Anti-regressao (este e o defeito)**: antes desta feature, o mesmo setup
produzia `[OK]` (ou silencio, com `--scope global`), porque a unica
comparacao existente era do artefato de projeto contra o sha do
**proprio** manifesto de projeto — que nao muda sozinho.

---

## Cenario 2 — Copia de projeto identica ao catalogo (US1 cenario 1)

1. Mesmo setup do Cenario 1, mas **sem** alterar o catalogo.
2. Rodar `cstk doctor`.

**Expected**: `[shadow-current] agents/foo`; nenhuma linha `[shadowed]`;
declaracao de cobertura com `interpretados == registros no arquivo`;
veredito `[OK] 2 de 2 fontes lidas integralmente; 0 divergencia(s), 0 nao comparado(s).`;
exit `0`.

Este e o **unico** cenario deste quickstart em que `[OK]` e a saida
correta: cobertura integral, zero divergencia e zero nao-comparado — as
tres condicoes de §3.5.

---

## Cenario 3 — Nenhum manifesto de projeto (US1 cenario 3)

1. CWD sem `./.claude/agents/.cstk-manifest` nem
   `./.claude/commands/.cstk-manifest`.
2. Rodar `cstk doctor`.

**Expected**: nenhum veredito de registro; a declaracao de cobertura
**ainda assim sai** (FR-006/SC-003) com as **tres** contagens rotuladas —
`fontes declaradas: ...`, `fontes encontradas: 0 de 2`,
`fontes lidas com sucesso: 0 de 2` — e ambas as fontes como `[absent]`
com `0/0/0`. Linha de veredito da secao MUST ser exatamente:

```
  [SEM-FONTE] nenhum manifesto de escopo de projeto encontrado no CWD; nada foi comparado.
```

exit `0`.

**Falha**: imprimir `[OK] 0 de 2 fontes lidas integralmente`. Um `[OK]`
sobre um escopo onde **nada** foi lido e o falso OK que a feature existe
para matar, so que produzido pela propria feature.

**Falha**: omitir a secao inteira porque "nao havia nada" — ausencia
silenciosa e indistinguivel de "nao olhei", que e a patologia de origem.

---

## Cenario 4 — `release-wave`: copia local deliberada sem registro (US2, FR-004/FR-005) — CASO NOMEADO

Setup **real, medido neste repo**: `.claude/skills/` contem exatamente um
item, `release-wave`, e o `.claude/skills/.cstk-manifest` local tem uma
unica linha de dados que **nao** e `release-wave` (e `agente-00c-runtime`).
`release-wave` nunca foi instalada pelo cstk — e uma skill local
deliberada, gitignored.

1. Rodar `cstk doctor` na raiz deste repo.

**Expected**: `release-wave` **nao aparece** em nenhuma linha da secao
Shadowed Scope, em nenhum estado — nem em `cstk doctor` puro, nem em
`cstk doctor --scope project`.

Sobre a varredura CLASSICA (comportamento vizinho, nao criado por esta
feature), o Expected e diferente em cada modo, e o teste MUST distinguir:

| Invocacao | `release-wave` na varredura classica |
|---|---|
| `cstk doctor` (default `--scope global`) | **nao aparece** — `_doctor_scope_dir` resolve para `$HOME/.claude/skills`, e `./.claude/` nunca e varrido |
| `cstk doctor --scope project` | aparece como `[ORPHAN]` (informativo; nao conta como drift, nao afeta o exit) |

> Escrever o teste a partir da forma antiga deste cenario ("continua
> sendo listada como `[ORPHAN]`", sem qualificar o modo) o faria falhar
> contra o `cstk doctor` puro. Achado do gate doc-quality sobre este
> proprio quickstart.

**Falha da feature** (qualquer um destes): `release-wave` classificada
como `shadowed`, `indeterminate`, `unmanaged-upstream`, ou contada como
"nao interpretada" na cobertura. A garantia e estrutural — a secao itera
o **manifesto**, nunca o diretorio, logo uma copia sem registro e
inalcancavel por este codigo.

**Variante 4.b (US2 cenario 2)**: criar `$HOME/.claude/skills/release-wave/`
com conteudo diferente (colisao de nome com o catalogo). Expected:
identico ao acima — sem registro de instalacao nao ha base de comparacao,
e nenhuma acusacao e feita.

---

## Cenario 5 — Nome removido/renomeado upstream (FR-010)

1. `./.claude/agents/.cstk-manifest` referencia `bar`; `./.claude/agents/bar.md`
   existe.
2. `$HOME/.claude/agents/bar.md` **nao** existe (removido/renomeado no
   catalogo).
3. Rodar `cstk doctor`.

**Expected**: `[unmanaged-upstream] agents/bar    sem correspondente no
catalogo atual (removido/renomeado upstream)`; exit `0` (a secao nunca
gateia — contrato §4); `bar` **nao** e contado como saudavel nem como
`shadowed`.

**Veredito da secao**: `[ACHADOS] 2 de 2 fontes lidas integralmente;
0 divergencia(s), 1 nao comparado(s) — informativo, nao altera o exit code.`

**`[OK]` aqui e falha da feature.** FR-010 e literal: a definicao "nao
pode ser contabilizada como saudavel por **ausencia de uma comparacao
possivel**". `unmanaged-upstream` e exatamente ausencia de comparacao
possivel — o artefato do catalogo nao existe para servir de lado direito.
Por isso ele entra na contagem `nao comparado(s)` junto com
`indeterminate`, e impede `[OK]` pela mesma clausula (§3.5).

**Distincao preservada**: agregar as duas contagens na linha de veredito
nao as confunde — a linha de achado acima diz `[unmanaged-upstream]` com
o motivo proprio, e `[indeterminate]` diria outro. O veredito agrega; as
linhas de achado discriminam.

> Este ponto e independente do exit code, e continua valendo apesar de
> `unmanaged-upstream` nunca gatear (precedente ORPHAN, contrato §4.4).
> **Nao gatear** e **nao poder ser chamado de saudavel** sao propriedades
> de canais diferentes: a primeira e sobre acionabilidade, a segunda sobre
> veracidade.

**Falha**: reportar `bar` como `[shadow-current]`/OK (afirma comparacao
que nao houve), ou omiti-lo.

---

## Cenario 6 — ADVERSARIAL: linha malformada (US3, FR-007/FR-008)

> Os cenarios 6-9 serao exercitados por uma sessao irma que monta os
> fixtures **por conta propria, sem alinhamento previo** — deliberadamente,
> para verificar em vez de confirmar. As categorias abaixo sao as
> nomeadas; **havera casos alem destes tres**, e a implementacao MUST se
> comportar pelo criterio binario do topo, nao por lista de casos.

1. Montar `./.claude/agents/.cstk-manifest` com header v1 valido e 3
   linhas de dados: 2 registros bem formados + 1 linha sem TAB algum
   (ex.: `bar baz malformada`).
2. Rodar `cstk doctor`.

**Expected**:
```
  ./.claude/agents/.cstk-manifest  [partial]  registros no arquivo: 3  interpretados: 2  nao interpretados: 1
  [PARCIAL] cobertura incompleta: ... nada nesta secao pode ser lido como saude total.
```
exit `0` (a secao e report-only — contrato §4; o sinal e o rotulo
`[partial]` + o veredito `[PARCIAL]`, nunca o exit code).

**Falha**: `registros no arquivo: 2  interpretados: 2  [full]` — sinal de
que o denominador herdou a gramatica do parser e so contou o que ja tinha
entendido.

**Base medida**: fixture com header + schema + 1 registro valido + linha
em branco + `bar baz malformada` + registro com 5 campos ⇒ denominador
`3`, numerador `1`, nao interpretados `2`.

---

## Cenario 7 — ADVERSARIAL: chave/coluna desconhecida

1. Manifesto com header v1 valido e uma linha de 5 campos TAB (coluna
   extra desconhecida), alem de registros validos.
2. Rodar `cstk doctor`.

**Expected**: a linha de 5 campos conta no denominador e **nao** no
numerador ⇒ `[partial]` + veredito `[PARCIAL]`; exit `0` (report-only).

**Falha**: tolerar silenciosamente o campo extra e contar como
interpretado. Um registro de forma desconhecida e exatamente o que a
declaracao de cobertura existe para expor — tolerar e voltar a afirmar
compreensao que nao se tem.

---

## Cenario 8 — ADVERSARIAL: versao de schema futura (FR-009)

1. Manifesto cuja primeira linha e `# cstk manifest v2` (ou qualquer
   header desconhecido).
2. Rodar `cstk doctor`.

**Expected**: a fonte aparece explicitamente como
`[unreadable]  registros no arquivo: ?  interpretados: ?  motivo: <msg>`;
veredito `[PARCIAL]`; exit `0` (report-only).

**Nota sobre a resposta do operador ao `block-001`**: "manifesto que falha
validacao de forma vira `indeterminate`, nunca erro gateante". O
"nunca erro gateante" e o que este `exit 0` implementa. O **nome do
estado** permanece `unreadable`, e nao `indeterminate`, porque FR-009
exige reportar a condicao *explicitamente* e `indeterminate` ja nomeia
outra coisa (falha de comparacao **por registro**, §3.2) — colapsar os
dois perderia a distincao que o proprio FR-009 pede. Ver research.md D13,
consequencia normativa 2.

**Fonte do comportamento subjacente**: `detect_schema_version` ja retorna
1 com `manifest: header desconhecido em <path>` nesse caso — a feature
apenas **para de engolir** esse erro.

**Falha**: tratar a fonte como `[absent]`, ou omiti-la, ou seguir
reportando `[OK]`. FR-009 e literal: reportar a condicao, nunca omitir
nem confundir com ausencia.

---

## Cenario 9 — ADVERSARIAL: arquivo sem newline final (armadilha do contador)

1. Manifesto com header v1 valido cujo **ultimo registro nao termina em
   `\n`**.
2. Rodar `cstk doctor`.

**Expected**: o ultimo registro e contado no denominador **e** no
numerador ⇒ `[full]`, sem falso `[partial]` e sem `[inconsistent]`.

**Por que este cenario existe (MEDIDO)**:
```
$ printf 'a\tb\tc\td' > m2.tsv          # 1 registro, sem \n final
$ grep -cv -e '^[[:space:]]*$' -e '^#' m2.tsv
0
$ awk '/^[[:space:]]*$/ {next} /^#/ {next} {c++} END{print c+0}' m2.tsv
1
```
Um denominador implementado com `grep -c` diria **0** onde o parser ve
**1**, produzindo numerador > denominador — **mais de 100% de cobertura**,
o mecanismo de honestidade mentindo a favor da ferramenta. O denominador
MUST ser robusto a isso.

---

## Cenario 9.a — ADVERSARIAL/SEGURANCA: `name` com path traversal

1. Manifesto de projeto valido em forma TSV, mas com um registro cujo
   campo 1 e `../../../.ssh/known_hosts` (4 campos, sha bem formado).
2. Rodar `cstk doctor`.

**Expected**: o registro e `unrecognized` — conta no **denominador**, nao
no numerador ⇒ `[partial]` + veredito `[PARCIAL]`; exit `0` (report-only:
um manifesto hostil MUST NOT conseguir mover o exit code do operador —
e precisamente essa a razao da postura, research.md D13). Nenhum `stat`,
`hash_file` ou
qualquer leitura ocorre fora de `./.claude/<kind>/` e
`$HOME/.claude/<kind>/`. Nenhum hash de arquivo externo e impresso.

**Falha**: qualquer saida que revele existencia ou prefixo de hash de um
arquivo fora do catalogo. Variantes a exercitar: `name` com `/`, com `\`,
com `-` inicial, vazio, com newline embutida, com 500 caracteres.

---

## Cenario 9.b — ADVERSARIAL/SEGURANCA: symlink apontando para segredo

1. `./.claude/agents/x.md` e um symlink para um arquivo sensivel
   (ex.: `~/.ssh/id_rsa`), e ha registro de `x` no manifesto de projeto.
2. Rodar `cstk doctor`.

**Expected**: `[indeterminate] agents/x    comparacao impossivel: symlink`;
**nenhum** hash do alvo e calculado nem impresso; veredito
`[ACHADOS] ... 0 divergencia(s), 1 nao comparado(s)`; exit `0`
(report-only).

**Verificacao critica do rotulo**: o veredito MUST NOT ser `[OK]`. Este
registro **foi interpretado** (produziu veredito), logo a cobertura
continua `full` e nada na declaracao de cobertura o denunciaria — o unico
mecanismo que impede o falso OK aqui e a clausula `count_nao_comparado = 0`
de §3.5. Um `[OK]` ao lado de `comparacao impossivel: symlink` seria a
ferramenta afirmando ausencia de divergencia sobre um artefato que ela
mesma admite nao ter comparado.

**Por que este cenario existe**: `[ -f ]` e `hash_file` seguem symlink por
padrao. Sem o teste `[ -h ]`, a secao hashearia o segredo e imprimiria seu
prefixo.

---

## Cenario 9.c — ADVERSARIAL/SEGURANCA: bytes de controle forjando saude

1. Manifesto com um registro cujo `name` (ou `toolkit_version`) contem
   sequencias ANSI/`\r`/`\b` desenhadas para apagar a linha `[DRIFT]` e
   escrever `[OK] 2 de 2 fontes lidas integralmente`.
2. Rodar `cstk doctor` com a saida capturada em arquivo E observada num
   terminal real.

**Expected**: os bytes de controle nao aparecem na saida (removidos por
`manifest_scrub_text`); o valor sai truncado a 64 caracteres; o exit code
reflete a realidade.

**Falha**: a inspecao visual do terminal mostrar uma linha de saude que o
arquivo capturado desmente. O exit code nunca foi forjavel — o alvo do
ataque e o **leitor humano**, e e ele que este cenario protege.

---

## Cenario 9.d — ADVERSARIAL/SEGURANCA: linha de dados contendo `*`

1. Manifesto com uma linha de dados que contem `*` (ex.: campo 1 = `*`).
2. Rodar `cstk doctor` num diretorio com varios arquivos.

**Expected**: exatamente **uma** iteracao para aquela linha; ela e
`unrecognized`; o numerador **nao** ultrapassa o denominador; nenhum
`[inconsistent]` e disparado.

**Por que este cenario existe**: com `IFS=<newline>` mas sem `set -f`, o
`for _line in $(...)` sofre pathname expansion e a linha vira N iteracoes,
inflando o numerador "por uso" e disparando `[inconsistent]` a partir de
input externo — isto e, um terceiro conseguiria acionar a mensagem
"reporte este caso" a vontade.

---

## Cenario 10 — Guarda de sanidade: numerador > denominador

1. Forcar (via stub/fixture de teste) um estado em que o classificador
   produza mais vereditos do que ha linhas de dados.
2. Rodar `cstk doctor`.

**Expected**: `[inconsistent]` com os dois numeros **brutos** exibidos e a
nota `(N > D: inconsistencia interna do contador — reporte este caso)`;
veredito `[PARCIAL]`; exit `0` (report-only).

**Falha**: normalizar (`min(N, D)`), arredondar, ou silenciar. Um contador
que se corrige sozinho para caber na narrativa e um contador que mente.

---

## Cenario 11 — Compatibilidade: saida classica inalterada

1. Rodar toda a suite existente: `./tests/run.sh test_doctor`.

**Expected**: os cenarios pre-existentes passam **sem edicao**
(`scenario_doctor_4_tipos_drift`, `_apenas_orphan_nao_gateia`,
`_fix_preserva_orphan`, `_tudo_ok_exit0`, `_fix_remove_missing`,
`_apos_fix_menos_drift`, `_manifest_ausente`, `_help`,
`_arg_posicional_invalido`, `_scope_invalido`, `_deps_*`,
`_distribution_paths_*`).

**Baseline MEDIDO (pre-implementacao, 2026-08-27)**:
`LC_ALL=C ./tests/run.sh test_doctor` ⇒ `# PASS: 22  FAIL: 0  ERROR: 0  ORPHANS: 0  TIME: 6s`.
Qualquer numero de FAIL apos a implementacao e regressao, nao "teste
desatualizado".

**Nota (garantia reforcada pela postura report-only)**: os cenarios
existentes que afirmam exit `0` continuam valendo **independentemente do
que houver no CWD** — nao apenas quando nao ha manifesto de projeto. Como
`section_rc` e a constante `0` (contrato §4.1), nenhum fixture de teste
pre-existente pode ter seu exit alterado por esta feature, mesmo se o CWD
em que a suite roda contiver `./.claude/agents/.cstk-manifest`.

Antes da emenda desta onda isso era uma fragilidade real do plano: a suite
roda no CWD do repo, o repo tem `.claude/`, e um `shadowed` acidental teria
quebrado cenarios que nada tem a ver com a feature. A postura report-only
elimina a classe inteira.

---

## Cenario 12 — `--fix` nao repara nem suprime a secao

1. Setup do Cenario 1 (uma divergencia `shadowed`).
2. Rodar `cstk doctor --fix`.

**Expected**: a copia de projeto **nao** e sobrescrita (FR-005); a linha
`[shadowed]` continua sendo emitida; exit `0` (report-only — `--fix` nao
suprime a **saida** da secao, e nao ha rc dela para suprimir).

**Falha**: `--fix` zerar o achado (equivaleria a destruir o trabalho local
que a feature promete preservar) ou suprimir a secao.

---

## Cenario 13 — `--deps` nao emite a secao

1. Rodar `cstk doctor --deps`.

**Expected**: saida identica a atual (`==> cstk doctor --deps` em stdout);
**nenhuma** linha de Shadowed Scope; exit inalterado.

**Fonte**: `--deps` e modo distinto que ja ignora `--fix`/`--scope`.

---

## Cenario 14 — Cobertura da lib nova

1. Rodar `./tests/run.sh --check-coverage`.

**Expected**: exit `0`. Se a implementacao criar
`cli/lib/manifest-coverage.sh` sem `tests/cstk/test_manifest-coverage.sh`,
o check falha com exit `1` — e essa falha e **correta**.

---

## Cenario 19 — INVARIANTE: nenhuma entrada move o exit code (report-only)

> Este cenario e o **teste de invariante** da postura decidida em
> `block-001`/`dec-020` (research.md D13, contrato §4.1). Nao e um teste
> de caso: e uma varredura que afirma uma propriedade sobre **todas** as
> entradas. Enquanto os demais cenarios verificam *o que a secao diz*,
> este verifica *o que a secao nao faz*.

**Invariante sob teste**:

```
INV-RC: para toda entrada possivel de ./.claude/<kind>/.cstk-manifest,
        a secao Shadowed Scope contribui com rc == 0.
```

### Procedimento

1. Montar um `HOME` e um CWD de teste com o **escopo classico limpo**
   (`cstk doctor` sairia `0` sem esta secao — baseline verificado antes).
2. Para **cada** fixture da matriz abaixo, substituir apenas
   `./.claude/agents/.cstk-manifest` (e/ou `commands`) e rodar
   `cstk doctor`, capturando `$?`.

| # | Fixture de manifesto de projeto | Estado que induz |
|---|---|---|
| 1 | registro divergente do catalogo | `shadowed` |
| 2 | registro identico ao catalogo | `shadow-current` |
| 3 | registro cujo artefato sumiu do catalogo | `unmanaged-upstream` |
| 4 | artefato de projeto e symlink | `indeterminate` (symlink) |
| 5 | artefato de projeto ausente | `indeterminate` (projeto-ausente) |
| 6 | linha sem TAB / com 5 campos / sha malformado | `partial` |
| 7 | `name` = `../../../.ssh/known_hosts` | `partial` (via `unrecognized`) |
| 8 | header `# cstk manifest v2` | `unreadable` |
| 9 | numerador forcado > denominador (stub) | `inconsistent` |
| 10 | manifesto ausente nos dois kinds | `absent` / `F = 0` |
| 11 | linha de dados contendo `*` | `unrecognized` sem inflar numerador |
| 12 | `name`/`toolkit_version` com ESC/`\r`/`\b` | texto sanitizado |
| 13 | mistura: 1 `shadowed` + 1 `partial` + 1 `unreadable` na outra fonte | combinacao |
| 14 | manifesto com 10.001 linhas de dados | `unreadable` (teto-excedido, R5) |
| 15 | manifesto de **uma unica linha de 50 MB sem `\n`** | `unreadable` (teto-excedido, R5) — valida que o teto e imposto por **leitura limitada**, nao por checagem de comprimento a posteriori (§7, nota da R5) |

**Expected — para as 15 linhas, sem excecao**: `$? == 0`.

**Expected adicional na linha 15**: o comando termina em tempo e memoria
limitados pelo teto, nao pelo tamanho do arquivo. Um teto post-hoc passa
no `exit 0` e falha aqui — motivo pelo qual a linha existe separada da 14.

**Expected complementar**: em cada uma, a secao **emitiu** o diagnostico
correspondente em stderr (o cenario nao pode passar por a secao ter sido
silenciosamente pulada — isso daria `0` pelo motivo errado). Verificar as
duas coisas na mesma execucao: exit `0` **e** presenca da linha de achado
esperada.

**Falha**: qualquer fixture produzindo `$? != 0`. Nao ha excecao
legitima — se uma delas gateia, a postura report-only nao foi
implementada, e um repositorio de terceiro recupera a capacidade de
decidir o resultado de `cstk doctor || exit 1` na maquina do operador.

### Teste de mutacao (obrigatorio — o cenario nao vale sem ele)

Um teste que so afirma `exit 0` passa trivialmente contra uma
implementacao que **nao emite a secao**. Para provar que o teste tem
poder de deteccao:

1. Alterar temporariamente a implementacao para `return 1` quando
   `count_shadowed >= 1`.
2. Rodar o Cenario 19.
3. **A linha 1 da matriz MUST falhar.** Se passar, o teste esta cego e
   precisa ser corrigido antes de valer como evidencia.
4. Reverter a alteracao.

> Por que esta exigencia esta escrita aqui: a propriedade sob teste e uma
> **ausencia** (nada gateia), e teste de ausencia e o que mais falha
> silenciosamente. E a mesma disciplina que a feature aplica ao contador
> de cobertura — um mecanismo de honestidade que nao pode ser verificado
> nao e um mecanismo de honestidade.

---

## Cenario 20 — Rotulo de veredito: `[OK]` so quando as tres condicoes valem

Complementa o Cenario 19: com o exit code fora de jogo, **o rotulo passou
a ser o unico sinal**, e por isso ganha teste proprio.

| Setup | `F=R=2`? | `count_shadowed` | `count_nao_comparado` | Veredito esperado |
|---|---|---|---|---|
| tudo identico ao catalogo | sim | 0 | 0 | `[OK]` |
| uma divergencia | sim | 1 | 0 | `[ACHADOS]` |
| um symlink | sim | 0 | 1 | `[ACHADOS]` |
| um `unmanaged-upstream` | sim | 0 | 1 | `[ACHADOS]` |
| uma linha malformada | nao (`partial`) | 0 | 0 | `[PARCIAL]` |
| header desconhecido | nao (`unreadable`) | 0 | 0 | `[PARCIAL]` |
| nenhum manifesto | `F = 0` | 0 | 0 | `[SEM-FONTE]` |

**Expected**: o rotulo exato de cada linha; exit `0` em **todas**.

**Falha**: `[OK]` em qualquer linha que nao seja a primeira. As linhas 3 e
4 sao as que mais provavelmente escapam numa implementacao ingenua,
porque `indeterminate` e `unmanaged-upstream` **nao afetam a cobertura**
— a fonte segue `full`, e so a clausula `count_nao_comparado = 0` de §3.5
impede o falso OK.
