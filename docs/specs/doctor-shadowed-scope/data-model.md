# Data Model: Doctor Shadowed Scope

**Feature**: `doctor-shadowed-scope` | **Date**: 2026-08-27 | **Phase**: 1

Nao ha persistencia nesta feature (Technical Context: Storage = N/A). As
"entidades" abaixo sao estruturas em memoria (variaveis de shell) e o
formato do arquivo texto ja existente que as alimenta. Campos marcados
`[PROPOSTA]` sao desenho novo desta feature; os demais foram lidos de
`cli/lib/manifest.sh` / `cli/lib/doctor.sh`.

---

## Entity: ProjectScopeInstallRecord (registro de instalacao de escopo de projeto)

Uma linha de dados de um `.cstk-manifest` sob `./.claude/<kind>/`.
Formato **existente**, schema v1 (lido de `cli/lib/manifest.sh`, constante
`_CSTK_MANIFEST_SCHEMA_V1`).

```
# cstk manifest v1
# schema: <skill-name>\t<toolkit-version>\t<source-sha256>\t<installed-at-iso>
agente-00c-clarify-answerer<TAB>9.0.0<TAB>671e67d4...e54c4<TAB>2026-08-23T00:34:44Z
```

| Campo | Posicao (TAB) | Tipo | Obrigatorio | Notas |
|-------|---------------|------|-------------|-------|
| `name` | 1 | string | sim | identidade. Para `commands`/`agents` corresponde a `<name>.md` no diretorio |
| `toolkit_version` | 2 | string | sim | versao do cstk **no momento da instalacao**. Contexto para o operador, nao veredito (research.md D2) |
| `source_sha256` | 3 | string 64x `[0-9a-f]` | sim | assinatura do conteudo **no momento da instalacao** |
| `installed_at` | 4 | ISO 8601 | sim | nao consumido por esta feature |

**Fonte (arquivo)**: `manifest_default_path project <kind>` →
`./.claude/<kind>/.cstk-manifest`, relativo ao CWD. `kind` ∈
{`agents`, `commands`} para esta feature (`skills` fora de escopo:
FR-001 cita agents e commands).

**Estados de reconhecimento** `[PROPOSTA]` — atribuidos pelo validador
novo, nao por `read_manifest` (que nao valida campos):

| Estado | Regra |
|--------|-------|
| `recognized` | exatamente 4 campos TAB; campos 1-3 nao vazios; campo 1 (`name`) casa `^[A-Za-z0-9._-]+$` **e** nao e `..`, nao inicia com `-`, tem <= 64 chars; campo 3 casa `^[0-9a-f]{64}$`; tudo apos remocao de `\r` terminal |
| `unrecognized` | qualquer outra linha de dados: campos a menos, campos a mais, campo vazio, sha fora de forma, **ou `name` fora de forma** |

> **Por que a forma do `name` e requisito de VALIDACAO, e nao so de
> seguranca**: `name` e o unico campo usado para compor path
> (`$HOME/.claude/<kind>/<name>.md` e `./.claude/<kind>/<name>.md`), e o
> manifesto de projeto e entrada nao confiavel (contrato §7, R1). Tratar
> `name` fora de forma como `unrecognized` faz a defesa de seguranca e a
> declaracao de honestidade usarem o **mesmo** mecanismo: o registro entra
> no denominador, nao entra no numerador, e a cobertura o expoe como
> `partial` — em vez de ser silenciosamente ignorado.

> **Invariante**: `read_manifest` NAO produz este estado. MEDIDO — seu
> filtro e `awk '/^[[:space:]]*$/ {next} /^#/ {next} {print}'`, que emite
> qualquer linha nao-comentario nao-vazia sem inspecionar campos. Um
> validador construido sobre ele classificaria 100% como `recognized` por
> construcao.

---

## Entity: CurrentCatalogArtifact (catalogo instalado corrente)

O artefato que o catalogo global contem **agora** para um dado `name`.

| Campo | Origem | Notas |
|-------|--------|-------|
| `path` | `$HOME/.claude/<kind>/<name>.md` | derivado de `name` + `kind` |
| `exists` | teste `[ -f ... ]` | ausente ⇒ `unmanaged-upstream` (FR-010) |
| `content_hash` | `hash_file "$path"` (`cli/lib/hash.sh:33`) | **a verdade da comparacao** (research.md D2) |
| `recorded_version` | campo 2 de `~/.claude/<kind>/.cstk-manifest` para `name` | contexto exibido; **nao** e o veredito |

> `recorded_version` e opcional: se o manifesto global nao tiver entrada
> para `name`, o campo sai vazio e o veredito nao muda — o veredito vem
> de `content_hash`. Nunca inferir versao a partir de mtime ou de
> qualquer outra pista (Principio VI; mesmo raciocinio ja escrito no
> cabecalho de `_doctor_distribution_paths` sobre nao inferir "quem esta
> desatualizado").

---

## Entity: ShadowVerdict (veredito por registro)

Produzido pela comparacao cross-scope. Um por `ProjectScopeInstallRecord`
com estado `recognized`.

| Campo | Tipo | Notas |
|-------|------|-------|
| `kind` | `agents` \| `commands` | |
| `name` | string | do registro |
| `state` | enum (abaixo) | |
| `project_hash` | string \| vazio | `hash_file ./.claude/<kind>/<name>.md` |
| `catalog_hash` | string \| vazio | `hash_file $HOME/.claude/<kind>/<name>.md` |
| `project_version` | string | campo 2 do registro de projeto |
| `catalog_version` | string \| vazio | do manifesto global, quando disponivel |

### State transitions (arvore de decisao, ordem literal) `[PROPOSTA]`

```
registro recognized   (name JA validado em forma — ver acima)
 |
 +-- ./.claude/<kind>/<name>.md OU $HOME/.claude/<kind>/<name>.md e symlink?
 |      -> indeterminate  (motivo: symlink)   [contrato §7 R2]
 |         [nunca hashear o alvo de um symlink: hash_file o seguiria]
 |
 +-- copia de projeto ./.claude/<kind>/<name>.md ausente?
 |      -> indeterminate  (motivo: projeto-ausente)
 |         [nao e MISSING: MISSING pertence a varredura classica e ja
 |          e reportado por ela quando --scope project; aqui a falta da
 |          ponta impede a comparacao, e isso se declara]
 |
 +-- artefato do catalogo $HOME/.claude/<kind>/<name>.md ausente?
 |      -> unmanaged-upstream            (FR-010)
 |
 +-- hash_file falhou em qualquer das pontas?
 |      -> indeterminate  (motivo: hash-indisponivel)
 |
 +-- project_hash == catalog_hash?
 |      -> shadow-current
 |
 +-- caso contrario
        -> shadowed                      (FR-003)
```

Nenhum caminho desta arvore produz "ausencia de relato". Todo registro
`recognized` recebe exatamente um `state` — a saida nunca e silencio
(FR-006/SC-003).

**Registros locais sem entrada de manifesto nao entram nesta arvore**: a
iteracao parte do manifesto, nao do diretorio (research.md D8). Eles
permanecem sob o tratamento existente `ORPHAN`, que nao conta como drift
nem afeta o exit (lido em `_doctor_record`).

---

## Entity: CoverageDeclaration (declaracao de cobertura)

Uma por **fonte declarada**, mais um agregado. Emitida em toda execucao,
inclusive quando nada foi encontrado (FR-006, SC-003).

| Campo | Tipo | Semantica |
|-------|------|-----------|
| `source_path` | string | caminho da fonte **declarada** (existindo ou nao) |
| `found` | bool | arquivo existe e e legivel |
| `readable_schema` | bool | `detect_schema_version` retornou 0 |
| `data_lines` | int >= 0 | **denominador** — linhas de dados no arquivo, contadas por caminho de granularidade de LINHA |
| `records_used` | int >= 0 | **numerador** — registros que produziram veredito |
| `unparsed` | int >= 0 | `data_lines - records_used` |
| `coverage_state` | enum (abaixo) | |

### `coverage_state` `[PROPOSTA]`

| Valor | Condicao | Gateia exit? | Efeito na linha de veredito (§3.5) |
|-------|----------|--------------|------------------------------------|
| `absent` | `found = false` | **nao** | impede `[OK]`; com `F = 0` forca `[SEM-FONTE]` |
| `unreadable` | `found = true`, `readable_schema = false` (FR-009) | **nao** | impede `[OK]`; forca `[PARCIAL]` |
| `full` | `data_lines == records_used` (inclui 0 == 0) | **nao** | condicao **necessaria e nao suficiente** para `[OK]`; com `count_shadowed >= 1` ou `count_nao_comparado >= 1` o rotulo e `[ACHADOS]` |
| `partial` | `data_lines > records_used` (FR-008) | **nao** | impede `[OK]`; forca `[PARCIAL]` |
| `inconsistent` | `records_used > data_lines` (research.md D7) | **nao** | impede `[OK]`; forca `[PARCIAL]` |

> **Nenhum `coverage_state` gateia** — a secao inteira e report-only
> (research.md **D13**, resposta do operador ao `block-001` em `dec-020`:
> *input controlado por terceiro pode produzir diagnostico, nunca
> veredito*). A coluna "Gateia exit?" e mantida, toda em `nao`,
> deliberadamente: apaga-la deixaria a propriedade por omissao, e omissao
> e o que faz a proxima pessoa "consertar" o desenho para gateante.
>
> **O que substitui o gate**: a coluna a direita. FR-008/FR-009 sao
> requisitos sobre **o que a saida afirma**, nao sobre exit code (nenhum
> FR desta feature menciona exit code — contrato §4.3), e continuam
> integralmente satisfeitos pela supressao do `[OK]`.

> **Regra dura**: `partial` e `inconsistent` NUNCA sao normalizados nem
> arredondados para `full`. `records_used` e `data_lines` sao sempre
> emitidos como numeros brutos, lado a lado, mesmo quando iguais.

### Independencia dos dois contadores

| | Denominador (`data_lines`) | Numerador (`records_used`) |
|---|---|---|
| Granularidade | linha | registro decomposto em campos |
| Regras | nao vazia; nao inicia com `#` | 4 campos TAB; 1-3 nao vazios; sha256 valido |
| Como e obtido | contagem direta do arquivo | efeito colateral do laco que **classifica** |
| Conhece o schema? | nao | sim |
| Usa `read_manifest`? | **nao** — le o arquivo diretamente | **sim, mas so como fonte das linhas**; `read_manifest` nao contribui com criterio nenhum para o numerador, que so incrementa quando a classificacao produz veredito |

Consequencia desejada: alterar o classificador **muda o numerador sem
mexer no denominador**, e a cobertura acusa a mudanca sozinha. Se ambos
descendessem da mesma regra, a cobertura seria 100% por construcao — o
defeito que a feature existe para matar.

---

## Entity: ShadowedScopeReport (agregado da secao)

| Campo | Tipo | Notas |
|-------|------|-------|
| `sources[]` | lista de `CoverageDeclaration` | sempre 2 nesta feature: agents e commands |
| `verdicts[]` | lista de `ShadowVerdict` | pode ser vazia |
| `count_shadowed` | int | **nao gateia**; `>= 1` troca o rotulo `[OK]` por `[ACHADOS]` (§3.5) |
| `count_shadow_current` | int | nao gateia; **unico** estado compativel com `[OK]` |
| `count_unmanaged_upstream` | int | nao gateia (research.md D5, generalizado pela D13); **entra em `count_nao_comparado`** |
| `count_indeterminate` | int | nao gateia; **entra em `count_nao_comparado`** |
| `count_nao_comparado` | int (derivado) | `= count_indeterminate + count_unmanaged_upstream`. `>= 1` impede `[OK]` (§3.5) |

> **Por que `count_nao_comparado` e derivado e nao acumulado a parte**: os
> dois estados que o compoem sao, literalmente, "houve registro mas nao
> houve comparacao" — `indeterminate` porque a comparacao falhou,
> `unmanaged-upstream` porque falta o lado direito. FR-010 e explicito
> para o segundo: "nao pode ser contabilizada como saudavel por ausencia
> de uma comparacao possivel". Nenhum dos dois afeta a **cobertura** (o
> registro foi interpretado; a fonte segue `full`), entao sem esta
> derivada nada impediria `[OK]` de sair ao lado deles.
>
> **Nao confundir com nao-gatear**: ambos continuam com `section_rc = 0`.
> Impedir `[OK]` e sobre **veracidade do texto**; gatear e sobre
> **acionabilidade**. Canais distintos (contrato §4.3/§4.4).
| `section_rc` | **`0` (constante)** | consumido por `doctor_main` via `$?` (mesma forma de `_doctor_distribution_paths`, por consistencia de wiring), mas **invariante**: nenhuma entrada o move de `0` |

### Invariante estrutural do `section_rc` `[PROPOSTA]`

```
INV-RC: para toda entrada possivel de ./.claude/<kind>/.cstk-manifest
        (bem formada, malformada, hostil, ausente ou ininterpretavel),
        section_rc == 0.
```

Consequencia de desenho, e nao so de disciplina: o valor **nao deve ser
acumulado** a partir das contagens. A implementacao MUST produzir `0`
por construcao (a funcao termina em `return 0`), em vez de calcular um rc
a partir de `count_shadowed`/`coverage_state` e por acaso sempre dar zero
— um acumulador e uma linha de `||` de distancia de voltar a gatear.

Verificado pelo Cenario 19 do quickstart, que e um teste de invariante
sobre entradas hostis, nao um teste de caso.
