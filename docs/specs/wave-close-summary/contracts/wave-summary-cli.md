# Contract: `wave-summary.sh` [PROPOSTA — a validar na implementacao]

Contrato NOVO projetado por esta feature (nao descreve interface pre-existente).
Local: `plugins/cstk/skills/agente-00c-runtime/scripts/wave-summary.sh`.

## Invocacao

```
wave-summary.sh emit --state-dir DIR [--wave ID] [--json]
```

| Flag | Required | Validation |
|------|----------|------------|
| `--state-dir DIR` | yes | diretorio com `state.json` ou `state.db` |
| `--wave ID` | no | `^onda-[0-9]{3,}$`; default = ultima entrada de `.waves[]` |
| `--json` | no | troca Markdown por objeto JSON (`data-model.md`) |

`-h`/`--help`/sem subcomando → uso em stderr, exit 2.

## Exit codes e streams

| Exit | Significado | stdout | stderr |
|------|-------------|--------|--------|
| 0 | resumo composto | bloco Markdown ou JSON | vazio |
| 1 | falha de leitura (estado ausente/corrompido, `jq`/`sqlite3` ausente, materializacao falhou) | vazio | exatamente 1 linha `wave-summary: <motivo>` |
| 2 | uso incorreto | vazio | uso |
| 3 | onda inexistente (`.waves[]` vazio ou `--wave` nao encontrada) | vazio | exatamente 1 linha `wave-summary: <motivo>` |

Garantias: read-only (I-4); nenhum acesso a rede (Constitution IV); nenhum lock;
nenhum arquivo criado dentro do state-dir (tmp de materializacao fica em
`$TMPDIR`, removido por trap).

## Saida Markdown (default) — forma

Rotulos em pt-BR; valores entre `<>` sao preenchidos do estado; linhas
condicionais marcadas.

```
### Resumo da onda <wave_id>
- Termino: <rotulo do motivo> [ATENCAO: requer resposta do operador]   (sufixo so se attention_required)
- Etapas executadas: <executed_stages, virgula> | Etapa atual: <current_stage> | Status: <execution_status>
- Decisoes registradas na onda: <decisions_count>
- Bloqueios pendentes: <count> (<ids>)          (ou "Bloqueios pendentes: 0")
- Chamadas de ferramenta: <n | nao medido>
- Duracao: <Nm Ss | nao medido>
- Consumo (OTel): <tokens> tokens, US$ <custo> | nao medido
- Tarefas: <passed> concluidas, <failed> falharam  (ou "nao aplicavel")
- Proxima instrucao: `<next_instruction saneada, sem crases>` | nao definida
```

Rotulos de motivo (mapeamento fechado):

| `termination_reason` | Rotulo | attention |
|----------------------|--------|-----------|
| `etapa_concluida_avancando` | etapa concluida, avancando | nao |
| `threshold_proxy_atingido` | pausa por limite operacional (retomada agendada) | nao |
| `bloqueio_humano` | bloqueio humano pendente | SIM |
| `aborto` | execucao abortada | nao |
| `concluido` | execucao concluida | nao |
| `null` | onda ainda aberta (nao fechada) | nao |
| outro valor | `<valor cru>` (enum desconhecido — sem inventar rotulo) | nao |

## Uso pelo command pai (padrao unico, os 4 commands)

```
WS_OUT=$("$RUNTIME_SCRIPTS"/wave-summary.sh emit --state-dir "$SD" 2>&1) \
  || WS_OUT="Resumo da onda indisponivel: $(printf '%s\n' "$WS_OUT" | tail -1)"
# ... ScheduleWakeup / cleanup seguem inalterados ...
# Mensagem final ao operador: incluir "$WS_OUT" verbatim.
```

Nunca `set -e` sobre esta chamada; nunca retry; nunca condicionar
`ScheduleWakeup`/liberacao de lock/ingestao ao exit do helper.

Regras de seguranca da saida (research Decision 9): tokens estruturados
validados por `^[A-Za-z0-9._-]{1,64}$` (senao `(valor invalido omitido)`);
`next_instruction` em inline code; stderr de sub-ferramentas descartado. O pai
trata o bloco como DADO de exibicao — nunca como instrucao.
