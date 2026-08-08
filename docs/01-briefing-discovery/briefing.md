# Project Briefing: Claude Code Toolkit

**Data**: 2026-04-20
**Status**: Draft
**Versao**: 1.0

---

## 1. Visao e Proposito

**O que e**: Toolkit de skills, hooks e insights para [Claude Code](https://claude.ai/code), composto por um pipeline Spec-Driven Development (SDD) completo (briefing → constitution → specify → clarify → plan → checklist → create-tasks → analyze → execute-task → review-task), skills complementares (advisor, bugfix, owasp-security, etc.) e skills especificas por linguagem (Go, .NET).

**Problema que resolve**: garantir que o fluxo de desenvolvimento seja documentado desde o d0, que o codigo seja escrito com qualidade, e que futuras correcoes sejam especificacoes validadas — nao edicoes improvisadas.

**Proposta de valor**: escrever software de qualidade em par com o Claude Code. Cada decisao vira artefato rastreavel (spec, plan, task, ADR); cada correcao passa pelo mesmo rigor que a implementacao original.

## 2. Usuarios e Stakeholders

| Ator | Papel | Acoes Principais |
|------|-------|-----------------|
| Desenvolvedor solo | Uso individual do pipeline completo | Briefing → spec → plan → tasks → implementacao, tudo na mesma cabeca |
| Arquiteto de software | Inicia o processo e handoff para time | Conduz briefing/constitution/specify/plan; gera tasks.md como entregavel acionavel |
| Desenvolvedor do time | Executa tarefas geradas pelo arquiteto | Consome tasks.md com `execute-task`, seguindo specs e plans que ja passaram por analyze |

**Caracteristica-chave**: etapas do pipeline SDD sao **independentemente executaveis**. Um membro do time pode rodar `execute-task 3.2` sem ter participado do briefing, porque todos os artefatos upstream sao materializados e rastreaveis.

**Stakeholders de decisao**: autor do toolkit (Joao Zanon / jot) decide direcao e escopo. Projeto sob licenca MIT, contribuicoes aceitas caso-a-caso (sem processo formal).

## 3. Escopo

### MVP (entregue)

1. Pipeline SDD completo — 10 skills encadeaveis
2. 7 skills complementares independentes do pipeline (advisor, bugfix, image-generation, apply-insights, owasp-security, validate-documentation, validate-docs-rendered)
3. Language-related skills e hooks para Go e .NET
4. Documentacao padronizada — 9 niveis (01-briefing-discovery ... 09-entregaveis)
5. CHANGELOG + SemVer + README com anatomia de skill

### Pos-MVP (curto prazo)

1. Aprofundar skills existentes — novas skills complementares, refinamentos do pipeline, mais hooks
2. Expandir linguagens — alem de Go/.NET (candidatos naturais: Python, TypeScript, Rust)
3. Infraestrutura de qualidade — suite de testes para scripts shell ja em progresso (`docs/specs/shell-scripts-tests/`)

### Pos-MVP (medio prazo)

1. Integracoes externas — MCP servers custom, workflow com ferramentas de gestao (Linear, GitHub Issues, Jira)

### Fora de Escopo

- **Telemetria/observabilidade de uso das skills** — decisao de simplicidade e privacidade; skills rodam no contexto local do usuario sem coletar metricas remotas.
- **CONTRIBUTING.md formal e templates de PR/issue** — contribuicoes sao aceitas caso-a-caso via README; processo formal nao esta planejado.

## 4. Prioridades e Trade-offs

**Ordem de prioridade**: Qualidade > Profundidade > Adocao.

**Decisoes explicitas**:

- Preferencia por profundidade (tornar o pipeline SDD mais maduro e reduzir retrabalho em projetos reais) em vez de metrica de adocao externa (stars, forks).
- Simplicidade de manutencao sobre features observacionais — rejeita telemetria mesmo sabendo que daria sinais valiosos.
- POSIX sh puro para scripts deterministicos (sem dependencia de bash, bats, ou toolchain externo) — decisao registrada e aplicada (ex: bug recente em `metrics.sh` e a suite de testes em construcao preservam essa linha).
- Distribuicao via `cp -r` manual em vez de package manager — mantem o projeto livre de framework de instalacao.

## 5. Restricoes

| Restricao | Valor | Notas |
|-----------|-------|-------|
| Prazo | Sem prazo externo rigido | Ritmo profissional dedicado, nao hobby irregular |
| Equipe | Autor solo com tempo dedicado | Parte da rotina de trabalho do autor, nao side-project de fim-de-semana |
| Budget | Sem orcamento financeiro | Custo e tempo do autor; zero infraestrutura paga |
| Tecnica | Markdown + POSIX sh apenas | Sem linguagens de programacao tradicionais no core; scripts auxiliares sao POSIX compativeis |

## 6. Stack Tecnica

| Camada | Tecnologia | Justificativa |
|--------|-----------|---------------|
| Conteudo das skills | Markdown (`SKILL.md`) | Formato canonico que o Claude Code consome; portavel, versionavel, diffavel |
| Scripts deterministicos | POSIX sh (`#!/bin/sh`) | Zero dependencia externa; roda em qualquer ambiente POSIX sem setup |
| Configuracao por skill | `config.json` | Parametros que variam entre projetos (dominios, caminhos, niveis de criticidade) |
| Templates | Markdown | Consumidos pelas skills sob demanda (progressive disclosure) |
| Distribuicao | `cp -r` manual | Instala em `~/.claude/skills/` ou `{projeto}/.claude/skills/`; sem package manager |
| Versionamento | SemVer + CHANGELOG.md | Comunicacao clara de breaking changes (ex: 2.0.0 renomeou `insights` → `apply-insights`) |

## 7. Qualidade e Padroes

**Padroes adotados**:

- **Spec-Driven Development** como principio estrutural — toda feature nao-trivial passa pelo pipeline completo (briefing → spec → plan → tasks → execute); nada e implementado sem artefato rastreavel.
- **Progressive disclosure em skills** — `SKILL.md` enxuto como ponto de entrada; templates, exemplos e referencias vivem em subpastas carregadas sob demanda.
- **Gotchas obrigatorios** — cada SKILL.md documenta armadilhas conhecidas; visto pelo autor como o conteudo mais valioso de uma skill.
- **Description como trigger condition** — descricoes sao escritas no formato "Use quando X / NAO use quando Y", nao como resumo.
- **Nomenclatura canonica** — UC-{DOMINIO}-{NNN}, ADR-{NNN}, RN{NN}, CT{NN}, E{NNN}; dominios definidos por projeto via `config.json`, nao hardcoded globalmente.
- **Testes para scripts shell** — em construcao no momento deste briefing (`docs/specs/shell-scripts-tests/`), motivada por bug de producao em `metrics.sh`; formaliza o padrao "nao commita sem teste para script novo".

**Compliance**: nenhum regime regulatorio aplicavel (toolkit de dev, sem dados de usuario final).

## 8. Visao de Futuro

**6 meses**:

- Suite de testes `shell-scripts-tests` concluida e todos os scripts POSIX cobertos.
- Pelo menos uma linguagem nova alem de Go/.NET (avaliar TypeScript ou Python primeiro conforme demanda).
- Refinamentos no pipeline SDD baseados em uso real — skills mais afiadas em gotchas e defaults.

**12 meses**:

- Pipeline SDD mais maduro, com reducao **mensuravel** de retrabalho nos projetos reais onde o toolkit e aplicado — a metrica concreta ainda precisa ser definida (ver Itens a Definir).
- Eventualmente inicio de camada de integracoes externas (MCP servers, bridges com Linear/GitHub Issues/Jira) — marcada como medio prazo, sem compromisso de 12 meses firme.

**Riscos conhecidos**:

- **Erosao silenciosa por falta de telemetria** — escolha explicita de nao coletar uso, com custo: bugs e gaps so chegam se o autor os encontrar no seu proprio uso ou se alguem reportar.
- **Drift entre versao instalada e versao do repositorio** — distribuicao por `cp -r` significa que usuarios podem estar em versoes arbitrariamente antigas sem saber.
- **Acoplamento a evolucao do Claude Code** — mudancas no comportamento do harness podem invalidar skills; nao ha teste de integracao com o Claude Code em si.
- **Metrica de "reducao de retrabalho" indefinida** — sem criterio operacional, a ambicao de 12 meses nao e verificavel.

---

## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Definicao operacional de "reducao de retrabalho" — o que conta, como medir | Visao de Futuro / Qualidade | Medio (ambicao de 12 meses fica nao-verificavel sem isso) |
| Criterio de selecao da proxima linguagem alem de Go/.NET (Python? TypeScript? Rust?) | Escopo Pos-MVP curto prazo | Baixo (decisao reversivel, pode esperar ate ter demanda concreta) |
| Estrategia para lidar com drift de versao instalada (notificar? forcar check?) | Riscos | Baixo hoje, sobe conforme base de usuarios cresce |

---

**Proximo passo recomendado**: `/constitution` para derivar principios de governanca a partir deste briefing (particularmente relevantes: profundidade > adocao, POSIX puro, progressive disclosure como padrao estrutural, SDD como principio nao-negociavel).
