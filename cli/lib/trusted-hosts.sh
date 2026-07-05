# trusted-hosts.sh — allowlist compartilhada de hosts confiaveis para
# download de artefatos de release (install/self-update/serve).
#
# Ref: docs/specs/enforced-guards/contracts/trusted-hosts.md
#      docs/specs/enforced-guards/data-model.md::TrustedHostAllowlist
#      docs/specs/enforced-guards/research.md Decision 7
#      docs/specs/enforced-guards/spec.md FR-012/FR-013/FR-014
#
# Funcao exportada:
#   trusted_host_check <url>
#     exit 0  URL usa esquema file:// (isento, FR-014) OU https:// com host
#             na allowlist (match exato, case-insensitive)
#     exit 1  esquema diferente de https/file, OU host fora da allowlist
#             (mensagem clara em stderr — o caller MUST checar o exit code
#             ANTES de iniciar qualquer download, FR-013)
#
# CSTK_TRUSTED_RELEASE_HOSTS: constante estatica, versionada no proprio
# toolkit (fonte: cli/lib/serve.sh, ja em producao antes desta feature —
# reuso, nao invencao, Constitution VI). data-model.md::TrustedHostAllowlist
# e explicito: "muda apenas via release nova do cstk (nao em runtime)" — por
# isso, ao contrario de CSTK_SERVE_ALLOW_UNVERIFIED (um bypass deliberado e
# auditado de US2), esta lista NAO e lida de env var. Alargar a allowlist via
# env silenciaria exatamente o tipo de enfraquecimento silencioso que esta
# feature existe para fechar (FR-015).
#
# Seguranca do parsing de host (CWE-290 — authentication/allowlist bypass by
# hostname spoofing, achado do gate owasp-security/dec-018 item 4): o host
# MUST ser extraido como o componente authority exato (entre o esquema e a
# primeira "/", com qualquer "userinfo@" removido ANTES da comparacao) e
# comparado por IGUALDADE EXATA (case-insensitive, pois DNS e case-
# insensitive) contra cada entrada da lista. MUST NOT usar grep/case
# *pattern* substring — isso aceitaria "https://evil.com/?x=github.com" ou
# "https://github.com.evil.com/..." como se fossem "github.com". Uma URL com
# porta explicita (ex: "github.com:443") e tratada como host DIFERENTE
# (rejeitada) — nao ha normalizacao de porta nesta v1 (nota do contrato).
#
# POSIX sh puro. Sem dependencias externas alem de: printf, sed, tr, case.

if [ -n "${_CSTK_TRUSTED_HOSTS_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_TRUSTED_HOSTS_LOADED=1

# Lista estatica de hosts confiaveis para download de releases do toolkit.
# Fonte: cli/lib/serve.sh:31 (_SERVE_ALLOWED_HOSTS), ja em producao antes
# desta feature. NAO overridable via env — ver nota acima.
CSTK_TRUSTED_RELEASE_HOSTS="github.com codeload.github.com objects.githubusercontent.com api.github.com"

# trusted_host_check URL
# Verifica que URL usa esquema https:// com host na allowlist, ou file://
# (isento). Ver contrato completo no cabecalho do arquivo.
trusted_host_check() {
  _thc_url="$1"

  case "$_thc_url" in
    file://*)
      # FR-014: fluxo de dev local documentado, sem host de rede — isento
      # por design (nao ha o que confundir, nao ha allowlist a aplicar).
      return 0
      ;;
    https://*)
      ;;
    *)
      printf 'trusted-hosts: URL rejeitada (esquema deve ser https:// ou file://): %s\n' \
        "$_thc_url" >&2
      return 1
      ;;
  esac

  # Extrai o authority exato: remove o esquema, corta na primeira "/"
  # subsequente (descarta path/query/fragment), remove userinfo
  # ("user:pass@") se presente, normaliza para lowercase. Cada passo em seu
  # proprio sed para leitura/auditoria facil — sempre igualdade exata
  # depois, nunca substring.
  _thc_host=$(printf '%s' "$_thc_url" | sed 's|^https://||; s|/.*||; s/^[^@]*@//')
  _thc_host=$(printf '%s' "$_thc_host" | tr '[:upper:]' '[:lower:]')

  for _thc_allowed in $CSTK_TRUSTED_RELEASE_HOSTS; do
    _thc_allowed_lc=$(printf '%s' "$_thc_allowed" | tr '[:upper:]' '[:lower:]')
    if [ "$_thc_host" = "$_thc_allowed_lc" ]; then
      return 0
    fi
  done

  printf 'trusted-hosts: host "%s" fora da lista de hosts confiaveis (%s); rejeitado antes de qualquer transferencia\n' \
    "$_thc_host" "$CSTK_TRUSTED_RELEASE_HOSTS" >&2
  return 1
}
