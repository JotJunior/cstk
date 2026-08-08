# Requirements Checklist: Empacotamento do cstk como Plugin do Claude Code

**Purpose**: Gate formal de qualidade de requisitos apos `plan` (pre `create-tasks`) — valida completude, clareza, consistencia, mensurabilidade, cobertura de cenarios e rastreabilidade de `spec.md`, com atencao aos gaps levantados pelo proprio `plan` (gate owasp F1 e assumptions A1-A5 de `research.md`).
**Created**: 2026-08-08
**Feature**: [spec.md](../spec.md)

## Completude

- [x] CHK001 - Todos os 13 FRs cobrem os tres eixos do problema (disponibilizacao do catalogo, dedup de hooks, convivencia sem drift entre caminhos)? [Completude, Spec §FR-001-FR-013] {auto}
- [x] CHK002 - Requisitos nao-funcionais de seguranca (integridade, origem confiavel, transporte, consentimento, zero coleta remota) estao cobertos? [Completude, Spec §FR-011, Delta FR-017] {auto}
- [x] CHK003 - Declaracoes explicitas de fora-de-escopo (nao-migracao forcada, binario nao substituido pelo plugin) estao documentadas? [Completude, Spec §FR-006, FR-010] {auto}
- [x] CHK004 - Placeholders (`TODO`, `TKTK`, `???`) foram todos resolvidos? [Completude] {auto} — `grep -c "TODO\|TKTK\|???"` sobre spec.md retorna 0.

## Clareza

- [x] CHK005 - Cada FR usa verbo imperativo testavel (MUST/MUST NOT)? [Clareza] {auto} — FR-001 a FR-013 usam MUST/MUST NOT de forma consistente (nenhum "should"/"pode" solto).
- [x] CHK006 - A frase "o mesmo conjunto de garantias de seguranca" na Delta FR-017 esta quantificada com evidencia de equivalencia real, ou e uma generalizacao imprecisa? [Ambiguity, Spec §Delta FR-017, Gap] {auto} — **Resolvido (dec-040, onda execute-task)**: `spec.md` Delta FR-017 reescrita trocando a frase por "garantias equivalentes em efeito, com mecanismos e responsaveis distintos, documentados por caminho" + tabela "Modelo de integridade por caminho de distribuicao" (verificacao/origem/transporte/consentimento/quem aplica) inserida na propria spec (nao mais so no plan).
- [x] CHK007 - Marcacoes `[NEEDS CLARIFICATION]` remanescentes na spec sao zero? [Ambiguity] {auto} — `grep -c "NEEDS CLARIFICATION"` retorna 0; as 5 duvidas originais foram todas resolvidas na secao Clarifications (2026-08-08), a 5a (A1) explicitamente como `[ASSUMPTION a validar empiricamente]`, nao como pendencia de clarify.
- [x] CHK008 - As assumptions de comportamento de plataforma (A1-A5) estao marcadas como tal na spec/research, nunca afirmadas como fato? [Clareza, Constitution VI, Spec §Clarifications] {auto} — spec.md linhas 34-45 rotula explicitamente `[ASSUMPTION a validar empiricamente]`; research.md linhas 281-293 lista as 5 (A1-A5) em tabela dedicada com coluna "Como validar".

## Consistencia

- [x] CHK009 - Delta FR-004 (`bash-guard-enforcement`) e FR-005 desta spec sao consistentes quanto a qual caminho vence no dedup plugin+classico? [Consistencia, Spec §FR-005, Delta FR-004] {auto} — ambos apontam "plugin vence" e "`cstk hooks install`/`cstk setup` MUST NOT registrar o snippet classico quando plugin detectado" (spec.md linhas 255-266 e 376-386, redacao identica).
- [x] CHK010 - O termo "Distribution Path" (Key Entities) e usado de forma consistente com o texto corrido dos FRs (FR-006 a FR-010)? [Consistencia, Spec §Key Entities] {auto} — spec.md linha 331 define o termo; FR-006/FR-008/FR-010 usam "caminho classico"/"caminho plugin" como sinonimos explicados na mesma entidade.
- [x] CHK011 - Requisitos nao contradizem o Principio IV (zero coleta remota) da constitution do projeto? [Constitution Alignment, Spec §FR-011] {auto} — FR-011 MUST NOT introduzir endpoint de telemetria/analytics/coleta remota; plan.md linha 53 confirma PASS explicito no gate de constitution ("Distribuicao 100% pelo proprio repo git").
- [x] CHK012 - FR-005 (dedup) e o Edge Case correspondente (linhas 190-198) descrevem o mesmo mecanismo sem divergencia de detalhe? [Consistencia, Spec §Edge Cases] {auto} — ambos citam "unica camada efetiva", "sem disparar duas vezes", "`cstk doctor` reporta duplicacao residual com remediacao".

## Mensurabilidade

- [x] CHK013 - SC-001 a SC-006 sao objetivamente verificaveis (nao dependem de julgamento subjetivo)? [Mensurabilidade, Spec §Success Criteria] {auto} — SC-003/SC-005 usam "100%"; SC-002 usa "zero passos manuais"; SC-004 usa binario alinhado/divergente via checksum (FR-008); unico ponto subjetivo residual e SC-001 ("tempo comparavel ao de habilitar qualquer outro plugin"), sem numero — ver CHK014.
- [x] CHK014 - SC-001 ("tempo do processo comparavel ao de habilitar qualquer outro plugin") tem um limiar numerico ou e apenas comparacao qualitativa? [Mensurabilidade, Spec §SC-001, Gap] {auto} — **Resolvido (dec-041, onda execute-task)**: `spec.md` SC-001 ganhou criterio objetivo ("no maximo 2 comandos do operador: `/plugin marketplace add` + `/plugin install`"), fundamentado em evidencia empirica real da FASE 1 (tasks 1.1.2/1.1.3, dec-037) — nao inventado. Segue sem medida de tempo em segundos por ser responsabilidade do harness, fora do controle do toolkit; a contagem de comandos e o criterio proprio agora presente.
- [x] CHK015 - SC-005 ("100% dos scripts... continuam passando na suite automatizada") e verificavel automaticamente via CI gate? [Mensurabilidade, Spec §SC-005] {auto} — `./tests/run.sh` (harness ja existente, ~1100+ cenarios) e o mecanismo objetivo citado no CLAUDE.md do projeto; nenhuma ambiguidade de "como medir".

## Cobertura de Cenarios

- [x] CHK016 - O happy path de habilitacao do plugin (US1) tem Acceptance Scenarios Given/When/Then completos? [Cobertura, Spec §US1] {auto} — 2 scenarios (linhas 70-77) cobrem habilitacao inicial + atualizacao de versao publicada.
- [x] CHK017 - Todos os 4 Edge Cases identificados (`$CLAUDE_PLUGIN_ROOT` indefinida, desabilitar plugin, marketplace fora de sync, script nao migrado) tem comportamento MUST definido, nao apenas a pergunta? [Cobertura, Spec §Edge Cases] {auto} — cada um dos 4 paragrafos (linhas 199-217) termina com frase MUST explicita de comportamento esperado.
- [x] CHK018 - O gate `requirement-coverage.sh` confirma 100% dos FRs com cenario associado? [Cobertura] {auto} — execucao desta onda: `RESULT|.../spec.md|requirements=13|covered=13|errors=0` (exit 0, zero FINDING).
- [x] CHK019 - O cenario de A1 falsa (plugin habilitado nao ativa hooks automaticamente) tem um comportamento de fallback definido na spec, alem da nota de assumption? [Cobertura, Edge Case, Gap] {auto} — **Resolvido (veredito real da FASE 1, dec-037)**: A1 foi **CONFIRMADA** empiricamente (spec.md §Clarifications, linhas 41-49) — o hipotetico "A1 falsa" nao se materializou, tornando o fallback discutido na task 1.5.2 (`cstk hooks install --scope project` permanece necessario) desnecessario na pratica. Gap fechado por resultado empirico, nao por documentacao adicional de um cenario que nao ocorreu.

## Dependencias e Premissas (A1-A5)

- [x] CHK020 - As 5 assumptions de comportamento de plataforma (A1-A5) estao TODAS listadas com id, origem e metodo de validacao? [Premissas, research.md §Assumptions abertas] {auto} — tabela em research.md linhas 283-289 lista A1 (hooks ativos sem gate extra), A2 (timing/reload), A3 (source relativo no marketplace do proprio repo), A4 (semantica ref tag vs main), A5 (permissao +x preservada), cada uma com coluna "Como validar".
- [x] CHK021 - Existe requisito ou artefato de planejamento que garanta que a validacao empirica de A1-A5 aconteça como GATE inicial do backlog (nao como nota de rodape ignoravel)? [Premissas, Assumption] {auto} — **Resolvido**: `tasks.md` FASE 1 materializou o gate como task bloqueante explicita (1.1-1.5, todas `[x]`), com regra dura no cabecalho da fase ("MUST concluir e produzir veredito ANTES de qualquer trabalho da FASE 4 em diante"). Nao ficou nota de rodape — virou backlog executado e concluido.
- [x] CHK022 - A5 (permissao de execucao `+x` sobrevive ao instalador) recebeu tratamento diferenciado por ser "critica e facil de passar batido"? [Premissas, research.md] {auto} — research.md linha 291-293 marca A5 com nota propria e ja antecipa o fallback tecnico (`sh "<path>"` em vez de exec direto) caso a assumption seja falsa — unica das 5 com plano B pre-desenhado.
- [x] CHK023 - A3 e A4 (semantica de `source` relativo e de `ref: <tag>` vs `ref: main`) tem fallback definido caso a validacao empirica revele comportamento diferente do assumido? [Premissas, Gap] {auto} — **Resolvido (veredito real da FASE 1, dec-037)**: A3 **CONFIRMADA** (source relativo resolve; sem fallback necessario). A4: a pergunta original presumia schema `git-subdir` que o cstk nao usa; o mecanismo real (`source` relativo) ganhou fallback explicito documentado em `spec.md` §Clarifications (linhas 68-76): "nunca assumir propagacao automatica de release — o fluxo de release do toolkit (tag + CHANGELOG) continua sendo o unico gatilho... o operador MUST rodar update explicito (`claude plugin marketplace update` + `claude plugin update --scope <escopo>`) + reiniciar a sessao".

## Rastreabilidade

- [x] CHK024 - Cada user story (US1-US4) liga-se a pelo menos um FR nomeado? [Traceability] {auto} — US1→FR-001/FR-002/FR-003; US2→FR-004/FR-005; US3→FR-006; US4→FR-008 (ligacao textual clara em cada secao "Why this priority").
- [x] CHK025 - As Delta Requirements (FR-004/`bash-guard-enforcement`, FR-017/`guards-defense-in-depth`) referenciam corretamente a capability e o FR original que modificam? [Traceability, Spec §Delta Requirements] {auto} — cabecalhos `### Capability: bash-guard-enforcement` / `### Capability: guards-defense-in-depth` com `#### MODIFIED` e o mesmo numero de FR (FR-004, FR-017) da capability original.
- [x] CHK026 - Os Success Criteria se ligam a Acceptance Scenarios ou FRs correspondentes (nenhum SC orfao)? [Traceability, Spec §Success Criteria] {auto} — SC-001↔US1, SC-002↔US2/FR-004, SC-003↔US3/FR-006, SC-004↔US4/FR-008, SC-005↔FR-009, SC-006↔FR-010; todos rastreaveis por numero/tema.

## Notas

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]` quando a evidencia mostra ausencia real).
- Nenhum item `{humano}` foi necessario neste dominio: todas as perguntas eram verificaveis contra spec.md/plan.md/research.md sem depender de julgamento de risco/negocio do dono do produto.
- **Gaps abertos (0)**: todos os 5 gaps originais (CHK006, CHK014, CHK019, CHK021, CHK023) foram fechados — CHK006/CHK014 por edicao de `spec.md` (dec-040/dec-041, onda execute-task, task 2.1/2.2 de `tasks.md`); CHK019/CHK021/CHK023 pelo veredito empirico real da FASE 1 (dec-037) ja incorporado em `spec.md` §Clarifications.
- **sug-002** (bug do `commit-mode.sh stage-derived` ignorando `--scope-dir`) **NAO** entra neste checklist: e um defeito do runtime do orquestrador (`agente-00c-runtime`), nao um gap de requisito desta feature — ja registrado como sugestao ao toolkit em `.claude/agente-00c-suggestions.md` (onda anterior, dec-028).

## Proximos Passos

- Checklist fechado — nenhum gap pendente. Seguir para as demais tarefas de `tasks.md` (FASE 3 em diante).
