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
- [ ] CHK006 - A frase "o mesmo conjunto de garantias de seguranca" na Delta FR-017 esta quantificada com evidencia de equivalencia real, ou e uma generalizacao imprecisa? [Ambiguity, Spec §Delta FR-017, Gap] {auto} — **[Gap]**: o proprio gate owasp do `plan` (dec-026, achado F1) classificou essa frase como **imprecisa**: a tabela `plan.md` §"Modelo de integridade por caminho de distribuicao" (linhas 169-176) mostra que os dois caminhos usam mecanismos distintos (sha256 fail-closed vs pin de `gitCommitSha`; allowlist de host vs confianca do harness) — comparaveis em forca, mas nao identicos. O `plan` propoe reescrita (linha 191-193: "garantias equivalentes em efeito, com mecanismos e responsaveis distintos, documentados por caminho") mas **nao a aplicou** (`plan` nao edita `spec.md` por desenho). A spec segue com a redacao imprecisa ate `clarify`/edicao manual re-tocar a Delta FR-017.
- [x] CHK007 - Marcacoes `[NEEDS CLARIFICATION]` remanescentes na spec sao zero? [Ambiguity] {auto} — `grep -c "NEEDS CLARIFICATION"` retorna 0; as 5 duvidas originais foram todas resolvidas na secao Clarifications (2026-08-08), a 5a (A1) explicitamente como `[ASSUMPTION a validar empiricamente]`, nao como pendencia de clarify.
- [x] CHK008 - As assumptions de comportamento de plataforma (A1-A5) estao marcadas como tal na spec/research, nunca afirmadas como fato? [Clareza, Constitution VI, Spec §Clarifications] {auto} — spec.md linhas 34-45 rotula explicitamente `[ASSUMPTION a validar empiricamente]`; research.md linhas 281-293 lista as 5 (A1-A5) em tabela dedicada com coluna "Como validar".

## Consistencia

- [x] CHK009 - Delta FR-004 (`bash-guard-enforcement`) e FR-005 desta spec sao consistentes quanto a qual caminho vence no dedup plugin+classico? [Consistencia, Spec §FR-005, Delta FR-004] {auto} — ambos apontam "plugin vence" e "`cstk hooks install`/`cstk setup` MUST NOT registrar o snippet classico quando plugin detectado" (spec.md linhas 255-266 e 376-386, redacao identica).
- [x] CHK010 - O termo "Distribution Path" (Key Entities) e usado de forma consistente com o texto corrido dos FRs (FR-006 a FR-010)? [Consistencia, Spec §Key Entities] {auto} — spec.md linha 331 define o termo; FR-006/FR-008/FR-010 usam "caminho classico"/"caminho plugin" como sinonimos explicados na mesma entidade.
- [x] CHK011 - Requisitos nao contradizem o Principio IV (zero coleta remota) da constitution do projeto? [Constitution Alignment, Spec §FR-011] {auto} — FR-011 MUST NOT introduzir endpoint de telemetria/analytics/coleta remota; plan.md linha 53 confirma PASS explicito no gate de constitution ("Distribuicao 100% pelo proprio repo git").
- [x] CHK012 - FR-005 (dedup) e o Edge Case correspondente (linhas 190-198) descrevem o mesmo mecanismo sem divergencia de detalhe? [Consistencia, Spec §Edge Cases] {auto} — ambos citam "unica camada efetiva", "sem disparar duas vezes", "`cstk doctor` reporta duplicacao residual com remediacao".

## Mensurabilidade

- [x] CHK013 - SC-001 a SC-006 sao objetivamente verificaveis (nao dependem de julgamento subjetivo)? [Mensurabilidade, Spec §Success Criteria] {auto} — SC-003/SC-005 usam "100%"; SC-002 usa "zero passos manuais"; SC-004 usa binario alinhado/divergente via checksum (FR-008); unico ponto subjetivo residual e SC-001 ("tempo comparavel ao de habilitar qualquer outro plugin"), sem numero — ver CHK014.
- [ ] CHK014 - SC-001 ("tempo do processo comparavel ao de habilitar qualquer outro plugin") tem um limiar numerico ou e apenas comparacao qualitativa? [Mensurabilidade, Spec §SC-001, Gap] {auto} — **[Gap]**: nao ha threshold (ex: "< N minutos", "<= M comandos"). Nao bloqueia porque a comparacao e com o proprio mecanismo nativo do harness (fora do controle do toolkit medir em segundos), mas fica sem criterio de aceite objetivo proprio — mensuravel apenas por comparacao qualitativa, nao por numero.
- [x] CHK015 - SC-005 ("100% dos scripts... continuam passando na suite automatizada") e verificavel automaticamente via CI gate? [Mensurabilidade, Spec §SC-005] {auto} — `./tests/run.sh` (harness ja existente, ~1100+ cenarios) e o mecanismo objetivo citado no CLAUDE.md do projeto; nenhuma ambiguidade de "como medir".

## Cobertura de Cenarios

- [x] CHK016 - O happy path de habilitacao do plugin (US1) tem Acceptance Scenarios Given/When/Then completos? [Cobertura, Spec §US1] {auto} — 2 scenarios (linhas 70-77) cobrem habilitacao inicial + atualizacao de versao publicada.
- [x] CHK017 - Todos os 4 Edge Cases identificados (`$CLAUDE_PLUGIN_ROOT` indefinida, desabilitar plugin, marketplace fora de sync, script nao migrado) tem comportamento MUST definido, nao apenas a pergunta? [Cobertura, Spec §Edge Cases] {auto} — cada um dos 4 paragrafos (linhas 199-217) termina com frase MUST explicita de comportamento esperado.
- [x] CHK018 - O gate `requirement-coverage.sh` confirma 100% dos FRs com cenario associado? [Cobertura] {auto} — execucao desta onda: `RESULT|.../spec.md|requirements=13|covered=13|errors=0` (exit 0, zero FINDING).
- [ ] CHK019 - O cenario de A1 falsa (plugin habilitado nao ativa hooks automaticamente) tem um comportamento de fallback definido na spec, alem da nota de assumption? [Cobertura, Edge Case, Gap] {auto} — **[Gap]**: a spec (FR-004) documenta a assumption e exige task de validacao empirica, mas nao define o que MUST acontecer operacionalmente se a validacao falhar (ex: instrucao de fallback para `cstk hooks install --scope project` permanecer necessaria). plan.md (linha 152, 159-161) trata isso como decisao a ser tomada DEPOIS do spike ("se A1 for falsa, SC-002 muda e o escopo precisa ser reavaliado") — correto para uma assumption ainda nao validada, mas o gap fica registrado para o backlog nao perder o fio.

## Dependencias e Premissas (A1-A5)

- [x] CHK020 - As 5 assumptions de comportamento de plataforma (A1-A5) estao TODAS listadas com id, origem e metodo de validacao? [Premissas, research.md §Assumptions abertas] {auto} — tabela em research.md linhas 283-289 lista A1 (hooks ativos sem gate extra), A2 (timing/reload), A3 (source relativo no marketplace do proprio repo), A4 (semantica ref tag vs main), A5 (permissao +x preservada), cada uma com coluna "Como validar".
- [ ] CHK021 - Existe requisito ou artefato de planejamento que garanta que a validacao empirica de A1-A5 aconteça como GATE inicial do backlog (nao como nota de rodape ignoravel)? [Premissas, Assumption] {auto} — plan.md trata como gate explicito: linha 152 ("Spike de validacao empirica (A1-A5) com plugin minimo descartavel... Derruba as 5 assumptions **antes** do trabalho caro") na Fase 1 da "Ordem de implementacao sugerida", reforcado na linha 159-161 ("A fase 1 e um **gate**, nao uma formalidade"). **Resolvido {auto}** no nivel do `plan`; a materializacao como task #1 explicita (bloqueante das fases seguintes) fica a cargo de `create-tasks` — ver Notas.
- [x] CHK022 - A5 (permissao de execucao `+x` sobrevive ao instalador) recebeu tratamento diferenciado por ser "critica e facil de passar batido"? [Premissas, research.md] {auto} — research.md linha 291-293 marca A5 com nota propria e ja antecipa o fallback tecnico (`sh "<path>"` em vez de exec direto) caso a assumption seja falsa — unica das 5 com plano B pre-desenhado.
- [ ] CHK023 - A3 e A4 (semantica de `source` relativo e de `ref: <tag>` vs `ref: main`) tem fallback definido caso a validacao empirica revele comportamento diferente do assumido? [Premissas, Gap] {auto} — **[Gap]**: A5 tem fallback pre-desenhado (CHK022); A1/A2 tem reavaliacao de escopo prevista (CHK019/CHK021); A3 e A4 nao tem fallback nem plano B documentado em research.md/plan.md — se a validacao empirica mostrar que `source` relativo nao funciona (A3) ou que `ref: main` nao atualiza como esperado (A4), o plano nao diz o que fazer a seguir.

## Rastreabilidade

- [x] CHK024 - Cada user story (US1-US4) liga-se a pelo menos um FR nomeado? [Traceability] {auto} — US1→FR-001/FR-002/FR-003; US2→FR-004/FR-005; US3→FR-006; US4→FR-008 (ligacao textual clara em cada secao "Why this priority").
- [x] CHK025 - As Delta Requirements (FR-004/`bash-guard-enforcement`, FR-017/`guards-defense-in-depth`) referenciam corretamente a capability e o FR original que modificam? [Traceability, Spec §Delta Requirements] {auto} — cabecalhos `### Capability: bash-guard-enforcement` / `### Capability: guards-defense-in-depth` com `#### MODIFIED` e o mesmo numero de FR (FR-004, FR-017) da capability original.
- [x] CHK026 - Os Success Criteria se ligam a Acceptance Scenarios ou FRs correspondentes (nenhum SC orfao)? [Traceability, Spec §Success Criteria] {auto} — SC-001↔US1, SC-002↔US2/FR-004, SC-003↔US3/FR-006, SC-004↔US4/FR-008, SC-005↔FR-009, SC-006↔FR-010; todos rastreaveis por numero/tema.

## Notas

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]` quando a evidencia mostra ausencia real).
- Nenhum item `{humano}` foi necessario neste dominio: todas as perguntas eram verificaveis contra spec.md/plan.md/research.md sem depender de julgamento de risco/negocio do dono do produto.
- **Gaps abertos (4)**: CHK006 (Delta FR-017 impreciso — F1), CHK014 (SC-001 sem threshold numerico, aceito como limitacao inerente), CHK019 (fallback de A1-falsa nao definido), CHK021 (materializacao do spike A1-A5 como task bloqueante #1 — resolvido no plan, pendente em create-tasks), CHK023 (fallback de A3/A4 nao definido).
- **sug-002** (bug do `commit-mode.sh stage-derived` ignorando `--scope-dir`) **NAO** entra neste checklist: e um defeito do runtime do orquestrador (`agente-00c-runtime`), nao um gap de requisito desta feature — ja registrado como sugestao ao toolkit em `.claude/agente-00c-suggestions.md` (onda anterior, dec-028).

## Proximos Passos

- `/create-tasks` — CHK006 e CHK021 viram a task #0 do backlog (gate de validacao empirica A1-A5 + aplicar a reescrita sugerida da Delta FR-017); CHK019/CHK023 viram tarefas de definicao de fallback, priorizadas conforme risco (dono do produto se quiser antecipar em vez de esperar o spike).
- `/clarify` — se o dono do produto preferir resolver CHK006 (redacao da Delta FR-017) via edicao direta da spec antes do backlog, em vez de deixar para uma task.
