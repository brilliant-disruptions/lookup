# LookUp alert chime: two soft bell strikes rising a fifth ("look up").
import math, struct, wave, sys
sr = 44100
dur = 1.9
n = int(sr * dur)
buf = [0.0] * n
def strike(t0, f, amp):
    partials = [(1.0, 1.0, 1.6), (2.0, 0.35, 0.9), (2.76, 0.18, 0.6), (5.4, 0.06, 0.3)]
    s0 = int(t0 * sr)
    for i in range(s0, n):
        t = (i - s0) / sr
        attack = min(1.0, t / 0.006)
        v = 0.0
        for mult, a, decay in partials:
            v += a * math.exp(-t / decay * 2.2) * math.sin(2 * math.pi * f * mult * t)
        buf[i] += amp * attack * v
strike(0.00, 1318.5, 0.55)   # E6
strike(0.22, 1975.5, 0.50)   # B6
peak = max(abs(x) for x in buf)
fade = int(0.15 * sr)
out = bytearray()
for i, x in enumerate(buf):
    g = 0.7 / peak
    if i > n - fade:
        g *= (n - i) / fade
    out += struct.pack('<h', int(max(-1, min(1, x * g)) * 32767))
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(bytes(out))
