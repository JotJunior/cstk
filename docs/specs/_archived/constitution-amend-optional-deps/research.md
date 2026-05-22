# Research: Constitution Amendment — Optional Dependencies

Phase 0 do `/plan`. Unknowns a resolver antes do design.

## Decision 1: Posicionamento da subsecao dentro do Principio II

**Decision**: Inserir subsecao nomeada `#### Optional dependencies with graceful
fallback (amendment 1.1.0)` entre o bloco `**MUST:**` existente do Principio II
e o bloco `**Rationale:**`. A subsecao comeca apos a ultima linha do bloco MUST
(`Exit codes convencionais (0 sucesso, 1 erro geral, 2 uso incorreto)`) e antes
da linha em branco que precede `**Rationale:**`.

**Rationale**:
- Leitura linear: contribuidor que le Principio II em ordem ve primeiro a regra
  geral (MUST), entao o carve-out (optional deps), entao o rationale. Estrutura
  logica "regra → excecao → justificativa".
- Heading `####` (4 sustenidos) mantem a hierarquia: Principio II = `###`,
  subsecao = `####`. Nao quebra outline existente.
- Anotacao `(amendment 1.1.0)` no titulo da subsecao marca origem sem poluir o
  corpo — futuros amendments podem reproduzir o padrao.

**Alternatives considered**:
- **Apendice no final do arquivo** — rejeitado: contribuidor pode ler Principio II
  inteiro e nao descobrir o carve-out.
- **Novo Principio VI separado** — rejeitado: seria supervalorizar. O carve-out e
  disciplina do II, nao principio novo. Alem disso, adicionar principio exigiria
  MAJOR bump, nao MINOR.
- **Reescrever Principio II inline** — rejeitado por SC-005: texto original deve
  permanecer byte-a-byte identico.

## Decision 2: Formato das tres condicoes cumulativas

**Decision**: Lista numerada explicita com o prefixo `(a)`, `(b)`, `(c)` em linhas
separadas, cada uma com ate duas frases. Titulo operacional "Tres condicoes
cumulativas (todas MUST ser satisfeitas)" precede a lista para deixar claro que
e conjuncao, nao disjuncao.

**Rationale**:
- "Cumulativas" em prosa deixa margem; `(a) AND (b) AND (c)` explicitos eliminam
  duvida.
- Letras em vez de numeros evita confusao com numeracao de itens MUST ja
  existente.
- Duas frases max por condicao garante que SC-001 (contribuidor resolve em < 5min)
  seja alcancavel.

**Alternatives considered**:
- **Prosa corrida** — rejeitado: dificulta checagem mental item-por-item.
- **Tabela** — rejeitado: condicoes nao tem colunas naturais; tabela empobreceria.

## Decision 3: Atualizacao do Sync Impact Report

**Decision**: Editar in-place o comentario HTML `<!-- Sync Impact Report ... -->`
no topo de `docs/constitution.md`. A linha `- Version: (none) → 1.0.0 [initial
ratification]` recebe nova linha abaixo: `- Version: 1.0.0 → 1.1.0 [MINOR:
optional-deps carve-out]`. O bloco "Artefatos que precisam atualizacao" ganha
novo item apontando `docs/specs/cstk-cli/plan.md §Complexity Tracking` com
status "pendente" ate FR-010 ser cumprido.

**Rationale**:
- Constitution §Governance exige Sync Impact Report atualizado em MAJOR/MINOR.
- Manter historico de bumps em linhas sequenciais (nao substituir) fornece
  trilha de auditoria.

**Alternatives considered**:
- **Substituir a linha antiga** — rejeitado: destroi historico.
- **Bloco separado para cada bump** — redundante para MINOR; linhas sequenciais
  suficientes.

## Decision 4: Verificacao automatizada de SC-005 (preservacao byte-a-byte)

**Decision**: SC-005 exige que o bloco MUST original do Principio II permaneca
byte-a-byte identico. Verificacao manual via `diff` seria trabalhosa. Estrategia:
durante a execucao do amendment, o mantenedor (ou teste automatizado, se
for adicionado) extrai o bloco MUST original antes da edicao, salva em tempfile,
aplica edicao, extrai o bloco MUST novo, roda `diff tempfile novo-bloco`.
Expectativa: zero saida = pass. Rodado manualmente durante a tarefa de
execucao e documentado no final.

**Rationale**:
- SC-005 e um invariante simples mas facil de violar acidentalmente (ex: trocar
  um trace whitespace enquanto edita).
- Verificacao e barata (comando unico); skip seria preguica.

**Alternatives considered**:
- **Nao verificar** — rejeitado, SC-005 existe por causa do risco de edicao
  acidental.
- **Pre-commit hook** — overkill para um amendment pontual.

## Decision 5: Ordem de aplicacao entre amendment e propagacao cstk-cli

**Decision**: Sequencia: (1) aplicar amendment em `docs/constitution.md` (US-1);
(2) atualizar `docs/specs/cstk-cli/plan.md` §Complexity Tracking referenciando
o amendment (US-2, FR-010); (3) re-rodar `/analyze` em `docs/specs/cstk-cli/`
para verificar que D1 deixa de aparecer como CRITICAL (US-2, FR-009); (4) marcar
o item correspondente no Sync Impact Report como "resolvido". Passos 1 e 2 sao
edicoes locais; passo 3 e validacao; passo 4 e bookkeeping.

**Rationale**:
- Inverter a ordem (atualizar plan do cstk-cli antes de amendar a constitution)
  referenciaria um amendment inexistente — inconsistente.
- Passo 3 e a prova de que o amendment cumpriu seu objetivo (tirar D1 do
  CRITICAL); pular equivale a confiar sem verificar.

**Alternatives considered**:
- **Paralelo** — rejeitado: FR-010 exige referenciar o amendment ja ratificado;
  se amendment for revertido, plan fica orfao.

## Decision 6: Formato da referencia ao primeiro caso concreto (jq em cstk-cli)

**Decision**: Na subsecao nova, apos listar as tres condicoes, adicionar
paragrafo: `Primeiro caso concreto sob esta regra: dep opcional em `jq` em
`cli/lib/hooks.sh` da feature cstk-cli, introduzida em amendment 1.1.0. Ver
[docs/specs/cstk-cli/spec.md](specs/cstk-cli/spec.md) §FR-009d e
[docs/specs/cstk-cli/plan.md](specs/cstk-cli/plan.md) §Complexity Tracking.`

Links sao relativos ao path do arquivo constitution.md, que vive em `docs/`.

**Rationale**:
- Um unico paragrafo e suficiente; expandir para tabela de casos seria prematuro
  (so ha um caso hoje).
- Links relativos funcionam em qualquer renderer Markdown (GitHub, VS Code,
  mdbook).

**Alternatives considered**:
- **Apenas mencao textual sem link** — rejeitado: SC-007 exige rastreabilidade
  bidirecional.
- **Tabela de casos registrados** — prematuro; sera adicionada quando houver
  segundo caso.
