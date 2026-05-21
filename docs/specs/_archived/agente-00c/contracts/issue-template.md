# Contract: Template de Issue no Toolkit GitHub

Issues abertas automaticamente em `JotJunior/claude-ai-tips` quando o 00C
identifica bug **impeditivo** em skill global durante uma execucao
(FR-021, User Story 5).

Issues sao a **unica excecao autorizada** ao Principio V (blast radius
confinado) para comunicacao externa via `gh`. Nao substituem a Sugestao
local (`agente-00c-suggestions.md`) — complementam.

---

## Formato de invocacao

```
gh issue create \
  --repo JotJunior/claude-ai-tips \
  --title "[agente-00C] Bug em <skill>: <resumo-de-uma-linha>" \
  --label "agente-00c,bug,skill-global" \
  --body "$(cat <<'EOF'
<corpo gerado segundo template abaixo>
EOF
)"
```

Labels: `agente-00c`, `bug`, `skill-global`. Se as labels nao existirem no
repo, criar antes (apenas na primeira execucao do experimento).

---

## Template do corpo da issue

```markdown
> Issue aberta automaticamente pelo agente-00C durante execucao
> `<execucao_id>` em `<timestamp>`.

## Skill afetada

**Nome**: `<skill-name>`
**Caminho instalado**: `~/.claude/skills/<skill-name>/`
**Versao** (se identificavel via SKILL.md frontmatter): `<versao ou "nao informada">`

## Diagnostico

[Descricao do bug em 3-5 paragrafos. O que foi observado, em que etapa da
pipeline, qual era o comportamento esperado vs o observado.]

## Reproducao

A execucao do agente-00C que detectou o bug:

- ID: `<execucao_id>`
- Projeto-alvo: `<projeto_alvo_descricao_anonimizada_se_necessario>`
- Etapa: `<etapa_corrente>`
- Onda: `<onda_id>`

Decisoes relevantes que evidenciam o bug:

- Decisao `<dec-NNN>`: [resumo curto]
- Decisao `<dec-NNN>`: [resumo curto]

## Por que e impeditivo

[Explicar por que o bug bloqueou progresso da pipeline e nao pode ser
contornado dentro dos limites de constitution. Ex: "skill clarify gerou 8
perguntas com opcoes contraditorias entre si — a etapa 'plan' nao pode ser
iniciada sem resolucao manual".]

## Proposta de correcao

[Mudanca concreta sugerida para a skill. Pode incluir trecho de SKILL.md
ou template afetado. Manter dentro de 200-400 palavras.]

## Anexos

- Path do relatorio (no projeto-alvo, NAO anexado a esta issue):
  `<projeto-alvo>/.claude/agente-00c-report.md`
- Path da sugestao detalhada:
  `<projeto-alvo>/.claude/agente-00c-suggestions.md#<sug-NNN>`
- Path do estado no momento da deteccao (backup):
  `<projeto-alvo>/.claude/agente-00c-state/state-history/<onda-id>-<timestamp>.json`

> Estes anexos vivem no maquina do operador (joao). Esta issue **nao
> uploada** o relatorio nem o estado — alinhado com Principio IV do toolkit
> (zero coleta remota).

---

🤖 Aberta automaticamente pelo agente-00C
```

---

## Regras

- **Tamanho maximo do corpo**: 4000 caracteres (limite pratico para
  legibilidade da issue). Se ultrapassar, truncar a secao "Diagnostico" e
  citar onde ler o detalhe completo (relatorio local).
- **Anonimizacao**: se a descricao do projeto-alvo contem dados sensiveis
  (nome de cliente, segredos, etc), substituir por placeholder antes de
  enviar. O orquestrador detecta heuristicamente: presenca de dominio
  conhecido em `descricao_curta`, presenca de string formato similar a token
  (>=20 chars alfanumericos seguidos), etc.
- **Idempotencia**: nao abrir issue duplicada. Antes de abrir, verificar via
  `gh issue list --search "agente-00C <skill-name> <hash-do-diagnostico>"`
  se ja ha issue aberta com mesmo hash. Hash = primeiros 8 chars do SHA1
  do `diagnostico` normalizado.
- **Falha de criacao**: se `gh issue create` falhar (rate limit, sem
  internet, repo privado etc), registrar a tentativa em
  `agente-00c-suggestions.md` com flag `issue_aberta: ERRO_<motivo>` e
  prosseguir com aborto da execucao (mesmo motivo: bug em skill global e
  impeditivo).
- **Privacidade**: nao incluir conteudo de `.env`, secrets, tokens, ou
  credenciais. Filtro automatico: regex match contra padroes comuns de
  token/secret antes do envio.

---

## Exemplo de issue gerada

**Titulo**:
```
[agente-00C] Bug em clarify: opcoes contraditorias entre perguntas geradas
```

**Corpo** (resumido):
```markdown
> Issue aberta automaticamente pelo agente-00C durante execucao
> `exec-2026-05-05T14-23-00Z-agente-00c-poc-foo` em `2026-05-05T15:42:11Z`.

## Skill afetada

**Nome**: `clarify`
**Caminho instalado**: `~/.claude/skills/clarify/`

## Diagnostico

Skill clarify gerou 8 perguntas para spec.md gerada na etapa anterior. As
perguntas 3 e 5 oferecem opcoes mutuamente contraditorias: pergunta 3 lista
"PostgreSQL" como opcao recomendada, pergunta 5 lista "MongoDB" como opcao
recomendada — ambas para o mesmo escopo de "armazenamento principal de
dados". Sem cross-check entre perguntas, o clarify-answerer escolhe ambas
sem perceber a contradicao, e a etapa plan recebe contexto incoerente.

## Por que e impeditivo

A etapa plan nao pode iniciar com escolhas contraditorias — o orquestrador
ja consumiu 1 retro-execucao do orcamento (limite 2 — Principio IV
constitution 00C) tentando resolver, sem sucesso. Terceira tentativa
violaria o limite.

## Proposta de correcao

Adicionar etapa de "consistency check entre perguntas" no fluxo da skill
clarify, ANTES de retornar perguntas ao orquestrador. Sugestao concreta:
secao "ETAPA 4.5: CROSS-CHECK" no SKILL.md.

🤖 Aberta automaticamente pelo agente-00C
```
