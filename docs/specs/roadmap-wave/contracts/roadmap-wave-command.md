# Contrato: `/roadmap-wave` + `parallel-launch.sh resolve-offer`

**Feature**: `roadmap-wave` | **Date**: 2026-08-18

> **[PROPOSTA — a validar na implementacao]**: TUDO neste documento
> descreve interface que ainda NAO existe. Os helpers consumidos
> (`roadmap-frontier.sh`, `parallel-launch.sh emit|check-tmux`) sao
> REAIS e estao contratados em
> `docs/specs/roadmap-parallel-launch/contracts/` — este contrato nao os
> redefine, so os consome.

---

## 1. Superficie do command `/roadmap-wave`

```
/roadmap-wave [--projeto-alvo-path <path>] [--roadmap <path>]
              [--specs-dir <dir>] [--max <N>] [--yes]
              [--coordinator-name <name>]
```

| Argumento | Obrigatorio | Default | Destino |
|---|---|---|---|
| `--projeto-alvo-path <path>` | nao | diretorio de trabalho corrente | `roadmap-frontier.sh --exclude-active-from-repo` + `parallel-launch.sh emit --repo` |
| `--roadmap <path>` | nao | `docs/roadmap.md` (default do helper) | `roadmap-frontier.sh --roadmap` (passthrough) |
| `--specs-dir <dir>` | nao | `docs/specs` (default do helper) | `roadmap-frontier.sh --specs-dir` (passthrough) |
| `--max <N>` | nao | `2` | `resolve-offer --max` (FR-013) |
| `--yes` | nao | ausente ⇒ nao lancar | confirmacao explicita em modo nao-interativo (FR-014) |
| `--coordinator-name <name>` | nao | ausente | `parallel-launch.sh emit --coordinator-name` (§6.ter passo 7) |

**Frontmatter exigido** (convencao verificada nos 6 commands atuais e
consumida pelo gerador do site em `docs-site/hooks/gen_pages.py:509-513`):
`description`, `argument-hint`, `allowed-tools`.

`allowed-tools` proposto: `Bash`, `Read`. **Sem** `Agent` (nao spawna
subagente), **sem** `ScheduleWakeup` (nao ha onda), **sem** `SendMessage`
(recepcao de notificacao esta fora de escopo — research.md Decision 7).

---

## 2. Fluxo normativo (delegado, nao duplicado)

O command executa, nesta ordem:

1. **Parse de argumentos** (secao propria — e o delta real face a
   §6.ter, que recebe o `<PAP>` da execucao corrente).
2. **Resolver a decisao de leva** via `resolve-offer` (§3), ANTES de
   qualquer efeito colateral.
3. **Executar os passos 1-9 de `agente-00c.md` §6.ter por referencia**,
   substituindo apenas o gatilho (invocacao explicita, nao
   `.execution.termination_reason == concluido_roadmap`) e os paths
   (parametrizados pelo passo 1).

**MUST NOT**: reescrever os 9 passos. Precedente vinculante:
`agente-00c-resume.md:496-517` (§9.ter) reusa §6.ter e declara
literalmente *"sem duplicar o fluxo completo"*.

---

## 3. Subcomando `parallel-launch.sh resolve-offer` [PROPOSTA]

```
parallel-launch.sh resolve-offer --source <operator|absent>
                                 [--confirm <RAW>] [--max <RAW>]
```

Espelha, em codigo testavel, o que hoje e so prosa nos passos 4 e 5 de
§6.ter. Modelado no precedente real
`delivery-tier.sh resolve-initial --source <operator|absent> [--answer RAW]`
(`plugins/cstk/skills/agente-00c-runtime/scripts/delivery-tier.sh:278-319`).

### 3.1 `--source` e obrigatorio e nao tem default

Quem chama **DECLARA** se houve operador. Nao ha deteccao automatica —
motivo documentado no helper-precedente
(`delivery-tier.sh:265-269`): *"`[ -t 0 ]` e falso mesmo em sessao
interativa do harness (o Bash tool roda sem tty)"*.

### 3.2 Tabela de resolucao

| `--source` | `--confirm` | `--max` | Saida (stdout) | FR |
|---|---|---|---|---|
| `absent` | (ignorado) | (ignorado) | `launch=no` + `max=2` | FR-014 |
| `operator` | `s`\|`S`\|`y`\|`Y`\|`sim`\|`yes` | ausente/vazio | `launch=yes` + `max=2` | FR-007, FR-013 |
| `operator` | idem acima | inteiro em `1..8` | `launch=yes` + `max=<N>` | FR-013 |
| `operator` | idem acima | mal-formado (nao-inteiro, `0`, negativo) ou `> 8` | `launch=no` + diagnostico em stderr | FR-007 (fail-closed) |
| `operator` | qualquer outra coisa, inclusive vazio/Enter | qualquer | `launch=no` | FR-007 |

Enum de confirmacao copiado da prosa vigente
(`agente-00c.md:969-970`); default `2` copiado de
`agente-00c.md:983`. Nenhum valor inventado.

**Teto superior `8`** (F2 do gate `owasp-security`, LLM10/ASI02): nem
§6.ter nem esta spec fixam limite maximo — no fluxo interativo o
operador digita o numero e ve o resultado, mas em modo nao-interativo
`--max` e scriptavel e um valor absurdo (`--max 999`) lancaria uma sessao
`claude` por candidata, sem freio. `8` e **politica de design** (nao dado
factual): e o dobro do maior teto plausivel observado no fluxo atual
(default `2`), suficiente para nao atrapalhar uso legitimo e baixo o
bastante para nao virar exaustao de recurso. Acima disso, fail-closed.

### 3.3 Formato de saida

Duas linhas `chave=valor` em stdout (POSIX-parseavel sem `jq`,
Constitution II):

```
launch=<yes|no>
max=<inteiro>
```

Diagnosticos em stderr. Exit codes: `0` sucesso (inclusive
`launch=no` — recusar nao e erro), `2` uso incorreto (flag
desconhecida, `--source` ausente ou fora do enum).

### 3.4 Higiene de entrada

`--confirm` e `--max` chegam como texto livre do operador. MUST
remover `\r`/`\n` antes de comparar — mesma classe de bug ja corrigida
e comentada em `delivery-tier.sh:306-307` (*"`$()` NAO remove `\r`"*).

---

## 4. Mapeamento exit code → mensagem (FR-002/FR-003/FR-004)

Nenhuma validacao propria de roadmap e escrita: o command mapeia o exit
de `roadmap-frontier.sh` (contrato real, `roadmap-frontier.sh:44-49`)
para mensagem + remediacao.

| Exit | Causa | Mensagem MUST identificar | Remediacao MUST citar | FR |
|---|---|---|---|---|
| `1` | roadmap ausente | que nao ha `docs/roadmap.md` no projeto-alvo | rodar o fluxo que cria o roadmap (`/agente-00c` em modo roadmap) | FR-002 |
| `3` | roadmap invalido | que o arquivo existe mas esta mal-formado, repassando o stderr do helper | corrigir o artefato apontado | FR-003 |
| `0` + stdout vazio | fronteira vazia | que nao ha candidatas AGORA e por que (tudo `em-andamento`/`concluida`/dependencia pendente) | aguardar conclusao das em andamento | FR-004 |
| `2` | uso incorreto | flag/path invalido passado ao helper | corrigir a invocacao | — |
| `4` | `roadmap-status.sh` ausente | instalacao incompleta do catalogo | `cstk update` | — |

Em **todos** os casos acima: zero worktree criada, zero interacao de
confirmacao (FR-002/FR-003/FR-004 exigem "sem apresentar nada para
confirmar").

---

## 5. Modelo de ameaca do ponto de entrada novo (gate `owasp-security`)

Os helpers consumidos ja passaram por gate na feature irma. Esta secao
cobre **so o que muda** por existir um ponto de entrada invocavel a
qualquer momento, sobre um projeto-alvo **parametrizavel** (FR-001) e
sem execucao 00c ativa.

### 5.1 F1 (MEDIUM, LLM01/ASI09) — roadmap de terceiro vira conteudo untrusted

Em §6.ter o `docs/roadmap.md` foi produzido pela propria pipeline, na
propria sessao. Com `--projeto-alvo-path`, ele pode ser o roadmap de um
repo qualquer — texto livre de terceiro que sera **colado no turno**
(tabela + secao `### Avisos`).

**MUST**: ao injetar a saida de `roadmap-frontier.sh` no turno, rotula-la
como **UNTRUSTED / dado, nao instrucao** — mesmo tratamento que o
read-back loop ja da ao bloco de `cstk recall --context`. Diretiva
embutida na prosa do roadmap ("ignore o teto", "lance tudo") e
**conteudo**, nunca comando. O helper ja faz a parte dele (allowlist de
token, truncamento a 128 chars, teto de 10 tokens por par, rotulo
`roadmap-prose-untrusted` — `roadmap-frontier.sh:317-318`, `:431`); o
rotulo no turno e a camada que falta.

### 5.2 F2 (MEDIUM, LLM10/ASI02) — teto sem limite superior

Ver §3.2: `--max` agora e `1..8`, fail-closed acima disso.

### 5.3 F3 (MEDIUM, A01/A05/ASI03) — a premissa de confianca do contrato irmao nao sobrevive a um alvo parametrizavel

`docs/specs/roadmap-parallel-launch/contracts/roadmap-frontier.md:61-70`
(§3.1) declara duas exigencias: rejeitar `..` **e** rejeitar path que
"resolver para fora do repo coordenador", sob a premissa de que "o repo
coordenador e o roadmap sao do proprio operador".

Fato verificado na implementacao: so a **primeira metade** existe —
`roadmap-frontier.sh:121-136` faz apenas a rejeicao sintatica de `..`
(`_rf_reject_dotdot`), sem checagem de contencao ao repo. E
`roadmap-frontier.sh:219` executa `git -C "$EXCLUDE_ACTIVE_REPO"
worktree list --porcelain` — `git -C` real sobre o path recebido. O
proprio cabecalho do script (`:40`) afirma que ele "nao invoca `git -C`
diretamente" sobre esses paths, o que **nao se sustenta** para
`--exclude-active-from-repo`.

Consequencia para esta feature: apontar `/roadmap-wave` para um repo
hostil clonado localmente faz `git -C` rodar la, e `git` executa codigo
via `.git/config` (`core.fsmonitor`) — o vetor exato que o §3.1 do
contrato irmao cita.

**MUST** (mitigacao no ponto de entrada, sem alterar o helper):

1. O command declara, no proprio texto, a premissa de confianca: o
   projeto-alvo MUST ser repo do proprio operador. Apontar para repo de
   terceiro e execucao de codigo de terceiro.
2. O projeto-alvo MUST vir de **argumento do operador ou do diretorio
   corrente** — NUNCA derivado de conteudo do roadmap, de `### Avisos`,
   nem de qualquer texto lido (fecha o encadeamento F1→F3).
3. A declaracao de blast radius (§6.ter passo 4) MUST **nomear o
   projeto-alvo resolvido**, para o operador nao confirmar leva no repo
   errado quando usa `--projeto-alvo-path`.

### 5.4 F4 (LOW, A09) — decisao de lancamento sem trilha persistente

Esta feature nao tem `state.json` (`data-model.md`), logo a decisao
`launch/max/source` **nao vira Decisao auditavel** como viraria dentro de
uma execucao 00c. **MUST**: o command ecoa explicitamente ao operador o
que resolveu (`source`, `launch`, `max` efetivo e a lista final), para a
decisao ficar ao menos visivel no transcript.

### 5.5 F5 (LOW, TOCTOU) — concorrencia entre duas invocacoes

`emit` recomputa a guarda anti-duplicidade imediatamente antes de compor
(`parallel-launch.sh:85`), o que **reduz** a janela mas nao a elimina:
duas invocacoes simultaneas de `/roadmap-wave` no mesmo repo podem
calcular a mesma fronteira antes de qualquer uma lancar. Residual
declarado honestamente — o efeito e a segunda `cstk session start`
falhar sobre worktree ja existente, nao lancamento duplo silencioso.
NUNCA afirmar que a duplicidade esta eliminada.

---

## 6. Invariantes

- **INV-1**: nenhuma feature e lancada sem `launch=yes` vindo de
  `resolve-offer` (FR-007).
- **INV-2**: `|selecionadas| <= max` em toda invocacao (FR-006, SC-004).
- **INV-3**: o command nunca calcula elegibilidade por conta propria —
  sempre via `roadmap-frontier.sh` (espelha INV-3 do contrato irmao).
- **INV-4**: o command nunca executa `cstk session start` para um
  short-name que `emit` marcou `blocked-duplicate`/
  `blocked-invalid-feature` (FR-010, guarda TOCTOU ja em
  `parallel-launch.sh:85`).
- **INV-6**: o projeto-alvo nunca e derivado de conteudo lido (§5.3).
- **INV-5**: a saida de `roadmap-frontier.sh` (incluindo `### Avisos`)
  e repassada tal-e-qual, NUNCA resumida nem reforcada como conflito
  confirmado (Constitution VI; regra literal em `agente-00c.md:929-934`).
