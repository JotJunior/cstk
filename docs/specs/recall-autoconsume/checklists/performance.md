# Performance Checklist: recall-autoconsume

**Purpose**: Validar a QUALIDADE dos requisitos de custo/performance do read-back
loop. A "performance" aqui e custo-por-onda (tool calls + wallclock), nao
throughput de servico. Foco em clareza e mensurabilidade dos requisitos —
nao na implementacao. "Unit tests for English."
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md)

## Targets de custo mensuraveis

- [ ] CHK001 - O custo adicional por onda esta quantificado com target especifico
  (<=1 invocacao de leitura por fase consumidora) em vez de adjetivo vago ("custo
  baixo")? [Clareza, Spec §SC-006]
- [ ] CHK002 - O custo total por feature esta quantificado (<=2 leituras, derivado
  de specify + plan apenas) e rastreavel ao escopo de fases consumidoras (FR-010)?
  [Mensurabilidade, Spec §FR-010, §SC-006]
- [ ] CHK003 - O requisito de "sem rede" e verificavel objetivamente (ausencia de
  qualquer I/O remoto durante o consumo), nao apenas afirmado? [Mensurabilidade, Spec §SC-006]

## Limite de payload (teto do bloco)

- [ ] CHK004 - O teto de tamanho do bloco injetado e quantificado (`--max-bytes`,
  default 2000) e a spec garante que ele NUNCA e excedido em 100% das execucoes
  (SC-004), verificavel por fixture de muitos achados longos? [Mensurabilidade, Spec §FR-006, §SC-004]
- [ ] CHK005 - O requisito define o comportamento de truncamento quando o conjunto
  de achados estoura o teto (cortar por N e por bytes) sem produzir saida malformada
  / linha cortada no meio? [Edge Case, Spec §FR-006]

## Controle de ruido (relevancia sem custo de tuning)

- [ ] CHK006 - A decisao de NAO aplicar piso de bm25 absoluto esta justificada com
  evidencia (bm25 adimensional, dependente de corpus) e o controle de ruido fica
  EXCLUSIVAMENTE no teto N pequeno + ordenacao bm25 — sem introduzir custo de
  calibracao? [Clareza, Spec §FR-007]
- [ ] CHK007 - O requisito de query com `LIMIT N` pequeno e explicito como mecanismo
  de conter custo de leitura/render, e o N e o mesmo do `--limit` (sem
  inconsistencia entre teto de query e teto de saida)? [Consistencia, Spec §FR-004, §FR-007]

## Degradacao sob falha (custo zero)

- [ ] CHK008 - A spec define que qualquer falha (sem deps, db ausente/corrompido,
  timeout) degrada para no-op de custo desprezivel, NUNCA atrasando a onda — e que
  isso e mensuravel (SC-003 = 100% no-op sem deps)? [Mensurabilidade, Spec §FR-012, §SC-003]
- [ ] CHK009 - Existe requisito de TETO DE TEMPO ("teto de tempo razoavel",
  US3-3) e ele esta quantificado, ou e um adjetivo vago que impede verificacao
  objetiva do "nunca trava a onda"? [Ambiguity, Spec §US3-3]
- [ ] CHK010 - O requisito enderece a leitura concorrente durante ingestao (WAL,
  "database is locked") como no-op de baixo custo, sem retry custoso ou espera que
  infle o wallclock da onda? [Edge Case, Spec §Edge Cases]

## Custo de escopo (fases certas)

- [ ] CHK011 - A spec justifica a EXCLUSAO de `execute-task` por custo (uma leitura
  por task violaria SC-006 e Principio V) com criterio claro de por que specify+plan
  pagam o custo e as demais fases nao? [Clareza, Spec §FR-010]
- [ ] CHK012 - O custo da escrita auditavel de consumo (FR-016) e desprezivel e nao
  conta contra o orcamento de leitura — o requisito distingue custo de LEITURA do
  indice do custo de REGISTRO no state.json? [Consistencia, Spec §FR-016, §SC-006]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
- CHK009 destaca um possivel gap de quantificacao (teto de tempo) — candidato a
  finding informativo / clarify se o gate considerar relevante.
