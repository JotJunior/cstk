/**
 * Icon — inline SVG feather-style (pixel-perfect do prototipo).
 * Nenhuma dependencia externa de icones.
 */
import React from 'react';

interface IconProps {
  name: string;
  size?: number;
  className?: string;
  style?: React.CSSProperties;
  'aria-hidden'?: boolean;
}

export function Icon({ name, size = 16, className, style, 'aria-hidden': ariaHidden = true }: IconProps) {
  const s = size;
  const props = {
    width: s,
    height: s,
    viewBox: '0 0 24 24' as const,
    fill: 'none' as const,
    stroke: 'currentColor' as const,
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    className,
    style,
    'aria-hidden': ariaHidden,
  };

  switch (name) {
    case 'home':
      return <svg {...props}><path d="M3 12 12 3l9 9"/><path d="M5 10v10h14V10"/></svg>;
    case 'folder':
      return <svg {...props}><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>;
    case 'git-branch':
      return <svg {...props}><circle cx="6" cy="3" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M6 5v8a4 4 0 0 0 4 4h2"/><path d="M18 8v2a4 4 0 0 1-4 4h-4"/></svg>;
    case 'activity':
      return <svg {...props}><path d="M22 12h-4l-3 9-6-18-3 9H2"/></svg>;
    case 'alert':
      return <svg {...props}><path d="M10.3 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>;
    case 'bar':
      return <svg {...props}><line x1="4" y1="20" x2="4" y2="10"/><line x1="10" y1="20" x2="10" y2="4"/><line x1="16" y1="20" x2="16" y2="14"/><line x1="22" y1="20" x2="2" y2="20"/></svg>;
    case 'check':
      return <svg {...props}><rect x="3" y="3" width="18" height="18" rx="3"/><path d="m8 12 3 3 5-6"/></svg>;
    case 'zap':
      return <svg {...props}><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>;
    case 'search':
      return <svg {...props}><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>;
    case 'sun':
      return <svg {...props}><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>;
    case 'moon':
      return <svg {...props}><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>;
    case 'chevron-down':
      return <svg {...props}><polyline points="6 9 12 15 18 9"/></svg>;
    case 'chevron-left':
      return <svg {...props}><polyline points="15 18 9 12 15 6"/></svg>;
    case 'chevron-right':
      return <svg {...props}><polyline points="9 6 15 12 9 18"/></svg>;
    case 'chevron-up':
      return <svg {...props}><polyline points="6 15 12 9 18 15"/></svg>;
    case 'external':
      return <svg {...props}><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>;
    case 'filter':
      return <svg {...props}><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>;
    case 'plus':
      return <svg {...props}><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>;
    case 'x':
      return <svg {...props}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>;
    case 'database':
      return <svg {...props}><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v6c0 1.66 4 3 9 3s9-1.34 9-3V5"/><path d="M3 11v6c0 1.66 4 3 9 3s9-1.34 9-3v-6"/></svg>;
    case 'clock':
      return <svg {...props}><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 16 14"/></svg>;
    case 'arrow-up':
      return <svg {...props}><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>;
    case 'arrow-down':
      return <svg {...props}><line x1="12" y1="5" x2="12" y2="19"/><polyline points="19 12 12 19 5 12"/></svg>;
    case 'menu':
      return <svg {...props}><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>;
    case 'users':
      return <svg {...props}><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>;
    case 'eye':
      return <svg {...props}><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/></svg>;
    case 'bolt':
      return <svg {...props}><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>;
    case 'help':
      return <svg {...props}><circle cx="12" cy="12" r="9"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>;
    case 'faq':
      return <svg {...props}><path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 8.5-8.5h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>;
    case 'retry':
      return <svg {...props}><polyline points="23 4 23 10 17 10"/><path d="M20.49 15A9 9 0 1 1 18 5.3L23 10"/></svg>;
    case 'flame':
      return <svg {...props}><path d="M8.5 14.5A2.5 2.5 0 0 0 11 17h2a4 4 0 0 0 4-4 6 6 0 0 0-6-6c-3.31 0-6 2.69-6 6 0 1.66.67 3.16 1.76 4.24"/><path d="M12 2c1 3 4 5 4 9"/></svg>;
    case 'wait':
      return <svg {...props}><circle cx="12" cy="12" r="9"/><polyline points="12 6 12 12 16 14"/></svg>;
    case 'lock':
      return <svg {...props}><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>;
    case 'cancel':
      return <svg {...props}><circle cx="12" cy="12" r="9"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>;
    case 'pause':
      return <svg {...props}><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>;
    case 'tree':
      return <svg {...props}><circle cx="12" cy="4" r="2"/><circle cx="5" cy="20" r="2"/><circle cx="19" cy="20" r="2"/><circle cx="12" cy="12" r="2"/><path d="M12 6v4M12 14l-6 4M12 14l6 4"/></svg>;
    case 'doc':
      return <svg {...props}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="17" x2="15" y2="17"/></svg>;
    case 'cpu':
      return <svg {...props}><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/></svg>;
    case 'spark':
      return <svg {...props}><path d="M3 12c3 0 3-6 6-6s3 6 6 6 3-4 6-4"/></svg>;
    case 'package':
      return <svg {...props}><path d="m12 2 8 4v12l-8 4-8-4V6z"/><path d="M4 6l8 4 8-4"/><line x1="12" y1="10" x2="12" y2="22"/></svg>;
    case 'sort':
      return <svg {...props}><polyline points="8 4 8 20"/><polyline points="5 17 8 20 11 17"/><polyline points="16 20 16 4"/><polyline points="13 7 16 4 19 7"/></svg>;
    case 'globe':
      return <svg {...props}><circle cx="12" cy="12" r="9"/><line x1="3" y1="12" x2="21" y2="12"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>;
    default:
      return <svg {...props}><circle cx="12" cy="12" r="9"/></svg>;
  }
}
