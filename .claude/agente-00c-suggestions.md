# Sugestoes do Agente-00C — feat-dashboard-refactor-20260728T120056Z

Total: 1 sugestoes registradas.

## sug-001 — skill `commit-mode.sh` — severidade: informativa

**Criada em**: 2026-07-28T15:10:37Z

**Issue aberta**: (nenhuma)

**Diagnostico**:

task-message so compara major.minor (cut -d'.' -f2) ao decidir contiguidade de runs; com task-ids de 3 niveis (N.M.K, convencao real deste tasks.md/execute-task), IDs de subsecoes DIFERENTES (ex: 4.1.3 e 4.2.1) tem o mesmo 'major' (4) e minors incrementais (1,2), sendo erroneamente fundidos num range '4.1.3-4.2.1' que mistura duas sub-fases distintas.

**Proposta**:

task-message deveria comparar o ID completo (todos os niveis) para decidir contiguidade, nao so major.minor; ou documentar explicitamente que --task-ids so deve receber IDs N.M (2 niveis), nunca N.M.K, evitando o uso ambiguo observado nesta execucao (feature dashboard-refactor, onda-012).

**Referencias**:

- ~/.claude/skills/agente-00c-runtime/scripts/commit-mode.sh

---

