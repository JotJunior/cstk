# Contract: ponteiro de referencia e marcadores [PROPOSTA — a validar na implementacao]

## Stub de secao no prompt-base (FR-003)

Cada secao movida e substituida, no MESMO lugar e com o MESMO heading
original, por um stub:

```markdown
### 5.e.bis Sequencia pre-spawn de subagente (model-routing)

<!-- ORCH-REF: root/clarify -->
> **Movida para referencia de fase.** Fase/condicao: etapa `clarify`.
> ANTES de executar qualquer passo desta secao, resolva e leia a referencia:
> `orchestrator-refs.sh path --orchestrator root --phase clarify` + tool Read
> no caminho retornado. Se o comando falhar ou a leitura falhar, NAO execute
> a fase de memoria: registre Decisao (`--classe operacional`) e bloqueio
> humano e encerre a onda (FR-010).
```

Regras:

1. O texto do stub e uniforme; so variam heading, `<orchestrator>/<phase>` e
   a frase de fase/condicao.
2. Secao destinada a varias fases (fragmento) tem um marcador `ORCH-REF` por
   fase e a frase lista as fases.
3. O prompt-base NAO ganha regra nova: o stub so encaminha. A regra FR-010 e
   escrita uma vez, numa secao curta "Referencias de fase" logo apos
   "Contrato de conclusao de turno", e repetida no stub por clareza.
4. Leitura unica por onda: a referencia da fase corrente e lida uma vez no
   inicio da fase (passo "Avancar"/5 do Loop); stubs dentro da mesma fase nao
   geram nova leitura (SC-006). Em retomada, a referencia da fase corrente e
   relida (contexto anterior nao existe).

## Variante do stub para a fase `bootstrap` (sem onda aberta — FR-010, CHK022)

A referencia `bootstrap` e lida na onda-001 ANTES de `state-ondas.sh start`
(invariante I-2: opt-ins coletados antes de abrir a onda) e no re-spawn pos
fallback de opt-ins. Nesse momento `wave-status` e `none`, entao "encerre a
onda" nao se aplica (`state-ondas.sh end` sai com `no-open-wave`). Verificado
empiricamente (state-dir descartavel, `wave-status` = `none`): `state-decisions.sh
register` (com `wave_id` nulo) e `bloqueios.sh register` funcionam sem onda
aberta; `state-ondas.sh record-skill` e `end` NAO (exit 1, `no-open-wave`) e
`state-ondas.sh start` recusa abrir a onda-001 sem opt-ins (I-2). O stub de
`bootstrap` substitui a ultima frase do stub padrao por:

```markdown
> Se o comando falhar ou a leitura falhar (arquivo ausente ou sem o marcador
> final `ORCH-REF-END`), NAO execute a fase de memoria e NAO chame
> `state-ondas.sh start` (nenhuma onda esta aberta): registre Decisao
> (`--classe operacional`) e bloqueio humano (`bloqueios.sh register`) e
> devolva o turno ao command pai IMEDIATAMENTE, sem relatorio de onda e sem
> `Schedule intent` (FR-010).
```

Sequencia executavel: (1) `state-decisions.sh register --classe operacional
--escolha bloqueio-humano-<motivo> --score 0 ...`; (2) `bloqueios.sh register
--decisao-id <dec> --pergunta ...`; (3) devolver o turno. Nao ha `end`,
`record-skill` nem `Schedule intent`. O bloqueio fica registrado no state (fonte de verdade do
command pai, nunca o texto do retorno). Como nao existe onda aberta, o
invariante "retomada sempre segue onda fechada" nao tem onda a fechar
(`wave-status` = `none`). O tratamento do pai ao receber o turno de volta e
o do fluxo de bloqueio ja existente (fora do escopo desta feature). A regra geral (nao prosseguir de memoria + bloqueio humano) e
a mesma dos demais stubs.

## Marcadores

| Marcador | Onde | Consumidor |
|----------|------|-----------|
| `<!-- ORCH-REF: <orchestrator>/<phase> -->` | prompt-base | teste FR-009 (todo marcador resolve para arquivo existente no subtree e no tarball) |
| `<!-- FRAGMENT:<id>:BEGIN -->` / `<!-- FRAGMENT:<id>:END -->` | referencias de fase | teste de sincronia (todas as copias de `<id>` do mesmo orquestrador byte-identicas) |
| `<!-- MCP-VS-BASH:BEGIN/END -->` | prompt-base (inalterado) | `tests/test_orchestrator-allowlist-guard.sh` (inalterado) |

`<id>` em kebab-case ingles (ex. `readback-loop`, `quality-gates`,
`stage-commit-hook`, `delivery-tier-propagation`, `briefing-high-items-gate`).

## Limite de tamanho (gate owasp-security, achado S2 — anti fail-open por truncamento)

Cada referencia MUST ter no maximo 2000 linhas, para que UMA chamada da tool
Read (limite padrao de 2000 linhas) carregue o arquivo inteiro — leitura
truncada silenciosa equivaleria a executar a fase sem parte das regras. O
teste de FR-009 afirma o limite por arquivo. A ultima linha de toda
referencia e o marcador `<!-- ORCH-REF-END -->`; o stub instrui a tratar
leitura sem esse marcador como falha de leitura (FR-010).

## Cabecalho da referencia

Cada arquivo de referencia comeca com:

```markdown
# Referencia de fase: <phase> (<orchestrator>)

> Conteudo movido do prompt-base `<agente>.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.
```

Seguido das secoes movidas, com headings originais preservados.
