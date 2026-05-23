# Performance Checklist: cstk Knowledge DB

**Purpose**: Validar a QUALIDADE dos requisitos nao-funcionais de performance/
escalabilidade da feature `cstk-knowledge-db` — busca FTS5/bm25, concorrencia
WAL multi-worktree, idempotencia de reindex e degradacao sob contencao. Valida
se os REQUISITOS sao mensuraveis e nao-ambiguos, nao o codigo.
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md) | [cstk-recall.md](../contracts/cstk-recall.md) | [ingest-helper.md](../contracts/ingest-helper.md)

## Busca / Ranking (FR-004, FR-010)

- [ ] CHK001 - O requisito de ordenacao por relevancia esta especificado de forma verificavel (criterio de ranking definido, ex: bm25), e nao apenas "ordenado por relevancia"? [Mensurabilidade, Spec §FR-010 / cstk-recall §5]
- [ ] CHK002 - O comportamento de truncamento por `--limit` esta especificado em relacao ao ranking (top-N por relevancia, nao N arbitrarios)? [Clareza, Spec §US1 AS3 / cstk-recall §5]
- [ ] CHK003 - Existe um requisito (ou ausencia justificada) de alvo de latencia/escala para a busca (ex: tamanho esperado do indice)? [Gap, Spec §Success Criteria]

## Concorrencia / Escalabilidade (FR-016)

- [ ] CHK004 - O modelo de concorrencia esta especificado com parametros mensuraveis (`journal_mode=WAL`, `busy_timeout` ~5000ms, retry/backoff limitado)? [Mensurabilidade, Spec §FR-016 / ingest-helper §7]
- [ ] CHK005 - O numero maximo de tentativas de retry e a politica de backoff (ate 3 tentativas, sleep crescente) estao quantificados sem ambiguidade? [Clareza, ingest-helper §7]
- [ ] CHK006 - O comportamento sob "database is locked" persistente alem do retry (skip da ingestao da onda, exit 0) esta especificado como degradacao mensuravel? [Mensurabilidade, Spec §FR-016 / ingest-helper §7]
- [ ] CHK007 - O requisito cobre o cenario de multiplas sessoes/worktrees terminando ondas quase simultaneamente sem corrupcao nem perda de registro? [Cobertura, Spec §Edge Cases / FR-016]

## Idempotencia & Custo de Reconstrucao (FR-015, SC-005)

- [ ] CHK008 - O requisito de reindex idempotente especifica que rodar N vezes nao infla contagem nem degrada conteudo (custo previsivel)? [Mensurabilidade, Spec §FR-015 / SC-005]
- [ ] CHK009 - O requisito define que o indice e descartavel/derivado, permitindo recriacao do zero como estrategia de recuperacao (em vez de migracao custosa)? [Clareza, Spec §Resumo / FR-014]

## Degradacao sob Falha (FR-018)

- [ ] CHK010 - O requisito garante que o custo de uma falha da camada de conhecimento e limitado (aviso + skip), nunca propagando latencia/bloqueio para o caminho critico da onda? [Completude, Spec §FR-018 / SC-003]
- [ ] CHK011 - O requisito de "fonte intacta" implica zero overhead de escrita transacional adicional sobre o state.json (somente leitura via jq)? [Consistencia, Spec §FR-009 / ingest-helper §8]

## Ambiguities & Gaps

- [ ] CHK012 - Ha ausencia de requisito explicito de escala maxima do indice (numero de projetos/features/ondas) que poderia afetar latencia de busca FTS5 — gap aceitavel ou a documentar? [Gap, Spec §Success Criteria]
- [ ] CHK013 - O sleep "crescente" do backoff esta quantificado (valores ou formula) ou e ambiguo o suficiente para divergencia de implementacao? [Ambiguity, ingest-helper §7]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente (CHK001+) para referencia cruzada
- Foco: ranking FTS5/bm25, concorrencia WAL, idempotencia de reindex, custo de degradacao
- Nota: como feature local sem servidor/rede, varios alvos classicos de performance (throughput de API, p99 de latencia distribuida) sao N/A por design — gaps CHK003/CHK012 sao deliberados e devem ser confirmados como aceitaveis, nao silenciosamente ignorados
