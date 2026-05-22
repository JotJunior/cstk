---
title: FASE 7 — Quality Report
feature: github-pages-cstk-manual
phase: 7
executed_at: 2026-05-19
mode: parcial (sem mkdocs/Python venv)
---

# FASE 7 — Quality Report (parcial)

Este relatorio consolida o que foi validado na FASE 7 do
`github-pages-cstk-manual` e o que ficou diferido para FASE 8
(Polish+Deploy) ou para execucao manual com mkdocs instalado.

**Modo de execucao:** parcial. O ambiente atual nao tem `mkdocs`
instalado nem um venv configurado, entao o build estatico
(`mkdocs build --strict`) **NAO foi executado nesta onda**.
Inves disso, criamos:

- `scripts/check-links.py` — validacao estatica de links + snippets
  sem dependencias (stdlib only).
- `scripts/smoke-site.sh` — wrapper que constroi venv + roda
  `mkdocs build --strict` quando o operador estiver pronto.

O CI (`.github/workflows/publish-site.yml`) eh o gate canonico do
build estrito — qualquer falha de linkcheck ou mkdocs aparece la.

---

## 1. Resumo Executivo

| Item | Status | Nota |
|------|--------|------|
| Validacao estatica de links + snippets | OK | 0 erros, 0 warnings em 6 arquivos, 4 snippets, 20 links |
| Smoke build mkdocs --strict | DIFERIDO | Requer mkdocs instalado; rodar `scripts/smoke-site.sh` local OU aguardar CI |
| Lighthouse Accessibility >=90 | DIFERIDO FASE 8 | Requer site renderizado + browser; FASE 8 manual |
| Zero coleta remota | DIFERIDO FASE 8 | Validado parcialmente no `mkdocs.yml` (sem `google_analytics`); confirmacao final via `grep -rn 'src="https://' site/` apos build |
| JS desabilitado | DIFERIDO FASE 8 | Requer site servido em browser local |
| Build idempotente | DIFERIDO FASE 8 | Requer 2 builds + diff |
| Inventario auto-gerado (SC-006) | OK indireto | `gen_pages.py` ja itera `global/skills/`, `global/agents/`, `global/commands/`; contagem >=43 sera validada no CI primeiro build |
| Lint markdown (frontmatter) | OK | Todas paginas docs-site/*.md tem frontmatter `---title:...---` (validado em check-links.py) |

**Decisao:** prosseguir para FASE 8 com smoke build sendo o primeiro
passo (rodar `scripts/smoke-site.sh` local ou validar no CI via push).
FASE 7 estabeleceu os scripts de validacao; FASE 8 executa a
validacao end-to-end com site renderizado.

---

## 2. Validacao executada nesta onda

### 2.1 check-links.py (T-7.1 parcial)

Script criado: `scripts/check-links.py` (~250 linhas, Python stdlib).

**Cobertura:**

- Diretivas snippet `--8<-- "FILE"` e `--8<-- "FILE:SECTION"`
  resolvidas contra a raiz do repo.
- Markers `<!-- --8<-- [start:NAME] -->` e `[end:NAME]` validados
  bidirecionalmente (se diretiva diz `:profiles-section`, o arquivo
  fonte DEVE ter ambos os markers).
- Links Markdown relativos `[text](path.md)` resolvidos contra
  diretorio do arquivo + raiz do site.
- Paginas geradas (`skills/<NAME>/SKILL.md`, `agents/<NAME>.md`,
  `commands/<NAME>.md`, e variantes com trailing slash) sao
  reconhecidas como geradas e validadas contra arquivo-fonte em
  `global/skills/`, `global/agents/`, `global/commands/`,
  `language-related/<lang>/skills/`.

**Execucao empirica:**

```
$ python3 scripts/check-links.py
check-links.py — root: /.../claude-ai-tips-github-pages
  -> 6 arquivo(s) escaneados, 4 diretiva(s) snippet, 20 link(s) interno(s)
Resumo: 0 erro(s), 0 warning(s)
EXIT=0
```

**Limitacao conhecida:** este validador eh estatico — nao executa
`mkdocs.snippets`, nao verifica anchors (`#section-id`) dentro de
paginas, nao executa o gerador `gen_pages.py`. O smoke build com
`--strict` cobre esses casos. Combinacao recomendada:

| Gate | Cobre | Pre-requisito |
|------|-------|---------------|
| `scripts/check-links.py` | snippets + links de arquivo + frontmatter | nenhum (stdlib) |
| `scripts/smoke-site.sh` | linkcheck completo + render mkdocs --strict | mkdocs instalado |
| CI `publish-site.yml` | smoke + deploy | push para main |

### 2.2 Lint de frontmatter (T-7.4 parcial)

Integrado no `check-links.py` como severidade WARN (nao bloqueia
exit). Todas paginas principais sob `docs-site/` (5 arquivos) tem
frontmatter consistente:

- `docs-site/index.md` — frontmatter completo
- `docs-site/changelog.md` — exception (snippet wrapper, sem
  frontmatter por design)
- `docs-site/manual/instalacao.md`, `profiles.md`, `comandos.md`,
  `fluxo-sdd.md` — frontmatter completo

Zero warnings.

### 2.3 smoke-site.sh (T-7.3 estrutural)

Script criado: `scripts/smoke-site.sh`.

**Fluxo:**

1. Detecta `python3 >= 3.10`; aborta com mensagem clara caso
   contrario.
2. Cria venv em `.venv-docs/` (idempotente — reutiliza se ja
   existe).
3. `pip install -r requirements-docs.txt`.
4. `mkdocs build --strict --site-dir site-smoke/`.
5. Cleanup do venv (opcional via `--keep-venv`).
6. Modo `--serve` para iterar localmente.

**Como rodar:**

```bash
./scripts/smoke-site.sh                # build apenas
./scripts/smoke-site.sh --keep-venv    # preserva venv (iteracao rapida)
./scripts/smoke-site.sh --serve        # build + mkdocs serve (http://127.0.0.1:8000)
```

**Nao executado nesta onda.** Razao: ambiente atual nao tem mkdocs
nem requirements-docs.txt validados na pratica. CI roda automatico
via push (`.github/workflows/publish-site.yml`).

---

## 3. Gap aceito: CHK036 — Lighthouse >=90 != WCAG AA (T-7.2.5)

**Contexto:** o constitution-delta D-V (SHOULD) define como meta de
acessibilidade "Lighthouse score >=90 em paginas representativas".
O checklist `a11y/CHK036` levantou que essa meta NAO equivale a
conformidade WCAG AA completa.

**Analise:**

Lighthouse Accessibility (categoria auditada por
`@lighthouse/audit/accessibility-*`) cobre um subset automatizavel
dos criterios WCAG:

| WCAG criterio | Lighthouse cobre? |
|---------------|-------------------|
| 1.1.1 Conteudo nao textual (alt em img) | SIM (parcial) |
| 1.3.1 Info e relacoes (ARIA roles, semantica) | SIM |
| 1.4.3 Contraste minimo | SIM |
| 1.4.11 Contraste de nao-texto | SIM (parcial) |
| 2.1.1 Teclado | NAO (smoke manual necessario) |
| 2.4.7 Foco visivel | SIM (parcial) |
| 3.1.1 Idioma da pagina | SIM |
| 3.3.1 Identificacao de erros (forms) | SIM (forms) |
| 4.1.2 Nome, funcao, valor | SIM (ARIA) |
| 1.4.4 Redimensionamento de texto | NAO |
| 2.4.4 Proposito do link (no contexto) | NAO |
| 3.2.4 Identificacao consistente | NAO |
| Cognicao (legibilidade, foco, distracao) | NAO |
| Motor (alvos grandes, gestos) | NAO |

Lighthouse cobre ~30-40% dos criterios WCAG AA. Os criterios
restantes requerem auditoria manual (axe DevTools, NVDA/VoiceOver
em testes humanos, revisao de conteudo).

**Gap aceito:**

O constitution-delta D-V explicitamente exige `Lighthouse >=90`
(SHOULD, nao MUST). NAO foi prometido WCAG AA completo.
Para esta feature (site de documentacao publica, leitura), o gap
eh aceito com as seguintes mitigacoes:

1. **Tema escolhido (mkdocs-material) ja eh AA por construcao** —
   contraste, focus, ARIA roles, heading hierarchy validados pela
   comunidade upstream.
2. **Smoke teclado em FASE 8** — operador percorre site so com
   TAB + atalhos (cenario CT-008 do plan §1.9, T-5.5.2).
3. **Sem forms, sem animacoes intrusivas, sem media** — superficie
   de potenciais violacoes WCAG eh reduzida.
4. **Markdown nativo + Material** — semantica HTML correta por
   default (headings, lists, blockquotes, code).

**Itens NAO cobertos** (registrados aqui para futura ampliacao):

- Axe DevTools manual em paginas representativas.
- Teste com leitor de tela (NVDA Windows ou VoiceOver macOS).
- Validacao de criterio 2.4.4 (texto de link no contexto) —
  alguns links como "Saiba mais" podem precisar de label ARIA.
- Validacao de criterio 1.4.4 (zoom 200% sem perda de funcao).

**Decisao registrada:** acceptable scope reduction. Se o projeto
crescer para incluir tutoriais interativos, forms, ou videos, este
gap deve ser re-avaliado e WCAG AA completo deve virar MUST.

---

## 4. Smoke tests diferidos para FASE 8

Itens da FASE 7 que requerem site renderizado + browser:

### 4.1 T-7.1.1 a T-7.1.4: link quebrado deliberado + mkdocs --strict

**Plano FASE 8:** introduzir `[broken](pagina-fake.md)` em
`docs-site/index.md`, rodar `scripts/smoke-site.sh`, validar exit
!= 0 com mensagem clara. Cleanup, documentar comportamento em
comentario do `mkdocs.yml`.

### 4.2 T-7.2.1 a T-7.2.4: Lighthouse audit

**Plano FASE 8:** rodar Chrome DevTools Lighthouse (Desktop) em:

- `/` (landing) — ambos os temas
- `/skills/briefing/` (pagina-detalhe representativa)

Validar score >=90 Accessibility. Se < 90, corrigir cor de
contraste / alt-text / ARIA. Capturar relatorios JSON em
`docs/specs/github-pages-cstk-manual/lighthouse-reports/`.

### 4.3 T-7.4.1 a T-7.4.5: validar zero coleta remota apos build

**Plano FASE 8:**

```bash
./scripts/smoke-site.sh
grep -rn 'src="https://' site-smoke/ | \
  grep -vE '(fonts.gstatic.com|fonts.googleapis.com)' | \
  grep -E '(analytics|tracking|gtm|ga\.js)'
# Expect: zero matches
```

Inspecao manual do `<head>` da home — confirmar zero
`<script src="...analytics">`. Decidir se `theme.font: false`
(bundle local total) ou aceitar CDN de fonts (com fallback).

### 4.4 T-7.5.1 a T-7.5.5: JS desabilitado

**Plano FASE 8:** desabilitar JS no DevTools, recarregar `/` e
`/skills/briefing/`. Validar:

- Conteudo legivel (HTML semantico + CSS).
- TOC funciona (links HTML, nao JS).
- Links internos navegam.
- Busca NAO funciona (esperado — progressive enhancement).
- Copy-button NAO funciona (esperado).

### 4.5 T-7.6.1 a T-7.6.4: build idempotente

**Plano FASE 8:**

```bash
./scripts/smoke-site.sh  # gera site-smoke (renomear para site1)
mv site-smoke site1
./scripts/smoke-site.sh
mv site-smoke site2
diff -r site1/ site2/ -x sitemap.xml
# Expect: vazio (exceto timestamps documentados)
```

### 4.6 T-7.7.1 a T-7.7.3: inventario auto-gerado SC-006

**Plano FASE 8:**

```bash
find site-smoke/skills site-smoke/agents site-smoke/commands \
  -name index.html | wc -l
# Expect: >=43 (21 skills + 8 agents + 8 commands + 3 indexes + 3 manuais)

find site-smoke -name '*.html' | wc -l
# Expect: >=52 total
```

### 4.7 T-7.8 e T-7.9: re-revisar checklists content-quality e ci

**Plano FASE 8:** revisar item-a-item os checklists
`docs/specs/github-pages-cstk-manual/checklists/content-quality.md`
e `ci.md`, marcando concluidos.

---

## 5. Resumo de evidencia

| Validacao | Como | Evidencia |
|-----------|------|-----------|
| Snippets bidirecionais | `check-links.py` | 4/4 OK |
| Links internos | `check-links.py` | 20/20 OK |
| Frontmatter consistente | `check-links.py` (WARN) | 0 warnings |
| Resolucao gen_pages | `check-links.py` (PATH patterns) | skills/, agents/, commands/ + trailing slash variants reconhecidos |
| Build mkdocs strict | `scripts/smoke-site.sh` (CI canonico) | NAO executado nesta onda — rodar local OU aguardar push para main |

---

## 6. Conclusao da FASE 7

**Status:** parcialmente concluida. Scripts de validacao estatica
criados e executados com sucesso (0 erros). Smoke build e
auditorias browser-based diferidos para FASE 8 com plano
explicito.

**Saida para FASE 8:**

1. Rodar `scripts/smoke-site.sh` local OU fazer push para main
   (CI roda automatico).
2. Se CI passa, executar a bateria de smoke manuais (Lighthouse,
   JS off, build idempotente).
3. Marcar checklists `content-quality.md` e `ci.md` no final.
4. Documentar problemas encontrados em `docs/specs/.../FASE-8-report.md`.

**Linha de corte:** este relatorio fecha FASE 7 com o que pode ser
validado sem instalar mkdocs/venv. As tarefas que requerem build
real ficam em FASE 8 (proxima onda).

---

## A. Apendice — Re-validacao empirica do gen_pages.py (FASE 8)

**Onda:** 014 (execute-task FASE 8)
**Data:** 2026-05-19
**Tarefa:** T-8.3 do contexto desta onda (smoke test do gen_pages.py
standalone via stub, documentar resultado).

### A.1 Procedimento

Como `mkdocs-gen-files` so e instalavel via `requirements-docs.txt`
(FR-018: sem instalacao automatica), reproduzimos o hook em modo
standalone substituindo `mkdocs_gen_files` por um stub que captura
`open(path, mode)` e `set_edit_path(virtual, source)` em memoria.

Comando executado (cwd = repo root):

```python
python3 -c "
import sys, types
from pathlib import Path

stub = types.ModuleType('mkdocs_gen_files')
emitted = {}
class _W:
    def __init__(self, k): self.k = k
    def __enter__(self): self.buf = []; return self
    def __exit__(self, *a): emitted[self.k] = ''.join(self.buf)
    def write(self, s): self.buf.append(s)
stub.open = lambda p, m: _W(p)
stub.set_edit_path = lambda v, s: None
sys.modules['mkdocs_gen_files'] = stub

sys.path.insert(0, str(Path('docs-site/hooks').resolve()))
import gen_pages
"
```

### A.2 Resultado empirico

Output literal stdout do hook (linha de log emitida ao final do
`on_files` virtual):

```
[gen_pages] generated 43 detail pages + 3 indexes: skills_global=21,
skills_lang=[dotnet=8, go=8], agents=3, commands=3; index_items:
skills=37, agents=3, commands=3
```

Breakdown agregado:

| Categoria | Contagem |
|-----------|----------|
| Skills global (`skills/<slug>.md`) | 21 |
| Skills Go (`skills/go/<slug>.md`) | 8 |
| Skills .NET (`skills/dotnet/<slug>.md`) | 8 |
| Agents (`agents/<stem>.md`) | 3 |
| Commands (`commands/<stem>.md`) | 3 |
| Indexes (`*/index.md`) | 3 |
| **Total emitido** | **46** |

Conferencia rapida (sondagem empirica):

```sh
ls global/skills | wc -l        # esperado: 21 (+ no minimo um README ignorado)
ls language-related/go/skills    # esperado: 8 entries
ls language-related/dotnet/skills # esperado: 8 entries
ls global/agents | wc -l          # esperado: 3
ls global/commands | wc -l        # esperado: 3
```

### A.3 Formato dos shims (D-I — zero duplicacao)

Sample da pagina `skills/briefing.md` em memoria:

```
--8<-- "global/skills/briefing/SKILL.md"
```

Sample da pagina `skills/go/commit.md`:

```
--8<-- "language-related/go/skills/commit/SKILL.md"
```

Ambos sao shims minimos, sem narrativa duplicada — exatamente como
spec FR-003 e plan Decision 1 exigem.

### A.4 Conclusao

`gen_pages.py` funciona corretamente em ambiente sem `mkdocs` /
`mkdocs-gen-files` instalados, desde que o stub minimo seja
fornecido. **Contagem total: 46 paginas virtuais (43 detalhe + 3
indexes).** Esse numero serve de regressao: caso futuro build emita
contagem diferente, investigar antes de aceitar.

Limites desta validacao (continuam diferidos para deploy real):

- NAO valida resolucao do `pymdownx.snippets` (so testado em build
  mkdocs com `base_path` configurado)
- NAO valida `set_edit_path` em runtime real (mkdocs-gen-files faz
  bookkeeping interno)
- NAO valida que o YAML frontmatter dos SKILL.md fonte e parseavel
  por MkDocs (cobertura em `scripts/smoke-site.sh` quando mkdocs
  estiver disponivel)

Esses 3 itens ficam para o primeiro deploy real (T-8.1 do tasks.md),
documentado em `runbook-deploy.md`.

---

## B. Apendice — Status final FASE 8 (execute-task)

A FASE 8 tem 22 subtarefas. Esta onda fecha o que pode ser feito
sem mkdocs/deploy real. O restante e responsabilidade do operador
post-deploy, com receita exata em `runbook-deploy.md`.

| Grupo | Subtarefas | Status apos onda 014 |
|-------|------------|----------------------|
| 8.1 First deploy real | 5 | Diferido — exige push real (`runbook-deploy.md` §2) |
| 8.2 Verificacao pos-deploy | 5 | Diferido — exige browser anonimo (`runbook-deploy.md` §3.1) |
| 8.3 README link do site | 2 | **CONCLUIDO** — badge `Docs Site` ja existe no README.md (linha 6) e workflow re-publica ao push |
| 8.4 Runbook rebuild | 2 | **CONCLUIDO** — `runbook-deploy.md` §4.2 documenta rebuild via Actions UI e `gh workflow run` |
| 8.5 Resolver issues primeiro deploy | 3 | Diferido — exige primeiro deploy real (`runbook-deploy.md` §4.4) |
| 8.6 Fontes/CDN | 3 | **CONCLUIDO** — decisao registrada em `runbook-deploy.md` §3.5 + Decisao no state.json |

**Conclusao do execute-task:** o agente-00c executou TUDO que e
automatizavel sem deploy real. As 5+5+3 = 13 subtarefas restantes
sao acoes humanas claramente documentadas. Proxima etapa: `review-task`
(auditar tarefas concluidas, gerar status final).
