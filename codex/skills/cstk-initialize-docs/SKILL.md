---
name: cstk-initialize-docs
description: "Create standard docs hierarchy (01-09 dirs, READMEs, briefing/UCs/DER/ADRs/APIs/tests/ops). Triggers: \"inicializar docs\", \"criar estrutura docs\", \"setup documentacao\". Skip if structure exists and no --force."
---

# CSTK Adaptation

Adapted from `JotJunior/cstk` skill `initialize-docs` at commit `35922cf`.
Use this as a Codex skill; follow local repository instructions and Codex tool names when source text mentions Claude-specific commands or slash commands.

# Skill: Inicializar Estrutura de Documentacao

Inicializa a estrutura padrao de documentacao do projeto, criando diretorios e arquivos de template.

## Argumentos

the user's request

## Instrucoes

Execute os seguintes passos para inicializar a estrutura de documentacao:

### 1. Verificar Estrutura Atual

Primeiro, verifique o diretorio `docs/` atual usando Glob e Bash.

### Configuracao

Se `config.json` existe no diretorio desta skill, usar a estrutura customizada
nele definida (campo `structure`, `docs_dir`, `keep_in_root`, `file_routing`).
Caso contrario, usar a estrutura default 01-09 documentada abaixo.

### 2. Estrutura Padrao de Diretorios

Crie os seguintes diretorios (se nao existirem):

```
docs/
-- 01-briefing-discovery/      # Documentos de briefing, requisitos iniciais
-- 02-requisitos-casos-uso/    # Casos de uso (UC-XXX-*.md)
-- 03-modelagem-dados/         # DERs, schemas de banco (DER-*.md)
-- 04-arquitetura-sistema/     # ADRs, diagramas de arquitetura (ADR-*.md)
-- 05-definicao-apis/          # Contratos de API
|   -- REST/                   # APIs REST
|   -- gRPC/                   # Definicoes gRPC/protobuf
|   -- WEBHOOKS/               # Webhooks
|   -- MESSAGING/              # Mensageria (RabbitMQ, Kafka, etc)
-- 06-ui-ux-design/            # Wireframes, mockups, guias de estilo
-- 07-plano-testes/            # Planos de teste, casos de teste
-- 08-operacoes/               # Runbooks, procedimentos operacionais
-- 09-entregaveis/             # Documentos de entrega, releases notes
```

### 3. Criar Diretorios

Preferir o script `scripts/scaffold.sh` (mesmo diretorio desta skill), que
cria todos os diretorios, gera READMEs template e e idempotente:

```bash
# Dry-run para ver o que seria feito
bash skills/initialize-docs/scripts/scaffold.sh --dry-run

# Criar estrutura
bash skills/initialize-docs/scripts/scaffold.sh

# Forcar reescrita de READMEs
bash skills/initialize-docs/scripts/scaffold.sh --force

# Usar diretorio customizado
bash skills/initialize-docs/scripts/scaffold.sh --dir=documentation
```

Alternativa manual (sem script), se o script nao estiver disponivel:

```bash
mkdir -p docs/01-briefing-discovery docs/02-requisitos-casos-uso \
         docs/03-modelagem-dados docs/04-arquitetura-sistema \
         docs/05-definicao-apis/REST docs/05-definicao-apis/gRPC \
         docs/05-definicao-apis/WEBHOOKS docs/05-definicao-apis/MESSAGING \
         docs/06-ui-ux-design docs/07-plano-testes \
         docs/08-operacoes docs/09-entregaveis
```

### 4. Criar READMEs Template

Para cada diretorio, crie um README.md se nao existir, com:
- Descricao do proposito do diretorio
- Convencoes de nomenclatura
- Tipos de arquivo esperados
- Links para templates relevantes

#### docs/README.md (Principal)

```markdown
# Documentacao do Projeto

| Diretorio | Descricao |
|-----------|-----------|
| [01-briefing-discovery](./01-briefing-discovery/) | Documentos iniciais, briefings, requisitos de negocio |
| [02-requisitos-casos-uso](./02-requisitos-casos-uso/) | Casos de uso detalhados (UC-*) |
| [03-modelagem-dados](./03-modelagem-dados/) | Modelagem de dados, DERs, schemas |
| [04-arquitetura-sistema](./04-arquitetura-sistema/) | Decisoes de arquitetura (ADR-*), diagramas |
| [05-definicao-apis](./05-definicao-apis/) | Contratos de API (REST, gRPC, Webhooks) |
| [06-ui-ux-design](./06-ui-ux-design/) | Wireframes, mockups, guias de estilo |
| [07-plano-testes](./07-plano-testes/) | Planos e casos de teste |
| [08-operacoes](./08-operacoes/) | Runbooks, procedimentos operacionais |
| [09-entregaveis](./09-entregaveis/) | Release notes, documentos de entrega |

## Convencoes de Nomenclatura

- **UC-XXX-NNN**: Caso de Uso
- **ADR-NNN**: Architectural Decision Record
- **DER-XXX**: Diagrama Entidade-Relacionamento
- **TC-NNN**: Test Case
- **RB-NNN**: Runbook
```

### 5. Mover Arquivos Existentes

Se existirem arquivos na raiz de `docs/`, mova-os para os diretorios apropriados:

| Padrao do Arquivo | Destino |
|-------------------|---------|
| `UC-*.md` | `02-requisitos-casos-uso/` |
| `DER-*.md`, `SCHEMA-*.md` | `03-modelagem-dados/` |
| `ADR-*.md` | `04-arquitetura-sistema/` |
| `*-api.md`, `*.proto.md` | `05-definicao-apis/{tipo}/` |
| `TC-*.md`, `TP-*.md` | `07-plano-testes/` |
| `RB-*.md`, `RUNBOOK-*.md` | `08-operacoes/` |
| `RELEASE-*.md`, `CHANGELOG*.md` | `09-entregaveis/` |
| `*.pdf`, `BRIEFING-*.md` | `01-briefing-discovery/` |
| `tasks-*.md`, `cronograma*.md` | manter na raiz de `docs/` |

### 6. Relatorio de Execucao

Ao final, exiba um relatorio com:
- Diretorios criados
- Arquivos movidos
- Templates criados
- Avisos (arquivos que nao puderam ser movidos automaticamente)

## Opcoes de Argumento

- `--dry-run`: Apenas mostra o que seria feito, sem executar
- `--force`: Sobrescreve READMEs existentes
- `--no-move`: Apenas cria diretorios e templates, nao move arquivos

## Notas

- Este comando e idempotente - pode ser executado multiplas vezes
- Arquivos ja existentes nao sao sobrescritos (exceto com `--force`)
- Arquivos de projeto como `tasks-*.md` e `cronograma.md` sao mantidos na raiz

---

## Gotchas

### Idempotente nao significa "rodar sem pensar"

Rodar duas vezes nao estraga nada (READMEs nao sobrescritos), mas se o projeto ja tem uma organizacao ALTERNATIVA (ex: `docs/rfcs/`, `docs/guides/`), a skill vai criar 01-09 ao lado sem aviso. Antes de rodar, verificar `docs/` — se existe organizacao alternativa, perguntar ao usuario se deve coexistir ou substituir.

### tasks-*.md e cronograma*.md ficam NA RAIZ de docs/

Nao mover esses arquivos para subdiretorios. Eles sao arquivos de projeto global, nao artefatos de categoria. O mapeamento do passo 5 exclui explicitamente esses padroes.

### --force sobrescreve READMEs, nao o conteudo dos diretorios

A flag `--force` regenera os READMEs template. Nao deleta arquivos reais (UCs, ADRs) dentro dos diretorios. Mas se o usuario customizou os READMEs, --force apaga essas customizacoes.

### Movimentacao automatica pode errar em casos ambiguos

Um arquivo `API-GATEWAY-SETUP.md` pode ir para 04-arquitetura ou 05-definicao-apis dependendo do conteudo. Quando o padrao nao bate claramente, listar o arquivo no relatorio como "nao movido — requer revisao manual" ao inves de chutar.

### Mover arquivo quebra links relativos

Se `UC-CAD-001.md` referencia `../outro-doc.md`, mover o UC para `02-requisitos-casos-uso/` quebra o link. Apos mover, avisar no relatorio sobre links que podem precisar atualizacao — nao tentar corrigir automaticamente.

## Source License

This skill includes material adapted from `JotJunior/cstk`, licensed under MIT. The copyright and permission notice are included in `references/cstk-license.md`.

