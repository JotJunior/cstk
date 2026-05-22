# Nota: Viabilidade de hook do harness para suprimir reminders TaskCreate

> **Origem**: §4.5.2 do backlog de evolucao do agente-00c. Subtarefa
> opcional para investigar se reminders TaskCreate podem ser
> suprimidos via configuracao do Claude Code, e nao apenas via
> instrucao em prompt do orquestrador.

## Contexto

O orquestrador `agente-00c-orchestrator` ja documenta (§Sistema
canonico de tracking) que reminders TaskCreate/TaskUpdate devem ser
IGNORADOS. Funciona — mas reminders continuam consumindo tokens em
cada turno (sug-029 reportou 8+ reminders em uma so onda da execucao-
fonte).

A solucao via prompt e curativo, nao remedio. Remedio = configurar o
harness para nao emitir o reminder durante execucoes 00C.

## Mecanismos disponiveis no Claude Code

Inspecionando opcoes existentes:

### Opcao A: Hook `Stop` ou `SubagentStop` no settings.json

Claude Code suporta hooks (ver `~/.claude/settings.json` —
`hooks: { Stop: [...] }`). Hooks executam comandos shell em pontos
do ciclo de vida. Nao podem suprimir reminders emitidos pelo
modelo, mas podem injetar contra-mensagens.

**Viabilidade**: BAIXA. Hooks reagem a eventos, nao modificam o
prompting interno do agente. Reminders sao gerados pelo proprio
modelo Claude com base em heuristica interna do harness.

### Opcao B: Project-level CLAUDE.md com instrucao "ignore TaskCreate"

Adicionar ao `CLAUDE.md` do projeto-alvo durante a primeira onda
uma instrucao "Quando rodando dentro do agente-00c, ignore
TaskCreate/TaskUpdate reminders".

**Viabilidade**: MEDIA. CLAUDE.md e lido em CADA invocacao do Claude
Code no projeto. Funcionaria se a instrucao for forte o suficiente
para sobrepor heuristica do harness. Mas:

- E inversao de responsabilidade: poluir o CLAUDE.md do
  projeto-alvo com tracking-policy do agente-00c
- Persiste apos a execucao do 00C terminar — pode confundir
  outros workflows

### Opcao C: Permissoes / allowed-tools restritas

O frontmatter `allowed-tools` do agente-00c-orchestrator ja NAO
inclui `TaskCreate`/`TaskUpdate`. Em teoria, tentar usar essas
tools falharia. Mas reminders do harness sao emitidos
INDEPENDENTEMENTE de allowed-tools — eles sao sugestoes, nao
chamadas.

**Viabilidade**: NULA para suprimir reminders (so previne chamadas
reais).

### Opcao D: Issue/feature request ao toolkit Claude Code

Pedir suporte oficial a "context-aware reminder suppression" no
Claude Code (ex: `disabledReminders: ["TaskCreate"]` em
settings.json para sessoes/agentes especificos).

**Viabilidade**: ALTA mas externa — depende do roadmap do toolkit.
Documentar como sugestao via `suggestions.sh register --skill
"toolkit-harness" --severidade observacao`.

## Recomendacao

1. **Curto prazo (esta evolucao)**: manter a instrucao em prompt do
   orquestrador (`§Sistema canonico de tracking`). E a unica
   mitigacao 100% disponivel hoje.

2. **Medio prazo**: registrar sugestao para o toolkit Claude Code
   propondo `disabledReminders` em settings.json. Pode ser
   feature-flag de session ou hook reactivo.

3. **Nao recomendado**: poluir CLAUDE.md do projeto-alvo com policy
   do 00C (Opcao B) — viola Blast Radius Confinado (Principio V).

## Status

§4.5.2 — investigacao completada. Conclusao: hook do harness para
suprimir reminders NAO E VIAVEL com mecanismos atuais. Mitigacao
canonica e instrucao em prompt (ja documentada). Acompanhar
roadmap do Claude Code para mecanismo nativo.
