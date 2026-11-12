import math
from pathlib import Path

p = Path(__file__).parent
N = 321
# Wider ideal cutoffs leave room for finite-filter transitions at 20/30 kHz.
f1, f2 = 18000 / 1e6, 32000 / 1e6
h = []
for n in range(N):
    k = n - (N - 1) / 2
    ideal = 2 * (f2 - f1) if k == 0 else (math.sin(2*math.pi*f2*k)-math.sin(2*math.pi*f1*k))/(math.pi*k)
    h.append(ideal * (0.54 - 0.46 * math.cos(2*math.pi*n/(N-1))))
response = sum(x * math.cos(2*math.pi*25000/1e6*(n-(N-1)/2)) for n, x in enumerate(h))
h = [round(x / response * 32768) for x in h]
with (p / 'rx_fir_coeff.vh').open('w') as out:
    out.write('function signed [15:0] fir_coef;\n input [8:0] n;\n begin\n case(n)\n')
    for n, x in enumerate(h):
        out.write(" 9'd%d: fir_coef = %s16'sd%d;\n" % (n, '-' if x < 0 else '', abs(x)))
    out.write(" default: fir_coef=0;\n endcase\n end\nendfunction\n")

# TX phase accumulator sampled every ten 1 MHz samples. A cosine quadrature
# reference permits an unknown carrier phase. Normalized 8-bit coefficients.
start, step, mask = 6333186975990, 140737488, (1 << 48) - 1
phase, freq, vals = 0, start, []
for n in range(10000):
    if n % 10 == 0:
        phi = 2 * math.pi * (phase >> 38) / 1024
        vals.append((round(127*math.sin(phi)), round(127*math.cos(phi))))
    phase, freq = (phase + freq) & mask, (freq + step) & mask
with (p / 'rx_lfm_coeff.vh').open('w') as out:
    for index, name in enumerate(('lfm_i', 'lfm_q')):
        out.write('function signed [7:0] %s;\n input [9:0] n;\n begin\n case(n)\n' % name)
        for n, v in enumerate(vals):
            x = v[index]
            out.write(" 10'd%d: %s = %s8'sd%d;\n" % (n, name, '-' if x < 0 else '', abs(x)))
        out.write(' default: %s=0;\n endcase\n end\nendfunction\n' % name)
