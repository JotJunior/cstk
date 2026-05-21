# Licoes da Implementacao do Agente-00C

> **Escopo**: licoes aprendidas durante a IMPLEMENTACAO das 8 fases (1-8)
> via Claude Code. Distinto de `lessons-from-first-run.md` (a ser escrito
> apos primeira execucao real do `/agente-00c` em projeto-alvo, FASE 9.3).
>
> **Quem escreveu**: agente Claude executando a propria spec, em sessao
> Claude Code Opus 4.7. Operador (jot) supervisionou direcao mas nao
> editou conteudo individual de cada fase.
>
> **Data**: 2026-05-06
> **Total da implementacao**: 487 cenarios de teste, 14 scripts shell
> POSIX, 6 prompts de agente/command, ~21k linhas de codigo + docs.

---

## Licao 1: jq tem armadilha sutil em `f | g(. as $x | ...)`

### O que aconteceu

Em `drift.sh` (FASE 5.4), a funcao `matches_aspecto` falhou silenciosamente
porque o `.` dentro de `contains(. | ascii_downcase)` referenciava `$t`
(input do pipe), nao o item iterado por `any($aspectos[]; ...)`.

```jq
# BUGADO — `.` em contains() refere-se a $t, nao ao aspecto
any($aspectos[]; ($t | contains(. | ascii_downcase)))

# CORRETO — captura aspecto explicitamente antes do pipe
any($aspectos[]; . as $a | $t | contains($a | ascii_downcase))
```

Resultado: drift_count sempre `0` mesmo com aspectos ausentes —
deteccao de `desvio_de_finalidade` quebrada silenciosamente.

### Por que e relevante para o toolkit

Outras skills (constitution, analyze, plan) que processam JSON
estruturado podem ter o mesmo bug latente. O sintoma e classico de
"feature funciona em smoke superficial mas falha sob carga real".

### Proposta de mudanca em skill especifica

**Skill afetada**: nenhuma especifica, mas todo SKILL.md que orienta
escrita de jq deveria ter um aviso:

> **Gotcha jq**: dentro de `f | g(...)`, o `.` dentro de g referencia o
> output de f, NAO o contexto upstream. Para iterar sobre uma lista e
> usar o item dentro de um pipe, capture explicitamente:
> `any(LIST[]; . as $x | $pipe | use($x))`.

**Formato proposto**: adicionar secao "Gotchas comuns em jq" em
`global/skills/plan/SKILL.md` (skill que mais provavelmente gera codigo
jq) ou criar `global/skills/jq-patterns/SKILL.md` autonomo.

**Avaliacao contra constitution do toolkit**: PASS — adicao informativa,
sem breaking change.

---

## Licao 2: Symlinks no macOS exigem dupla resolucao em path validation

### O que aconteceu

Em `path-guard.sh` (FASE 6.1), a primeira versao bloqueava `/etc` mas
nao bloqueava `~/.ssh` quando passado via `HOME` custom apontando para
tmpdir. Causa: zonas proibidas como `${HOME}/.ssh` estavam em formato
canonico, mas o path resolvido do projeto-alvo era `/private/var/...`,
fora do match.

Tambem: incluir `/private` puro como zona proibida quebrou tests reais
porque `mktemp -d` usa `/private/var/folders/...` como root de
tmpdirs em macOS.

### Solucao

1. Listar zonas tanto na forma canonica (`/etc`, `${HOME}/.ssh`) quanto
   na resolvida (`/private/etc`).
2. **Resolver** cada zona via `realpath` antes de comparar (defesa T2
   contra symlinks adversariais que apontam para zona proibida via
   `HOME` custom).
3. NAO incluir `/private` ou `/var` puros — listar subdirs especificos
   (`/private/var/log`, `/private/var/db`, etc) sem incluir
   `/private/var/folders` (mktemp legitimo).

### Por que e relevante para o toolkit

Skills que validam paths (potencialmente `owasp-security`, ou um futuro
`security-audit`) podem ter o mesmo gap em macOS. CI tipicamente roda
em Linux onde `/etc` resolve para `/etc` (sem `/private` prefixo), mas
operadores em darwin descobrem o bug em runtime.

### Proposta de mudanca

**Skill afetada**: `owasp-security`.

Adicionar checklist item:

> **Path validation deve cobrir BSD/macOS**: paths como `/etc`, `/var`,
> `/usr` resolvem para `/private/etc`, etc no macOS via `realpath`.
> Listas de zonas proibidas precisam incluir AMBAS as formas, OU
> resolver dinamicamente via `realpath` antes de comparar.

**Formato proposto**: adicionar regra no checklist OWASP A03 (Injection)
ou A05 (Security Misconfiguration) — path traversal com symlinks.

**Avaliacao contra constitution do toolkit**: PASS — refinamento de
skill existente, adiciona valor sem mudar interface.

---

## Licao 3: "Sem skill formal" no plan.md gerou ambiguidade sobre ONDE colocar scripts auxiliares

### O que aconteceu

O `plan.md` da feature (Phase 1) afirma:

> **Forma**: slash command + agente custom orquestrador + agentes
> especializados — **sem skill formal**, pois progressive disclosure
> cabe nas instrucoes do agente custom.

Mas FASES 2-8 produziram 14 scripts POSIX que precisavam ser
distribuidos via `cstk install`. O mecanismo `cstk install` so suporta
3 destinos: `global/skills/*`, `global/commands/*`, `global/agents/*`.

Decisao em FASE 2: criar skill **interna** `agente-00c-runtime/` com
`SKILL.md` marcando "NAO user-invocavel — biblioteca interna do
agente-00C". Funciona, mas viola o espirito de "sem skill formal".

### Por que e relevante para o toolkit

Outras features que **precisam** de scripts auxiliares mas tem mesma
discomfort com "skill virou pacote" tambem precisariam de ajuste.

### Proposta de mudanca

**Opcao A (skill marker)**: documentar em `global/skills/SKILL-FORMAT.md`
(ou no proprio formato da skill) que skills com `description` comecando
em `(internal — usado por outros agentes)` sao automaticamente
filtradas no Skill auto-trigger do Claude Code (nao aparecem como
sugestoes user-facing). 

**Opcao B (extender install)**: extender `cstk install` para suportar
um quarto kind, `lib/`, destinado a `~/.claude/lib/<NOME>/scripts/`
para bibliotecas que nao sao user-invocaveis nem agente nem command.

**Opcao C (manter)**: manter status quo — skills internas sao convencao
documentada, marcador via `description` e suficiente. Sem mudanca de
codigo.

**Avaliacao contra constitution do toolkit**: 
- Opcao A: PASS — adicao convencional, sem breaking.
- Opcao B: PASS com cuidado — extensao de manifest schema; SemVer MINOR.
- Opcao C: PASS — sem mudanca.

**Recomendacao**: Opcao C por simplicidade, com nota em
`docs/constitution.md` reconhecendo que skills internas sao padrao
aceitavel.

---

## Licao 4: Cobertura por convencao `tests/test_<n>.sh` exige disciplina mas previne drift

### O que aconteceu

A regra do toolkit (CLAUDE.md §"Como testar scripts shell") estabelece
mapping 1-para-1 entre scripts POSIX e tests:

```
global/skills/<X>/scripts/<n>.sh -> tests/test_<n>.sh
cli/lib/<n>.sh                   -> tests/cstk/test_<n>.sh
```

`tests/run.sh --check-coverage` falha se algum script nao tem teste
correspondente.

Durante implementacao, isso forçou criar 14 testes para os 14 scripts
da skill `agente-00c-runtime/`. Inicialmente parecia overhead — alguns
scripts sao "trivialmente testaveis" e questionei a necessidade.

### Por que e relevante (e por que eu estava errado)

3 bugs reais foram descobertos APENAS porque os testes obrigatoriamente
existem:

1. **drift.sh `matches_aspecto`** — bug jq descrito em Licao 1.
2. **path-guard.sh `/private` blanket** — descrito em Licao 2.
3. **cycles.sh tick design** — primeira versao tentava inferir mudanca
   de etapa via `.etapa_corrente` do estado; falhava em test
   `scenario_tick_progress_made_zera` porque o teste setava etapa antes
   de tick-ar. Refatorei para `reset` explicito (operador-controlled).

Sem a regra de cobertura forçada, esses 3 bugs entrariam em producao.

### Proposta de mudanca em skill especifica

**Skill afetada**: nenhuma — a propria regra do toolkit ja existe.

Mas: a skill `apply-insights` poderia incluir uma "best practice" no
playbook indicando que `--check-coverage` exit non-zero como politica
e provavelmente o investimento de teste com maior ROI em projetos
shell-heavy.

**Formato proposto**: adicionar regra em
`global/skills/apply-insights/playbook.md` (se existir):

> **Insight**: cobertura forçada por convencao (script.sh ↔ test_script.sh)
> com gate em CI captura bugs sutis que smoke superficial nao pega.
> Investimento amortizado em 3+ deteccoes ao longo da implementacao.

**Avaliacao contra constitution do toolkit**: PASS.

---

## Licao 5: Slash commands + agentes custom como "interface", scripts POSIX como "engine" funciona bem

### O que aconteceu

A arquitetura final do agente-00C tem 3 camadas:

1. **Slash commands** (`/agente-00c`, `/agente-00c-resume`, `/agente-00c-abort`) — interface user-facing, parsing de args + invocacao do orquestrador.
2. **Agentes custom** (`agente-00c-orchestrator`, `clarify-asker`, `clarify-answerer`) — comportamento dependente de LLM (raciocinio, geracao, decisao via score).
3. **Scripts POSIX** (`agente-00c-runtime/scripts/*.sh`) — primitivas determinacas (mutacao de state, validacoes, integracao com gh/git).

Cada camada testavel independentemente:
- Slash commands testados manualmente (FASE 9.1 — shell-simulation)
- Agentes testados via execucao real (FASE 9.3 — pendente)
- Scripts testados unitariamente (487 cenarios em `tests/`)

### Por que e relevante

Esse padrao (interface/comportamento/engine) generaliza para outras
features que misturam LLM + automacao deterministica.

### Proposta

**Skill afetada**: nenhuma criada, mas valeria criar:

`global/skills/sdd-architecture-patterns/SKILL.md` — uma skill que
sugere essa estratificacao quando spec menciona "agente automatizado +
scripts auxiliares + slash commands". 

Conteudo:
- Quando aplicar a estratificacao 3-camadas
- Como mapear FRs para cada camada
- Padrao de teste por camada

**Avaliacao contra constitution**: PASS — adicao prescritiva, sem
breaking.

---

## Sintese para FASE 9.4.2 (proposta de mudancas em skills)

| FR proposto | Skill afetada | Tipo | Esforco |
|-------------|---------------|------|---------|
| FR-LESSON-01 | (gotchas jq em todo SKILL.md ou jq-patterns/) | Documentacao | Baixo |
| FR-LESSON-02 | owasp-security | Documentacao + checklist | Medio |
| FR-LESSON-03 | constitution.md do toolkit + global/skills convention | Politica | Baixo |
| FR-LESSON-04 | apply-insights/playbook.md | Documentacao | Baixo |
| FR-LESSON-05 | sdd-architecture-patterns/ (nova skill) | Nova skill | Alto |

**Issues no toolkit**: nao foram abertas automaticamente — operador
(jot) decide quais lessons priorizar e abre via /agente-00c-suggestions
ou manual em sessao dedicada (FASE 9.4.4).

## Sintese para FASE 9.4.3 (amendment da constitution?)

**Avaliacao**: nao requer amendment.

Lessons 1-5 sao todas refinamentos prescritivos ou novas skills,
NAO mudancas de principio. A constitution v1.1.0 do toolkit (com
carve-out para jq, POSIX sh, skills sem deps obrigatorias) ja cobre
o suficiente.

**Possivel adicao informativa** (NAO amendment, NAO breaking): nota
de rodape em "Principio II — POSIX sh puro" reconhecendo que skills
internas (consumidas por outros agentes, nao user-invocaveis) sao
padrao aceitavel via marcador no `description`.

---

## O que esta licao NAO cobre

Estas sao licoes da IMPLEMENTACAO, nao da EXECUCAO REAL. Quando o
agente-00C for invocado pela primeira vez em projeto-alvo (FASE 9.3),
licoes adicionais surgirao:

- Como o LLM se comporta com a heuristica score 0..3 na pratica.
- Quanto tempo realmente leva uma onda tipica.
- Quao acionavel e o relatorio para o operador.
- Quantos bloqueios humanos sao gerados em uma execucao tipica.
- Se o operador gosta do formato do relatorio ou pede mudancas.

Essas vivem em `lessons-from-first-run.md` (a ser criado pos-FASE 9.3).
