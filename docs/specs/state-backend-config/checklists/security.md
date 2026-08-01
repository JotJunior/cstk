# Security Checklist: Configuração de Backend do state.db (Cutover Fase 2)

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca das clausulas
vinculantes P1-P8 do contrato `contracts/state-backend-runtime.md`
(parsing seguro da config, allowlist de valor, checagem de capability,
permissoes e escrita atomica) — nao a implementacao (o script
`state-backend.sh` ainda nao existe; contrato em status PROPOSTA). "Unit
tests for English."
**Created**: 2026-08-01
**Feature**: [spec.md](../spec.md)

> Legenda: `{auto}` = resolvivel contra spec/plan/contracts (resolvido com
> citacao). `{humano}` = julgamento de risco/negocio (aberto). Marcadores de
> gap: `[Gap]` requisito ausente, `[Ambiguity]` interpretacao multipla,
> `[Conflict]` contradicao entre artefatos.
>
> Contexto: o gate `owasp-security` ja rodou sobre o design do `plan.md`
> (dec-021, onda-003) e identificou os 6 riscos SEC-01..SEC-06; as
> mitigacoes foram escritas como as 8 clausulas vinculantes P1-P8 do
> contrato na MESMA onda, antes de qualquer codigo (dec-021, escolha
> "corrigir-agora"). Este checklist audita a QUALIDADE dessas clausulas
> como requisito — nao repete a revisao de superficie de ataque em si.

## Parsing seguro do arquivo de config (P1, P2, P5 — SEC-01)

- [x] CHK001 - A proibicao de `.`/`source`/`eval` sobre o arquivo de config esta especificada de forma inequivoca e consistente entre o contrato e o plano? [Clareza/Consistencia, contracts/state-backend-runtime.md P1 / plan.md §SEC-01 L194,201-216] {auto} — SIM: contrato P1 ("MUST NOT usar `.`/`source`/`eval`... um arquivo `key=value` e shell sintaticamente valido; sourcea-lo executaria `state_backend=$(comando)`") e plan.md SEC-01 + secao dedicada L201-216 dizem a mesma coisa com o mesmo exemplo de exploit, e citam verificacao empirica (`grep` por `. "$…CONFIG"` em `cli/lib/` e nos 42 scripts do runtime: nenhum resultado hoje).
- [x] CHK002 - Existe um cenario de teste (quickstart) que valida OBJETIVAMENTE que um valor malicioso na config (ex.: `state_backend=$(touch /tmp/pwned)`) nunca e executado, so tratado como valor-fora-da-allowlist? [Mensurabilidade/Cobertura, quickstart.md] {auto} — RESOLVIDO (task 2.2.3, `/analyze` de fechamento FASE 7): `quickstart.md` Scenario 2.5 "Payload de injeção na config nunca é executado — CHK002" cobre exatamente esse caso, implementado em `tests/test_state-backend.sh::scenario_payload_de_injecao_nunca_e_executado` (verifica canary NAO criado + `reason=config-invalida`).
- [x] CHK003 - A regra de parsing "primeiro `=`, `#`/linha em branco ignorados, linha sem `=` invalida a config" esta especificada com precisao suficiente para implementacao sem ambiguidade? [Clareza, contracts/state-backend-runtime.md P2] {auto} — SIM: P2 e explicito nos 4 sub-casos (split no primeiro `=`; comentario; branco; sem `=` ⇒ invalida) e FR-002 reforca o formato `key=value` sem parser YAML/JSON.
- [x] CHK004 - O requisito "toda expansao de variavel MUST ser citada" (P5) tem um criterio de verificacao objetivo e automatizavel (ex.: gate de lint/shellcheck sobre `state-backend.sh`), ou depende só de revisao manual de codigo? [Mensurabilidade, contracts/state-backend-runtime.md P5] {auto} — RESOLVIDO (task 2.1.4): confirmado que `.shellcheckrc`/`shellcheck.yml` (glob `**/*.sh`) cobre `state-backend.sh`; `shellcheck -x` rodado sobre o script e sobre os testes desta feature (`tests/test_state-backend.sh`, `tests/test_config-roundtrip.sh`) com 0 achados. Continua advisory (nao-gateante em CI, `tests/README.md`), mas deixou de depender SO de revisao manual.

## Validacao de valor e chaves desconhecidas (P3, P4 — SEC-02)

- [x] CHK005 - O requisito de validar o valor contra a allowlist `sqlite`\|`json` ANTES de qualquer uso, com fallback `config-invalida` ⇒ `json`, e consistente entre o contrato (P3), o plano (SEC-02) e a spec (FR-008, Edge Cases)? [Consistencia, contracts/state-backend-runtime.md P3 / plan.md §SEC-02 / spec.md FR-008 + Edge Cases L176-180] {auto} — SIM: as 3 fontes convergem no mesmo comportamento (fora do dominio ⇒ tratado como config invalida ⇒ fallback ao backend legado, nunca repassado adiante), e o contrato reforca "Contrato de nao-falha" (`resolve` nunca falha por config invalida, sempre exit 0).
- [x] CHK006 - Existe um cenario de teste distinto para "valor SINTATICAMENTE valido (tem `=`) mas FORA da allowlist" (ex.: `state_backend=mysql`), separado do cenario de "linha sem `=`"? [Cobertura, quickstart.md Scenario 7] {auto} — RESOLVIDO (task 2.2.4): `quickstart.md` Scenario 2.6 "Valor sintaticamente válido porém fora da allowlist — CHK006", implementado em `tests/test_state-backend.sh::scenario_valor_fora_da_allowlist_vira_config_invalida`.
- [x] CHK007 - O comportamento "chave desconhecida e ignorada, nao e erro" (P4) tem algum cenario ou criterio de aceite que o exercite, ou fica so implicitamente coberto pelo requisito de extensibilidade (P4/FR-002)? [Cobertura, contracts/state-backend-runtime.md P4] {auto} — RESOLVIDO (task 2.2.5): `quickstart.md` Scenario 2.7 "Chave desconhecida é ignorada — CHK007", implementado em `tests/test_state-backend.sh::scenario_chave_desconhecida_e_ignorada`.

## Checagem de capability e prioridade do catalogo instalado (P8 — SEC-03)

- [x] CHK008 - A prioridade do catalogo instalado (`~/.claude/skills/...`) sobre a arvore do repo na checagem de capability, quando ambos coexistem, esta especificada como divergencia DELIBERADA (nao um bug) em relacao ao resolvedor de 3 camadas ja existente (`_state_migrate_script_path`)? [Clareza, contracts/state-backend-runtime.md P8 + nota L147-150 / plan.md §SEC-03 L218-231] {auto} — SIM: contrato e plano documentam explicitamente a inversao de ordem e o motivo (a config e por-usuario e serve as execucoes 00c reais, que consomem o catalogo instalado; a ordem PATH→repo→instalado serve a testes/CI, nao a esta decisao) — reduz o risco de a divergencia ser "corrigida" por engano numa revisao futura.
- [x] CHK009 - Existe um cenario de teste que force a COEXISTENCIA de repo + catalogo instalado com capabilities DIFERENTES entre os dois (ex.: catalogo instalado antigo, repo com o script novo) e confirme que o catalogo instalado prevalece? [Cobertura, quickstart.md] {auto} — RESOLVIDO (task 3.1.4): `quickstart.md` Scenario 4.5 "Coexistência repo + catálogo instalado com capabilities divergentes — CHK009", implementado em `tests/test_state-backend.sh::scenario_enable_sqlite_recusa_coexistencia_divergente_catalogo_prevalece` — unico risco Media (SEC-03) do checklist, agora com contrapartida de teste.
- [x] CHK010 - O requisito de P8 "MUST reportar qual caminho foi validado" esta refletido no conteudo obrigatorio das mensagens de diagnostico especificadas em `FR-004A` e na tabela "Diagnosticos de recusa" de `contracts/cli-surface.md`? [Consistencia, contracts/state-backend-runtime.md P8 / plan.md §SEC-03 L227 "enable-sqlite MUST reportar qual caminho foi validado" / spec.md FR-004A L233-241 / contracts/cli-surface.md L53-62] {auto} — RESOLVIDO (task 1.1, dec-034): `contracts/cli-surface.md` §Comportamento + §Diagnosticos de recusa agora exigem a linha literal `cstk state enable-sqlite: capability verificado via <origem> (<path>)` no sucesso e na recusa "Runtime incapaz"; `contracts/state-backend-runtime.md` ganhou nota "Decisao de conteudo da mensagem (CHK010, task 1.1 — resolvida, dec-034)" logo apos a nota de P8, amarrando a decisao ao texto vinculante. Escopo explicitamente restrito aos 2 casos ligados a checagem de capability (nao se aplica as recusas por `sqlite3` ausente/versao insuficiente).

## Permissoes e escrita atomica (P6, P7 — SEC-05, SEC-06)

- [x] CHK011 - O requisito de permissoes (diretorio `700`, arquivo de config `600`) esta ancorado num precedente ja existente e testado no toolkit (nao e um padrao novo inventado para esta feature)? [Traceability, contracts/state-backend-runtime.md P6 / plan.md §SEC-05] {auto} — SIM: P6 cita explicitamente `_state_db_secure_perms` (`_state-db.sh:147-152`) como o precedente que ja aplica `600` ao `state.db` — a clausula reusa um padrao validado, nao introduz um novo.
- [x] CHK012 - O requisito de escrita atomica (`mktemp` no MESMO diretorio + `mv`) esta justificado com a razao tecnica especifica (por que "mesmo diretorio" importa, por que `mv` neutraliza troca de symlink) e nao apenas citado como boa pratica generica? [Clareza, contracts/state-backend-runtime.md P7 / plan.md §SEC-06 L199] {auto} — SIM: plan.md SEC-06 explicita que `mv` "substitui o alvo sem seguir symlink, o que tambem neutraliza troca de link" (TOCTOU/CWE-367 e CWE-59), e P7 referencia `research.md Decision 7` para a decisao de design completa.
- [x] CHK013 - Existe algum cenario de teste (quickstart ou spec) que verifique as permissoes resultantes (`700`/`600`) apos `enable-sqlite`, ou a ausencia de arquivo temporario/estado parcial em caso de falha no meio da escrita? [Cobertura, quickstart.md] {auto} — RESOLVIDO (task 3.2.4): `quickstart.md` Scenario 5.5 "Permissões e atomicidade — CHK013", implementado em `tests/test_state-backend.sh::scenario_enable_sqlite_permissoes_700_600_sem_residuo` (verifica `700`/`600` e ausencia de residuo de `mktemp`).

## Consistencia e limites declarados do modelo de ameaca

- [x] CHK014 - O modelo de ameaca aceito para a resolucao via `PATH`/`command -v` (SEC-04, severidade Baixa) declara explicitamente por que o risco e aceito, em vez de simplesmente omitir o tema? [Clareza, plan.md §SEC-04 L233-241] {auto} — SIM: plan.md justifica com dois argumentos verificaveis — (a) e o padrao ja vigente para `state-db-migrate.sh`, esta feature nao amplia a superficie; (b) quem controla o `PATH` do usuario ja pode executar codigo diretamente, sem precisar deste vetor. Registrado para nao ser "redescoberto como novidade" numa auditoria futura.
- [x] CHK015 - O comportamento fail-safe de FR-008 (config ausente/invalida ⇒ fallback ao backend LEGADO, nunca ao novo/mais privilegiado) esta explicitamente avaliado como a direcao de degradacao correta, e nao apenas implicito? [Clareza, plan.md §"Avaliacao positiva" L243-249] {auto} — SIM: plan.md declara textualmente que "um arquivo corrompido nunca promove uma execucao a SQLite silenciosamente — a promocao exige ativacao explicita" e classifica isso como "fail-closed em relacao a mudanca de comportamento, que e a direcao certa".
- [ ] CHK016 - O apetite de risco por avancar para `/create-tasks` com os gaps de cobertura de teste das clausulas P1 (CHK002), P3 (CHK006) e P8/SEC-03 (CHK009, unico risco Media sem teste) e aceitavel, ou esses 3 cenarios devem ser adicionados ao `quickstart.md` ANTES de gerar o backlog de tarefas? [Risco, quickstart.md] {humano} — decisao do dono: os 6 gaps de cobertura (CHK002, CHK004, CHK006, CHK007, CHK009, CHK013) sao todos de MENSURABILIDADE/COBERTURA (a clausula existe e e clara, so falta o teste que a exercite) — nenhum e ambiguidade ou contradicao de requisito. `/create-tasks` pode gerar as tarefas de teste faltantes diretamente a partir destes CHKs; a decisao humana e se CHK009 (unico risco Media) deve bloquear o avanco ou seguir como tarefa normal do backlog.
  > **Resultado observado (`/analyze` de fechamento, FASE 7, task 7.2)**: o
  > caminho "backlog normal, sem bloquear `/create-tasks`" foi de fato o
  > seguido — `/create-tasks` gerou as tarefas 2.1.4/2.1.5, 2.2.3-2.2.6,
  > 3.1.4/3.1.5, 3.2.4/3.2.5, e todos os 6 gaps (CHK002, CHK004, CHK006,
  > CHK007, CHK009 incluso) fecharam antes do `review-task`. Isso VALIDA
  > empiricamente que a escolha implicita nao bloqueante nao deixou nenhum
  > risco Media/Alta sem teste ao final da feature — mas o item permanece
  > `{humano}` (nao e este orquestrador quem detem a autoridade de decisao
  > de risco do dono do produto; apenas o resultado factual e registrado).

## Notes

- Items `{auto}` resolvidos com `[x]`: 15 de 15 (CHK001-CHK015). CHK002,
  CHK004, CHK006, CHK007, CHK009, CHK013 fechados no `/analyze` de
  fechamento da FASE 7 (task 7.2), apos confirmar empiricamente que os
  cenarios de `quickstart.md` (2.5/2.6/2.7/4.5/5.5) e os tests
  correspondentes em `tests/test_state-backend.sh` ja existiam desde as
  FASES 2-3 do backlog. CHK010 resolvido na task 1.1 (dec-034).
- Item `{humano}` aguardando dono do produto: CHK016 (decisao formal de
  risco nao delegavel a este orquestrador) — resultado observado anotado
  inline, decisao permanece aberta para o dono confirmar.
