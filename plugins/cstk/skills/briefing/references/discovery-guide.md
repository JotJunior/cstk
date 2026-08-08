# Discovery Guide: 7 Dimensoes da Entrevista

Roteiro detalhado para a etapa de entrevista do `briefing`. Cada dimensao tem 1-2
perguntas. Perguntas sao feitas **UMA POR VEZ**, aguardando resposta.

---

## DIMENSAO 1: Visao e Proposito

**O que captura**: A essencia do projeto — o que e, por que existe, qual problema resolve.

**Pergunta 1.1 — Elevator Pitch**:

```markdown
## Pergunta 1: Visao do Projeto

Descreva o projeto em 2-3 frases, como se estivesse explicando para alguem
que nunca ouviu falar dele.

**O que preciso saber**:
- O que o projeto FAZ
- Qual PROBLEMA resolve
- Para QUEM

**Exemplo**: "Um sistema de gestao de pedidos que permite lojistas acompanharem
vendas em tempo real e emitirem notas automaticamente. Resolve o problema de
visibilidade operacional para pequenos comercios."

Responda com sua descricao livre.
```

---

## DIMENSAO 2: Usuarios e Stakeholders

**O que captura**: Quem usa o sistema e quem toma decisoes.

**Pergunta 2.1 — Atores Principais**:

```markdown
## Pergunta 2: Usuarios e Atores

Quem sao os USUARIOS do sistema? Liste os tipos de usuario (personas/papeis)
e o que cada um faz.

**Exemplos de papeis**: admin, operador, cliente final, parceiro, sistema externo

**Formato sugerido**:
- [Papel]: [O que faz no sistema]
- [Papel]: [O que faz no sistema]

Responda listando os papeis, ou descreva livremente.
```

---

## DIMENSAO 3: Escopo e Prioridades

**O que captura**: O que esta dentro e fora do escopo, e o que e mais importante.

**Pergunta 3.1 — Features Core vs Nice-to-Have**:

```markdown
## Pergunta 3: Escopo e Prioridades

Quais sao as funcionalidades ESSENCIAIS (sem elas o projeto nao faz sentido)
vs funcionalidades DESEJAVEIS (agregam valor mas podem esperar)?

**Formato sugerido**:

**Essenciais (MVP)**:
1. [Feature]
2. [Feature]

**Desejaveis (pos-MVP)**:
1. [Feature]
2. [Feature]

Responda listando ou descrevendo livremente.
```

**Pergunta 3.2 — Trade-offs** (se projeto nao-trivial):

```markdown
## Pergunta 4: Trade-offs

Quando precisar escolher, qual sua prioridade?

| Opcao | Descricao |
|-------|-----------|
| A | **Velocidade de entrega** — Lancar rapido, iterar depois |
| B | **Qualidade e robustez** — Fazer bem feito, mesmo que demore |
| C | **Escopo completo** — Entregar tudo planejado, ajustando prazo |
| D | **Experiencia do usuario** — UX impecavel, mesmo sacrificando features |

Responda com a letra (ou ordene por prioridade, ex: "B > D > A > C").
```

---

## DIMENSAO 4: Restricoes

**O que captura**: Limites reais do projeto — tempo, equipe, orcamento, tech.

**Pergunta 4.1 — Restricoes do Projeto**:

```markdown
## Pergunta 5: Restricoes

Quais restricoes o projeto tem? Responda o que souber:

- **Prazo**: Ha deadline? (ex: "lancar em 3 meses", "sem prazo fixo")
- **Equipe**: Quantas pessoas? Qual experiencia? (ex: "1 dev fullstack senior")
- **Budget**: Ha limitacao de custo? (ex: "usar apenas servicos free-tier")
- **Tecnica**: Alguma tecnologia obrigatoria ou proibida? (ex: "tem que ser em Go", "sem vendor lock-in")

Responda o que for relevante — pode pular itens que nao se aplicam.
```

---

## DIMENSAO 5: Contexto Tecnico

**O que captura**: Stack, infraestrutura, integracoes.

**Pergunta 5.1 — Stack e Infraestrutura**:

Pular se ja inferido de arquivos do projeto (go.mod, package.json, etc.).

```markdown
## Pergunta 6: Stack Tecnica

Qual a stack tecnica do projeto? Se ainda nao decidiu, descreva preferencias.

**Categorias**:
- **Backend**: (ex: Go, Node.js, Python, Java)
- **Frontend**: (ex: React, Vue, mobile nativo, nenhum)
- **Banco de dados**: (ex: PostgreSQL, MongoDB, SQLite)
- **Infraestrutura**: (ex: Docker, Kubernetes, serverless, VPS)
- **Integracoes externas**: (ex: Stripe, SendGrid, APIs de terceiros)

Responda o que souber. Se preferir que eu sugira, diga "sugira baseado no projeto".
```

---

## DIMENSAO 6: Qualidade e Padroes

**O que captura**: Expectativas de qualidade, compliance, observabilidade.

**Pergunta 6.1 — Padroes de Qualidade**:

```markdown
## Pergunta 7: Qualidade e Padroes

Quais padroes de qualidade sao importantes para o projeto?

| Opcao | Descricao |
|-------|-----------|
| A | **Testes rigorosos** — TDD, cobertura alta, CI/CD |
| B | **Seguranca primeiro** — OWASP, auditoria, compliance (LGPD/GDPR) |
| C | **Observabilidade** — Logging, metricas, alertas, tracing |
| D | **Performance** — Baixa latencia, alta concorrencia |
| E | **Acessibilidade** — WCAG, i18n, suporte a multiplos dispositivos |
| F | **Documentacao** — Codigo documentado, ADRs, specs completos |

Selecione todas que se aplicam (ex: "A, B, F") ou descreva suas expectativas.
```

---

## DIMENSAO 7: Visao de Futuro

**O que captura**: Direcao de longo prazo, escalabilidade, evolucao.

**Pergunta 7.1 — Evolucao**:

```markdown
## Pergunta 8: Visao de Futuro

Como voce ve o projeto daqui a 6-12 meses?

- Vai crescer em **usuarios**? (escala)
- Vai crescer em **features**? (escopo)
- Vai precisar de **mais desenvolvedores**? (equipe)
- Ha planos de **monetizacao** ou **mudanca de modelo**?

Descreva livremente o que imagina para o futuro do projeto.
```

---

## Regras da Entrevista

1. **Uma pergunta por vez** — aguardar resposta antes de avancar
2. **Adaptar ao contexto** — pular perguntas cujas respostas ja sao conhecidas
3. **Aceitar respostas livres** — nao forcar formato; extrair informacao do texto
4. **Aceitar "nao sei"** — marcar como `[a definir]` e seguir em frente
5. **Aceitar atalhos** — se usuario responder varias dimensoes de uma vez, registrar todas
6. **Maximo 10 perguntas** — se usuario disser "chega", "pronto" ou "prossiga", encerrar
7. **Nao julgar respostas** — registrar fielmente; criticas sao trabalho do `/advisor`
8. **Confirmar inferencias** — quando preencher algo inferido, confirmar brevemente
