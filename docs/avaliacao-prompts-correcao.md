# Prompts de correção — backlog priorizado

Prompts prontos para colar no Claude Code, derivados da avaliação do projeto.
Cada prompt é autocontido: traz contexto, caminhos e critérios de aceite.
Resolva na ordem dos blocos (P0 → P1 → P2).

---

## Bloco P0 — Agora (baixo custo, alto impacto)

### P0.1 — Adicionar arquivo LICENSE formal

```
O README.md anuncia licença MIT (badge na linha 4 e seção "## Licença" no fim do
arquivo), mas não existe arquivo LICENSE em lugar nenhum do repositório. Como o
projeto é distribuído publicamente via `curl | sh`, isso é uma lacuna jurídica.

Crie um arquivo LICENSE na raiz com o texto oficial da licença MIT, preenchendo
o titular dos direitos (JotJunior) e o ano corrente. Ajuste o link do badge MIT
no README.md para apontar para ./LICENSE em vez de #licença. Confirme que a
seção "## Licença" no fim do README continua coerente.

Critério de aceite: arquivo LICENSE válido na raiz; badge e seção do README
apontando para ele.
```

### P0.2 — Corrigir números desatualizados na documentação de entrada

```
Há drift entre a documentação voltada ao usuário e o estado real do repositório:

1. README.md (por volta da linha 23) afirma "20 skills globais", mas existem 23
   pastas em global/skills/. A árvore listada no README também omite
   agente-00c-runtime, model-selector e decision-tree.
2. CLAUDE.md afirma "~237 scenarios" na suíte de testes, mas `tests/run.sh --list`
   reporta 1052 cenários.

Conte o número real de skills (pastas em global/skills/) e o número real de
cenários (`./tests/run.sh --list | grep -c "::"`), e corrija ambos os arquivos.
Inclua as três skills ausentes na árvore do README. Não invente outros valores:
derive tudo do repositório.

Critério de aceite: contagens no README.md e CLAUDE.md batem com a realidade;
árvore do README lista todas as skills existentes.
```

### P0.3 — Automatizar verificação de números derivados (anti-drift)

```
Para evitar que os números do README/CLAUDE.md voltem a divergir do repositório
(ver P0.2), crie um teste no harness existente (tests/) que valide os valores
derivados: contagem de skills em global/skills/ e contagem de cenários da suíte.
O teste deve falhar (exit 1) se o número documentado divergir do real.

Siga as convenções do harness em tests/lib/harness.sh e o mapeamento de cobertura
descrito em CLAUDE.md ("Como testar scripts shell"). Garanta que
`./tests/run.sh --check-coverage` continue com zero órfãos após adicionar o teste.

Critério de aceite: novo teste passa quando os docs estão corretos e falha quando
manualmente dessincronizados; suíte completa continua verde.
```

### P0.4 — Higiene de repositório (.gitignore e artefatos versionados)

```
A raiz do repositório tem artefatos que normalmente não deveriam estar sob
controle de versão: arquivos .DS_Store (vários), diretório .idea/, diretório tmp/
(incluindo tmp/exec-2026-05-18-iniciacao-membro-rolledback), e HTMLs de saída de
execução na raiz (arvore-decisoes-model-routing.html, arvore-decisoes-via-skill.html,
fluxograma-decisoes-model-routing.html).

Atualize o .gitignore para cobrir .DS_Store, .idea/ e tmp/. Remova esses arquivos
do controle de versão com `git rm --cached` (preservando-os em disco quando fizer
sentido). Decida, e justifique no commit, se os HTMLs de execução devem ser
removidos da raiz ou movidos para dist/ ou docs/. Não apague nada que seja
fonte/produto real — apenas artefatos descartáveis.

Critério de aceite: .gitignore atualizado; artefatos descartáveis fora do índice
do git; raiz do repositório limpa.
```

---

## Bloco P1 — Em seguida (estratégico)

### P1.1 — Separar narrativa de onboarding da trilha avançada

```
O projeto tem uma porta de entrada simples ("produtividade no dia a dia com
Claude Code") mas por trás existe um framework sofisticado: o orquestrador
autônomo agente-00c tem ~1535 linhas no agente principal, mais um runtime com
~15 scripts, model-routing, reconciliação de half-records e knowledge-db com
métricas em camadas. O README.md (739 linhas) mistura os dois níveis e intimida
o usuário casual.

Reestruture a documentação de entrada em duas trilhas claras:
1. Um "Getting Started" enxuto no topo do README: instalar via cstk, usar 3-4
   skills básicas, primeiro resultado em minutos.
2. Uma trilha "Avançado / Orquestrador autônomo" separada (seção própria ou
   arquivo em docs/), cobrindo agente-00c, feature-00c, recall e model-routing.

Não reescreva o conteúdo técnico existente — reorganize e sinalize o público de
cada parte. Preserve todos os links internos e o site MkDocs (mkdocs.yml).

Critério de aceite: usuário novo consegue identificar em <1 minuto o caminho
básico vs. o avançado; nenhum link quebrado; build do MkDocs (`--strict`) passa.
```

### P1.2 — Avaliar separação entre core toolkit e skills de domínio (Fotus)

```
O repositório mistura um toolkit genérico (pipeline SDD, cstk CLI, orquestrador)
com skills muito específicas de domínio: dimensionamento solar fotovoltaico
(dimensionar, montar-kit), relatório de descontos Fotus (relatorio-descontos-fotus)
e previsão (fotus-predict). Isso dilui a proposta de valor: quem quer o pipeline
SDD não quer a skill de kit solar, e vice-versa.

NÃO execute a separação ainda. Primeiro produza uma análise (documento markdown em
docs/) avaliando:
- Quais skills/MCPs são "core genérico" vs. "domínio Fotus".
- Custo/benefício de separar em plugins ou marketplaces distintos.
- Impacto na instalação via cstk (manifest, perfis em cli/lib/profiles.sh) e no
  empacotamento de release.
- Recomendação final com um plano de migração faseado, se valer a pena.

Critério de aceite: documento de decisão claro o suficiente para eu aprovar ou
recusar a separação, com plano faseado caso aprovada.
```

### P1.3 — Guia de contribuição para reduzir bus factor

```
O projeto é mantido por uma única pessoa e acumulou invariantes não-triviais
(ex.: INV-1..INV-6 do model-routing, contratos de CLI, reconciliação de
half-records, o read-back loop do recall). A documentação de specs internas é
excelente, mas falta um guia que exponha o MODELO MENTAL do sistema para um
terceiro contribuir com segurança.

Crie um CONTRIBUTING.md na raiz cobrindo:
- Como o sistema "pensa": fluxo do pipeline SDD, papel do cstk, do recall e dos
  orquestradores, em alto nível e com diagramas (use mermaid).
- Fluxo de desenvolvimento: editar fonte em global/skills ou cli/lib, rodar
  `cstk doctor` antes de editar, sincronizar com `cstk update`, regra de ouro
  dos testes 1:1 (já descrita em CLAUDE.md).
- Como adicionar uma skill nova, um comando e um teste correspondente.
- Política de versionamento (SemVer, quando bumpar MAJOR — ex.: rename de skill).

Reaproveite o conteúdo já existente em CLAUDE.md e README.md em vez de duplicar;
referencie-os quando apropriado.

Critério de aceite: um desenvolvedor externo consegue, lendo só o CONTRIBUTING.md,
entender a arquitetura e abrir um PR seguindo as convenções.
```

---

## Bloco P2 — Baixa prioridade (refinamento)

### P2.1 — Tornar a convenção de cobertura de testes mais robusta

```
A convenção atual de cobertura mapeia 1:1 o script para `test_<base>.sh`. A
release 3.19.1 já teve que tratar "falsos órfãos" porque tests com nomes
descritivos (os granulares de model-selector e tests de aspecto como
runtime-log-redaction, secrets-filter-backup, skills-cache-protocol) não casam
essa regra, e a solução foi uma allowlist de "internos" em
`tests/run.sh::_is_internal_test`. Conforme o projeto cresce, isso vai exigir
cada vez mais exceções manuais.

Avalie substituir a inferência por nome por metadados explícitos de cobertura no
cabeçalho de cada teste (ex.: um comentário `# covers: <caminho do script>`) que o
`--check-coverage` leia para montar o mapa script→teste. Mantenha
retrocompatibilidade com a convenção 1:1 onde já existe. Atualize a documentação
em CLAUDE.md e tests/README.md.

NÃO implemente direto: primeiro proponha o desenho (formato do metadado, como o
runner consome, plano de migração dos tests existentes) para eu aprovar.

Critério de aceite: proposta de desenho clara; se aprovada e implementada,
`--check-coverage` continua detectando órfãos reais sem precisar de allowlist
manual crescente.
```

---

## Como usar

Cole um prompt por vez no Claude Code, na ordem dos blocos. Os prompts P1.2 e
P2.1 pedem análise/desenho antes da execução de propósito — são mudanças com
trade-offs que valem sua aprovação antes de mexer no código.
