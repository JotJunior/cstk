# Análise — separação entre core toolkit e skills de domínio

> **Status:** documento de decisão (P1.2 do backlog de correção).
> **Pedido original:** avaliar separar o toolkit genérico das "skills de
> domínio Fotus" (dimensionamento solar fotovoltaico: `dimensionar`,
> `montar-kit`; relatório `relatorio-descontos-fotus`; `fotus-predict`).
> **NÃO executar a separação** — apenas recomendar.

## TL;DR

**A premissa do pedido está desatualizada para o estado atual deste
repositório.** Nenhuma das skills Fotus citadas existe aqui. O acoplamento de
domínio real e remanescente é **outro**: 6 das 7 skills em
`language-related/go/skills/` codificam o projeto-cliente **GOB**. Essas skills,
porém, **já estão estruturalmente isoladas** (namespace `language-related/`,
fora dos perfis default `sdd`/`complementary`). 

**Recomendação: NÃO separar em repositório/marketplace distinto agora.** O custo
de fragmentar instalação, release e CI supera o ganho. Em vez disso, aplicar duas
ações baratas (limpeza de referências incidentais + parametrização do vocabulário
"GOB"). Plano faseado abaixo.

## 1. O que realmente existe (auditoria)

Inventário factual de skills no repositório (via `find . -name SKILL.md`):

| Grupo | Local | Qtd | Natureza |
|-------|-------|-----|----------|
| Globais | `global/skills/` | 23 | Genéricas (pipeline SDD, cstk, orquestrador, utilidades) |
| Go | `language-related/go/skills/` | 7 | Específicas de stack Go — 6 codificam "GOB" |
| .NET | `language-related/dotnet/skills/` | 8 | Específicas de stack .NET — **já deprecated** (v3.12.0, remoção v4.0.0) |

### 1.1 As skills Fotus não existem

Busca por `fotus|dimensionar|montar-kit|relatorio-descontos|fotus-predict|fotovolt`
em todo o repositório retorna **apenas dois falsos/incidentais**:

- `global/skills/model-selector/examples/good-opus.md` — casa por substring
  (`subdimensionar`), não é skill.
- `docs/01-briefing-discovery/agente-00c-analise-licoes-aprendidas.md` — menção
  narrativa "DPO Fotus" num texto de lições aprendidas.

Conclusão: as skills de dimensionamento solar **ou nunca estiveram neste repo, ou
já foram extraídas**. A separação que o pedido teme já está feita para o domínio
Fotus. Não há o que separar.

### 1.2 O acoplamento de domínio real: GOB nas skills Go

6 de 7 skills Go nomeiam explicitamente o projeto-cliente **GOB** na
`description` e no corpo (ex.: *"add a full CRUD vertical slice ... to an existing
**GOB** Go microservice"*):

```
go-add-entity  go-add-migration  go-add-test
go-add-consumer  go-review-pr  go-review-service
```

(A sétima, `commit`, é genérica.) Isso é exatamente o anti-padrão que o
`## Contribuindo` do README proíbe para skills **globais** ("não nomear clientes,
empresas ou projetos específicos") — mas as skills Go vivem em
`language-related/`, um namespace que o próprio toolkit trata como "stack-specific,
opt-in", não como core genérico.

## 2. Já existe separação estrutural (e ela funciona)

O acoplamento de domínio **não está misturado no core**. Há três camadas de
isolamento já implementadas:

1. **Namespace de diretório.** Core em `global/skills/`; stack-specific em
   `language-related/{go,dotnet}/`.
2. **Perfis de instalação** (`scripts/profiles.txt.in` → `cli/lib/profiles.sh`).
   Os perfis default `sdd` e `complementary` **não incluem** nenhuma skill
   `language-related`. Elas só entram via `cstk install --profile all` ou
   perfis `language-*` auto-derivados pelo `build-release.sh`.
3. **Escopo de instalação.** Hooks de `language-*` só são instalados em
   `--scope project` (omitidos em global, com aviso — FR-009c).

Ou seja: quem instala o pipeline SDD **não recebe** as skills Go/.NET por padrão.
A "diluição de proposta de valor" que o pedido descreve já é mitigada no ponto de
entrega.

## 3. Custo × benefício de separar em plugins/marketplaces distintos

| Eixo | Separar (repo/plugin à parte) | Manter (status atual) |
|------|-------------------------------|------------------------|
| **Instalação** | Quebra o one-liner `curl \| sh`; usuário Go passa a gerenciar 2 fontes. Manifest do cstk teria de cruzar origens. | `cstk install --profile all/go` já resolve num comando. |
| **Release/empacotamento** | `build-release.sh` deixa de auto-derivar `all:*`/`language-*:*`; precisa de 2 pipelines + 2 tags + 2 changelogs. | Um tarball, uma release, derivação automática. |
| **CI/testes** | Suite (1090+ scenarios) e o harness 1:1 teriam de ser fatiados ou duplicados. | Uma suite, um `--check-coverage`. |
| **Manutenção** | Bus factor piora (mais superfícies p/ um mantenedor único — ver P1.3). | Uma árvore. |
| **Ganho real** | Marginal: o isolamento por perfil já entrega o efeito "não polui o pipeline SDD". | — |

O benefício pretendido (não poluir quem quer só o SDD) **já é obtido** pelos
perfis. O custo de separação fisíca é alto e recai sobre um mantenedor único.

## 4. Recomendação

**Não separar em repositório/marketplace distinto.** Em vez disso, duas ações
faseadas de baixo custo que resolvem o acoplamento residual real:

### Fase 1 — Higiene incidental (baixo esforço, sem breaking change)
- Generalizar as 2 menções incidentais a Fotus (exemplo do model-selector e a
  lição aprendida), se incomodarem — são ilustrativas, não funcionais.
- Documentar explicitamente no README/CONTRIBUTING que `language-related/` é a
  "zona stack-specific opt-in", deixando claro que pode conter acoplamento de
  stack (não de cliente).

### Fase 2 — Desacoplar "GOB" das skills Go (médio esforço)
- Parametrizar o vocabulário "GOB" nas 6 skills Go: trocar referências fixas ao
  projeto por um placeholder (ex.: `<service>`/`config.json` por projeto), igual
  ao que a regra de generalização do README pede para skills globais.
- Alternativa, se as skills Go forem inerentemente GOB-específicas e não
  generalizáveis: movê-las para `<projeto-GOB>/.claude/skills/` (como
  `create-report` em v3.12.0) e manter aqui só o que é Go-genérico (`commit`).
- Qualquer das duas é **MAJOR** se mudar nomes/contratos públicos (ver política
  de versionamento).

### Fase 3 — Reavaliar .NET na v4.0.0
- As 8 skills `dotnet-*` já estão marcadas para remoção em v4.0.0. A remoção
  resolve metade da superfície "stack-specific" sem trabalho extra de separação.

## 5. Decisão pendente do mantenedor

- [ ] Aprovar **manter junto** (recomendado) + executar Fase 1.
- [ ] Aprovar Fase 2 (desacoplar/extrair GOB) — e, se sim, parametrizar vs extrair.
- [ ] Recusar e separar mesmo assim (assumindo o custo de 2 pipelines).

> Este documento corrige a premissa do pedido (skills Fotus inexistentes) e
> aterrissa a decisão no acoplamento real (GOB/Go). Nenhuma mudança de código foi
> feita — aguarda aprovação.
