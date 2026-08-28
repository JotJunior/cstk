/**
 * fetchApi<T> — cliente tipado para ApiEnvelope<T>.
 *
 * Suporte a ETag/304:
 *  - Armazena ETag por path em localStorage (prefixo "etag:")
 *  - Envia If-None-Match se ETag existe
 *  - 304: retorna dados do cache sem re-parsear body
 *  - 200: valida shape com ApiEnvelopeSchema (Zod), persiste ETag
 *
 * Conteudo UNTRUSTED (campos like contexto/justificativa) chegam como
 * string crua — a UI usa TextRaw para renderizar sem dangerouslySetInnerHTML.
 */
import { ApiEnvelopeSchema, type ApiEnvelope } from '@cstk-panel/shared-types';
import { z } from 'zod';

// Silence unused-import on RawApiEnvelopeSchema (available for callers via shared-types direct import)
void 0;

const BASE_URL = '/api/v1';
const ETAG_PREFIX = 'etag:';
const BODY_PREFIX = 'body:';

/** Armazena o ultimo body parseado por path (cache de 304). */
const bodyCache = new Map<string, unknown>();

function etagKey(path: string): string {
  return ETAG_PREFIX + path;
}

function getStoredEtag(path: string): string | null {
  try {
    return localStorage.getItem(etagKey(path));
  } catch {
    return null;
  }
}

function storeEtag(path: string, etag: string): void {
  try {
    localStorage.setItem(etagKey(path), etag);
  } catch {
    // localStorage can fail in some browsers — best-effort
  }
}

/** Parse envelope com schema Zod. Lanca ZodError se shape invalida. */
function parseEnvelope<T>(json: unknown, dataSchema: z.ZodType<T>): ApiEnvelope<T> {
  return ApiEnvelopeSchema(dataSchema).parse(json) as unknown as ApiEnvelope<T>;
}

/**
 * Busca dados tipados da API com suporte a ETag/304.
 *
 * @param path  - caminho relativo (ex: '/overview')
 * @param dataSchema - schema Zod para o campo `data` do envelope
 * @param init  - opcoes extras para fetch
 */
export async function fetchApi<T>(
  path: string,
  dataSchema: z.ZodType<T>,
  init?: RequestInit
): Promise<ApiEnvelope<T>> {
  const url = `${BASE_URL}${path}`;
  const storedEtag = getStoredEtag(path);

  const headers: Record<string, string> = {
    Accept: 'application/json',
    ...(init?.headers as Record<string, string> | undefined),
  };

  if (storedEtag) {
    headers['If-None-Match'] = storedEtag;
  }

  const res = await fetch(url, { ...init, headers });

  // 304 Not Modified: retornar cache sem re-parsear body
  if (res.status === 304) {
    const cached = bodyCache.get(path);
    if (cached) {
      return cached as ApiEnvelope<T>;
    }
    // Cache miss inesperado apos 304 — refetch sem ETag
    const res2 = await fetch(url, {
      ...init,
      headers: { Accept: 'application/json' },
    });
    if (!res2.ok) {
      throw new Error(`HTTP ${res2.status} em ${path}`);
    }
    const json = await res2.json();
    const data = parseEnvelope(json, dataSchema);
    bodyCache.set(path, data);
    const newEtag = res2.headers.get('ETag');
    if (newEtag) storeEtag(path, newEtag);
    return data;
  }

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} em ${path}`);
  }

  const json = await res.json();
  const data = parseEnvelope(json, dataSchema);

  // Persistir ETag e body para proximas requisicoes
  const etag = res.headers.get('ETag');
  if (etag) {
    storeEtag(path, etag);
    bodyCache.set(path, data);
  }

  return data;
}

/** Limpar ETag + cache de um path (forcar refetch). */
export function invalidateEtag(path: string): void {
  try {
    localStorage.removeItem(ETAG_PREFIX + path);
    localStorage.removeItem(BODY_PREFIX + path);
  } catch {
    // best-effort
  }
  bodyCache.delete(path);
}
