// "Add to Apple Wallet": the invite as an event pass that comes up on the
// lock screen when it's time, with where to look on the front and the
// details on the back. Signed here with the Pass Type ID certificate (PKCS#7
// detached over manifest.json, as Apple requires), zipped as .pkpass.
//
// Only offered once the PASS_* secrets are set (README.md).

import forge from 'node-forge';
import { cloudWords } from './ics';
import type { Invite } from './invite';
import { zip } from './zip';

export type PassConfig = {
  passTypeId: string;
  teamId: string;
  certPem: string;
  keyPem: string;
  keyPassword?: string;
  wwdrPem: string;
};

export type PassImages = Record<string, Uint8Array>; // icon.png, icon@2x.png, logo.png …

async function sha1Hex(data: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-1', data));
  return [...d].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function passJson(cfg: Pick<PassConfig, 'passTypeId' | 'teamId'>, code: string, inv: Invite, url: string) {
  const expires = new Date(new Date(inv.end).getTime() + 60 * 60 * 1000).toISOString();
  const forecast = cloudWords(inv.clouds);
  return {
    formatVersion: 1,
    passTypeIdentifier: cfg.passTypeId,
    teamIdentifier: cfg.teamId,
    serialNumber: code,
    organizationName: 'LookUp',
    description: `${inv.title}: an invite to look up`,
    logoText: 'LookUp',
    foregroundColor: 'rgb(244, 246, 250)',
    backgroundColor: 'rgb(11, 19, 40)',
    labelColor: 'rgb(196, 245, 94)',
    // On the lock screen from a little before it starts until it's over.
    relevantDate: inv.start,
    relevantDates: [{ startDate: new Date(new Date(inv.start).getTime() - 15 * 60 * 1000).toISOString(), endDate: inv.end }],
    expirationDate: expires,
    eventTicket: {
      primaryFields: [{ key: 'what', label: 'LOOK UP', value: inv.title }],
      secondaryFields: [
        { key: 'when', label: 'WHEN', value: inv.start, dateStyle: 'PKDateStyleMedium', timeStyle: 'PKDateStyleShort' },
        ...(inv.face ? [{ key: 'face', label: 'FACE', value: inv.face }] : []),
      ],
      auxiliaryFields: [
        ...(inv.place ? [{ key: 'place', label: 'NEAR', value: inv.place }] : []),
        ...(forecast ? [{ key: 'sky', label: 'FORECAST', value: forecast.replace(/[.:].*$/, '') }] : []),
      ],
      backFields: [
        // The sender's words: Wallet must never turn any of them into a link or a number to call.
        { key: 'look', label: 'Where to look', value: inv.look, dataDetectorTypes: [] },
        ...(forecast ? [{ key: 'forecast', label: 'Forecast', value: forecast }] : []),
        { key: 'link', label: 'The invite', value: url, attributedValue: `<a href="${url}">Open in LookUp</a>` },
      ],
    },
  };
}

/** The signed .pkpass for one invite. */
export async function buildPass(cfg: PassConfig, code: string, inv: Invite, url: string, images: PassImages): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const files: [string, Uint8Array][] = [['pass.json', enc.encode(JSON.stringify(passJson(cfg, code, inv, url)))]];
  for (const [name, bytes] of Object.entries(images)) files.push([name, bytes]);
  const manifest: Record<string, string> = {};
  for (const [name, bytes] of files) manifest[name] = await sha1Hex(bytes);
  const manifestBytes = enc.encode(JSON.stringify(manifest));

  const cert = forge.pki.certificateFromPem(cfg.certPem);
  const wwdr = forge.pki.certificateFromPem(cfg.wwdrPem);
  const key = cfg.keyPassword
    ? forge.pki.decryptRsaPrivateKey(cfg.keyPem, cfg.keyPassword)
    : forge.pki.privateKeyFromPem(cfg.keyPem);
  if (!key) throw new Error('pass key');
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(forge.util.binary.raw.encode(manifestBytes));
  p7.addCertificate(cert);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key,
    certificate: cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
  const signature = forge.util.binary.raw.decode(der);

  return zip([...files, ['manifest.json', manifestBytes], ['signature', signature]]);
}
