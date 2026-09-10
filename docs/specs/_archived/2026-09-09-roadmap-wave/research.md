# Research: Retomada da Oferta de Leva Paralela do Roadmap

**Feature**: `roadmap-wave` | **Date**: 2026-08-18 | **Fase**: Phase 0

> Regra deste documento (Constitution VI): toda afirmacao sobre o
> comportamento atual do repo tem `path:linha` ou output literal
> observado. O que ainda nao existe esta marcado
> `[PROPOSTA — a validar na implementacao]`.

---

## Decision 1 — O ponto de entrada e um slash command novo, nao uma skill

**Decision**: criar `plugins/cstk/commands/roadmap-wave.md` (invocavel
como `/roadmap-wave`). Nao criar skill nova, nao estender subagente,
nao criar subcomando do binario `cstk`.

**Rationale** (fonte real, nao inferencia):

- `plugins/cstk/commands/agente-00c.md:909-912` declara o invariante
  literal: *"**Esta oferta e EXCLUSIVAMENTE do command pai (FR-012 —
  inegociavel)**: nenhuma decisao de leva parte do subagente
  orquestrador (`Agent` `agente-00c-orchestrator`, sem tool Bash de
  rede/sessao para isso) nem de uma sessao-filha — so a coordenadora
  interage com o operador e lanca."* Uma **skill** e auto-invocavel por
  um agente (o campo `description` e trigger condition — Constitution
  III), logo colocar a oferta numa skill abriria exatamente o caminho
  que esse invariante fecha.
- Um **subcomando do binario `cstk`** foi rejeitado por dois motivos
  verificados: (i) `CLAUDE.md` §"Distribuicao via plugin nativo"
  registra que *"O binario `cstk` NAO e empacotado no plugin (FR-006,
  por desenho)"* — o ponto de entrada ficaria indisponivel para quem
  instala pelo plugin nativo; (ii) o lancamento exige executar os
  comandos compostos por `parallel-launch.sh emit`, e o proprio helper
  documenta em `plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh:17-19`
  que *"Quem executa e o command pai (/agente-00c, /agente-00c-resume),
  que ja tem Bash e ja e o dono da interacao com o operador"*.

**Alternatives considered**:

| Alternativa | Rejeitada porque |
|---|---|
| Skill `roadmap-wave` | auto-invocavel por agente ⇒ viola FR-012 de `roadmap-parallel-launch` citado acima |
| Subcomando `cstk roadmap wave` | binario fora do plugin nativo (CLAUDE.md, FR-006 `claude-plugin-packaging`) + sem canal de interacao com o operador dentro do harness |
| Estender `/agente-00c-resume` com flag | o gatilho de resume e uma execucao 00c existente (`state-dir`, lock, onda); a spec pede um ponto de entrada que roda SEM execucao 00c ativa (FR-001A: basta o roadmap) |

---

## Decision 2 — Reuso DRY por referencia, com o precedente literal do resume

**Decision**: o novo command NAO reescreve o fluxo de oferta. Ele
descreve (a) o proprio gatilho (invocacao explicita do operador),
(b) o parse de argumentos proprio, (c) o modo nao-interativo, e
delega os passos de oferta/lancamento a `agente-00c.md` §6.ter
por referencia.

**Rationale**: o padrao ja existe e esta escrito no corpus.
`plugins/cstk/commands/agente-00c-resume.md:496-517` (§9.ter) reusa os
9 passos de `agente-00c.md` §6.ter e fecha com a frase literal:
*"esta secao so aponta o gatilho equivalente para quem le este command,
sem duplicar o fluxo completo."* O mesmo se repete em §9.quater
(`:519-545`) para §6.quater. Duplicar os 9 passos num terceiro arquivo
criaria tres copias divergentes da mesma regra de blast radius.

**Delta real face a §6.ter** (o que o novo command precisa dizer por si):

| Aspecto | §6.ter (`agente-00c.md`) | `/roadmap-wave` [PROPOSTA] |
|---|---|---|
| Gatilho | `.execution.termination_reason == concluido_roadmap` apos onda | invocacao explicita do operador, sem execucao 00c |
| Projeto-alvo | `<PAP>` da execucao corrente | argumento do command; default = diretorio de trabalho corrente (FR-001) |
| Roadmap/specs | defaults `docs/roadmap.md` / `docs/specs` | idem + passthrough `--roadmap`/`--specs-dir` (FR-001) |
| Teto | pergunta interativa, default 2 (passo 5) | idem + `--max N` explicito (FR-013) |
| Nao-interativo | "cai em nao lancar" (passo 4) | idem, resolvido por helper testavel (Decision 3) |

---

## Decision 3 — A regra de nao-interatividade sai da prosa e vira codigo testavel

**Decision**: adicionar o subcomando
`parallel-launch.sh resolve-offer` [PROPOSTA — a validar na
implementacao], que recebe declaracao explicita de origem e devolve a
decisao de leva (lancar ou nao + teto efetivo). O command chama o
helper em vez de decidir por prosa.

**Rationale** (precedente direto, com fonte):

- `plugins/cstk/skills/agente-00c-runtime/scripts/delivery-tier.sh:255-277`
  documenta por que a regra saiu da prosa: *"Existe para tirar a regra da
  prosa do command e coloca-la em codigo testavel: antes desta funcao,
  'execucao nao-interativa => cloud-public' era so uma instrucao em
  linguagem natural, e um spike headless (2026-08-15) mostrou um agente
  sobrepondo-a com raciocinio de Principio VI, gravando `local` a partir
  do briefing."*
- O mesmo bloco fixa o motivo de `--source` ser **obrigatorio e sem
  default**: *"Nao ha deteccao automatica porque nao existe sinal
  confiavel no shell — `[ -t 0 ]` e falso mesmo em sessao interativa do
  harness (o Bash tool roda sem tty), o que tornaria toda execucao
  'nao-interativa'"*. Consequencia para esta feature: **o helper NAO
  detecta interatividade**; quem chama DECLARA (`--source
  operator|absent`).
- O lint que ja existe cobre a prosa, mas so a prosa:
  `tests/test_command-prompt-noninteractive-lint.sh:25-27` declara o
  limite honesto — *"isto verifica que a clausula ESTA ESCRITA, nao que
  o agente a OBEDECE"*. Ou seja, o lint garante FR-014 no papel; so o
  helper garante FR-014 em execucao.

**Onde mora o subcomando**: em `parallel-launch.sh`, nao em script
novo. Motivos: mesma familia de feature e mesmo contrato
(`contracts/parallel-launch.md`); e a "regra de ouro" de `CLAUDE.md`
(*"ao adicionar um `.sh` novo ... criar o `test_<nome>.sh`
correspondente"*, gateada por `./tests/run.sh --check-coverage`) —
`tests/test_parallel-launch.sh` ja existe (25 cenarios) e recebe os
cenarios novos sem criar orfao.

**Alternatives considered**:

| Alternativa | Rejeitada porque |
|---|---|
| So prosa no command | precedente empirico do spike headless (delivery-tier) mostra prosa sendo sobreposta pelo agente |
| Script novo `roadmap-wave.sh` | duplicaria o dominio de `parallel-launch.sh` e criaria mais um arquivo + test file, sem ganho |
| Deteccao automatica via `[ -t 0 ]` | comprovadamente falso-negativo no harness (fonte acima) |

---

## Decision 4 — Semantica exata de `resolve-offer` [PROPOSTA]

**Decision**: contrato determinístico, fail-closed, espelhando os passos
4/5/6 de §6.ter:

- `--source absent` (sem operador) ⇒ `launch=no` SEMPRE, qualquer que
  seja o resto. E o fail-safe de FR-014 e o espelho literal do
  `--source absent` do `delivery-tier.sh resolve-initial`.
- `--source operator --confirm <RAW>` ⇒ `launch=yes` somente para
  `s|S|y|Y|sim|yes`; qualquer outra coisa (inclusive vazio/Enter) ⇒
  `launch=no`. Enum copiado da prosa ja vigente em
  `agente-00c.md:969-970`: *"Recusa (qualquer resposta != `s`/`S`/`y`/
  `Y`/`sim`/`yes`, inclusive Enter)"*.
- `--max <RAW>` ausente ou vazio ⇒ teto **2**, valor fixado em
  `agente-00c.md:983` (*"Enter/vazio => default **2** (FR-003,
  fixado pela clarify/SC-001)"*).
- `--max` presente e mal-formado (nao-inteiro, `0`, negativo) ⇒
  `launch=no` + diagnostico em stderr. **Politica de design**, nao dado
  factual: entre "assumir 2" e "nao lancar", a escolha fail-closed
  preserva FR-007 (nunca lancar sem confirmacao inequivoca) quando a
  intencao do operador esta ambigua.

**Rationale**: cada valor acima tem origem citavel no corpus atual
(nenhum enum/limite inventado). O unico grau de liberdade novo — o
tratamento de `--max` invalido — e politica de erro, categoria que
Constitution VI (`docs/constitution.md:259-260`) explicitamente permite
resolver por default de design.

---

## Decision 5 — Selecao quando candidatas excedem o teto, sem operador presente

**Decision**: em modo nao-interativo com confirmacao explicita
(`--source operator --confirm sim --max T`), a selecao e **as T
primeiras da fronteira**, na ordem emitida por `roadmap-frontier.sh`.

**Rationale**: nao e regra nova — e a mesma que §6.ter passo 6 ja
oferece ao operador interativo, literal em `agente-00c.md:993`:
*"Escolha ate <T> (numeros separados por espaco, ou Enter para as <T>
primeiras da fronteira)"*. A ordem da fronteira e deterministica: a
tabela emitida tem coluna `ordem`
(`docs/specs/roadmap-parallel-launch/contracts/roadmap-frontier.md:188-191`).

---

## Decision 6 — Pre-condicao: roadmap valido, e so

**Decision**: o command NAO checa briefing/constitution.

**Rationale**: decidido na fase clarify e registrado em
`docs/specs/roadmap-wave/spec.md` §Clarifications (Q1) e normatizado em
FR-001A. Tecnicamente o gate ja e o proprio exit code do helper —
`roadmap-frontier.sh:44-49` define `1` = roadmap AUSENTE, `3` = roadmap
PRESENTE mas invalido, `0` = sucesso inclusive fronteira vazia. Nao ha
codigo novo de validacao a escrever (FR-002/FR-003/FR-004 sao mapeamento
de exit code para mensagem).

**Evidencia empirica coletada nesta onda** (execucao real, repo cstk que
nao tem `docs/roadmap.md`):

```
$ roadmap-frontier.sh --exclude-active-from-repo "$PWD"
roadmap-status: roadmap nao encontrado: docs/roadmap.md
REAL exit=1
```

E `parallel-launch.sh check-tmux` retornou `exit=0` (tmux presente nesta
maquina). Ambos os helpers instalados em `~/.claude/skills/` estao
identicos aos do repo (`diff -q` sem diferenca) — nao ha drift a
reconciliar antes de implementar.

---

## Decision 7 — Recepcao de notificacao (§6.quater) esta FORA de escopo

**Decision**: `/roadmap-wave` nao implementa recepcao de `SendMessage`
de sessao-filha.

**Rationale**: a spec de `roadmap-wave` nao tem nenhum FR sobre
notificacao — os 14 FRs cobrem calcular fronteira, recusar com
remediacao, oferecer, confirmar, lancar e reportar. §6.quater/§9.quater
cobrem esse fluxo para a coordenadora de uma execucao `/agente-00c`.
Registrado aqui explicitamente para que a ausencia seja lida como
escopo, nao como esquecimento.
