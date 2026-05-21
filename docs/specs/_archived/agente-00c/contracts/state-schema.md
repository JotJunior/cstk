# Contract: Schema do Estado em Disco

Schema do arquivo `<projeto-alvo>/.claude/agente-00c-state/state.json`.
Toda onda comeca lendo + validando este arquivo. Schema-version invalido = bloqueio.

---

## state.json — versao 1.0.0

```json
{
  "schema_version": "1.0.0",
  "execucao": {
    "id": "exec-2026-05-05T14-23-00Z-agente-00c-poc-foo",
    "projeto_alvo_path": "/Users/jot/Projects/_lab/poc-foo",
    "projeto_alvo_descricao": "POC de bot Slack que sumariza threads",
    "stack_sugerida": null,
    "status": "em_andamento",
    "motivo_termino": null,
    "iniciada_em": "2026-05-05T14:23:00Z",
    "terminada_em": null
  },
  "etapa_corrente": "specify",
  "proxima_instrucao": "Continuar specify com base em briefing.md gerado na onda 001. Stack ainda nao escolhida — clarify-answerer decide na proxima etapa clarify.",
  "ondas": [
    {
      "id": "onda-001",
      "inicio": "2026-05-05T14:23:00Z",
      "fim": "2026-05-05T14:51:00Z",
      "etapas_executadas": ["briefing"],
      "tool_calls": 42,
      "wallclock_seconds": 1680,
      "motivo_termino": "etapa_concluida_avancando",
      "proxima_onda_agendada_para": "2026-05-05T14:56:00Z"
    }
  ],
  "decisoes": [
    {
      "id": "dec-001",
      "onda_id": "onda-001",
      "timestamp": "2026-05-05T14:31:22Z",
      "etapa": "briefing",
      "agente": "orquestrador-00c",
      "contexto": "Briefing pergunta 4: stakeholders — operador unico ou time?",
      "opcoes_consideradas": ["Operador unico", "Time pequeno", "Multi-time"],
      "escolha": "Operador unico",
      "justificativa": "Briefing do 00C marca uso pessoal sem stakeholders externos; projeto-alvo herda esse padrao por default. Sem indicacao em descricao curta de outros stakeholders.",
      "score_justificativa": null,
      "referencias": ["docs/specs/agente-00c/briefing.md#2-usuarios-e-stakeholders"],
      "artefato_originador": "briefing.md"
    }
  ],
  "bloqueios_humanos": [],
  "orcamentos": {
    "recursividade_max": 3,
    "profundidade_corrente_subagentes": 1,
    "retro_execucoes_max_por_feature": 2,
    "retro_execucoes_consumidas": 0,
    "ciclos_max_por_etapa": 5,
    "ciclos_consumidos_etapa_corrente": 1,
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "tool_calls_onda_corrente": 0,
    "inicio_onda_corrente": null
  },
  "metricas_acumuladas": {
    "ondas_total": 1,
    "tool_calls_total": 42,
    "tempo_wallclock_total_segundos": 1680,
    "profundidade_max_atingida": 1,
    "subagentes_spawned": 2,
    "decisoes_total": 14,
    "bloqueios_humanos_total": 0,
    "sugestoes_skills_globais_total": 0,
    "issues_toolkit_abertas": 0
  },
  "whitelist_urls_externas": [
    "https://pkg.go.dev/**",
    "https://api.github.com/repos/JotJunior/claude-ai-tips/**"
  ],
  "historico_movimento_circular": []
}
```

---

## Regras de validacao na retomada

Em cada onda, ANTES de qualquer acao, o orquestrador valida:

1. **Arquivo existe e e JSON parseavel.** Se nao: bloqueio com mensagem
   "Estado nao parseavel". Operador resolve manualmente.
2. **`schema_version` presente e suportado.** Hoje, apenas "1.0.0". Versao
   diferente = bloqueio com mensagem indicando atualizacao do orquestrador
   ou migracao manual.
3. **`execucao.status` consistente com presenca de `terminada_em`.** Se
   status terminal mas `terminada_em` nulo, ou vice-versa, bloqueio.
4. **`profundidade_corrente_subagentes <= 3`.** Invariante. Violacao =
   aborto.
5. **`ciclos_consumidos_etapa_corrente <= 5`.** Limite de Principio IV.
6. **`retro_execucoes_consumidas <= 2`.** Limite de Principio IV.
7. **Cada Decisao tem os 5 campos preenchidos** (contexto, opcoes,
   escolha, justificativa, agente). Decisao com campo faltando = bloqueio
   por violacao de Principio I.
8. **Cada BloqueioHumano referencia uma Decisao existente.**
9. **`whitelist_urls_externas` e array de strings nao vazias.**

Falha em qualquer validacao = bloqueio sem auto-correcao silenciosa
(Principio III).

---

## Backups (state-history/)

A cada onda, ANTES de sobrescrever `state.json`:

```
mv state.json state-history/onda-<NNN>-<timestamp>.json
```

Backups permitem auditoria post-mortem e rollback manual em casos extremos.
Sao incluidos no commit local feito ao final de cada onda.

Limite pratico de quantidade de backups: nao ha enforcement automatico, mas
relatorio final indica caminho dos backups e tamanho total ocupado para o
operador limpar manualmente se desejar.
