# Example: Good Feature Spec

Este exemplo ilustra uma spec bem escrita — foco em QUE/POR QUE, sem detalhes de implementacao, com success criteria mensuraveis e technology-agnostic.

---

# Feature Specification: Password Reset via Email

**Feature**: `password-reset-email`
**Created**: 2026-03-15
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Request reset link (Priority: P1)

Usuario esqueceu a senha e precisa recuperar acesso sem contato humano. Na tela
de login, clica em "Esqueci minha senha", fornece o email, e recebe um link
temporario por email para definir nova senha.

**Why this priority**: Sem esta story, usuarios bloqueados precisam contactar
suporte — o custo operacional e o tempo de resolucao sao inaceitaveis.

**Independent Test**: Do estado "usuario com conta ativa", solicitar reset e
verificar que o email chega com link funcional em <2 minutos.

**Acceptance Scenarios**:

1. **Given** email pertence a conta ativa, **When** usuario solicita reset, **Then** sistema envia email com link valido por 1h
2. **Given** email nao cadastrado, **When** usuario solicita reset, **Then** sistema retorna mensagem neutra (sem revelar se email existe)
3. **Given** 3 solicitacoes em menos de 5 minutos, **When** usuario solicita a 4a, **Then** sistema bloqueia temporariamente

---

### User Story 2 - Consume reset link (Priority: P1)

Usuario recebe o email, clica no link, e define nova senha. Apos sucesso, todas
as sessoes ativas sao invalidadas.

**Why this priority**: Sem esta story, o link enviado na P1 nao tem efeito.
P1 tambem pois e o fechamento do fluxo critico.

**Independent Test**: Do estado "link valido emitido", acessar o link e
redefinir senha — login subsequente com senha nova deve funcionar.

**Acceptance Scenarios**:

1. **Given** link valido e nao expirado, **When** usuario define senha que atende politica, **Then** senha e atualizada e todas sessoes sao invalidadas
2. **Given** link expirado, **When** usuario tenta acessar, **Then** sistema pede novo link
3. **Given** link ja utilizado, **When** usuario tenta reutilizar, **Then** sistema rejeita

---

### Edge Cases

- What happens when o servico de email esta indisponivel no momento da solicitacao?
- How does system handle concurrent requests do mesmo usuario em janelas diferentes?
- What happens when a conta foi deletada entre a emissao do link e a tentativa de uso?

## Requirements

### Functional Requirements

- **FR-001**: System MUST enviar link unico e temporario (expira em 1h) para o email cadastrado
- **FR-002**: System MUST invalidar link apos primeiro uso bem-sucedido
- **FR-003**: Users MUST be able to definir nova senha via link sem autenticacao previa
- **FR-004**: System MUST invalidar todas sessoes ativas apos reset concluido
- **FR-005**: System MUST aplicar rate limiting por email (max 3 solicitacoes por 5 minutos)
- **FR-006**: System MUST retornar mensagem neutra para emails nao cadastrados (sem vazar existencia)

### Key Entities

- **Reset Token**: representa um pedido de reset valido — associado a um usuario, com validade, estado (ativo/consumido/expirado) e rastreabilidade de uso
- **User**: conta existente cujo acesso pode ser recuperado

## Success Criteria

### Measurable Outcomes

- **SC-001**: 95% dos usuarios que solicitam reset conseguem acessar em <5 minutos
- **SC-002**: Tempo entre solicitacao e recebimento do email e <2 minutos em p95
- **SC-003**: Volume de tickets de suporte relacionados a "senha esquecida" reduz em 80% apos lancamento
- **SC-004**: Zero vazamentos de existencia de email por resposta diferente entre email cadastrado e nao cadastrado

---

## Por que esta spec e boa

1. **User stories independentes e testaveis**: P1 de solicitar e P1 de consumir podem ser validadas separadamente
2. **Success criteria mensuraveis e technology-agnostic**: "5 minutos", "2 minutos p95", "80% de reducao" — nenhuma mencao a framework ou banco
3. **Edge cases pensados**: indisponibilidade de servico externo, concorrencia, deletion race
4. **Rate limiting e seguranca mencionados no QUE, nao no COMO**: diz "aplicar rate limiting", nao "Redis com sliding window"
5. **Sem detalhes de implementacao**: nao menciona "bcrypt", "JWT", "Redis" — isso vai para o `/plan`
