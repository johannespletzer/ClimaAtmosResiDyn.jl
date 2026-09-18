import csv, math, numpy as np
rows=list(csv.DictReader(open("/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn.jl/experiments/tag_closure/output/b1_base/energy_tag_closure.csv")))
t=np.array([float(r["time"])/86400 for r in rows]); G=np.array([float(r["gross_residual"]) for r in rows])
def fit(tt,yy):
    one=np.ones_like(tt); out={}
    for name,X in [("const",one[:,None]),("linear",np.c_[one,tt]),("sqrt",np.c_[one,np.sqrt(tt)])]:
        b,*_=np.linalg.lstsq(X,yy,rcond=None); r=yy-X@b; out[name]=(float(r@r),X.shape[1],b)
    best=None
    for tau in np.geomspace(0.05,200,500):
        X=np.c_[one,1-np.exp(-tt/tau)]; b,*_=np.linalg.lstsq(X,yy,rcond=None); r=yy-X@b
        if best is None or r@r<best[0]: best=(float(r@r),tau,b)
    out["satexp"]=(best[0],3,(*best[2],best[1])); return out
for lo,hi in [(0.25,7.5),(0.25,2.0),(0.25,10)]:
    m=(t>=lo-1e-9)&(t<=hi+1e-9); tt=t[m]; yy=G[m]; n=m.sum(); o=fit(tt,yy)
    aic={k:n*math.log(v[0]/n)+2*v[1] for k,v in o.items()}; b=min(aic,key=aic.get)
    print(f"days {lo}-{hi}: n={n} best={b} dAIC " + " ".join(f"{k}{aic[k]-aic[b]:+.0f}" for k in aic), "satexp a,b,tau(d)=", ["%.3g"%x for x in o["satexp"][2]])
    if hi==2.0:
        a_,b_,tau=o["satexp"][2]; bs=o["sqrt"][2]
        for d in (5,7,10):
            print(f"   extrapolated to day {d}: satexp {a_+b_*(1-math.exp(-d/tau)):.3g}, sqrt {bs[0]+bs[1]*math.sqrt(d):.3g}, actual {G[np.argmin(abs(t-d))]:.3g}")
# daily increments
for d in range(1,11):
    i=np.argmin(abs(t-d)); j=np.argmin(abs(t-(d-1)))
    print(f"day {d}: G={G[i]:.3e} dG={G[i]-G[j]:.2e}  ({(G[i]-G[j])/4.79e23:.2e} of C-sphere intE)")
