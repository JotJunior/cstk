# Requirements Checklist: orchestrator-slim

**Purpose**: validar a qualidade dos requisitos (spec + plan + contratos) da feature de enxugamento dos prompts dos orquestradores — foco em paridade (FR-004/FR-016), falha segura (FR-010) e medicao (FR-011/FR-012). Profundidade Standard, audiencia Author (defaults da skill; execucao autonoma).
**Created**: 2026-09-29
**Feature**: [spec.md](../spec.md)

## Completude

- [x] CHK001 - Todo FR tem ao menos um cenario/criterio de aceite associado? [Completude, Spec §FR-001..FR-018] {auto} — evidencia: `requirement-coverage.sh spec.md` => `requirements=18|covered=18|errors=0`.
- [x] CHK002 - O comportamento com referencia ausente/ilegivel em runtime esta definido? [Completude, Spec §FR-010, US4-AC3] {auto} — FR-010 (nao prosseguir de memoria + bloqueio humano); regra literal do stub em `contracts/pointer-format.md` (Stub de secao).
- [x] CHK003 - O comportamento em retomada no meio de uma fase esta definido? [Cobertura, Spec §Edge Cases] {auto} — Edge Case "Retomada..." + `contracts/pointer-format.md` regra 4 (referencia da fase corrente relida em retomada).
- [x] CHK004 - O cenario de instalacao fora de sincronia (catalogo antigo x orquestrador novo) esta coberto? [Cobertura, Spec §Edge Cases] {auto} — Edge Case "Instalacao anterior..." + `plan.md` §Riscos (linha "Referencia ausente em instalacao antiga" => `path` exit 1 => bloqueio humano).
- [x] CHK005 - Esta declarado o que fica fora de escopo (referencias cruzadas ja inconsistentes antes da feature)? [Completude, research Decision 4] {auto} — `research.md` Decision 4, bloco "Fora de escopo (pre-existente...)" lista os itens e o destino (sugestao, nao correcao).
- [x] CHK006 - Todo local de uso de conteudo movido tem destino de leitura definido (nenhuma secao movida fica sem fase que a leia)? [Completude, data-model §Inventario] {auto} — coluna "Destino" preenchida para as 16 secoes movidas de O e as 12 de F. **Ressalva**: ver CHK021 (bloco Finalize terminal).
- [x] CHK007 - Fonte do numero da meta (40%) e sua precedencia sobre a paridade estao registradas? [Rastreabilidade, Spec §FR-018, Clarifications] {auto} — FR-018 cita block-001/dec-015 opcao A; FR-004/FR-017 fixam a precedencia da paridade (dec-011).

## Clareza

- [x] CHK008 - O criterio "mover para referencia" e objetivo (nao "secao pesada")? [Clareza, Spec §FR-001, dec-012] {auto} — FR-001: (a) NAO roda em 100% das ondas E (b) ganho liquido positivo (SC-006); decisao secao a secao em `data-model.md` §Inventario (coluna "100%?").
- [x] CHK009 - "Sem alteracao semantica" esta operacionalizado com procedimento verificavel? [Mensurabilidade, Spec §FR-004, FR-016] {auto} — FR-004 limita alteracoes a (i) mover, (ii) reescrever ref. interna; `research.md` Decision 8: preservacao de linhas + blocos de comando + literais contratuais, diff zero, allowlist `rewritten-lines.tsv`.
- [x] CHK010 - O termo "fase" (que inclui `bootstrap` e `toolkit-issue`, nao etapas do pipeline) esta definido? [Clareza, data-model §PhaseReference] {auto} — tabela "Fases/condicoes com arquivo" define `bootstrap` (primeira invocacao) e `toolkit-issue` (severidade impeditiva) e a condicao de leitura de cada uma.
- [x] CHK011 - "Prompt-base" e "Referencia de fase" estao definidos como entidades? [Clareza, Spec §Key Entities] {auto} — secao Key Entities.
- [x] CHK012 - Os literais/marcadores exigidos (`ORCH-REF`, `FRAGMENT`, `ORCH-REF-END`) tem formato exato especificado? [Clareza, contracts/pointer-format.md] {auto} — secao "Marcadores" e "Limite de tamanho" do contrato.
- [x] CHK013 - "Ganho liquido de tokens" esta quantificado com limiar testavel? [Mensurabilidade, Spec §SC-006, plan Performance Goals] {auto} — plan: "toda fase com `loaded_bytes` < baseline"; quickstart Cenario 2 verifica `loaded_bytes` (base+1 ref) < `base_bytes` baseline; tokens caem para bytes (dec-010).

## Consistencia

- [x] CHK014 - Os limites numericos de SC-001/FR-018 sao consistentes com o plano? [Consistencia, Spec §SC-001, plan Performance Goals] {auto} — 146014 x 0,60 = 87608 e 104702 x 0,60 = 62821 (calculo conferido nesta onda) == plan "O <= 87608 / F <= 62821"; baseline conferido por `git show 9f97e99:... | wc -c` = 146014 / 104702.
- [x] CHK015 - As somas de bytes movidos do data-model batem com a tabela de research? [Consistencia, data-model, research Decision 6] {auto} — soma recalculada nesta onda: O = 82627, F = 61519 (== research Decision 6).
- [x] CHK016 - A secao MCP-vs-Bash permanece byte-identica conforme FR-007 na estrutura proposta? [Consistencia, Spec §FR-007] {auto} — data-model §Inventario: "Orientacao MCP-vs-Bash ... manter (FR-007)" nos dois; teste `test_orchestrator-allowlist-guard.sh` sem mudanca.
- [x] CHK017 - O escopo dos testes a migrar e consistente entre research e data-model? [Consistencia, research Decision 9, data-model §Testes] {auto} — 11 testes que asserem literais + `test_doc-subcommands.sh` (DOC_DIRS) = 12 linhas na tabela de migracao; plan §Scale "12 testes migrados".
- [ ] CHK018 - FR-001 ("mais uma referencia compartilhada ... sem duplicacao") e plan Decision 2 (nenhuma referencia compartilhada; fragmentos duplicados entre arquivos de fase do MESMO orquestrador) descrevem a mesma estrutura? [Ambiguity, Spec §FR-001, dec-013, research Decision 2] {auto} — FR-001 le-se incondicional; Key Entities e condicional ("quando o conteudo e comum aos dois orquestradores"); plan mede 0 blocos byte-identicos entre O e F. A duplicacao intra-orquestrador e imposta por SC-006 (1 leitura/fase) e guardada por teste de FRAGMENT. Redacao da spec nao reflete essa decisao => reconciliar o texto do FR-001 (condicional + duplicacao por fragmento).

## Mensurabilidade dos criterios de aceite

- [x] CHK019 - Cada SC pode virar verificacao automatizada? [Mensurabilidade, Spec §SC-001..SC-006] {auto} — SC-001 (script de medicao, quickstart C1), SC-002 (teste de paridade, C3), SC-003 (suite), SC-004 (FR-009 teste, C4), SC-005 (relatorio com fonte/n, C8), SC-006 (tabela por fase, C2).
- [x] CHK020 - O requisito de medicao proibe explicitamente valor estimado/inventado? [Clareza, Spec §FR-012, FR-017, US3-AC2/AC3] {auto} — FR-012 "MUST NOT preencher com valor estimado"; contrato `measure-cli.md`: "NUNCA derivar tokens de bytes"; coluna sem dado => `indisponivel`.

## Cobertura de cenarios e edge cases

- [ ] CHK021 - Todo passo movido que executa numa fase SEM arquivo de referencia proprio tem destino de leitura? [Gap, data-model §Inventario, baseline O:2067-2085 / F:627-637] {auto} — o bloco "Finalize terminal (FR-008)" (`commit-mode.sh finalize`, invocado ao concluir `review-features` em O e `review-task` em F) vive DENTRO das secoes 9.ter (O) / 10.qui (F) que o data-model move com destino `specify, clarify, plan, checklist, create-tasks`. Em F nao existe fase `review-task` com referencia; em O, `review-features` so recebe 5.f.ter. Resultado: a onda terminal nao leria o bloco e o push+PR do modo atomic-commit poderia ser omitido/improvisado (regressao de FR-005). Acao: definir destino do bloco (manter no prompt-base, ou adicionar `review-task` a F e `review-features` ao destino do fragmento em O) — atualizar data-model/plan e a tarefa de mover.
- [ ] CHK022 - O comportamento de falha de leitura da referencia `bootstrap` (antes de a onda-001 estar aberta) esta definido de forma executavel? [Ambiguity, Spec §FR-010, contracts/pointer-format.md] {auto} — o stub manda "registre Decisao + bloqueio humano e encerre a onda", mas em `bootstrap` `state-ondas.sh start` ainda nao rodou (invariante I-2: coleta de opt-ins antes de abrir onda), logo nao ha onda aberta para `end`. Definir a sequencia exata para esse caso (ex.: registrar bloqueio sem onda + devolver ao pai, sem `Schedule intent`) para nao violar o invariante "retomada segue onda fechada".
- [x] CHK023 - Ha requisito para link interno "ver secao X" ficar valido apos a mudanca? [Cobertura, Spec §Edge Cases, research Decision 4] {auto} — Edge Case "Secao referenciada por outra secao" + stub com heading/numeracao original (Decision 4) mantendo ~29 referencias externas resolviveis sem editar consumidores.
- [x] CHK024 - A leitura truncada de uma referencia grande (fail-open) esta coberta por requisito? [Cobertura, contracts/pointer-format.md §Limite de tamanho] {auto} — limite de 2000 linhas por arquivo + marcador final `ORCH-REF-END`; ausencia do marcador = falha de leitura (FR-010); teste de FR-009 afirma o limite.
- [x] CHK025 - O caso "contagem de tokens indisponivel offline" tem comportamento definido? [Cobertura, Spec §FR-011, FR-017, dec-010] {auto} — FR-011 (gate cai para bytes e declara); `measure-cli.md` (`ORCH_TOKEN_COUNTER` ausente => `indisponivel`); fato medido em `research.md` Decision 7 (tiktoken/anthropic ausentes, sem `ANTHROPIC_API_KEY`).
- [x] CHK026 - O caso "periodo depois sem ondas observadas" tem comportamento definido? [Cobertura, Spec §US3-AC3, FR-017] {auto} — US3 AC3 + quickstart Cenario 8 (periodo sem ondas => `indisponivel`, sem afirmar reducao observada).

## Dependencias, premissas e nao-funcionais

- [x] CHK027 - A restricao de distribuicao (agente = 1 arquivo; skill = diretorio) esta documentada como premissa com fonte? [Premissa, Spec §Contexto, FR-008] {auto} — `research.md` Decision 1 cita `cli/lib/install.sh:599-600,753`, `scripts/build-release.sh:162-168`, `marketplace.json:11`.
- [x] CHK028 - O limite conhecido de alcance das referencias (mesma dependencia do runtime) esta declarado honestamente? [Premissa, research Decision 1 "Limite honesto"] {auto} — o texto declara que `CLAUDE_PLUGIN_ROOT` visivel ao Bash do subagente nao foi determinado e que as referencias sao tao alcancaveis quanto os scripts ja exigidos.
- [x] CHK029 - Requisitos de seguranca da carga de instrucao a partir de disco (traversal/symlink/injecao SQL) estao especificados? [Nao-funcional, contracts, plan §Riscos] {auto} — S1 (resolucao `strict` + confinamento sem symlink + `phase` `[a-z0-9-]+`) em `orchestrator-refs-cli.md`; S2 (limite/marcador) em `pointer-format.md`; S3 (regex de datas antes do SQL) em `measure-cli.md`; gate owasp-security ja executado (onda-004, `skills_invoked`).
- [x] CHK030 - Requisito de idioma (identificadores em ingles) e de POSIX sh e verificavel? [Nao-funcional, Spec §FR-014, plan Constitution Check II] {auto} — FR-014; plan: `#!/bin/sh` + `set -eu`, sqlite3 opcional com fallback confinado ao script de medicao (carve-out 1.1.0).

## Rastreabilidade

- [x] CHK031 - Toda user story se liga a FRs e a um teste independente? [Rastreabilidade, Spec §US1-US4] {auto} — cada US traz "Independent Test"; mapeamento US->FR->cenario no quickstart (C1/C2 US1, C3 US2, C8 US3, C4/C5 US4).
- [x] CHK032 - O baseline (FR-013) tem ponto de captura unico e versionado, anterior a qualquer edicao? [Rastreabilidade, Spec §FR-013, plan §Ordem de implementacao] {auto} — commit `9f97e99` fixado; plan §Ordem passo 1 exige `measurements/baseline.md` e inventarios ANTES de editar os prompts.

## Notes

- Items `{auto}` ja resolvidos com evidencia citada; 3 abertos: CHK018 [Ambiguity] (-> `/clarify`/ajuste de redacao do FR-001), CHK021 [Gap] e CHK022 [Ambiguity] (-> tarefas de requisito em `/create-tasks`, com correcao de data-model/plan).
- Nenhum item `{humano}` em aberto.
- Gate `requirement-coverage.sh` (spec.md): exit 0, 18/18 FRs cobertos.
