---
name: create-use-case
description: 'DEPRECATED (3.12.0, removal 4.0.0) — use specify instead. Documents a functional UC with flows, actors, business rules, test cases.'
deprecated: true
deprecated_since: "3.12.0"
remove_in: "4.0.0"
deprecated_reason: "Substituida pela skill `specify` (formato SDD com user stories, success criteria e integracao com o pipeline orquestrado pelo agente-00c). UC classico nao tem mais espaco no fluxo atual."
replacement: "specify"
argument-hint: "[descricao da funcionalidade ou caminho para documento base]"
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
---

# Skill: Criar Caso de Uso

Crie um documento de caso de uso completo seguindo o template em `templates/use-case.md` (no mesmo diretorio desta skill).

## Argumentos

$ARGUMENTS

## Instrucoes

Analise o argumento fornecido. Ele pode ser:
1. **Item de tarefa**: Descricao de funcionalidade/requisito
2. **Documento de base**: Arquivo existente com especificacoes para detalhar

### Passos para criacao

1. **Identifique o dominio** do caso de uso com base no contexto do projeto.

   O dominio e um codigo curto (2-6 letras maiusculas) que agrupa UCs relacionados.

   **Ordem de precedencia** ao derivar o dominio:
   1. Campo `domains` em `config.json` (mesmo diretorio desta skill), se
      preenchido com dominios do projeto
   2. Dominios ja usados em UCs existentes (Glob `UC-*.md` + extrair prefixos)
   3. Perguntar ao usuario via AskUserQuestion

   NAO existe uma lista universal — os dominios fazem sentido relativos ao
   projeto em questao.

   Exemplos comuns (ilustrativos — nao usar sem verificar o contexto):
   - **AUTH**: Autenticacao e autorizacao
   - **CAD**: Cadastros e dados mestres
   - **PED**: Pedidos e vendas
   - **FIN**: Financeiro e pagamentos

   Se o projeto ja tem UCs existentes, derivar os codigos usados via
   Glob `UC-*.md` e usar os mesmos padroes. Inventar codigos novos sem
   consultar convencoes existentes fragmenta a documentacao.

2. **Determine o proximo ID** disponivel:
   - Padrao: `UC-{DOMINIO}-{NUMERO}` (ex: UC-CAD-001)
   - Preferir o script `scripts/next-uc-id.sh` (mesmo diretorio desta skill):
     ```bash
     bash skills/create-use-case/scripts/next-uc-id.sh AUTH
     # → UC-AUTH-003 (ou UC-AUTH-001 se for o primeiro)

     # Listar dominios e contagem de UCs existentes:
     bash skills/create-use-case/scripts/next-uc-id.sh --list
     ```
   - Alternativa manual: Glob `UC-*.md` e incrementar o maior numero do dominio

3. **Leia o template** em `templates/use-case.md` (diretorio desta skill)

4. **Gere o documento** preenchendo todas as secoes do template

5. **Valide** contra o checklist de qualidade

6. **Salve** no diretorio de casos de uso do projeto

## Estrutura do Documento UC

O documento gerado deve conter as 14 secoes do template:

1. Informacoes Gerais (tabela com ID, Nome, Dominio, Prioridade, Versao, Status)
2. Descricao (minimo 2 paragrafos: O QUE faz e POR QUE)
3. Atores (tabela: Primario, Secundario, Sistema)
4. Pre-condicoes (lista numerada)
5. Pos-condicoes (sucesso e falha)
6. Fluxo Principal (diagrama Mermaid `sequenceDiagram` + tabela de passos)
7. Fluxos Alternativos (tabela: passo, condicao, acao)
8. Excecoes (tabela: codigo E001..E00N, excecao, tratamento)
9. Regras de Negocio (tabela: RN01..RN0N + detalhamento de regras complexas)
10. Requisitos Nao-Funcionais (tabela: RNF01..RNF0N)
11. Dados Tecnicos (mapeamento de campos, endpoints, request/response)
12. Casos de Teste (tabela: CT01..CT0N com cenario, entrada, resultado)
13. Metricas e Monitoramento (tabela: nome_metrica, descricao)
14. Dependencias (tabela: UC relacionado, relacao, descricao)
15. Referencias (links para documentos)

### Diagramas

Usar Mermaid:
- `sequenceDiagram` para fluxo principal
- `flowchart TD` para decisoes complexas
- `erDiagram` para relacionamentos de dados

### Exemplos de Qualidade

**Regra de Negocio bem escrita:**
```markdown
| ID   | Regra                                                    |
|------|----------------------------------------------------------|
| RN01 | CNPJ/CPF deve ser unico no sistema                       |
| RN02 | Razao Social e obrigatoria (minimo 3 caracteres)         |

### Detalhamento RN01 - Validacao de Documento

A validacao segue o algoritmo:
1. Remover formatacao
2. Validar digitos verificadores
3. Consultar API externa se disponivel
```

**Caso de Teste bem escrito:**
```markdown
| ID   | Cenario              | Entrada              | Resultado Esperado    |
|------|----------------------|----------------------|-----------------------|
| CT01 | Cliente PJ valido    | CNPJ 12345678000199  | CODPARC retornado     |
| CT02 | CNPJ invalido        | CNPJ 11111111111111  | Erro E001             |
```

## Checklist de Qualidade

Antes de finalizar, verificar:
- [ ] Todas as secoes obrigatorias preenchidas
- [ ] Diagrama Mermaid valido e legivel
- [ ] Regras de negocio com detalhamento quando complexas
- [ ] Casos de teste cobrindo sucesso, erro e edge cases (minimo 5)
- [ ] Mapeamento de campos completo (se integracao)
- [ ] Dependencias identificadas
- [ ] Data de criacao no rodape

## Saida Esperada

1. Gere o documento completo em Markdown
2. Pergunte ao usuario o diretorio onde salvar (ou sugira baseado no projeto)
3. Salve com Write no padrao `UC-{DOMINIO}-{NUMERO}-{nome-descritivo}.md`

---

## Gotchas

### Dominio nao e enum fixo — e convencao do projeto

A lista de dominios (AUTH, CAD, PED...) sao exemplos. Use o dominio que faz sentido no projeto atual. Se ja existem UCs, siga os codigos usados. Se o projeto e novo, pergunte ao usuario via AskUserQuestion ou configure em `config.json` — nao invente codigos novos silenciosamente.

### Glob `UC-*.md` antes de atribuir numero — senao colisao silenciosa

Dois UCs com mesmo ID (UC-CAD-001) quebram rastreabilidade e podem ser sobrescritos. Sempre listar existentes e pegar o proximo sequencial DENTRO do dominio (UC-CAD-005 nao bloqueia UC-PED-001).

### Diagrama Mermaid com ator nao declarado quebra o render

No `sequenceDiagram`, todo participante deve estar declarado no topo com `participant Nome`. Usar um ator diretamente na primeira seta sem declarar pode passar local mas falha em GitHub/viewers. Sempre declarar antes de usar.

### Minimo 5 casos de teste (sucesso + erro + edge case)

UC com 2 CTs e incompleto. A cobertura minima e: 1-2 sucessos (happy paths diferentes), 1-2 erros (validacao, permissao), 1 edge case (limite, concorrencia, timeout). Menos que isso nao esta pronto para implementacao.

### Regras de negocio RN01..RNxx precisam ser ACIONAVEIS

"Sistema deve ser robusto" e "Dados devem ser validados" nao sao regras, sao desejos. Regra acionavel: "RN01 - CNPJ deve ser unico no sistema" ou "RN02 - Limite de credito nao pode ultrapassar 3x o faturamento mensal".

### Descricao < 100 caracteres reprova

Minimo dois paragrafos explicando O QUE a funcionalidade faz e POR QUE existe. Descricao curta (uma frase) e sinal de que o UC nao foi pensado — reprova no `validate-documentation`.

### Mapeamento de campos e obrigatorio para integracoes

Se o UC envolve integracao com API externa ou entre servicos, secao "Dados Tecnicos" precisa de tabela de campos (nome externo → nome interno, tipo, transformacao). Sem isso, o plano tecnico vai chutar.