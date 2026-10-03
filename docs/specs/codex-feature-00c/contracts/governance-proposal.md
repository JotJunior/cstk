# Decisão de governança: redesenho POSIX

**Status**: alternativa POSIX autorizada pelo mantenedor em 2026-10-03,
na conversa de revisão do PR #223. A emenda para usar Python não foi aprovada.

A versão anterior introduzia Python obrigatório no adaptador, hooks,
instalador e build de release, sem exceção na constitution. O mantenedor
solicitou a reescrita e a resolução dos três achados da revisão.

O incremento foi portado para POSIX sh e awk: transporte MCP/JSONL, parser
JSON, ciclo de vida, hooks, instalação, empacotamento e testes. A biblioteca
JSON não usa eval nem jq; jq/sqlite3 permanecem nos helpers transacionais
canônicos existentes. O builder de release deixa de depender de Python.

As seis skills recebem triggers explícitos e Gotchas. A regra constitucional
permanece vigente, sem alteração de versão, carve-out ou Sync Impact Report
por emenda. A mudança do pacote experimental para 0.6.0 identifica a troca do
runtime e dos entrypoints públicos de .py para .sh.

O histórico do conflito permanece em review.md e
[evidência histórica](../evidence/implementation-history.md).
A validação da solução atual está em [validation-posix.md](../validation-posix.md).
Aceite semântico nativo continua condicionado aos testes reais documentados;
a escolha POSIX não equivale a certificação desses testes.
