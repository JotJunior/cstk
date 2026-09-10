#!/bin/sh
# Hook Elicitation: resolve a elicitation sem UI, devolvendo accept + content.
# Registrar em .claude/settings.json:
#   {"hooks":{"Elicitation":[{"matcher":"spike-url-elicit",
#     "hooks":[{"type":"command","command":"<path deste script>"}]}]}}
# O matcher casa o NOME DO SERVIDOR MCP, nao a tool.
cat > /dev/null   # troque por `cat >> input.jsonl` para capturar o payload
printf '{"hookSpecificOutput":{"hookEventName":"Elicitation","action":"accept","content":{"answer":"RESPOSTA-DO-HOOK"}}}\n'
