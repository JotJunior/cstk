# Contracts: validate-docs-sdd-profile

Contrato de interface do MOTOR deterministico dos perfis spec-profile e
plan-profile. A "interface externa" desta feature e a **CLI do script POSIX**
`global/skills/validate-documentation/scripts/validate-sdd.sh` (args + exit
codes + formato de saida machine-readable), consumida pelo operador e pelos
orquestradores `agente-00c`/`feature-00c` como gate pos-artefato.

> **[PROPOSTA — a validar na implementacao]** Este e um contrato NOVO,
> projetado do zero para uma interface que AINDA NAO EXISTE (a skill
> `validate-documentation` nao possui `scripts/` hoje). Nenhum campo abaixo e
> extraido de fonte real observada — sao decisoes de design a serem
> confirmadas/ajustadas quando o script for implementado em `/execute-task`.
> Distingue-se, por construcao (Constitution VI), de um contrato de API REAL
> que exigiria fonte rastreavel. O formato/severidade seguem o precedente REAL
> de `create-tasks/scripts/validate-tasks-template.sh` e
> `validate-docs-rendered/scripts/validate.sh` (esses, sim, verificados por
> leitura).

## Command: `validate-sdd.sh`

**Localizacao**: `global/skills/validate-documentation/scripts/validate-sdd.sh`
**Tipo**: CLI POSIX sh (Constitution II — sem dependencia externa obrigatoria)
**Auth**: N/A (ferramenta local, sincrona)

### Invocacao

```
validate-sdd.sh FILE [--sdd-spec | --sdd-plan] [--spec SPEC_MD]
```

| Argumento / Flag | Obrigatorio | Descricao |
|------------------|-------------|-----------|
| `FILE` (posicional) | sim | Caminho do artefato a validar (ex.: `docs/specs/x/spec.md`). |
| `--sdd-spec` | nao | Forca o spec-profile, ignorando a deteccao por path (FR-014). |
| `--sdd-plan` | nao | Forca o plan-profile, ignorando a deteccao por path (FR-014). |
| `--spec SPEC_MD` | nao | Caminho explicito da `spec.md` correspondente para o check de referencia de IDs `FR-`/`SC-` (FR-012). Default: `<dir-de-FILE-ou-pai>/spec.md` resolvido pela convencao `docs/specs/<feature>/`. |

> **Nota (CHK014 [Ambiguity], resolvido em `/execute-task`)**: a restricao de
> convencao `docs/specs/<feature>/spec.md` acima aplica-se SOMENTE ao
> **default automatico** (quando `--spec` nao e informado). A flag
> **explicita** `--spec SPEC_MD` aceita QUALQUER path, inclusive fixtures de
> teste fora dessa convencao (`tests/test_validate-sdd.sh` exercita esse
> caso). O default so tenta resolver `<dir-de-FILE>/spec.md` quando `FILE`
> segue a convencao reconhecida; fora dela e sem `--spec`, o check
> `dangling-fr-sc-ref` e silenciosamente pulado (nunca fabrica um path).

**Selecao de perfil** (precedencia):
1. Flag explicita `--sdd-spec` / `--sdd-plan` (FR-014) vence tudo.
2. Deteccao automatica por convencao de path (FR-015):
   - `*/docs/specs/<feature>/spec.md` → spec-profile;
   - `*/docs/specs/<feature>/{plan,research,data-model,quickstart}.md`
     ou `*/docs/specs/<feature>/contracts/*.md` → plan-profile.
3. Nenhuma flag + path fora de convencao reconhecida → **perfil
   indeterminado** (FR-016): exit 2 com mensagem clara, sem aplicar perfil.

`--sdd-spec` e `--sdd-plan` sao mutuamente exclusivas (passar ambas → exit 2,
uso incorreto).

### Saida (stdout) — machine-readable

Uma linha por achado, seguida de uma linha de resultado. Formato paralelo ao
`validate-tasks-template.sh` (`FINDING|severity|code|msg`):

```
FINDING|<severity>|<code>|<mensagem>
...
RESULT|<file>|profile=<spec|plan>|errors=<N>|warnings=<M>
```

- `severity ∈ {error, warning, info}` — mapeia 1:1 para a taxonomia canonica
  da skill (Erro / Aviso / Info — FR-017). NAO introduzir taxonomia
  divergente.
- `code` — slug kebab-case estavel do tipo de achado (catalogo abaixo).
- `mensagem` — texto pt-br curto, sem `|` (o pipe e o separador).
- A linha `RESULT` sempre e emitida (inclusive com 0 achados).

### Exit codes

| Exit | Significado |
|------|-------------|
| `0` | Conformante: zero achados de severidade `error` (avisos/infos podem existir e NAO bloqueiam — FR-017). |
| `1` | Reprovado: >= 1 achado `error`. |
| `2` | Uso incorreto, arquivo inexistente, flags conflitantes, OU perfil indeterminado (FR-016). |

Racional do exit-por-Erro (nao exit-por-qualquer-finding): ver `research.md`
Decision 3.

## Catalogo de finding codes

### spec-profile (US1)

| code | severity | FR | Condicao |
|------|----------|-----|----------|
| `missing-section` | error | FR-001 | Falta uma das 3 secoes obrigatorias (`User Scenarios & Testing`, `Requirements`, `Success Criteria`). |
| `impl-detail-in-spec` | error | FR-002 | Termo de stack/linguagem/framework/lib/API especifica detectado no corpo da spec. |
| `sc-not-measurable` | error | FR-003 | Success Criterion sem metrica quantificavel OU com jargao tecnico de implementacao. |
| `too-many-clarifications` | error | FR-004 | Mais de 3 marcadores `[NEEDS CLARIFICATION]` no total. |
| `na-placeholder-section` | warning | FR-005 | Secao deixada com placeholder `N/A` em vez de removida. |
| `vague-adjective` | warning | FR-006 | Adjetivo vago sem quantificacao em Requirements/Success Criteria. |
| `coupled-user-story` | warning | FR-007 | User story que depende de outra para ser testada isoladamente. |
| `duplicate-id` | error | (Gotcha da skill: "IDs duplicados sao erro") | ID `FR-`/`SC-` repetido no mesmo documento. |

### plan-profile (US2)

| code | severity | FR | Condicao |
|------|----------|-----|----------|
| `missing-section` | error | FR-008 | Falta uma das 4 secoes obrigatorias de `plan.md` (`Summary`, `Technical Context`, `Constitution Check`, `Project Structure`). |
| `template-placeholder` | error | FR-009 | Token de template nao preenchido em qualquer artefato `/plan` (ex.: `[FEATURE]`, `[Topico]`, `[Endpoint/Command/Event]`, `[DATE]`, `[short-name]`). |
| `unlabeled-contract` | error | FR-010 | Entrada em `contracts/*.md` sem rotulo inequivoco real-vs-proposto (`[PROPOSTA — a validar na implementacao]` ou marcacao equivalente de contrato real). |
| `residual-clarification` | error | FR-011 | `[NEEDS CLARIFICATION]` remanescente em `plan.md`. |
| `dangling-fr-sc-ref` | error | FR-012 | ID `FR-`/`SC-` citado em `plan.md` que NAO existe na `spec.md` correspondente (checagem semantica; ver FR-013 — NAO e resolucao de path/anchor). |

> **Fora de escopo do script (FR-013/FR-018)**: NENHUM code de resolucao de
> link/anchor no disco, sintaxe Mermaid, frontmatter YAML ou cobertura
> cross-artifact. Esses pertencem a `validate-docs-rendered` e `analyze`
> (ver `research.md` Decision 4).

## Exemplos de saida

Artefato conformante (spec-profile):

```
$ validate-sdd.sh docs/specs/enforced-guards/spec.md
RESULT|docs/specs/enforced-guards/spec.md|profile=spec|errors=0|warnings=0
# exit 0
```

Artefato reprovado (plan-profile, placeholder + ref pendente):

```
$ validate-sdd.sh docs/specs/x/plan.md
FINDING|error|template-placeholder|Token de template nao preenchido: [FEATURE]
FINDING|error|dangling-fr-sc-ref|plan.md cita FR-099, ausente na spec.md correspondente
RESULT|docs/specs/x/plan.md|profile=plan|errors=2|warnings=0
# exit 1
```

Perfil indeterminado (FR-016):

```
$ validate-sdd.sh /tmp/qualquer/spec.md
Perfil nao determinado para '/tmp/qualquer/spec.md': path fora da convencao docs/specs/<feature>/ e nenhuma flag informada. Use --sdd-spec ou --sdd-plan.
# exit 2
```
