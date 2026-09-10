# Data Model: roadmap-mode

**Feature**: `roadmap-mode`
**Escopo**: modelo de **documento** (artefato Markdown versionado no
repositorio do projeto-alvo) + um campo de estado de execucao. Nao ha
modelo de banco de dados nesta feature — ver "Nao-entidades" ao final.

---

## Entity: Roadmap

Artefato canonico de nivel de projeto (`<projeto-alvo>/docs/roadmap.md`),
irmao de `docs/briefing.md` e `docs/constitution.md`. Nao pertence a
nenhuma feature e nao vive sob `docs/specs/`.

| Campo | Tipo | Obrigatorio | Notas |
|---|---|---|---|
| `titulo` | texto | sim | heading H1 do documento |
| `gerado_por` | texto | sim | proveniencia: comando + modo que produziu |
| `atualizado_em` | data ISO (`YYYY-MM-DD`) | sim | data da ultima geracao/merge |
| `entradas` | lista de `EntradaDeRoadmap` | sim | >= 1; ordenada por `ordem` |

**Invariantes**:

- `entradas` nunca e vazia. Um roadmap sem entradas nao e um roadmap
  valido — a geracao que resultaria em zero entradas e erro, nao artefato.

  > **Assimetria deliberada produtor vs leitor**: o gate de conclusao
  > (produtor) **reprova** um roadmap de 0 entradas — nao deixa a etapa
  > concluir. Ja o leitor de portfolio (`roadmap-status.sh`) trata 0
  > entradas como sucesso com aviso, nao como erro. Nao e contradicao:
  > o produtor deve impedir que o artefato invalido exista, e o leitor
  > nao deve derrubar o relatorio global por causa de um artefato que
  > alguem editou a mao. Rigor na escrita, tolerancia na leitura.
- `short-name` e unico dentro de `entradas` (chave natural, Decision 5).
- O documento e a **fonte da verdade da intencao** (quais features, em
  que ordem, por que). Nao e fonte da verdade do **progresso** — esse e
  derivado do portfolio (Decision 4).

**Relacionamentos**:

- `Roadmap` 1—N `EntradaDeRoadmap` (composicao; entradas nao existem fora
  de um roadmap).
- `EntradaDeRoadmap` 0..1—1 diretorio de feature em
  `docs/specs/<short-name>/` (associacao fraca por convencao de nome; a
  ausencia do diretorio e informacao valida, significa `nao-iniciada`).

---

## Entity: EntradaDeRoadmap

Uma feature sugerida. E a unidade consumida pelo `/feature-00c`.

| Campo | Tipo | Obrigatorio | Notas |
|---|---|---|---|
| `short_name` | texto kebab-case | sim | **chave natural**; deve casar `^[a-z][a-z0-9-]*$` |
| `ordem` | inteiro >= 1 | sim | posicao sugerida de execucao; unica no roadmap |
| `descricao` | texto | sim | acionavel — suficiente para iniciar a feature sem reescrever contexto |
| `depende_de` | lista de `short_name` | sim | pode ser vazia (representada por `-`) |
| `justificativa` | texto | sim | por que a feature e considerada necessaria |
| `status` | enum derivado | — | **nunca persistido**; calculado na leitura |

**Enum `status`** (derivado — Decision 4):

| Valor | Condicao observada |
|---|---|
| `nao-iniciada` | `docs/specs/<short_name>/` nao existe |
| `em-andamento` | diretorio existe, mas `tasks.md` ausente ou com pendentes |
| `concluida` | `tasks.md` existe e nao tem nenhuma linha pendente |

**Validacoes**:

- `short_name` MUST casar `^[a-z][a-z0-9-]*$` — mesma regra que o
  `/feature-00c` aplica ao seu argumento de short-name
  (`plugins/cstk/commands/feature-00c.md:93`). Entrada que nao casa e
  invalida na origem: o gerador corrige antes de escrever, nunca deixa
  para o consumidor descobrir.
- `short_name` MUST NOT colidir com uma feature ja existente em
  `docs/specs/` com intencao diferente — colisao de nome e resolvida
  **reusando** a entrada existente (FR-005), nunca gerando um nome
  alternativo.
- Cada valor em `depende_de` MUST existir como `short_name` de outra
  entrada do mesmo roadmap (integridade referencial interna).
- O grafo formado por `depende_de` MUST ser aciclico, e `ordem` MUST ser
  compativel com ele: se `A` depende de `B`, entao `ordem(B) < ordem(A)`.
- `descricao` e `justificativa` sao **propostas de escopo** (julgamento
  de design, permitido pelo Principio VI). Qualquer dado factual
  concreto citado nelas (endpoint, assinatura, valor) exige fonte
  rastreavel; sem fonte, o texto descreve a capacidade sem afirmar fatos
  externos (FR-008).

**State transitions**: nenhuma no artefato. O `status` derivado transita
`nao-iniciada → em-andamento → concluida` como **consequencia observada**
do trabalho no portfolio, nunca por escrita no roadmap. Nao ha transicao
reversa automatica; se um diretorio de feature e removido, a entrada
volta a `nao-iniciada` por derivacao — comportamento correto e desejado.

---

## Entity: ModoDeExecucao (campo de estado)

Nao e uma entidade nova no state: e um **campo booleano top-level**
adicionado ao documento de estado da execucao ja existente.

| Campo | Tipo | Default | Persistencia |
|---|---|---|---|
| `.roadmap_mode_enabled` | booleano | `false` | `execution.extra_fields` sob backend SQLite; campo top-level sob backend JSON |

**Invariantes**:

- Default `false` — ausencia do campo e lida como `false`, garantindo
  que execucoes anteriores (sem o campo) sigam a pipeline completa
  (retro-compatibilidade + SC-003).
- Escrito uma unica vez, no `init` da execucao. Retomadas leem do
  estado e nunca re-perguntam ao operador (paridade com
  `.atomic_commit_enabled`).
- Nao exige migracao de schema — verificado empiricamente (Decision 1).

---

## Nao-entidades (fora de escopo, deliberadamente)

- **Tabela de roadmap na `knowledge.db`**: nao criada. O indice de
  conhecimento e derivado e reconstruivel; o roadmap ja e versionado em
  git no projeto-alvo, que e a fonte da verdade adequada.
- **Coluna `roadmap_mode_enabled` em `state.db`**: nao criada
  (Decision 1).
- **Registro de progresso por entrada**: nao existe — o progresso e
  derivado (Decision 4).
