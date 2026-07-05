# Contract: Trusted Host Allowlist (US3 — install/self-update/serve)

## Lista de hosts (fonte: `cli/lib/serve.sh:31`, ja em producao — reuso, nao invencao)

```
github.com
codeload.github.com
objects.githubusercontent.com
api.github.com
```

[PROPOSTA] Extraida para `cli/lib/trusted-hosts.sh` como constante unica
`CSTK_TRUSTED_RELEASE_HOSTS="github.com codeload.github.com objects.githubusercontent.com api.github.com"`,
consumida por `serve.sh` (substitui `_SERVE_ALLOWED_HOSTS` local),
`install.sh` (`_install_resolve_urls`) e `self-update.sh` (`_su_resolve_urls`).

## Funcao de checagem (generalizacao de `_serve_check_host_allowlist`)

Contrato de comportamento (mesma logica ja testada em `serve.sh`, sem
mudanca): dado um valor de `--from`/URL de download:

1. Esquema **DIFERENTE** de `https://` → rejeita (esquema ja e outra
   checagem, preexistente e preservada — FR-014/Acceptance Scenario 1 de US3
   nao se aplica a `file://`, que segue sem checagem de host).
2. Esquema `file://` → **pula** a checagem de host inteiramente (FR-014
   explicito — fluxo de dev local nao exige allowlist).
3. Esquema `https://` → extrai o host (entre `https://` e o proximo `/`),
   compara contra `CSTK_TRUSTED_RELEASE_HOSTS` via match **EXATO** de string
   (sem wildcard/glob — os 4 valores sao dominios literais, nao padroes).
4. Host fora da lista → rejeita ANTES de qualquer download (FR-013),
   mensagem no mesmo padrao de qualidade da rejeicao de `http://` ja
   existente (ex: `"install: host '<host>' fora da lista de hosts confiaveis
   (github.com, codeload.github.com, objects.githubusercontent.com,
   api.github.com); rejeitado antes de qualquer transferencia"`).

## Pontos de aplicacao

| Arquivo | Funcao hoje | Mudanca |
|---------|-------------|---------|
| `cli/lib/install.sh` | `_install_resolve_urls` (so esquema) | adiciona checagem de host apos aceitar esquema `https`/`file` |
| `cli/lib/self-update.sh` | `_su_resolve_urls` (so esquema) | idem |
| `cli/lib/serve.sh` | `_serve_check_host_allowlist` (ja valida host) | passa a ler de `CSTK_TRUSTED_RELEASE_HOSTS` compartilhada em vez da constante local — sem mudanca de comportamento observavel |

**Explicitamente fora do escopo desta feature** (nao ha FR pedindo): `cli/lib/update.sh`
e `cli/lib/list.sh` — ambos aceitam `http://` hoje e nenhum valida host;
achado registrado em `research.md` Decision 7 como debito tecnico, nao
corrigido aqui.

## Caso `file://` (preservado, Acceptance Scenario 3 de US3)

Nenhuma mudanca de comportamento. Continua funcionando exatamente como hoje
— sem checagem de host, sem exigir presenca em allowlist.

## Garantias de seguranca do parsing de host (achado do gate `owasp-security`)

A extracao do componente host da URL MUST ser exata, nunca "contains"/
substring — caso contrario abre bypass por host confusable:

- **MUST** extrair apenas o componente authority real (entre `https://` e o
  proximo `/`, com qualquer `userinfo@` removido ANTES da comparacao) e
  compara-lo por igualdade EXATA contra cada entrada de
  `CSTK_TRUSTED_RELEASE_HOSTS`. Reusa a implementacao ja existente e testada
  de `_serve_check_host_allowlist` (`cli/lib/serve.sh`), que ja faz essa
  extracao corretamente hoje — nao reescrever do zero.
- **MUST NOT** usar `grep`/`case *pattern*` que apenas verifica se a
  substring do host confiavel APARECE em algum lugar da URL — isso aceitaria
  `https://evil.com/?x=github.com` ou `https://github.com.evil.com/...`
  como se fossem `github.com` (classe de vulnerabilidade: CWE-290,
  authentication/allowlist bypass by hostname spoofing).
- Comparacao de host MUST ser case-insensitive (DNS e case-insensitive;
  `GitHub.com` e `github.com` sao o mesmo host) — normalizar para lowercase
  antes de comparar.
- Fora de escopo desta v1 (nota, nao requisito): normalizacao de porta
  explicita (`github.com:443`) — os 4 hosts da lista nao tem porta nas fontes
  observadas; se uma URL com porta explicita aparecer, tratar como host
  diferente (rejeitar) e nao como equivalente, ate haver necessidade real.
