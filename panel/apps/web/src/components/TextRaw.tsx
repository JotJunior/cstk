/**
 * TextRaw — renderiza campo UNTRUSTED como textContent puro.
 *
 * NUNCA usa dangerouslySetInnerHTML.
 * Implementa FR-011 (conteudo UNTRUSTED).
 * Ref: spec.md FR-011; quickstart §Cenario 4; constitution Principio V.
 *
 * O conteudo e inserido via React children (string) — React escapa
 * automaticamente todo HTML/script, produzindo textContent literal.
 */
import React from 'react';

interface TextRawProps {
  /** Campo UNTRUSTED — sera renderizado como textContent puro. */
  value: string | null | undefined;
  /** Se true, usa fonte monoespaco (campos tecnicos como evidencia). */
  mono?: boolean;
  /** Classe CSS adicional. */
  className?: string;
  /** Numero maximo de caracteres antes de truncar. */
  maxLength?: number;
}

export function TextRaw({ value, mono = false, className = '', maxLength }: TextRawProps) {
  if (value == null || value === '') {
    return <span className={`text-raw ${className}`} style={{ color: 'var(--text-3)' }}>-</span>;
  }

  const display =
    maxLength != null && value.length > maxLength
      ? value.slice(0, maxLength) + '…'
      : value;

  return (
    <span
      className={`text-raw${mono ? ' mono-field' : ''}${className ? ' ' + className : ''}`}
      title={maxLength != null && value.length > maxLength ? value : undefined}
    >
      {/* React escapa automaticamente — nenhum HTML e interpretado */}
      {display}
    </span>
  );
}
