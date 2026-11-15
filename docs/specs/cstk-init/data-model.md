# Data Model: cstk-init

Sem persistencia propria (research Decision 10): as entidades existem durante uma
execucao, como linhas TSV emitidas pelos scripts e como estrutura do relatorio na
conversa. Os unicos artefatos persistidos sao os documentos do projeto-alvo
(`docs/briefing.md`, `docs/constitution.md`, `docs/specs/<short>/...`).
Tokens de enum em ingles; rotulos exibidos ao operador em pt-BR.

## Entity: ProbeResult

Saida de `init-probe.sh preflight` (FR-022, edge cases "diretorio alvo inexistente" e
"arvore suja").

| Campo | Tipo | Valores / Regra |
|-------|------|-----------------|
| root | path absoluto | raiz resolvida com `pwd -P` |
| write | enum | `ok`, `denied-missing`, `denied-not-dir`, `denied-readonly` |
| vcs | enum | `git-clean`, `git-dirty`, `none` |

Regra: `write != ok` → encerra antes de qualquer escrita (exit != 0).

## Entity: ArtifactState

Saida de `init-probe.sh artifacts` (FR-008, research Decision 4).

| Campo | Tipo | Valores / Regra |
|-------|------|-----------------|
| artifact | enum | `briefing`, `constitution`, `spec` |
| state | enum | briefing: `absent`, `canonical`, `legacy`, `both`; constitution: `absent`, `present`; spec: `present` |
| path | path relativo | `-` quando `absent`; dois caminhos separados por `,` em `both` |
| detail | texto | constitution: versao lida do rodape ou `-`; spec: short-name |

## Entity: InventoryItem

Linha de `init-inventory.sh inventory` — fonte rastreavel de tudo que o modelo escreve
(Key Entity "Inventario do projeto", FR-002).

| Campo | Tipo | Valores / Regra |
|-------|------|-----------------|
| kind | enum | `readme`, `doc`, `manifest`, `ci`, `config`, `test`, `source-dir`, `license`, `changelog`, `secret-bearing`, `symlink-escape` |
| path | path relativo a raiz | nunca conteudo |

Regras: diretorios `.git`, `node_modules`, `vendor`, `dist`, `build`, `.venv`, `target`,
`.claude` sao ignorados; acima do teto de itens (default 1000, `--max-items`; FR-030a) emite `TRUNCATED\t<n-omitidos>` e o aviso ao operador e obrigatorio;
`secret-bearing` nunca tem conteudo lido (FR-019). `symlink-escape` (FR-023, dec-021): caminho cujo destino resolvido (`pwd -P`) sai da raiz; e listado (so o caminho do link) e nunca lido nem seguido, de modo que nada fora da raiz entra no inventario. Valores de configuracao nunca fazem parte de uma linha (FR-024): so o caminho.

## Entity: Divergence

Linha de `init-conformance.sh check` (Key Entity "Relatorio de conformidade", FR-009).

| Campo | Tipo | Valores / Regra |
|-------|------|-----------------|
| artifact | path relativo | artefato avaliado |
| rule | id | `missing-section` (derivada de template) ou `CR-NNN` (catalogo) |
| detail | texto | titulo ausente ou descricao da regra |
| proposal | enum | `add-section`, `migrate-path`, `fix-footer`, `add-principle`, `add-delta-section`, `manual` |
| decision | enum | `pending` → `accepted` / `refused` (definido na conversa) |

### State Transitions

```
pending --(operador confirma)--> accepted --(Edit + guard + scan ok)--> applied
pending --(operador recusa)----> refused   (arquivo byte a byte igual; SC-004)
pending --(sem resposta / nao-interativo)--> pending (listada no resumo)
accepted --(scan detecta segredo)--> pending (valor redigido por Edit, campo `[PENDENTE: ...]`, reescaneado)
```

## Entity: EvidenceSignal

Linha de `init-candidates.sh evidence` (FR-014, dec-008).

| Campo | Tipo | Valores / Regra |
|-------|------|-----------------|
| signal | enum | `source-module`, `test-group`, `doc-page`, `workspace` |
| key | texto | nome normalizado do sinal (ultimo segmento do caminho) |
| path | path relativo | evidencia citavel |

## Entity: FeatureCandidate

Agrupamento de `EvidenceSignal` feito pelo modelo; existe so na conversa.

| Campo | Tipo | Regra |
|-------|------|-------|
| suggested_name | kebab-case | validado por `init-candidates.sh name` |
| evidence | lista de paths | >= 1, todos presentes no inventario |
| decision | enum | `proposed`, `confirmed`, `renamed`, `merged`, `split`, `discarded` |
| collision | enum | `free`, `exists-active`, `exists-archived` |
| outcome | enum | `spec-created`, `kept-existing`, `skipped`, `none` |

### Relationships

- `FeatureCandidate` 1..N `EvidenceSignal`.
- `FeatureCandidate` (confirmada) 0..1 spec reconstituida; 0..N documentos complementares.

### State Transitions

```
proposed -> confirmed | renamed | merged | split | discarded
confirmed|renamed --(collision=free)--> spec-created
confirmed|renamed --(collision!=free)--> kept-existing | skipped | renamed (FR-016)
discarded -> outcome=none (SC-005: zero spec)
```

## Entity: Pending

Campo sem fonte e sem resposta (Key Entity "Pendencia", FR-006, FR-018).

| Campo | Tipo | Regra |
|-------|------|-------|
| file | path relativo | documento onde o marcador ficou |
| line | inteiro | linha do marcador `[PENDENTE: ...]` |
| question | texto | pergunta que resolveria o campo |

Fonte deterministica: `init-provenance.sh lint` (linhas `PENDING`).

## Entity: RunSummary

Resumo exibido no fim de toda execucao (FR-020; template `templates/summary.md`).

| Campo | Conteudo |
|-------|----------|
| cstk_version | `init-probe.sh version` (ou `unknown`) |
| mode | por artefato (`create` / `review`) |
| created | arquivos criados |
| amended | arquivos alterados com confirmacao (+ emenda de versao da constitution) |
| refused | divergencias recusadas |
| pending | lista de `Pending` |
| notices | `vcs-none`, `vcs-dirty`, `secrets-scan-unavailable`, `inventory-truncated`, `non-interactive` |
| next_steps | proximas etapas SDD sugeridas (`clarify`, `plan`, `create-tasks`) |
