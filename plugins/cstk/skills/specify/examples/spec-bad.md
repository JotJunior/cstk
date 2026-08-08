# Example: Common Anti-Patterns in Specs

Este exemplo mostra erros tipicos em specs, anotados com correcao sugerida.

---

## Anti-padrao 1: Detalhes de implementacao na spec

### Errado

> **FR-001**: System MUST hash passwords with bcrypt (cost factor 12) and store
> in PostgreSQL `users.password_hash` column.

**Por que esta errado**: "bcrypt", "cost factor 12" e "PostgreSQL column" sao
detalhes de implementacao. A spec responde QUE e POR QUE; COMO vai para `/plan`.

### Correto

> **FR-001**: System MUST store credentials using industry-standard one-way
> hashing with adaptive cost.

A decisao de algoritmo (bcrypt vs Argon2), parametros, e coluna do banco vai
para o plano tecnico.

---

## Anti-padrao 2: Success criteria com jargao tecnico

### Errado

- **SC-001**: API response time under 200ms
- **SC-002**: Database handles 1000 TPS
- **SC-003**: React components render efficiently with <50ms paint time

**Por que esta errado**: "API", "TPS", "React", "paint time" — nada disso e
verificavel pela perspectiva do usuario. Se voce trocar React por Vue, o
sistema ainda precisa ser bom para o usuario.

### Correto

- **SC-001**: 95% dos cliques retornam resultado visivel em <1s
- **SC-002**: Sistema suporta 10.000 usuarios concorrentes sem degradacao percebida
- **SC-003**: Busca retorna resultados em <2 segundos mesmo com 1M de registros

---

## Anti-padrao 3: User stories que dependem umas das outras

### Errado

> **Story P1**: Usuario cria conta
> **Story P2**: Usuario configura perfil (requer Story P1 completa)
> **Story P3**: Usuario busca outros usuarios (requer Story P2 completa)

**Por que esta errado**: Se so implementar P1, nao ha MVP — nao da para logar
ou usar o sistema. Stories deveriam ser camadas de valor independente.

### Correto

Reestruturar para que cada story entregue valor standalone:

> **Story P1**: Login + uso minimo da feature principal (entrega valor ao usuario)
> **Story P2**: Personalizacao de perfil (melhora UX, mas P1 ja e usavel)
> **Story P3**: Descoberta social (agrega mas nao bloqueia uso basico)

---

## Anti-padrao 4: Adjetivos vagos sem quantificacao

### Errado

> **FR-005**: System MUST be fast and responsive
> **FR-006**: System MUST be secure
> **FR-007**: UI MUST be intuitive

**Por que esta errado**: "Fast", "secure", "intuitive" — quem mede? Como
testa? Tres pessoas vao discordar da definicao.

### Correto

> **FR-005**: System MUST responder a acoes de usuario em <500ms em 99% dos casos
> **FR-006**: System MUST seguir OWASP Top 10:2025 como baseline (em checklist separado)
> **FR-007**: 80% dos novos usuarios MUST completar onboarding sem ajuda (medido em teste de usabilidade)

---

## Anti-padrao 5: Excesso de `[NEEDS CLARIFICATION]`

### Errado

Spec com 8 marcadores `[NEEDS CLARIFICATION]` espalhados — "qual provider de
email?", "qual TTL do token?", "quanto tempo guardar logs?", "mobile ou web?",
etc.

**Por que esta errado**: Mais de 3 marcadores indica que a spec deveria voltar
ao briefing antes de escrever. A skill limita exatamente por isso.

### Correto

- Priorizar: escopo > seguranca > UX > tech
- Manter so os 3 mais criticos como `[NEEDS CLARIFICATION]`
- Para o resto, usar defaults informados e documentar a suposicao:
  > FR-009: System MUST reter logs por 90 dias (*default padrao indústria; ajustar em /plan se compliance específico exigir*)

---

## Anti-padrao 6: Secoes vazias com "N/A"

### Errado

> ## Key Entities
>
> N/A

**Por que esta errado**: "N/A" e ruido no documento e confunde skills
downstream (`/plan`, `/create-tasks`).

### Correto

Remover a secao inteira. Se a feature nao envolve entidades de dados, o
header nao precisa existir.
