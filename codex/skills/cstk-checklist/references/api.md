# Dominio: API

Items exemplo para checklist de qualidade de requisitos de API.

## Contratos e Schemas

- Sao formatos de request/response definidos para todos os endpoints? [Completude]
- Sao versoes de API e estrategia de versionamento especificadas? [Clareza]
- Sao schemas (JSON Schema, OpenAPI) mantidos como contrato formal? [Consistencia]

## Error Handling

- Sao formatos de resposta de erro especificados para todos os cenarios de falha? [Completude]
- Codigos de erro seguem convencao consistente (HTTP status + error code)? [Consistencia]
- Mensagens de erro definem se sao seguras para exibir ao usuario final? [Spec §FR-X]

## Autenticacao e Autorizacao

- Sao requisitos de autenticacao consistentes entre todos os endpoints? [Consistencia]
- Sao definidos escopos/permissions necessarios por endpoint? [Cobertura]
- Tokens e sessoes tem TTL e politica de refresh definidos? [Clareza]

## Rate Limiting e Throttling

- Sao requisitos de rate limiting quantificados com thresholds especificos? [Clareza]
- Comportamento em caso de exceder rate limit e definido? [Completude]
- Rate limits variam por tipo de usuario/plano? [Cobertura]

## Retry e Idempotencia

- Sao requisitos de retry/timeout definidos para dependencias externas? [Cobertura, Gap]
- Endpoints que mutam estado sao idempotentes (ou exigem idempotency-key)? [Clareza]
- Politica de backoff em falhas e especificada? [Clareza]

## Observabilidade

- Requisitos de logging estruturado sao definidos? [Cobertura]
- Metricas por endpoint (latencia, taxa de erro) sao requeridas? [Cobertura]
- Tracing distribuido e especificado para requisicoes cross-service? [Cobertura, Gap]

## Paginacao e Filtros

- Paginacao tem estrategia definida (cursor, offset, etc.) e limites? [Clareza]
- Filtros e ordenacao seguem convencao consistente entre endpoints? [Consistencia]

## Deprecacao

- Politica de deprecacao de endpoints e definida (aviso, periodo de sunset)? [Completude, Gap]
