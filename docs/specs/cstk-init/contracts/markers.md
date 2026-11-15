# Contract: marcadores de origem, pendencia e reconstituicao

[PROPOSTA — a validar na implementacao] — formato novo, verificado por
`init-provenance.sh lint` (contracts/cli-invocation.md §7). Tokens literais abaixo;
texto ao redor em pt-BR.

## 1. Origem de fato (FR-007, SC-002)

| Marcador | Uso |
|----------|-----|
| `(fonte: `<caminho>`)` | fato extraido de um artefato do projeto |
| `(fonte: `<caminho>:<linha>`)` | idem, com linha |
| `(informado pelo operador)` | resposta dada na sessao |

`<caminho>` e relativo a raiz do projeto e MUST existir (senao `DANGLING`). Caminho absoluto, segmento `..` ou symlink cujo destino resolvido saia da raiz e `BAD-MARKER` (FR-023, dec-021); a verificacao resolve o caminho com `cd -P`/`pwd -P`. Nunca aponta
para arquivo `secret-bearing` com valor copiado; citar a existencia da configuracao e
permitido (FR-019).

## 2. Pendencia (FR-006, FR-018, SC-006)

```
[PENDENTE: <pergunta que resolveria o campo>]
```

Substitui o valor do campo. Nunca acompanha valor presumido. Toda ocorrencia aparece no
resumo final (linhas `PENDING` do lint). Ciclo de vida (FR-029): na execucao seguinte o artefato com pendencia entra em modo de revisao; o operador e reconsultado so nos campos pendentes e preencher e um `amend` confirmado.

## 3. Spec reconstituida (FR-015)

Logo apos o titulo da spec:

```
<!-- cstk-init:reconstructed -->
> **Origem**: spec reconstituida a partir do projeto existente por `cstk-init` em
> AAAA-MM-DD. Nao foi escrita antes da implementacao; descreve comportamento observado.
```

Requisitos:

- User Scenarios, Success Criteria e prioridades (FR-028, dec-026 D3): cenario de aceite derivado de teste existente cita `(fonte: `<caminho-do-teste>[:<linha>]`)`; sem fonte, `[PENDENTE: <pergunta>]`. Success Criterion com meta numerica exige `(fonte: ...)` na mesma linha; sem fonte, `[PENDENTE: ...]`. Prioridade de user story sem fonte, `[PENDENTE: ...]`.
- Observado: `- **FR-NNN**: O sistema <comportamento>. (fonte: `<caminho>[:<linha>]`)` —
  formato reconhecido por `checklist/scripts/requirement-coverage.sh` (linha 139).
- Inferido: subsecao `### Inferido (nao confirmado)` com itens `- **INF-NNN**: ...`, sem
  as palavras `MUST`, `MUST NOT`, `SHOULD`.
- `## Delta Requirements`: `**Skip**: spec reconstituida de comportamento ja existente;
  nao altera comportamento documentado — cstk-init, AAAA-MM-DD`.

## 4. Emenda de constitution (FR-010)

Segue a skill `constitution` (Sync Impact Report em comentario HTML no topo, bump
SemVer, `**Last Amended**` atualizado no rodape). Entrada do Sync Impact Report cita
`cstk-init` como origem e a regra de conformidade aplicada (`CR-NNN` ou
`missing-section`).
