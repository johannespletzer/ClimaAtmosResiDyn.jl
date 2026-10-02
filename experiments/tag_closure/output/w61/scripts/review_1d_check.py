"""W61 review: the anti-diffusive regime of main's form is a flat-state result.

One periodic dimension, rho = 1, spectral derivatives. A tag holds chi = phi q.
Main's form (the share inside the operator): T = -D4(chi - phi q_r).
The passive form: T = -D4(chi) + phi D4(q_r). The variance rate is the
integral of chi T. Case A has q > q_r everywhere (no regime) and main's form
still raises the variance. Case C has the regime on a third of the domain and
main's form lowers the variance in total. Case B is the flat state.
Run with the python/3.12 module: python3 review_1d_check.py
"""
import numpy as np

N = 256
x = np.arange(N) * 2 * np.pi / N
k = np.fft.fftfreq(N, 1 / N)
dx = 2 * np.pi / N


def D2(f):
    return np.real(np.fft.ifft(-(k**2) * np.fft.fft(f)))


def D4(f):
    return D2(D2(f))


def rates(q, qr, phi):
    chi = phi * q
    t_main = -D4(chi - phi * qr)
    t_passive = -D4(chi) + phi * D4(qr)
    return np.sum(chi * t_main) * dx, np.sum(chi * t_passive) * dx


qr = np.ones(N)
phi = 0.5 + 0.4 * np.cos(x)
q = qr + 0.1 / phi - 0.05  # q - q_r between 0.061 and 0.95
print("A: no regime, min(q - q_r) = %.3f, main %.4g, passive %.4g"
      % ((q - qr).min(), *rates(q, qr, phi)))
main, passive = rates(0.3 * qr, qr, phi)
print("B: flat, q = 0.3 q_r: ratio %.6f, 1 - q_r/q = %.6f" % (main / passive, 1 - 1 / 0.3))
q = 1 + 0.9 * np.cos(x)
qr = 0.5 * np.ones(N)
phi = 0.5 + 0.4 * np.sin(3 * x)
print("C: regime on %.2f of the domain, main %.4g, passive %.4g"
      % (np.mean((q > 0) & (q < qr)), *rates(q, qr, phi)))
