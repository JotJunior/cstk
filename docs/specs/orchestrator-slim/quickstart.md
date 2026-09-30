# Quickstart / Cenarios de Teste: orchestrator-slim

Todos os cenarios rodam localmente, sem rede. Suite completa: `LC_ALL=C`
(ver nota de locale do repositorio), em background com log (~12 min).

## Cenario 1 — Reducao do prompt-base (US1, SC-001) — happy path

1. `scripts/measure-orchestrator-prompts.sh --ref 9f97e994d5cde46d1447744c68c9def8da14e6e3 > /tmp/b.md`
2. `scripts/measure-orchestrator-prompts.sh --ref HEAD > /tmp/a.md`
3. Comparar a tabela prompt-base.
4. **Expected**: O <= 87608 bytes e F <= 62821 bytes (>= 40% cada); coluna
   tokens `indisponivel` com a declaracao "gate avaliado em bytes (dec-010)"
   quando `ORCH_TOKEN_COUNTER` nao esta definida.

## Cenario 2 — Ganho liquido por fase (SC-006)

1. Na saida de `--ref HEAD`, ler a tabela por fase.
2. **Expected**: para toda fase, `loaded_bytes` (prompt-base + 1 referencia)
   < `base_bytes` do baseline do mesmo orquestrador; nenhuma fase cita mais de
   uma referencia.

## Cenario 3 — Paridade deterministica (US2, SC-002, FR-016)

1. Rodar o teste de paridade (preservacao de linhas + blocos de comando +
   literais contratuais) contra `9f97e99`.
2. **Expected**: 0 linhas faltantes fora de `rewritten-lines.tsv`; diff vazio
   de blocos de comando; 100% dos padroes de `contract-literals.tsv` casam no
   baseline e no corpus novo.
3. **Error case**: remover uma linha "REGRA DURA" de uma referencia.
   **Expected**: o teste falha citando a linha ausente.

## Cenario 4 — Resolucao nos dois canais (US4, SC-004, FR-009)

1. Para cada marcador `ORCH-REF` dos dois prompts-base, rodar
   `orchestrator-refs.sh path` no subtree do repositorio.
2. Gerar o tarball (`scripts/build-release.sh`) e checar que
   `catalog/skills/agente-00c-runtime/references/orchestrators/<o>/<p>.md`
   existe para cada marcador.
3. `cp -R` do skill dir para um `$HOME` temporario e repetir o passo 1 pelo
   script copiado.
4. **Expected**: todos resolvem, exit 0.
5. **Error case**: apagar uma referencia na copia temporaria. **Expected**:
   `path` sai com exit 1, stdout vazio.

## Cenario 5 — Falha segura em runtime (US4 cenario 3, FR-010)

1. Inspecionar o stub de uma secao movida e a secao "Referencias de fase" do
   prompt-base.
2. **Expected**: instrucao literal de nao executar a fase de memoria,
   registrar Decisao + bloqueio humano e encerrar a onda quando
   `orchestrator-refs.sh path` falhar ou o Read falhar.
3. Inspecionar o stub da fase `bootstrap` (variante sem onda aberta, em
   `contracts/pointer-format.md`). **Expected**: instrucao literal de NAO
   chamar `state-ondas.sh start`, registrar Decisao (`--classe operacional`)
   + bloqueio humano e devolver o turno ao command pai sem relatorio de onda
   e sem `Schedule intent`.

## Cenario 6 — Sincronia de fragmentos e MCP-vs-Bash (FR-007)

1. Rodar o teste de sincronia de `FRAGMENT` e
   `tests/test_orchestrator-allowlist-guard.sh`.
2. **Expected**: todas as copias de cada fragmento byte-identicas; bloco
   MCP-VS-BASH byte-identico entre O e F (sem mudanca).
3. **Error case**: alterar 1 byte numa copia de `readback-loop`. **Expected**:
   teste falha nomeando o fragmento e os dois arquivos.

## Cenario 7 — Suite completa (SC-003, FR-015)

1. `LC_ALL=C sh tests/run.sh > <log> 2>&1` em background preso ao pai.
2. **Expected**: verde, incluindo `test_doc-counts.sh`,
   `tests/cstk/test_build-release.sh`, `tests/cstk/test_quickstart-e2e.sh`
   (fixtures regeneradas via `tests/cstk/fixtures/regen.sh` se o conteudo do
   skill mudou).

## Cenario 8 — Medicao observada honesta (US3, FR-012/FR-017)

1. `scripts/measure-orchestrator-prompts.sh --ref HEAD --observed`.
2. **Expected**: cada numero traz `n` e cobertura; periodo "depois" sem ondas
   => `indisponivel`; nenhuma afirmacao de reducao de tokens observada.
3. **Error case**: `--db` apontando para arquivo inexistente. **Expected**:
   secao observada `indisponivel`, exit 0.
