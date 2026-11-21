import { describe, expect, it } from 'vitest';
import { APPLE_EULA, SUPPORT_EMAIL, privacyPage, servePage } from '../src/pages';

describe('public pages', () => {
  it('serves privacy and support as HTML, and Terms as Apple\'s standard licence', async () => {
    const p = servePage('/privacy')!;
    expect(p.headers.get('content-type')).toContain('text/html');
    expect(await p.text()).toContain(SUPPORT_EMAIL);
    expect(await servePage('/support')!.text()).toContain('Limit Access');
    const t = servePage('/terms')!;
    expect(t.status).toBe(302);
    expect(t.headers.get('location')).toBe(APPLE_EULA);
    expect(servePage('/nope')).toBeNull();
  });

  it('the policy says what leaves the phone, and never claims more than the app does', () => {
    const p = privacyPage();
    for (const s of ['no analytics', 'Open-Meteo', 'half-degree', 'LookUp album', 'Limited', 'use them only to reply', 'update this page before']) expect(p).toContain(s);
    expect(p).not.toMatch(/precise location|track you across/i);
  });
});
