# Quickstart: Show Tips

**Feature**: `show-tips` | **Date**: 2026-05-27 | **Phase**: 1 (Design)

Cenarios de validacao do mecanismo de dicas. Cada cenario e verificavel via
`tests/cstk/test_show-tip.sh` (POSIX, despachado por `tests/run.sh`).

---

## Cenario 1: Exibir dica de uma skill especifica (happy path — US3)

**Pre-condicao**: `tips/catalog.md` contem >= 1 entrada com `skill: review-task`.

1. Rodar `cstk show-tip review-task`
2. **Expected**: stdout contem um bloco destacado com bordas visuais (FR-004),
   o nome `review-task`, a categoria (`uso`/`gotcha`/`avancado`), o texto da
   dica e ao menos 1 exemplo. Exit 0.

---

## Cenario 2: Variacao entre execucoes (US1 cenario 2 / FR-003)

**Pre-condicao**: `tips/catalog.md` contem >= 3 entradas para `review-task`.

1. Rodar `cstk show-tip review-task` varias vezes (ex: 10x).
2. **Expected**: as dicas exibidas variam (nao e sempre a mesma). Pelo menos 2
   dicas distintas aparecem nas 10 invocacoes. Mecanismo POSIX (`/dev/urandom` +
   `awk`), NUNCA `$RANDOM`. Exit 0 em todas.

> Verificacao adicional (test): `grep -n 'RANDOM' cli/lib/show-tip.sh` retorna
> vazio (gate de bash-ism), e `shellcheck -s sh cli/lib/show-tip.sh` nao emite
> SC3028.

---

## Cenario 3: Dica aleatoria sem especificar skill (US3 cenario 3 / FR-010)

1. Rodar `cstk show-tip` (sem argumentos).
2. **Expected**: uma dica de QUALQUER skill do catalogo e exibida em bloco
   destacado. Exit 0.

---

## Cenario 4: Catalogo vazio ou inacessivel (error case — FR-006 / SC-003)

**Pre-condicao**: catalogo ausente — rodar `cstk show-tip --phase plan
--catalog /tmp/nao-existe.md`.

1. Rodar o comando.
2. **Expected**: stdout VAZIO, exit 0 (fail-silent). NENHUM erro fatal, nenhuma
   interrupcao. Diagnostico (se houver) so em stderr, nunca em stdout.

---

## Cenario 5: Skill sem dicas, modo explicito (error case — US3 cenario 2)

**Pre-condicao**: `tips/catalog.md` NAO contem entradas para `skill: inexistente`.

1. Rodar `cstk show-tip inexistente`
2. **Expected**: stdout com mensagem amigavel ("Sem dicas cadastradas para
   `inexistente`.") + sugestao de skills disponiveis. Exit 0. (Modo explicito
   informa; modo automatico `--phase` apenas silencia.)

---

## Cenario 6: Auditoria de cobertura completa (SC-004 — happy path)

**Pre-condicao**: catalogo com >= 2 dicas (categorias `uso`+`gotcha`) para TODAS
as 38 skills (`global/skills/*` + `language-related/*/skills/*`).

1. Rodar `cstk show-tip --audit`
2. **Expected**: stdout relatorio "cobertura completa"; exit 0.

---

## Cenario 7: Auditoria com gaps (SC-004 — error case)

**Pre-condicao**: catalogo com uma skill faltando dicas.

1. Rodar `cstk show-tip --audit`
2. **Expected**: stdout lista os gaps (skill → contagem atual, categorias
   faltantes); exit 1.

---

## Cenario 8: Integracao com orquestrador (US4)

1. Simular invocacao do orquestrador: `TIP=$(cstk show-tip --phase plan); echo "[$TIP]"`
2. **Expected**: `$TIP` contem bloco pronto para exibicao (ou vazio se sem
   mapeamento + catalogo vazio). O orquestrador nao parseia o catalogo. Exit 0.

---

## Cenario 9: Adicionar nova dica em < 5 min (SC-005)

1. Editar `tips/catalog.md`, adicionar um bloco `---`/frontmatter/corpo para uma
   skill existente, sem tocar `cli/lib/show-tip.sh`.
2. Rodar `cstk show-tip <skill>`
3. **Expected**: a nova dica passa a ser candidata a exibicao. Nenhuma mudanca
   de codigo necessaria (FR-008 extensibilidade).

---

## Performance (SC-002)

Cada invocacao do `cstk show-tip` retorna em < 1s em ambiente POSIX, sem rede.
Verificavel: `time cstk show-tip review-task` < 1s.
