# Contracts: Instalação Codex

**Fonte**: cli/cstk, cli/lib/install.sh, cli/lib/install-codex.sh e
scripts/build-release.sh. Contrato existente, inventariado em 2026-10-02.

## Command: cstk install --cli=codex

No checkout: `sh cli/cstk install --cli=codex`. A CLI global só oferece o
fluxo quando sua versão contém o adaptador. Aceita também `--cli codex`;
Claude continua default e --cli=claude/claude-code seleciona o caminho Claude.

| Opção | Tipo | Efeito |
|-------|------|--------|
| --cli | string | codex seleciona o adaptador |
| --codex-home | path | Instalação isolável; default CODEX_HOME ou ~/.codex |
| --knowledge-db | path | Banco explícito; default CSTK_KNOWLEDGE_DB ou ~/.claude/cstk/knowledge.db |
| --dry-run | flag | Relatório de preparação sem instalar/escrever |
| --from | origem do catálogo | Reutiliza o fluxo verificado da CLI |

O alvo Codex instala globalmente as seis entradas; perfis sdd/all. Não
representa um conjunto parcialmente instalado por projeto. Ver validação
real de opções em cli/lib/install.sh antes de adicionar outra combinação.

## Efeitos observados

Codex com capacidade plugin add e utilitário SHA-256 são verificados antes
da instalação. Checkout usa source-tree; release inclui catalog/codex e segue
verificação de origem/hash existente. Não há instalação de pip nem auth.

CODEX_HOME/cstk contém packages/<versão>-<hash>, marketplace local estável e
install.json. Cache é mantido pelo CLI nativo. Fonte/cache/hooks gerenciados
editados recebem erro, sem sobrescrita automática. Lock de instalação exclui
escritor concorrente. Outros plugins/configurações/handlers são preservados.

mcp.json recebe CSTK_KNOWLEDGE_DB explícito. Instalar não cria/migra o banco.
Hooks são mesclados em CODEX_HOME/hooks.json; comandos apontam ao pacote por
hash. Hooks do manifest instalado ficam vazios para evitar duplicação.
Confiança/revisão é do operador. Nova sessão é necessária para usar o plugin.

## Diagnósticos e códigos do helper

| Exit | Condição |
|------|----------|
| 0 | Sucesso ou dry-run válido |
| 1 | Erro geral/dependência/capacidade/validação |
| 2 | Uso inválido do parser argparse do helper |
| 3 | Instalação já bloqueada por proprietário |
| 4 | Edição local/conflito de integridade/symlink em área gerenciada |

O shell externo pode reportar o contexto do erro; os códigos acima descrevem
o helper POSIX. Falha não é promessa de rollback de todas as operações do
CLI nativo. Recibo/hash verificados e teste de reinstalação detectam divergência.
