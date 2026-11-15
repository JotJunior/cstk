# Resumo de execucao — cstk-init

Template do `SKILL.md` (passo final, obrigatorio em TODA execucao, inclusive as que encerram cedo). Este arquivo e um TEMPLATE de skill, nao um relatorio de sessao. Apresente o resultado preenchido na conversa (nao grave arquivo). Entidade: RunSummary (FR-020). Regras: so caminho e nome de chave, NUNCA valor de configuracao ou de segredo (FR-024); pendencia vem das linhas `PENDING` de `init-provenance.sh lint`; secao sem itens diz `nenhum`.

```markdown
## Resumo — cstk-init

**Projeto**: <raiz resolvida (ROOT de init-probe.sh preflight)>
**Versao do cstk usada como padrao**: <versao | unknown> (origem: <plugin-json | manifest | unknown>)
**Modo**: briefing = <create | review | nenhum>; constitution = <create | review | nenhum>; features = <registradas | recusado | nao oferecido>

### Arquivos criados
- `<caminho>` — <briefing | constitution | spec | data-model | checklist>

### Arquivos alterados (com confirmacao)
- `<caminho>` — <operacao: amend | migrate>; <o que mudou, ex.: secao acrescentada, versao 1.0.0 -> 1.1.0, movido para docs/briefing.md>

### Divergencias recusadas
- `<caminho>` — <regra: CR-NNN | missing-section> — recusada pelo operador (arquivo identico ao original)

### Divergencias pendentes de decisao (nao aplicadas)
- `<caminho>` — <regra> — <motivo: manual | modo nao-interativo | sem confirmacao>

### Campos pendentes
- `<caminho>:<linha>` — <pergunta do marcador [PENDENTE: ...]>

### Avisos (notices)
- <vcs-none | vcs-dirty | secrets-scan-unavailable | inventory-truncated | non-interactive> — <uma linha de contexto>
- (modo nao-interativo com briefing criado) briefing gravado sem revisao do operador — conteudo so descritivo com origem e `[PENDENTE: ...]`

### Perguntas em aberto (so modo nao-interativo)
- <pergunta que ficou sem resposta>

### Proximos passos sugeridos (pipeline SDD)
1. `/clarify` nas specs registradas com campos `[PENDENTE: ...]` ou ambiguidades
2. `/plan` e depois `/create-tasks` para features que vao evoluir
3. `/reconcile-docs` quando o codigo mudar e as specs reconstituidas ficarem desatualizadas
```

## Notices — quando emitir

| Notice | Condicao |
|--------|----------|
| `vcs-none` | `init-probe.sh preflight` -> `VCS<TAB>none` (sem como desfazer; escrita so com confirmacao) |
| `vcs-dirty` | `VCS<TAB>git-dirty` |
| `secrets-scan-unavailable` | `init-guard.sh scan --probe` exit 4: zero escritas; citar `cstk install` (perfil `sdd`) |
| `inventory-truncated` | `init-inventory.sh` terminou com `TRUNCATED<TAB><n>`: inventario, briefing e candidatas PARCIAIS |
| `non-interactive` | `--non-interactive` ou `AGENTE_00C_STATE_DIR` definido; se o briefing foi criado nesse modo, declare tambem "briefing gravado sem revisao do operador" |

## Regras de preenchimento

- **Execucao que encerrou cedo** (preflight negado, irma do catalogo ausente, scanner indisponivel, arvore suja sem confirmacao): preencha as secoes que se aplicam, deixe `nenhum` nas demais e declare o motivo do encerramento em Avisos. Nada foi escrito = "Arquivos criados: nenhum".
- **Execucao idempotente** (projeto em conformidade, sem pendencias): "nada precisa ser criado ou alterado"; ofereca apenas etapas ainda nao realizadas (registro de features).
- Nunca liste como "criado" um arquivo que ja existia.
- `lint` `invalid` apos gravar: liste o arquivo em "Arquivos criados" e a causa (`DANGLING`/`BAD-MARKER`, linha) em Avisos, com a oferta de correcao; o arquivo NAO e removido.
- Nunca inclua valor de configuracao, token, chave ou trecho de arquivo `secret-bearing`.
