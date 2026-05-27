# Catalogo de Dicas — Fixture Audit OK para Testes
#
# Contem apenas 1 skill "mock-skill-a" com 2 entradas (uso+gotcha).
# Para o teste de audit, o universo de skills sera sobrescrito via
# CSTK_REPO_ROOT apontando para um diretorio de fixture com apenas
# essa skill.

---
skill: mock-skill-a
category: uso
text: Use mock-skill-a para validar cobertura do catalogo.
---
Exemplo de uso:

```
/mock-skill-a
```

---
skill: mock-skill-a
category: gotcha
text: Nao use mock-skill-a em producao — e uma skill de teste.
---
Cuidado:

  # Errado em producao
  /mock-skill-a

  # Apenas em testes
  sh tests/cstk/test_show-tip.sh

---
