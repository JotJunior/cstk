/**
 * Helpers de formatacao — portados do prototipo
 * (docs/06-ui-ux-design/castk-panel/project/components.jsx).
 *
 * Funcoes puras, sem React/DOM, testaveis em node-env.
 * Locale pt-BR; duracao a partir de segundos; "ha Xm" relativo.
 */

/** Numero compacto: >=10k vira "12.3k"; senao milhar pt-BR. */
export function fmtNum(n: number | null | undefined): string {
  if (n == null) return '—';
  if (n >= 10_000) return (n / 1000).toFixed(1).replace('.0', '') + 'k';
  return new Intl.NumberFormat('pt-BR').format(n);
}

/** Duracao a partir de segundos: "45s" | "12m 30s" | "10h 39m". */
export function fmtDur(sec: number | null | undefined): string {
  if (sec == null || sec < 0) return '—';
  if (sec < 60) return `${sec}s`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  if (m < 60) return s ? `${m}m ${String(s).padStart(2, '0')}s` : `${m}m`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}h ${String(rm).padStart(2, '0')}m`;
}

/**
 * Contagem de tokens compacta: "812" | "12.3k" | "4.06M".
 * `null` → "—" (nunca "0": ausencia de medicao nao e consumo zero —
 * Principio III; ver AgentUsageRollup em @cstk-panel/shared-types).
 */
export function fmtTokens(n: number | null | undefined): string {
  if (n == null) return '—';
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(2).replace(/\.?0+$/, '') + 'M';
  if (n >= 1_000) return (n / 1000).toFixed(1).replace('.0', '') + 'k';
  return new Intl.NumberFormat('pt-BR').format(n);
}

/** Duracao a partir de milissegundos (agent_duration_ms do schema v10). */
export function fmtMs(ms: number | null | undefined): string {
  if (ms == null || ms < 0) return '—';
  if (ms < 1000) return `${ms}ms`;
  return fmtDur(Math.round(ms / 1000));
}

/** Fracao 0..1 → percentual. */
export function fmtPct(v: number | null | undefined, digits = 0): string {
  if (v == null) return '—';
  return `${(v * 100).toFixed(digits)}%`;
}

/** ISO → "dd/mm hh:mm" pt-BR. */
export function fmtTimestamp(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  });
}

/** ISO → relativo "agora" | "ha 4m" | "ha 2h" | "ha 1d". */
export function fmtRelative(iso: string | null | undefined): string {
  if (!iso) return '—';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '—';
  const diff = (Date.now() - t) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return `ha ${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `ha ${Math.floor(diff / 3600)}h`;
  return `ha ${Math.floor(diff / 86400)}d`;
}
