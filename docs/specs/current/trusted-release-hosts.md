# Capability: trusted-release-hosts

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-012

`install` e `self-update` MUST validar o host de origem de qualquer URL remota de download contra uma lista mantida de hosts confiaveis, adicionalmente a checagem de esquema (https/file) ja existente.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-013

Uma tentativa de download cujo host nao pertence a lista de hosts confiaveis MUST ser rejeitada antes de qualquer transferencia de dado, com diagnostico claro (padrao de qualidade equivalente a rejeicao de `http://` ja existente).

*Introduzida por: enforced-guards (2026-07-28)*

### FR-014

A checagem de host confiavel MUST NOT se aplicar a origens locais (`file://`) — o fluxo de desenvolvimento local documentado do toolkit MUST continuar funcionando sem exigir presenca em allowlist de host.

*Introduzida por: enforced-guards (2026-07-28)*

