// "Add to calendar": one event, with a reminder ten minutes before. Opens
// in Apple Calendar, Google Calendar and Outlook alike.

import type { Invite } from './invite';

const stamp = (d: Date) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

/** RFC 5545 text: backslash, semicolon, comma and newlines escaped. */
const text = (s: string) => s.replace(/\\/g, '\\\\').replace(/;/g, '\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');

/** Lines longer than 75 octets continue on the next, indented by a space. */
function fold(line: string): string {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out: string[] = [];
  let cur = '';
  for (const ch of line) {
    if (enc.encode(cur + ch).length > (out.length ? 74 : 75)) {
      out.push(cur);
      cur = '';
    }
    cur += ch;
  }
  out.push(cur);
  return out.join('\r\n ');
}

export function inviteIcs(code: string, inv: Invite, url: string, now: number): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//LookUp//Invite//EN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${code}@lookup-invite`,
    `DTSTAMP:${stamp(new Date(now))}`,
    `DTSTART:${stamp(new Date(inv.start))}`,
    `DTEND:${stamp(new Date(inv.end))}`,
    `SUMMARY:${text(`${inv.title}: look up`)}`,
    `DESCRIPTION:${text([inv.look, cloudWords(inv.clouds), url].filter(Boolean).join('\n\n'))}`,
    ...(inv.place ? [`LOCATION:${text(inv.place)}`] : []),
    `URL:${url}`,
    'BEGIN:VALARM',
    'TRIGGER:-PT10M',
    'ACTION:DISPLAY',
    `DESCRIPTION:${text(`${inv.title} in 10 minutes. ${inv.look}`)}`,
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return lines.map(fold).join('\r\n') + '\r\n';
}

/** Honest words for the forecast at the time, or nothing without one. */
export function cloudWords(clouds: number | undefined): string {
  if (clouds === undefined) return '';
  if (clouds <= 25) return 'Clear skies forecast.';
  if (clouds <= 60) return 'Some cloud forecast: gaps are likely.';
  return 'Cloudy forecast: it may be hidden.';
}
