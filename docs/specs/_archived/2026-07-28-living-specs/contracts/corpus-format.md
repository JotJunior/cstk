# Contract: Living Spec Corpus (docs/specs/current/)

> **[PROPOSTA — a validar na implementacao]** — contrato NOVO; nenhum
> formato existente e afirmado aqui.

**Feature**: `living-specs` | FRs: FR-002..FR-007, FR-009

## Layout

```
docs/specs/current/
├── <capability-a>.md
├── <capability-b>.md
└── ...
```

Um arquivo por capability (research Decision 5). Diretorio nasce vazio e e
criado pelo primeiro merge (US2 cenario 4). Paralelo a
`docs/specs/_archived/` — o corpus e destino ADICIONAL, o archive existente
nao muda (FR-006).

## Estrutura de `<capability-slug>.md`

```markdown
# Capability: <capability-slug>

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.
> **Enforcement (CHK034)**: esta advertencia em prosa passa a ter
> checagem deterministica — `delta-gate.sh` e `delta-merge.sh` validam as
> invariantes estruturais abaixo como pre-checagem (code
> `corpus-malformed`, severity=error) ANTES de qualquer validacao
> referencial ou mutacao; ver `delta-gate-cli.md` §Codes/invariante 6 e
> `delta-merge-cli.md` invariante 2-ter.

## Requirements

### FR-NNN

<texto integral do requisito, comportamento atual>

*Introduzida por: <feature-short-name> (<YYYY-MM-DD>)*
*Ultima modificacao: <feature-short-name> (<YYYY-MM-DD>)*

## Removed Requirements

### FR-MMM [REMOVED]

<ultimo texto vigente antes da remocao>

*Introduzida por: <feature> (<data>)*
*Removida por: <feature> (<YYYY-MM-DD>)* — <motivo declarado no delta>

## Renamed Identifiers

| Antigo | Novo | Feature | Data |
|--------|------|---------|------|
| FR-AAA | FR-BBB | <feature> | <YYYY-MM-DD> |
```

Regras:

1. `### FR-NNN` unico por arquivo considerando `## Requirements` E
   `## Removed Requirements` E coluna "Antigo"/"Novo" de
   `## Renamed Identifiers` (id aposentado nunca e reciclado).
2. Linha `*Ultima modificacao:*` presente apenas apos o primeiro MODIFIED;
   `*Introduzida por:*` e imutavel (proveniencia de origem — SC-004).
3. Entradas ordenadas por id crescente dentro de cada secao (determinismo:
   dois merges com os mesmos inputs produzem bytes identicos).
4. Secoes `## Removed Requirements` / `## Renamed Identifiers` so existem
   quando nao-vazias.

## Semantica de aplicacao (delta -> corpus)

| Tipo | Pre-condicao (senao: bloqueio) | Efeito |
|------|-------------------------------|--------|
| ADDED | id NAO existe no arquivo (nenhuma secao) | nova entrada em `## Requirements` com `Introduzida por` |
| MODIFIED | id ativo em `## Requirements` | texto substituido, id preservado, `Ultima modificacao` atualizada |
| REMOVED | id ativo em `## Requirements` | entrada movida para `## Removed Requirements` com `Removida por` + motivo |
| RENAMED | old ativo; new inexistente em qualquer secao | heading vira new id; linha na tabela de renames |

Violacao de qualquer pre-condicao => FINDING|error + exit 1 SEM nenhuma
mutacao (merge atomico via mktemp + mv — clarify: bloqueio com diagnostico,
nunca merge silencioso/last-write-wins).
