# Security Checklist: Knowledge DB Metrics Ingestion

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca da feature
(confinamento de dependencia, scrub de texto livre, ausencia de superficie
de ataque nova, proveniencia). NAO valida implementacao — valida se os
requisitos escritos sao claros, completos, testaveis e consistentes.
**Created**: 2026-05-24
**Feature**: [spec.md](../spec.md)

> Dominios ux/a11y deliberadamente fora deste gate: FR-005 poe o painel
> (unica superficie de UI/leitura) fora de escopo. Sem authN/Z, sem
> endpoint, sem dado em transito — a feature e ingestao local stateless.

## Protecao de Dados / Scrub de Segredos

- [ ] CHK001 - O requisito de scrub de texto livre (FR-006) define COM PRECISAO quais campos sao "texto livre" (sujeitos a `secrets-filter`) versus "estruturado/numerico" (ingeridos sem filtro)? [Clareza, Spec §FR-006]
- [ ] CHK002 - A fronteira "texto livre vs estruturado" e consistente entre FR-006, o Edge Case "Texto livre com segredo" e as entidades de Key Entities (ex: `motivo_termino`, `contexto`, `event_type`)? [Consistencia, Spec §FR-006 / §Edge Cases / §Key Entities]
- [ ] CHK002a - Para a entidade Evento (FR-020), o requisito esclarece se `event_type` (vocabulario fechado) e estruturado e portanto NAO passa pelo filtro, enquanto eventuais mensagens livres do evento passam? [Gap, Spec §FR-020]
- [ ] CHK003 - SC-007 define um criterio VERIFICAVEL de ausencia de segredo no indice ("nenhum padrao de segredo conhecido presente apos ingestao de fixture com segredos plantados")? E o conjunto de "padroes conhecidos" e o mesmo coberto por `secrets-filter`? [Mensurabilidade, Spec §SC-007]
- [ ] CHK004 - Os requisitos definem o que acontece se o `secrets-filter` falhar/estiver ausente durante a ingestao de um campo de texto livre — o campo e omitido, redigido, ou a ingestao daquele registro e pulada? [Gap, Spec §FR-003 / §FR-006]

## Confinamento de Dependencia (blast radius)

- [ ] CHK005 - FR-004 quantifica "confinado" de forma verificavel (a dep de `sqlite3` e `secrets-filter` so pode aparecer em `recall.sh`)? Existe criterio objetivo para auditar a violacao (ex: grep em `cli/lib/*` exceto `recall.sh`)? [Mensurabilidade, Spec §FR-004]
- [ ] CHK006 - Os requisitos sao consistentes quando a camada B (FR-018/FR-020) faz os ORQUESTRADORES gravarem campos novos: a gravacao de instrumentacao introduz dependencia de `sqlite3`/`secrets-filter` nos orquestradores, ou permanece confinada (orquestrador so escreve JSON no state, ingestao continua so em `recall.sh`)? [Consistencia, Spec §FR-004 / §FR-018 / §FR-020]
- [ ] CHK007 - A spec define que a ingestao MUST NOT abrir nenhuma comunicacao externa nova (rede, processo, arquivo fora de `~/.claude/cstk/`)? [Gap, Spec §FR-002 / §FR-005]

## Integridade da Fonte de Verdade

- [ ] CHK008 - FR-002 ("ler `state.json` somente leitura, MUST NOT modificar") tem criterio de verificacao objetivo (ex: hash do `state.json` inalterado antes/depois da ingestao)? [Mensurabilidade, Spec §FR-002]
- [ ] CHK009 - Os requisitos definem o comportamento quando o `state.json` esta corrompido/ilegivel (Edge Case): pular com aviso E continuar reindex dos demais — esse comportamento esta especificado sem ambiguidade de "qual aviso, qual exit code"? [Clareza, Spec §FR-003 / §Edge Cases]
- [ ] CHK010 - A spec garante que escrita no indice derivado (que VIVE fora do state) nunca pode corromper ou bloquear o `state.json` transacional (isolamento de falha)? [Cobertura, Spec §FR-001 / §FR-002]

## Logging / Auditoria

- [ ] CHK011 - Os avisos emitidos em stderr nos caminhos de fallback (FR-003) tem requisito de NAO vazar segredo nem caminho sensivel? [Clareza, Spec §FR-003 / §FR-006]
- [ ] CHK012 - A proveniencia ingerida (projeto/feature/onda/execucao) e definida como dado estruturado (sem PII/segredo) — algum campo de proveniencia poderia carregar texto livre nao-filtrado? [Gap, Spec §FR-008]

## Notes

- Marcar items concluidos com `[x]`.
- Items revelando ambiguidade: levar a `/clarify` antes de `/create-tasks`.
- Foco do dominio: scrub de texto livre (FR-006/SC-007), confinamento de dep
  (FR-004), integridade do state (FR-002), isolamento de falha do indice.
