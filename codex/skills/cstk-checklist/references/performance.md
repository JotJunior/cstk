# Dominio: Performance

Items exemplo para checklist de qualidade de requisitos de performance.

## Targets Mensuraveis

- Sao requisitos de performance quantificados com metricas especificas (p50, p95, p99)? [Clareza]
- Sao targets de performance definidos para todas as jornadas criticas? [Cobertura]
- Definicoes incluem condicoes de medicao (load, concorrencia)? [Clareza]

## Escalabilidade

- Sao requisitos de carga concorrente quantificados (RPS, usuarios simultaneos)? [Clareza]
- Estrategia de scaling (horizontal, vertical, elastico) e especificada? [Completude]
- Limites de crescimento (storage, compute) sao documentados? [Cobertura]

## Degradacao Gracios

- Sao requisitos de degradacao definidos para cenarios de alta carga? [Edge Case, Gap]
- Politica de circuit breaker e documentada? [Cobertura]
- Fallbacks em caso de dependencia lenta/indisponivel sao definidos? [Completude]

## Caching

- Sao camadas de cache especificadas (CDN, app, DB)? [Cobertura]
- TTLs e politica de invalidacao sao definidos? [Clareza]
- Cache miss handling (stampede protection) e especificado? [Gap]

## Queries e I/O

- Sao requisitos de latencia de query definidos? [Clareza]
- N+1 query prevention e requisito explicito? [Cobertura]
- Indices necessarios sao mapeados a queries criticas? [Traceability]

## Tamanho de Payload

- Limites de tamanho de resposta (paginacao) sao definidos? [Clareza]
- Compressao (gzip, brotli) e requerida? [Cobertura]
- Lazy loading de recursos pesados e especificado? [Completude]

## Observabilidade de Performance

- Metricas de latencia, throughput e erro por endpoint sao requeridas? [Cobertura]
- Alertas de degradacao tem thresholds definidos? [Clareza]
- Profiling em producao (sampling) e permitido/requerido? [Gap]

## Mobile e Frontend

- Budget de performance de frontend (LCP, FID, CLS) e definido? [Clareza]
- Tamanho maximo de bundle inicial e especificado? [Cobertura]
- Estrategia de imagem (lazy load, formatos modernos) e requisito? [Completude]
