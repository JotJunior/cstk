# Governance Proposal: Adaptadores de executor

**Status**: proposta para revisão; não aprovada nem aplicada.
**Origem**: plan.md Constitution Check II; constitution 1.3.0, Governance.

## Problema observado

O adaptador entregue usa Python obrigatório em controllers, hooks e
instalador. A constitution exige scripts POSIX e não prevê exceção para
adaptadores de executor. O carve-out transacional não cobre esses componentes.
A autorização para desenvolver compatibilidade Codex não é registro de
ratificação deste texto.

## Alternativas concretas

1. **Emenda delimitada**: propor uma subseção do Princípio II para adaptadores
   de executor, mantendo o núcleo compartilhado POSIX. É o caminho recomendado
   para revisão porque conserva a implementação já testada e a separação
   canônica; requer aprovação do mantenedor.
2. **Redesenho POSIX**: portar controladores, hooks e instalador; manter o
   processo constitucional atual, com nova estimativa e validação de contratos.

## Texto candidato da emenda

> Adaptadores específicos de executor podem usar um runtime adicional quando
> a implementação fica confinada ao adaptador e aos seus pontos identificados
> de empacotamento/instalação; a linguagem, versão mínima e dependências são
> explicitadas na spec/plan; ausência produz diagnóstico imediato; o núcleo
> compartilhado e seus scripts permanecem POSIX; os fluxos que não selecionam
> o adaptador continuam funcionando sem a dependência adicional; os testes
> comprovam esses limites; nenhuma regra canônica da pipeline é duplicada.

## Superfície que deve ser declarada numa proposta de emenda formal

- adapters/codex (runtime e hooks);
- cli/lib/install-codex.py (instalação selecionada);
- scripts/build-codex-plugin.py e integração build-release.sh (distribuição);
- versão mínima Python e contrato de diagnóstico a definir explicitamente;
- fallback/preservação do caminho Claude e impacto do build de release.

## Critérios para fechar o bloqueio

Decisão real do mantenedor; emenda em spec própria conforme Governance;
classificação SemVer pelo efeito da regra; Sync Impact Report e propagação
exigida às features ativas/CLAUDE.md; testes de limites/dependências e novo
Constitution Check. Não presumir que ampliar a regra seja MINOR: redefinir
um MUST pode exigir MAJOR conforme a classificação da emenda.

A padronização atual apenas torna a decisão revisável. Não modifica
constitution.md nem cria consentimento no estado de execução.
