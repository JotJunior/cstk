/**
 * TextBlockRaw — variante multi-linha de TextRaw para conteudo UNTRUSTED
 * (feature session-tail, FR-005, Principio V).
 *
 * NUNCA usa dangerouslySetInnerHTML. O conteudo e inserido via React
 * children (string) dentro de um `<pre>` — React escapa automaticamente
 * todo HTML/markup ativo, produzindo textContent literal mesmo quando o
 * texto se parece com uma instrucao ou contem `<script>`.
 *
 * Ref: contracts/sessions-api.md (`SessionTailEntryDTO.text`); tasks.md
 * §6.2; quickstart.md Cenario "conteudo com formatacao/comandos embutidos".
 */
import React from 'react';

interface TextBlockRawProps {
  /** Campo UNTRUSTED — sera renderizado como textContent puro, multi-linha. */
  value: string | null | undefined;
  /** Classe CSS adicional. */
  className?: string;
  /** Numero maximo de caracteres antes de truncar (alem de FR-006 no servidor). */
  maxLength?: number;
}

export function TextBlockRaw({ value, className = '', maxLength }: TextBlockRawProps) {
  if (value == null || value === '') {
    return (
      <div className={`text-block-raw${className ? ' ' + className : ''}`} style={{ color: 'var(--text-3)' }}>
        -
      </div>
    );
  }

  const display =
    maxLength != null && value.length > maxLength
      ? value.slice(0, maxLength) + '…'
      : value;

  return (
    <pre className={`text-block-raw${className ? ' ' + className : ''}`}>
      {/* React escapa automaticamente — nenhum HTML/markup e interpretado */}
      {display}
    </pre>
  );
}
