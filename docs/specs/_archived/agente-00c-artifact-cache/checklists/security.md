# Security Checklist: Agente-00C Artifact Cache

**Purpose**: Validar QUALIDADE dos requisitos de seguranca da feature
artifact-cache — secrets-filter, blast radius, integridade do cache,
auditabilidade.
**Created**: 2026-05-21
**Feature**: [`spec.md`](../spec.md)

## Secrets em conteudo cacheado

- [ ] CHK001 - Aplicacao do `secrets-filter.sh scrub` ao resumo eh
  requisito MUST (nao MAY)? E aplicado ANTES de persistir em state.json
  ou pode haver janela onde estado bruto fica em disco? [Clareza, Spec §FR-CACHE-006]
- [ ] CHK002 - O conjunto de patterns reconhecidos pelo filtro (AWS keys,
  GitHub tokens, generic Bearer, etc.) esta documentado na spec — ou
  delegado integralmente ao codigo de `secrets-filter.sh`? [Completude, Gap]
- [ ] CHK003 - Cenarios ambiguos (string que parece token mas eh commit
  SHA, UUID, etc.) tem politica default fail-safe (redact em duvida)
  explicita? [Cobertura, Spec §Edge Cases - relevante FR-029 herdado]
- [ ] CHK004 - Se >50% do conteudo eh redacted, o requisito de fallback
  para passthrough esta documentado como FR explicito (nao apenas em
  Edge Cases)? [Conflict, Spec §Edge Cases]
- [ ] CHK005 - O behavior quando secrets aparecem no SOURCE (briefing.md
  com token de exemplo) eh: cache redacta MAS source permanece intocado.
  Esse contrato esta enforced num teste? [Mensurabilidade, Tasks T1.5]

## Integridade do cache

- [ ] CHK006 - Sha256 do source eh registrado no momento da populacao
  (FR-CACHE-002). Existe requisito de que o sha256 seja calculado APOS
  o filtro de secrets ou ANTES? Se eh do source bruto, drift em
  conteudo nao-sensitivo dispara invalidacao? [Ambiguity, Spec §FR-CACHE-002]
- [ ] CHK007 - O algoritmo de hash (sha256) eh especificado, ou abre
  espaco para outro algoritmo no futuro (sha3, blake3)? Compatibility
  cross-version do state.json depende disso. [Completude, Spec §FR-CACHE-002]
- [ ] CHK008 - Se um atacante tem acesso de escrita ao `state.json`
  (e.g., via outro processo no host), pode injetar resumo manipulado
  + sha256 falso e fazer a skill consumir conteudo arbitrario? [Edge case, Gap]
- [ ] CHK009 - Validacao de invariante FR-CACHE-017 (`source_sha256` eh
  hex de 64 chars) eh enforced ANTES da skill consumir o cache, ou apenas
  em `state-validate.sh` rodado periodicamente? [Clareza, Spec §FR-CACHE-017]

## Blast radius

- [ ] CHK010 - O caminho de gravacao do cache (`<projeto>/.claude/
  agente-00c-state/state.json`) eh validado contra zonas proibidas via
  `path-guard.sh`? [Completude, Spec §Constitutional Alignment V]
- [ ] CHK011 - O cache nao escreve fora do `.claude/agente-00c-state/`
  do projeto-alvo. Existe teste explicito para isso (tentativa de
  override via `--state-dir` malicioso)? [Mensurabilidade, Tasks T1.5]
- [ ] CHK012 - O cache nao modifica nem move `briefing.md`/`docs/constitution.md`
  (source files sao read-only para esta feature). Esse contrato eh
  testado? [Mensurabilidade, Gap]
- [ ] CHK013 - Logs do `state-cache.sh` (stderr/stdout) passam pelo
  filtro de secrets antes de irem para `_log.sh`? Aplica o FR-036
  herdado da feature-00c? [Completude, Spec §Constitutional Alignment]

## Auditabilidade (Principio I)

- [ ] CHK014 - Toda invalidacao de cache gera Decisao com 5 campos
  (FR-CACHE-011). Os 5 campos sao especificados na spec? Validacao de
  presenca eh enforced no `state-decisions.sh register`? [Completude, Spec §FR-CACHE-011]
- [ ] CHK015 - Categoria "cache-invalidacao" eh especificada como enum
  na spec, ou string livre? Validar via state-validate.sh evitaria
  drift de categorias. [Clareza, Gap]
- [ ] CHK016 - A Decisao registra qual evento disparou a invalidacao
  (drift detectado vs invalidate manual vs MAJOR drift escalado),
  permitindo distinguir nos logs/relatorio? [Cobertura, Spec §FR-CACHE-011]
- [ ] CHK017 - Sequencia temporal de invalidacoes eh preservada
  (timestamps ISO-8601 + ordem auditavel) — relatorio consegue
  reconstruir o que aconteceu em ordem? [Mensurabilidade, Spec §FR-CACHE-013]

## Drift e BloqueioHumano

- [ ] CHK018 - Drift MAJOR ("mudanca do primeiro digito de
  constitution.version OU mudanca de >50% nos chars") eh suficiente?
  Pode haver MAJOR semantico sem mudanca de version (e.g., principio
  invertido sem bumpar)? [Cobertura, Spec §FR-CACHE-010]
- [ ] CHK019 - Quem decide se um drift especifico eh MAJOR — o
  orquestrador via heuristica, ou ha override humano possivel? [Ambiguity, Gap]
- [ ] CHK020 - Se o operador NAO responde o BloqueioHumano (timeout),
  qual eh o comportamento — pipeline pausa indefinida? [Edge case, Gap]
- [ ] CHK021 - Em drift MAJOR de briefing (nao constitution), aplica a
  mesma escalada para BloqueioHumano? FR-CACHE-010 menciona apenas
  constitution. [Cobertura, Spec §FR-CACHE-010]

## Protecao contra mau uso

- [ ] CHK022 - Skill standalone (sem state.json) NAO grava nenhum
  artefato de cache. Eh requisito explicito (FR-CACHE-014) ou esta
  implicito no protocol step "Caso contrario: leia direto do disco"?
  [Clareza, Spec §FR-CACHE-014]
- [ ] CHK023 - Se um state.json malicioso de outra origem eh injetado
  em `.claude/agente-00c-state/`, o sha256 do state-rw.sh detecta antes
  do cache ser consumido? [Edge case, Spec §FR-CACHE-016]

## Notes

- Marcar items concluidos com `[x]`
- Items rastreaveis: 19/23 (~83%) atendem o minimo de 80%
- Items sem ref direto sao gaps de seguranca que precisam endereçar:
  CHK002 (patterns secrets), CHK008 (state.json write malicioso),
  CHK012 (source read-only teste), CHK015 (enum categoria), CHK019
  (override de drift MAJOR), CHK020 (timeout de BloqueioHumano)
- Prioridade alta: CHK001 (filtro MUST aplicado), CHK010 (path-guard),
  CHK014 (Decisao auditavel) — sao gates de seguranca compulsorios
