# Security Checklist: recall-autoconsume

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca do read-back loop
(modo `cstk recall --context` + passo PRE-DECISAO nos orquestradores). Foco em
clareza, completude e testabilidade dos requisitos — nao na implementacao.
"Unit tests for English."
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md)

## Modelo de confianca do conteudo recuperado

- [ ] CHK001 - A spec define EXPLICITAMENTE que o body recuperado do indice deve
  ser tratado como UNTRUSTED no ponto de injecao (PRE-DECISAO), em vez de assumir
  que o scrub na ingestao o torna seguro para qualquer uso downstream? [Gap, Spec §FR-015]
- [ ] CHK002 - O requisito distingue a fronteira onde o scrub OCORRE (ingestao,
  FR-017 da spec arquivada) da fronteira onde o conteudo e CONSUMIDO (injecao
  PRE-DECISAO), de modo que a premissa "seguro por construcao" seja rastreavel e
  falsificavel? [Clareza, Spec §FR-015]
- [ ] CHK003 - Existe requisito que enderece o risco de prompt-injection /
  influencia adversarial (ASI09 / LLM01) quando o body — texto livre de execucoes
  passadas — e injetado no contexto de decisao do orquestrador, ou esse risco esta
  apenas documentado como finding LOW sem requisito derivado? [Gap, Ambiguity]
- [ ] CHK004 - A spec especifica que o bloco injetado e claramente DELIMITADO /
  rotulado como "conhecimento recuperado (nao-autoritativo)" para que o
  orquestrador nao confunda achados passados com instrucao corrente? [Gap]

## Read-only e blast radius

- [ ] CHK005 - O requisito de read-only (FR-014) e mensuravel — define que o modo
  NAO escreve no indice, NAO escreve no state.json, NAO escreve em nenhum artefato
  transacional — de forma verificavel por teste? [Mensurabilidade, Spec §FR-014]
- [ ] CHK006 - A spec define que o consumo permanece ESTRITAMENTE LOCAL (sem rede,
  sem coleta remota), alinhado ao Principio IV, de forma objetivamente verificavel
  (ausencia de qualquer chamada de rede)? [Clareza, Spec §FR-015]
- [ ] CHK007 - Os requisitos de blast radius cobrem o caso da escrita auditavel da
  Decisao "consumo" no state.json (FR-016) — deixando claro que essa e a UNICA
  escrita permitida e que ela e feita pelo runtime transacional, nao pelo modo
  --context? [Consistencia, Spec §FR-014, §FR-016]

## Validacao de entrada do modo --context

- [ ] CHK008 - Sao definidos requisitos de validacao para os termos de consulta
  derivados (aspectos_chave / descricao), incluindo neutralizacao de sintaxe FTS5
  via `fts_query_escape` reaproveitado (FR-002/FR-009)? [Cobertura, Spec §FR-009]
- [ ] CHK009 - A spec especifica o comportamento para entrada degenerada/hostil
  (termos so com stopwords, NUL bytes, metacaracteres FTS5) — tratada como zero
  resultados / no-op sem propagar erro? [Edge Case, Spec §FR-009]
- [ ] CHK010 - Os requisitos definem que o filtro anti-eco (`--exclude-feature`,
  FR-005) nao pode ser contornado por valores de feature manipulados, mantendo a
  garantia SC-002 (0% auto-eco) sob entrada adversarial? [Cobertura, Spec §FR-005]

## Vazamento e auditoria de seguranca

- [ ] CHK011 - A spec garante que NENHUM novo re-scrub e introduzido na leitura
  (FR-015 + Out of Scope) e que isso nao reabre o risco de vazamento — ou seja, a
  premissa de scrub-na-ingestao e suficiente e esta documentada como tal? [Consistencia, Spec §FR-015]
- [ ] CHK012 - Os requisitos definem que mensagens de aviso (stderr) da degradacao
  graciosa NAO vazam conteudo do indice nem segredos (apenas diagnostico de no-op)?
  [Gap, Spec §FR-012]
- [ ] CHK013 - O evento auditavel de consumo (FR-016/FR-017) especifica que
  registra termos derivados e contagem de achados, SEM persistir o body bruto
  recuperado (que poderia reintroduzir conteudo sensivel no state.json)? [Clareza, Spec §FR-016]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
- Findings deste checklist alimentam o gate owasp-security (LLM01/ASI09 ja
  marcado LOW via dec-013); CHK001-CHK004 sao o hardening derivado.
