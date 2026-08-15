# `tests/eval/` — evals de obediência (FORA do gate de release)

Estes scripts medem o que a suíte determinística **não** consegue medir: se
um agente real, lendo a prosa dos commands, **obedece** às cláusulas que
`tests/test_*.sh` apenas verifica estarem escritas.

## Por que ficam fora de `./tests/run.sh`

O runner descobre testes por `tests/test_*.sh`; os arquivos aqui usam o
prefixo `eval_` justamente para **não** serem coletados. Isso é
deliberado, por três razões:

1. **Não-determinismo.** A saída depende de um LLM. Um eval que gateia
   release transforma a suíte em flaky e treina todo mundo a ignorar
   vermelho.
2. **Custo.** Cada execução consome tokens reais e leva minutos.
3. **Credencial.** Exige `claude` autenticado no runner — o CI do repo
   não tem, e dar essa credencial ao CI é uma decisão de segurança
   separada.

Um eval vermelho é **sinal para investigar**, nunca um bloqueio automático.

## Quando rodar

- Depois de mexer nos blocos de prompt de `plugins/cstk/commands/*.md`.
- Depois de mudar a resolução de tier em `delivery-tier.sh`.
- Antes de uma release que toque qualquer um dos dois.

## Evals disponíveis

| Script | O que mede | Origem |
|---|---|---|
| `eval_noninteractive-tier.sh` | `/agente-00c` headless: não trava no warm-up **e** resolve `cloud-public` sem operador | quickstart Cenário 17 |

## Como rodar

```sh
./tests/eval/eval_noninteractive-tier.sh
```

Exit `0` = comportamento conforme. Exit `1` = divergência (investigar).
Exit `2` = não foi possível avaliar (sem `claude` no PATH, etc.) — **não**
é reprovação.

## Histórico: por que este diretório existe

O Cenário 17 do quickstart ficou marcado `[ACEITAÇÃO MANUAL]` por toda a
feature `delivery-tier` porque ninguém sabia como testá-lo. Quando
finalmente foi executado à mão (2026-08-15), achou **dois** defeitos reais
que a suíte de 2966 cenários não pegava:

1. `/agente-00c` abortava no warm-up de permissões sem criar state-dir —
   nenhuma execução agendada conseguia iniciar.
2. Com o warm-up vencido, o agente **inferiu** o tier do briefing e gravou
   `local`, em vez do `cloud-public` que o FR-003 exige.

Ambos viraram correção + cobertura determinística (a decisão saiu da prosa
e virou `delivery-tier.sh resolve-initial`; o lint de classe cobre a
cláusula em todos os commands). O resíduo — obediência em runtime — é o
que estes evals cobrem.

**Armadilha registrada**: na primeira inspeção do spike, `delivery-tier.sh
get` devolveu `cloud-public` e parecia confirmar sucesso. Era o fail-safe
de *state-dir inexistente* — o command havia abortado antes de criar
qualquer estado. **Sempre confirme que o state-dir existe** antes de dar
um eval por aprovado; um valor correto pelo motivo errado é pior que um
vermelho.
