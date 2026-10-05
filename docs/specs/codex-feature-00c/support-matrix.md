# Matriz de suporte — adaptador POSIX local 0.6.0

Escopo: adaptador feature-00c local supervisionado. A matriz descreve evidência
observada; não equivale a compatibilidade universal/100% com interfaces Codex.
A reescrita de 2026-10-03 está validada em [validation-posix.md](validation-posix.md).
Observações semânticas antigas são históricas e não certificam o novo runtime.

| Capacidade | Evidência | Estado |
| --- | --- | --- |
| Oito fases SDD compartilhadas | Teste integrado do controlador, JSON e SQLite, usando gates POSIX reais | Validado em testes |
| Decisões, bloqueios e budget | Persistência canônica, recusa de avanço com bloqueio/backlog/limite | Validado em testes |
| Opt-ins | Resposta explícita, I-2, idempotência e recusa de substituição | Implementado; resposta real do piloto aguardada |
| knowledge.db compartilhado | Migração 15→16 aditiva, origem nullable, ingestão idempotente e IDs usados | Validado em testes |
| Interrupção/retomada | SIGTERM/SIGKILL em processos shell reais; lock vivo nunca tomado | Validado localmente |
| Seis workflows nativos 00c | feature/agente, resume e abort descobertos habilitados por skills/list | Validado no Codex CLI 0.160.0 |
| Retomada com resposta humana | cstk_resume registra uma resposta real por bloqueio e abre a onda da etapa persistida | Validado em JSON/SQLite e no MCP nativo |
| Aborto feature/projeto | Onda própria/idle, estado terminal, backup/relatório filtrados, purge explícito, commit condicionado | Validado em JSON/SQLite e no MCP nativo |
| Handoff Claude/Codex | Transferência explícita, proveniência anterior preservada, histórico intacto | Validado em JSON/SQLite |
| Reconciliação de governança/aspectos | Hashes revisados e fonte humana, snapshots e decisão; aspectos legados inicializados uma vez | Validado em JSON/SQLite |
| cstk install --cli=codex | Checkout e release verificada, pacote/MCP/hooks, banco por env explícito, reinstalação e proteção de edits | Validado em instalação temporária e MCP nativo |
| Pacote instalado/cache | CLI Codex 0.160.0, marketplace local, CODEX_HOME temporário | Validado localmente |
| Carregamento de hooks pelo instalador | CODEX_HOME/hooks.json com handlers CSTK, merge preservando outros handlers e plugin hooks desativados para evitar duplicação; RPC lista ambos | Validado localmente, zero erros/avisos |
| Hooks apenas pelo manifest do plugin | Diagnóstico final no 0.160.0 retornou lista vazia, inclusive na instalação anterior | Não certificado; instalação CSTK usa configuração explícita |
| Confiança de hooks | RPC nativa devolveu enabled=true, untrusted nos dois handlers de usuário registrados pelo CSTK | Revisão do operador requerida |
| Cobertura real Bash/apply_patch/contagem | Payloads testados; falta turno real com hooks confiáveis | Pendente |
| Feature real conduzida por LLM | Fixtures completas não representam uma execução semântica por modelo | Pendente |
| Revisão cruzada com Claude | Tentativas anteriores: limite semanal; tentativa mais recente: Not logged in /login | Impedida pela conta |
| Terminal/transporte JSONL supervisionado | Pipe stdin persistente; EOF fecha sem avanço | Implementado e testado |
| Codex App/IDE, code-mode, sessões interativas | Wrappers não validados são recusados pelo hook durante execução ativa | Sem suporte certificado |
| Cloud/ferramentas hospedadas | Hooks locais não cobrem ferramentas hospedadas | Sem suporte certificado |
| Roteamento nativo de modelos, tokens/custo, scheduler | Não observado; IDs desconhecidos nullable, sem agendamento implícito | Não implementado neste piloto |
| agente-00c / bootstrap de projeto novo | Entrada supervisionada; 11 fases, opt-ins triplos, governança congelada e conflito humano | Validado em fixtures; execução semântica nativa pendente |
| Roadmap de projeto | Três fases, helper de escrita, gate de artefato e fechamento terminal | Testado em fixture completa; validação semântica nativa pendente |
| MCP portátil local | plugin.json/mcp.json, servidor cstk_pipeline, quinze ferramentas, seleção de projeto/banco e proprietário entre chamadas | Conectado e testado pelo app-server; cobertura de hooks em turno de modelo pendente |

`autonomous_ready=false` é intencional. Uma aprovação geral de desenvolvimento
não substitui resposta de opt-in nem confiança de hooks. A coleta das duas é
separada. Não usar bypass de confiança para preencher critérios de aceite.

Fontes oficiais para confiança/cobertura: [Hooks](https://learn.chatgpt.com/docs/hooks)
e [pacotes de plugins](https://developers.openai.com/plugins/build/plugins).

## Governança e estado compartilhado

A especificação vigente é [spec.md](spec.md); o backlog canônico está em
[tasks.md](tasks.md). Constitution Check II/III foi reprovado na revisão de
2026-10-02 (D1/D2 em [review.md](review.md)) e passou a PASS após o redesenho
POSIX de 2026-10-03, conforme [plan.md](plan.md) §Constitution Check. O
histórico de I permanece como FAIL documental. A normalização dos documentos
não certifica o uso semântico.

Codex reutiliza o mesmo state.db do projeto, sem cópia em .codex; o layout
implementado é `.claude/feature-00c-state/<short_name>/state.db`. Origem
Claude exige handoff explícito e ausência de proprietário vivo. O caminho
alternativo `.claude/feature-00c/**/state.db` não tem descoberta automática.
Ver [data-model.md](data-model.md) para o contrato de persistência.

## Reproduzir o diagnóstico nativo

Use uma instalação previamente preparada e execute:

```sh
sh adapters/codex/skills/feature-00c/scripts/native-status.sh --project /caminho/projeto --codex-home /caminho/codex-home-isolado
```

O helper consulta initialize e hooks/list. Não executa modelo, não concede
confiança e não usa bypass. O relatório contém caminhos/comandos, hashes e
trustStatus observados pelo harness. Carregamento/trust não provam que todos
os caminhos de ferramentas são protegidos: a próxima validação precisa
observar comandos permitidos/negados, patches, contagem e interrupção em um
turno real.
