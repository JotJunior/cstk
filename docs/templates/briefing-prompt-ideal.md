# Prompt Ideal — Briefing do agente-00c

> **Para que serve**: este é um template preenchível que você cola como argumento
> de `/agente-00c` (ou `/briefing`). Ele mapeia 1:1 com as seções que a skill
> `briefing` consolida, mais os campos extras que uma **arquitetura complexa**
> exige a jusante (`specify` → `plan` → `create-tasks` → `checklist`).
>
> **Por que funciona**: a entrevista do briefing tem regra explícita — "se o
> usuário responder várias dimensões de uma vez, registre TODAS e pule as
> perguntas equivalentes". Preenchendo os slots na ordem que a síntese espera,
> o agente vai direto à validação fazendo **zero ou quase zero perguntas**.
>
> **Como podar**: cada bloco marcado `‹CORTAR p/ entrega simples›` é opcional.
> Veja o "Guia de poda" no fim. As §1–§5 são o mínimo irredutível.

---

## Como usar

```
/agente-00c <cole o template preenchido abaixo>
```

(ou `/briefing <...>` para rodar só o discovery isolado). Blocos deixados como
`[a definir]` viram pendências em "Itens a Definir" — não quebram o fluxo.

---

## Template (copie a partir daqui)

```markdown
# Briefing — [NOME DO PROJETO]

## 1. Visão e Propósito
- **O que é** (2-3 frases, linguagem leiga): ...
- **Problema central que resolve**: ...
- **Proposta de valor / por que alguém usaria**: ...

## 2. Usuários e Stakeholders
Liste papéis + o que cada um faz. INCLUA sistemas externos como atores.
- [Papel humano]: [ações principais]
- [Papel humano]: [ações principais]
- [Sistema externo / integração] (ator não-humano): [o que troca com o sistema]
- **Quem decide prioridades / aprova entregas**: ...

## 3. Escopo
**MVP (essencial — sem isso não faz sentido):**
1. [feature] — [1 linha do que faz]
2. [feature] — ...
3. ...

**Pós-MVP (desejável, pode esperar):**
1. ...

**Fora de escopo (explicitamente NÃO faremos):**
- ...

## 4. Prioridades e Trade-offs
- **Ordem de prioridade** (ex.: Qualidade > Segurança > UX > Velocidade > Escopo): ...
- **Trade-offs aceitos conscientemente**: ...

## 5. Restrições
- **Prazo**: [deadline ou "flexível"]
- **Equipe**: [tamanho + perfil/senioridade]
- **Budget / custo**: [limite, free-tier, cloud específica...]
- **Técnica obrigatória/proibida**: [ex.: "tem que ser Go", "sem vendor lock-in", "on-prem"]

## 6. Stack e Arquitetura  ‹núcleo para arquitetura complexa›
**Stack por camada:**
- Backend: ...
- Frontend: ...
- Banco(s) de dados: ... [um por serviço? compartilhado?]
- Infra / deploy: [Docker, K8s, serverless, VPS...]
- Mensageria / eventos: [RabbitMQ, Kafka, SQS, "nenhuma"]

**‹CORTAR p/ entrega simples› Decomposição em serviços/módulos:**
| Serviço/Módulo | Responsabilidade (bounded context) | Dono dos dados | Comunicação (sync REST/gRPC ou async eventos) |
|---|---|---|---|
| [auth-service] | ... | [tabelas X] | ... |
| [orders-service] | ... | ... | ... |

**‹CORTAR p/ entrega simples› Integrações externas (mapeamento):**
| Integração | Direção (in/out/bidi) | Protocolo | Dado trocado | Criticidade |
|---|---|---|---|---|
| [Stripe] | out | REST/webhook | pagamentos | alta |

**‹CORTAR p/ entrega simples› Decisões de arquitetura já tomadas (viram ADRs):**
- [ex.: "API gateway na borda", "event sourcing em pedidos", "BFF por canal"]

## 7. Qualidade e Padrões (NFRs)
Marque o que se aplica e quantifique quando der:
- [ ] **Testes rigorosos** (TDD / cobertura alvo: __% / CI-CD)
- [ ] **Segurança** (OWASP, authn/authz: [OAuth2.1/JWT/...], auditoria)
- [ ] **Observabilidade** (logs estruturados, métricas, tracing distribuído, alertas)
- [ ] **Performance** (SLO: latência p95 __ms, throughput __req/s, concorrência __)
- [ ] **Acessibilidade / i18n** (WCAG, idiomas, dispositivos)
- [ ] **Documentação** (ADRs, specs, OpenAPI)
- **Compliance aplicável**: [LGPD / GDPR / PCI-DSS / nenhum]
- **Disponibilidade alvo**: [ex.: 99.9% / best-effort]

## 8. Visão de Futuro
- **6 meses**: ...
- **12 meses**: ...
- **Escala esperada** (usuários / volume de dados / RPS): ...
- **Riscos conhecidos**: ...

## 9. Setup / Bootstrap  ‹só se multi-workspace›
- **Monorepo / multi-workspace?** [sim/não] → tipo: [npm workspaces / go.work / cargo workspace]
- **Workspaces e suas deps canônicas** (para gerar `scripts/bootstrap-deps.sh`):
  - [services/auth]: express, zod, jsonwebtoken...
  - [services/web]: react, react-query...
```

---

## Por que os blocos extras (além das 7 dimensões da skill)

A skill `briefing` tem 7 dimensões, mas para **arquitetura complexa** os
artefatos a jusante sofrem se faltar:

| Bloco extra | Quem consome | Sintoma se faltar |
|---|---|---|
| Decomposição em serviços (§6) | `plan` §Project Structure | plano monolítico ou bounded contexts errados |
| Mapeamento de integrações (§6) | `specify` (tabelas de mapeamento são obrigatórias) | UCs sem contrato de dados → `clarify` estoura perguntas |
| NFRs quantificados (§7) | `checklist` (quality gate) e `constitution` | princípios vagos, critérios de aceite não-testáveis |
| Bootstrap multi-workspace (§9) | pré-flight do `briefing` | N bloqueios humanos `npm install` no meio da pipeline (FR-018 não instala sozinho) |

## Guia de poda para entregas simples

Para um projeto single-service / CRUD, apague nesta ordem:

1. **§9** inteira (se não é monorepo).
2. As 3 sub-tabelas `‹CORTAR›` da **§6** — deixe só "Stack por camada".
3. Colapse a **§7** marcando 2-3 checkboxes sem quantificar.

As **§1–§5** são o mínimo irredutível — com elas o briefing já fecha sozinho.

---

## Mapeamento template → seções do briefing salvo

Para auditoria (o briefing final é salvo em `docs/01-briefing-discovery/briefing.md`):

| Seção deste prompt | Seção do `briefing.md` gerado |
|---|---|
| §1 Visão e Propósito | 1. Visão e Propósito |
| §2 Usuários e Stakeholders | 2. Usuários e Stakeholders |
| §3 Escopo | 3. Escopo (MVP / Pós-MVP / Fora) |
| §4 Prioridades e Trade-offs | 4. Prioridades e Trade-offs |
| §5 Restrições | 5. Restrições |
| §6 Stack e Arquitetura | 6. Stack Técnica (+ insumo p/ ADRs) |
| §7 Qualidade e Padrões | 7. Qualidade e Padrões |
| §8 Visão de Futuro | 8. Visão de Futuro |
| §9 Setup / Bootstrap | seção "Setup / Bootstrap" + `scripts/bootstrap-deps.sh` |
