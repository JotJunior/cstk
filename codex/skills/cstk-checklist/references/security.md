# Dominio: Security

Items exemplo para checklist de qualidade de requisitos de seguranca.

## Autenticacao

- Sao requisitos de autenticacao especificados para todos os recursos protegidos? [Cobertura]
- Politica de senha e definida (tamanho, complexidade, historico)? [Clareza]
- MFA e requerido para operacoes sensiveis? [Cobertura]
- Comportamento em tentativas falhas (lockout, captcha) e especificado? [Completude]

## Autorizacao e Acesso

- Modelo de autorizacao (RBAC, ABAC) e documentado? [Completude]
- Requisitos de deny-by-default estao explicitos? [Spec §FR-X]
- Escalacao de privilegios tem trilha de auditoria? [Cobertura]

## Protecao de Dados

- Sao requisitos de protecao de dados definidos para informacoes sensiveis? [Completude]
- Dados em repouso sao criptografados (campos sensiveis, banco)? [Clareza]
- Dados em transito usam TLS com versoes minimas especificadas? [Clareza]
- Retencao e descarte de dados tem politica definida? [Cobertura, Compliance]

## Input Validation

- Requisitos de validacao de input sao definidos para todos os endpoints? [Cobertura]
- Sanitizacao contra injection (SQL, XSS, command) esta especificada? [Completude]
- Tamanho maximo de payloads e definido? [Clareza]

## Logging e Auditoria

- Eventos de seguranca (login, acesso negado, mudanca de permissao) sao logados? [Cobertura]
- Logs contem dados suficientes para forensics sem vazar segredos? [Clareza]
- Politica de retencao de logs atende compliance? [Compliance]

## Secrets e Credenciais

- Secrets nao ficam em codigo/config versionado (vault, env vars)? [Completude]
- Rotacao de secrets tem processo definido? [Gap]
- Chaves de API e tokens tem escopo minimo (least privilege)? [Clareza]

## Threat Modeling

- O modelo de ameacas esta documentado e requisitos alinhados a ele? [Traceability]
- Vetores de ataque conhecidos para o dominio foram considerados? [Cobertura]

## Compliance

- Requisitos de LGPD/GDPR/PCI/HIPAA aplicaveis sao mapeados? [Compliance]
- Direito de consentimento e remocao de dados (onde aplicavel) e definido? [Compliance]
