# Relatorio de reconciliacao

- Modo: `<single|all>` | dry-run: `<sim|nao>`
- Auditoria pos-execucao: `<clean|violation|skipped-no-git>`
- Avisos: `<lista de notices: constitution-unavailable, no-git, versao arquivada existente, ...>` (omitir se vazio)

## Resumo por feature

Uma linha por feature processada (obrigatorio em `--all`; em feature unica, uma linha).

| Feature | Local | Status | Motivo | stale | removed | undocumented | possible-regression | unverifiable |
|---------|-------|--------|--------|-------|---------|--------------|---------------------|--------------|
| `<nome>` | `<active ou archived>` | `<reconciled, no-divergence, skipped ou error>` | `<obrigatorio em skipped/error>` | `<n>` | `<n>` | `<n>` | `<n>` | `<n>` |

## Divergencias — `<feature>`

Em `--dry-run`, as acoes usam o prefixo `proposed-`.

| Tipo | Documento | Trecho (heading, linha ou FR-NNN) | Afirmacao da doc | Evidencia | Acao |
|------|-----------|-----------------------------------|------------------|-----------|------|
| `<type>` | `<doc>` | `<locator>` | `<claim curto>` | `<path>:<line>` ou `absent:<path>` (vazio so em `unverifiable`) | `<action>` |

Regras de preenchimento:

- Evidencia sempre por referencia `arquivo:linha` ou `absent:<caminho>`; nunca o
  conteudo da linha quando puder conter valor sensivel.
- `possible-regression`: pedir decisao humana; nenhum documento e alterado.
- `unverifiable`: indicar o que faltou verificar; nada e escrito.

## Documentos alterados

`<lista de docs_changed>` (vazio em `--dry-run` e em `no-divergence`).
Sem divergencia: "nenhuma divergencia encontrada" e nada gravado.
