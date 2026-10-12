#!/usr/bin/python3
# Memory-pressure probe: allocate TOTAL MB (half random, half zero per page, ~2:1 compressible),
# then walk a HOT MB working set every second for DUR s and report walk latency.
import os, sys, time, random
TOTAL, HOT, DUR = (int(a) for a in sys.argv[1:4])
PG = 4096
with open("/proc/self/oom_score_adj", "w") as f: f.write("1000")
buf = bytearray(TOTAL << 20)
rnd = os.urandom(PG // 2)
for off in range(0, len(buf), PG):
    buf[off:off + PG // 2] = rnd if off % (64 * PG) else os.urandom(PG // 2)
print("filled", flush=True)
hot_pages = range(0, HOT << 20, PG)
cold_lo = HOT << 20
lat, cold = [], []
end = time.time() + DUR
while time.time() < end:
    t = time.perf_counter()
    for off in hot_pages: buf[off] = (buf[off] + 1) & 255
    lat.append((time.perf_counter() - t) * 1000)
    t = time.perf_counter()
    for _ in range(50): buf[random.randrange(cold_lo, len(buf), PG)] ^= 1
    cold.append((time.perf_counter() - t) * 1000)
    time.sleep(max(0, 1 - (time.perf_counter() - t)))
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(len(v) * p))]
print("hot-walk ms p50 %.1f p95 %.1f max %.1f | cold-50pg ms p50 %.1f p95 %.1f max %.1f | n=%d"
      % (pct(lat, .5), pct(lat, .95), max(lat), pct(cold, .5), pct(cold, .95), max(cold), len(lat)))
