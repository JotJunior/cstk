# Catalogo de Dicas — Fixture Minimal para Testes
#
# Contem 2 skills: specify (2 entradas) e plan (2 entradas).
# Nao contem: clarify (para testar skill sem dicas).
#
# Fixture para tests/cstk/test_show-tip.sh

---
skill: specify
category: uso
text: Use /specify para converter descricao em SDD com user stories, FRs e criterios de sucesso.
---
Exemplo de uso basico:

```
/specify
Nova feature: endpoint de exportacao de relatorios em CSV.
```

O specify gera user stories, requisitos funcionais e criterios de sucesso.

---
skill: specify
category: gotcha
text: specify opera sobre descricao em linguagem natural — nao use para refinar spec existente (use clarify).
---
Exemplo de gotcha:

  # Errado: spec.md ja existe, usar clarify
  /specify

  # Correto: feature nova
  /specify
  Quero um sistema de notificacoes push.

---
skill: plan
category: uso
text: Use /plan para gerar plano tecnico (arquitetura, modelo de dados, contratos de API) a partir de uma spec.
---
Apos specify gerar spec.md:

```
/plan
```

Gera plan.md, research.md, data-model.md e contratos de API.

---
skill: plan
category: gotcha
text: plan requer spec.md existente — rode /specify primeiro se estiver comecar do zero.
---
Exemplo de gotcha:

  # Sem spec.md, plan vai falhar ou gerar saida vazia
  /plan

  # Correto: primeiro specify, depois plan
  /specify && /plan

---
