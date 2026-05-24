# API / Contracts Checklist: Knowledge DB Metrics Ingestion

**Purpose**: Validar a QUALIDADE dos requisitos de contrato/schema desta
feature. "API" aqui = o contrato do indice SQLite (schema versionado das
entidades novas), a chave natural de idempotencia, e os contratos
`recall-ingest-schema.md` / `layer-b-instrumentation.md`. NAO valida
implementacao — valida se os contratos escritos sao claros, completos,
versionados e consistentes.
**Created**: 2026-05-24
**Feature**: [spec.md](../spec.md)

## Contratos e Schema Versionado

- [ ] CHK001 - FR-007 define um criterio inequivoco de quando o `schema_version` MUST passar de 1 para 2 ("quando as entidades novas forem introduzidas") — e fica claro se as 5 entidades (Execucao, Onda, SinalDeAlerta, Task, Evento) entram TODAS no bump v2 ou se camada B (Task/Evento) seria um v3 futuro? [Clareza, Spec §FR-007 / §FR-010]
- [ ] CHK002 - Cada entidade nova (Execucao, Onda, SinalDeAlerta, Task, Evento) tem seu conjunto de colunas/atributos especificado como contrato formal (Key Entities + contrato `recall-ingest-schema.md`), sem campo "TBD"? [Completude, Spec §Key Entities / contracts/recall-ingest-schema.md]
- [ ] CHK003 - Os atributos listados em FR-011 (Execucao) e FR-012 (Onda) sao CONSISTENTES com os campos realmente presentes no `state.json` (ex: `metricas_acumuladas.*`, `.ondas[].wallclock_seconds`)? Algum campo citado pode nao existir em execucoes antigas? [Consistencia, Spec §FR-011 / §FR-012]
- [ ] CHK004 - O contrato define tipos/nullabilidade de cada coluna (ex: `terminada_em` nulo para execucao em andamento, `duracao` derivada nula quando termino ausente)? [Clareza, Spec §FR-011 / §Edge Cases]
- [ ] CHK005 - A relacao entre entidades (Onda -> Execucao, Task/Evento -> Execucao/Onda, SinalDeAlerta -> Execucao/Onda) e definida com chave de junção explicita no contrato? [Completude, Spec §Key Entities]

## Idempotencia (chave natural)

- [ ] CHK006 - FR-008 especifica a chave natural de idempotencia para CADA entidade nova, nao so genericamente? Para Execucao, Onda, SinalDeAlerta, Task e Evento a chave esta definida individualmente? [Cobertura, Spec §FR-008]
- [ ] CHK007 - A chave natural de Task `(projeto, feature, execucao_id, task_id)` (Clarif Q2) e consistente com o padrao existente `UNIQUE(project, feature, wave, source_id)` citado na spec? [Consistencia, Spec §Clarifications Q2 / §FR-008]
- [ ] CHK008 - Para a entidade Evento, FR-020/Clarif Q3 define uma chave natural que distingue duas ocorrencias do MESMO `event_type` no mesmo wave (ex: dois `lock_contention` na mesma onda) sem colapsar uma sobre a outra? [Gap, Spec §FR-020 / §Clarifications Q3]
- [ ] CHK009 - SC-004 ("delta de linhas = 0 em re-ingestao") e mensuravel para todas as 5 entidades, incluindo execucao `em_andamento` re-ingerida (valores atualizam, contagem nao muda)? [Mensurabilidade, Spec §SC-004 / §Edge Cases]

## Reuso vs Duplicacao de Logica

- [ ] CHK010 - FR-017 define o contrato de REUSO de `model-routing-report.sh aggregate` de forma verificavel — qual e a interface consumida e o criterio de "0 divergencias" (SC-006)? [Clareza, Spec §FR-017 / §SC-006]
- [ ] CHK011 - A spec deixa claro se o mix de roteamento e MATERIALIZADO no indice ou COMPUTADO na consulta (MetricaDerivada "pode ser materializada ou computada") — e a escolha nao quebra a propriedade de indice derivado (FR-001)? [Ambiguity, Spec §FR-017 / §Key Entities MetricaDerivada]

## Compatibilidade de Schema / Versionamento

- [ ] CHK012 - O requisito de migracao de schema antigo (Edge Case "schema_version = 1 em disco") garante criacao idempotente das tabelas ausentes SEM perda de dado existente, e isso esta declarado como contrato? [Completude, Spec §Edge Cases / §FR-007]
- [ ] CHK013 - O contrato `layer-b-instrumentation.md` define o formato EXATO dos campos novos que os orquestradores gravam no `state.json` (FR-018/FR-020), de modo que produtor (orquestrador) e consumidor (ingestao) concordem? [Consistencia, contracts/layer-b-instrumentation.md / §FR-018]
- [ ] CHK014 - FR-022 (retro-compatibilidade) define o contrato de "campo ausente => entidade vazia, sem erro" para Task e Evento, com criterio mensuravel (SC-009: 0 registros, 0 erros)? [Mensurabilidade, Spec §FR-022 / §SC-009]

## Notes

- Marcar items concluidos com `[x]`.
- "Contrato" aqui = schema do indice + chave natural + contratos em
  `contracts/`. Nao ha REST/gRPC nesta feature.
- Items que revelam campo "TBD" ou chave indefinida -> `/clarify`.
