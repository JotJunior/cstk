#!/bin/sh
# test_secrets-filter.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/secrets-filter.sh"

scenario_scrub_token_com_palavra_chave() {
  capture sh -c "printf '%s' 'api_key=\"abc1234567890123456789xyz\"' | '$SCRIPT' scrub"
  assert_stdout_contains "[REDACTED]" || return 1
  case "$_CAPTURED_STDOUT" in
    *abc1234567890*) _fail "token nao redacted" ""; return 1 ;;
  esac
}

scenario_scrub_aws_key() {
  capture sh -c "printf '%s' 'AWS key: AKIAIOSFODNN7EXAMPLE present' | '$SCRIPT' scrub"
  assert_stdout_contains "[REDACTED-AWS-KEY]" || return 1
  case "$_CAPTURED_STDOUT" in
    *AKIAIOSFODNN7EXAMPLE*) _fail "AWS nao redacted" ""; return 1 ;;
  esac
}

scenario_scrub_bearer_token() {
  capture sh -c "printf '%s' 'Authorization: Bearer eyJhbGciOiJI.deadbeef' | '$SCRIPT' scrub"
  assert_stdout_contains "Bearer [REDACTED]" || return 1
  case "$_CAPTURED_STDOUT" in
    *eyJhbG*) _fail "bearer nao redacted" ""; return 1 ;;
  esac
}

scenario_scrub_basic_auth_em_url() {
  capture sh -c "printf '%s' 'https://admin:supersecret@db.example.com/foo' | '$SCRIPT' scrub"
  assert_stdout_contains "https://[REDACTED]@db.example.com" || return 1
  case "$_CAPTURED_STDOUT" in
    *supersecret*) _fail "basic auth nao redacted" ""; return 1 ;;
  esac
}

scenario_scrub_env_file() {
  _env="$TMPDIR_TEST/.env"
  printf 'DB_PASSWORD=mysupersecretpwd\nAPI=abcdef1234567890\n' > "$_env"
  capture sh -c "printf '%s' 'leaking mysupersecretpwd here and abcdef1234567890 there' | '$SCRIPT' scrub --env-file '$_env'"
  case "$_CAPTURED_STDOUT" in
    *mysupersecretpwd*) _fail "env DB_PASSWORD nao redacted" ""; return 1 ;;
    *abcdef1234567890*) _fail "env API nao redacted" ""; return 1 ;;
  esac
  assert_stdout_contains "[REDACTED-ENV]" || return 1
}

scenario_scrub_env_valor_curto_ignorado() {
  # Valores < 8 chars sao ignorados (alta taxa de falsos positivos)
  _env="$TMPDIR_TEST/.env"
  printf 'SHORT=ab\n' > "$_env"
  capture sh -c "printf '%s' 'has ab in middle' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "has ab in middle" || return 1
  # Nao deve ter aplicado [REDACTED-ENV]
  case "$_CAPTURED_STDOUT" in
    *REDACTED*) _fail "valor curto foi redacted indevidamente" ""; return 1 ;;
  esac
}

scenario_scrub_hash_git_nao_redacted() {
  # Hashes git (40 chars hex) sem palavra-chave NAO devem ser redacted
  capture sh -c "printf '%s' 'commit abcdef1234567890abcdef1234567890abcdef12 fixed' | '$SCRIPT' scrub"
  assert_stdout_contains "abcdef1234567890abcdef" || return 1
}

scenario_check_detecta_secret() {
  capture sh -c "printf '%s' 'api_key=abcdef1234567890123456789' | '$SCRIPT' check"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "check com secret" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "SECRETS DETECTADOS" || return 1
}

scenario_check_input_limpo_exit_0() {
  capture sh -c "printf '%s' 'just plain text without secrets' | '$SCRIPT' check"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "check limpo" "$_CAPTURED_EXIT"; return 1; }
}

# ===== allow-list de identificadores publicos (§1.3) =====

scenario_allow_list_saml_issuer_baseline() {
  # SAML_ISSUER esta na baseline `.secrets-filter-ignore` global do script.
  # Valor longo (>=30 chars) — sem allow-list seria redatado; com,
  # preservado.
  _env="$TMPDIR_TEST/.env"
  printf 'SAML_ISSUER=https://login.microsoftonline.com/abcde-12345-tenant/v2.0\n' > "$_env"
  capture sh -c "printf '%s' 'metadata at https://login.microsoftonline.com/abcde-12345-tenant/v2.0 published' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "login.microsoftonline.com" || return 1
  case "$_CAPTURED_STDOUT" in
    *REDACTED-ENV*) _fail "SAML_ISSUER foi redacted" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_allow_list_public_wildcard_baseline() {
  # PUBLIC_* na baseline → PUBLIC_API_URL nao deve ser redatado.
  _env="$TMPDIR_TEST/.env"
  printf 'PUBLIC_API_URL=https://api.example.com/v1/something/longer/than/threshold\n' > "$_env"
  capture sh -c "printf '%s' 'frontend pings https://api.example.com/v1/something/longer/than/threshold daily' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "api.example.com" || return 1
  case "$_CAPTURED_STDOUT" in
    *REDACTED-ENV*) _fail "PUBLIC_API_URL redacted" ""; return 1 ;;
  esac
}

scenario_allow_list_secret_real_ainda_redatado() {
  # DB_PASSWORD nao esta na allow-list → ainda deve ser redatado.
  _env="$TMPDIR_TEST/.env"
  printf 'SAML_ISSUER=https://login.microsoftonline.com/abcde-12345-tenant/v2.0\n' > "$_env"
  printf 'DB_PASSWORD=correcthorsebatterystaple\n' >> "$_env"
  capture sh -c "printf '%s' 'leak: correcthorsebatterystaple should redact' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "[REDACTED-ENV]" || return 1
  case "$_CAPTURED_STDOUT" in
    *correcthorsebatterystaple*) _fail "secret real nao redacted" ""; return 1 ;;
  esac
}

scenario_allow_list_override_explicito() {
  # --ignore-file override permite adicionar chave nao-baseline.
  _env="$TMPDIR_TEST/.env"
  _ig="$TMPDIR_TEST/.ignore"
  printf 'CUSTOM_PUBLIC_ID=projeto-foo-v1\n' > "$_env"
  printf 'CUSTOM_PUBLIC_ID\n' > "$_ig"
  capture sh -c "printf '%s' 'identifier projeto-foo-v1 publico' | '$SCRIPT' scrub --env-file '$_env' --ignore-file '$_ig'"
  assert_stdout_contains "projeto-foo-v1" || return 1
  case "$_CAPTURED_STDOUT" in
    *REDACTED-ENV*) _fail "override falhou" ""; return 1 ;;
  esac
}

scenario_allow_list_override_por_projeto_alvo() {
  # Auto-descoberta: `.claude/agente-00c-state/secrets-filter-ignore`
  # relativo ao diretorio do .env-file.
  _proj="$TMPDIR_TEST/proj"
  mkdir -p "$_proj/.claude/agente-00c-state"
  _env="$_proj/.env"
  printf 'INTERNAL_ID=tenant-abc-def-123\n' > "$_env"
  printf 'INTERNAL_ID\n' > "$_proj/.claude/agente-00c-state/secrets-filter-ignore"
  capture sh -c "printf '%s' 'tenant-abc-def-123 leakable?' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "tenant-abc-def-123" || return 1
}

scenario_heuristica_slug_publico_curto_nao_redatado() {
  # Valor curto (<30 chars) e slug-like (apenas A-Z, 0-9, _.-) NAO deve
  # ser redatado, mesmo sem allow-list explicita. Chave nao baseline.
  _env="$TMPDIR_TEST/.env"
  printf 'CUSTOM_SLUG=projeto-alpha-staging\n' > "$_env"
  capture sh -c "printf '%s' 'env points to projeto-alpha-staging today' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "projeto-alpha-staging" || return 1
  case "$_CAPTURED_STDOUT" in
    *REDACTED-ENV*) _fail "slug curto redacted" ""; return 1 ;;
  esac
}

scenario_heuristica_slug_valor_longo_ainda_redatado() {
  # Valor que parece slug MAS tem >=30 chars NAO se beneficia da heuristica.
  # (Sem allow-list, e redatado).
  _env="$TMPDIR_TEST/.env"
  printf 'CUSTOM_LONG=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$_env"
  capture sh -c "printf '%s' 'cred=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa here' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "[REDACTED-ENV]" || return 1
}

scenario_heuristica_slug_valor_com_caractere_especial_redatado() {
  # Valor curto mas com caractere fora de [A-Za-z0-9_.-] NAO se beneficia.
  _env="$TMPDIR_TEST/.env"
  printf 'WEIRD=pwd!@#$xyz\n' > "$_env"
  capture sh -c "printf '%s' 'leak pwd!@#\$xyz here' | '$SCRIPT' scrub --env-file '$_env'"
  assert_stdout_contains "[REDACTED-ENV]" || return 1
}

scenario_scrub_env_valor_inicia_metachar_ere_e164() {
  # Regressao issue #21: valor do .env iniciando por `+` (numero E.164 Twilio)
  # abortava com 'sed: RE error: repetition-operator operand invalid' porque
  # o valor era interpolado cru num `sed -E` (ERE) e `+` virava operador de
  # repeticao sem operando. Deve redatar sem abortar.
  _env="$TMPDIR_TEST/.env"
  printf 'TWILIO_WHATSAPP_NUMBER=+552724640808\n' > "$_env"
  capture sh -c "printf '%s' 'whatsapp +552724640808 vazou aqui' | '$SCRIPT' scrub --env-file '$_env'"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "scrub abortou" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[REDACTED-ENV]" || return 1
  case "$_CAPTURED_STDOUT" in
    *552724640808*) _fail "numero E.164 nao redacted" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_scrub_env_valor_inicia_asterisco() {
  # Mesma classe do bug: valor iniciando por `*` (metachar de repeticao).
  _env="$TMPDIR_TEST/.env"
  printf 'GLOB_SECRET=*supersecretvalue\n' > "$_env"
  capture sh -c "printf '%s' 'config has *supersecretvalue inside' | '$SCRIPT' scrub --env-file '$_env'"
  [ "$_CAPTURED_EXIT" -eq 0 ] || { _fail "scrub abortou" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "[REDACTED-ENV]" || return 1
  case "$_CAPTURED_STDOUT" in
    *supersecretvalue*) _fail "valor com * nao redacted" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ==== issue #169: segredo curto (<20 chars) e bloco PEM ====

scenario_scrub_segredo_curto_alta_confianca() {
  # Regressao issue #169: `password=hunter2` (7 chars) escapava do `{20,}` da
  # regra generica e saia EM CLARO. Regra 4b (limiar {4,}) fecha o caso.
  capture sh -c "printf '%s' 'password=hunter2' | '$SCRIPT' scrub"
  assert_stdout_contains "[REDACTED]" || return 1
  case "$_CAPTURED_STDOUT" in
    *hunter2*) _fail "segredo curto nao redacted" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_scrub_segredo_curto_variantes_de_palavra_chave() {
  for _kw in password passwd api_key apikey access_key secret_key private_key client_secret auth_token access_token refresh_token secret; do
    capture sh -c "printf '%s' '${_kw}: sk4tPr1v' | '$SCRIPT' scrub"
    case "$_CAPTURED_STDOUT" in
      *sk4tPr1v*) _fail "palavra-chave $_kw nao cobre segredo curto" "$_CAPTURED_STDOUT"; return 1 ;;
    esac
  done
}

scenario_scrub_curto_nao_redige_prosa_com_palavra_generica() {
  # Contra-prova do trade-off: `key`/`auth`/`token` genericos NAO entram na
  # regra 4b — continuam so no `{20,}` para nao redigir prosa comum.
  capture sh -c "printf '%s' 'a key: valor comum de prosa' | '$SCRIPT' scrub"
  assert_stdout_contains "key: valor" || return 1
  capture sh -c "printf '%s' 'auth: bearer' | '$SCRIPT' scrub"
  assert_stdout_contains "auth: bearer" || return 1
}

scenario_scrub_pwd_curto_preserva_diagnostico() {
  # `pwd` fica DE FORA da regra 4b de proposito: `PWD=/algum/caminho` num
  # dump de ambiente e diagnostico legitimo do enforcement-log.
  capture sh -c "printf '%s' 'PWD=/tmp/lab' | '$SCRIPT' scrub"
  assert_stdout_contains "PWD=/tmp/lab" || return 1
}

scenario_scrub_bloco_pem() {
  # Regressao issue #169: bloco PEM inteiro saia EM CLARO (corpo base64 nao
  # tem palavra-chave proxima, escapava de todas as regras).
  capture sh -c "printf -- '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\n-----END PRIVATE KEY-----\ndepois\n' | '$SCRIPT' scrub"
  assert_stdout_contains "[REDACTED-PEM-BLOCK]" || return 1
  assert_stdout_contains "depois" || return 1
  case "$_CAPTURED_STDOUT" in
    *MIIEvQIBADANBg*)   _fail "corpo PEM nao redacted" "$_CAPTURED_STDOUT"; return 1 ;;
    *"BEGIN PRIVATE"*)  _fail "marcador PEM nao removido" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_scrub_bloco_pem_check_detecta() {
  capture sh -c "printf -- '-----BEGIN RSA PRIVATE KEY-----\nZGVhZGJlZWY=\n-----END RSA PRIVATE KEY-----\n' | '$SCRIPT' check"
  [ "$_CAPTURED_EXIT" -eq 1 ] || { _fail "check deveria detectar PEM" "exit=$_CAPTURED_EXIT"; return 1; }
}

scenario_scrub_pem_mencionado_em_prosa_nao_engole_arquivo() {
  # Deteccao estrita RFC 7468 (marcador SOZINHO na linha): uma mencao inline
  # em doc/prosa nao pode suprimir o restante do arquivo.
  capture sh -c "printf '%s\n%s\n' 'doc: o marcador \`-----BEGIN PRIVATE KEY-----\` deve ser escrubado' 'linha seguinte preservada' | '$SCRIPT' scrub"
  assert_stdout_contains "linha seguinte preservada" || return 1
  case "$_CAPTURED_STDOUT" in
    *"[REDACTED-PEM-BLOCK]"*) _fail "mencao em prosa virou bloco PEM" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

run_all_scenarios
