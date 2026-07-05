# Performance Checklist: Recall Memory Mirror

**Purpose**: Validar qualidade dos requisitos de performance — varredura de `.md` no ingest/reindex,
FTS5 busca unificada, upsert idempotente SQLite, tamanho de body sem ceiling, e garantias de
degradacao graciosa.
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | Plan: [plan.md](../plan.md) | Research: [research.md](../research.md)

## Targets e Escalabilidade

- [x] CHK021 - A ausencia de SLA de performance e documentada como intencional (escopo dev local)? [Assumption, plan.md §Technical Context] {auto}
  > Evidencia: Plan Technical Context: "Scale/Scope: dezenas de projetos x dezenas de memorias = trivial para SQLite FTS5". Spec: "Performance Goals: N/A". Adequado para ferramenta dev local single-user sem SLA.

- [x] CHK024 - A latencia de busca FTS5 unificada (com memorias) tem target documentado? [Clareza, plan.md §Technical Context] {auto}
  > Evidencia: Plan: "busca FTS5 sub-ms". Para ferramenta dev local sem concorrencia, sub-ms e suficiente como target.

- [ ] CHK025 - A ausencia de SLA de duracao do `--reindex` completo (telemetria + memorias) e aceitavel para o cenario de uso? [Assumption] {humano}
  > Contexto: Plan diz "trivial" mas nao quantifica. Para dezenas de projetos x dezenas de memorias (potencialmente centenas de arquivos `.md`) o reindex pode levar alguns segundos. Nenhum gate de CI depende do tempo de reindex atualmente — confirmar se e aceitavel.

## Garantias de Corretude no I/O

- [x] CHK022 - O requisito de replicar o padrao `find || :` (protecao contra exit!=0 com matches) no reindex de memorias esta documentado como MUST? [Completude, plan.md §Riscos, Contrato Cmd 4] {auto}
  > Evidencia: Plan riscos: "replicar o padrao `|| :` — recall.sh L1698-1707; coberto por M11". Contrato Cmd 4: "O gotcha do `find` DEVE ser replicado." Requisito DEVE explicito com cenario de teste M11.

- [x] CHK027 - O `--list-memories` usa SELECT direto em vez de busca FTS (sem overhead de ranking bm25)? [Clareza, research.md Decision 9] {auto}
  > Evidencia: Research Decision 9: "SELECT direto da tabela relacional `memories` ordenado por slug. Modo proprio mantem `recall_mode_search` simples." Contrato Cmd 5 confirma.

## Idempotencia e Overhead de Reingestao

- [x] CHK023 - O custo de reingestao repetida (upsert `INSERT OR REPLACE` em SQLite) e proporcional ao volume documentado? [Assumption, Spec §SC-003] {auto}
  > Evidencia: Spec SC-003: "N execucoes produzem sempre o mesmo numero de entradas". `INSERT OR REPLACE` em SQLite para dezenas de entradas tem custo desprezivel. Sem SLA de duracao de ingestao — aceitavel para o escopo.

## Tamanho de Payload

- [ ] CHK026 - O `body_scrubbed` sem tamanho maximo definido pode causar linha FTS gigante? Deve haver ceiling ou e aceito sem limite? [Gap, data-model.md] {humano}
  > Contexto: Nenhum campo de `memories` tem MAX length definido. MEMORY.md reais sao tipicamente pequenos (<100KB), mas a spec nao documenta ceiling. FTS5 do SQLite nao tem limite pratico para esse escopo, mas a ausencia de limite e uma decisao que cabe ao dono do produto confirmar como intencional.

## Degradacao Graciosa (Requisitos)

- [x] CHK028 - Os requisitos de degradacao graciosa (sqlite3/jq/secrets-filter ausentes) estao documentados para TODOS os novos modos? [Completude, Spec §FR-008, SC-004] {auto}
  > Evidencia: Spec FR-008: "Ausencia de sqlite3 ou jq MUST resultar em degradacao graciosa: aviso stderr, exit 0". SC-004: "Ausencia de `sqlite3` nunca produz exit!=0 em nenhum caminho". Contrato Cmd 3 tabela de degradacao cobre: sqlite3/jq/secrets-filter ausentes; `~/.claude/projects/` inexistente; `memory/` dir inexistente; `.md` vazio.

- [x] CHK029 - A degradacao graciosa do `--reindex` para projeto sem `memory/` dir esta documentada? [Cobertura, Spec §US3 cenario 3, Contrato Cmd 4] {auto}
  > Evidencia: Spec US3 cenario 3: "projeto sem diretorio `memory/` → reindex termina normalmente sem erro". Contrato Cmd 4 invariantes: "projeto sem `memory/` dir | reindex termina normal, 0 memorias p/ esse projeto".

## Notes

- Items `{auto}` resolvidos com evidencia citada; `{humano}` aguardando decisao do dono do produto
- **7 de 9 items passaram automaticamente**
- **CHK026** `{humano}` [Gap]: ausencia de ceiling em `body_scrubbed` — confirmar se e aceitavel sem limite explicito ou se deve ser documentado no contract
- **CHK025** `{humano}` [Assumption]: SLA de duracao do `--reindex` — confirmar que "trivial" e suficiente como especificacao
- Gaps nao sao bloqueantes para implementacao (escopo dev local sem SLA); mas devem ser decididos antes de `/execute-task`
