# Prototype: can Python reproduce the R numbers for the hard parts? (textbook examples)
import sys
import numpy as np
import pandas as pd
import scipy.stats as st
import statsmodels.api as sm
from statsmodels.miscmodels.ordinal_model import OrderedModel


def scoreci_mp(b, c, n, conf_level):
    """Line-by-line port of PropCIs::scoreci.mp (Tango's score interval, §8.1.2)."""
    pa = 2 * n
    z = st.norm.ppf(1 - (1 - conf_level) / 2)

    def bound(direction):
        proot = (c - b) / n
        dp = 1 - proot if direction > 0 else 1 + proot
        for _ in range(50):
            dp = 0.5 * dp
            p2 = proot + direction * dp
            pb = -b - c + (2 * n - c + b) * p2
            pc = -b * p2 * (1 - p2)
            q21 = (np.sqrt(pb ** 2 - 4 * pa * pc) - pb) / (2 * pa)
            score = (c - b - n * p2) / np.sqrt(n * (2 * q21 + p2 * (1 - p2)))
            if abs(score) < z:
                proot = p2
            if dp < 1e-7 or abs(z - score) < 1e-6:
                return p2
        raise RuntimeError("scoreci_mp did not converge")

    ul = 1.0 if c == n else bound(+1)
    ll = -1.0 if b == n else bound(-1)
    return ll, ul


def generalized_cmh(x, y, strata):
    """Generalized CMH 'general association' statistic, as R's mantelhaen.test for I x J x K."""
    xs, ys = np.unique(x), np.unique(y)
    I, J = len(xs), len(ys)
    s = np.zeros((I - 1) * (J - 1))
    V = np.zeros((len(s), len(s)))
    df = pd.DataFrame({"x": x, "y": y, "k": strata})
    for _, g in df.groupby("k"):
        t = pd.crosstab(pd.Categorical(g.x, xs), pd.Categorical(g.y, ys), dropna=False).values.astype(float)
        nk = t.sum()
        if nk < 2:
            continue
        rs, cs = t.sum(1), t.sum(0)
        nvec = t[:-1, :-1].flatten()
        m = np.outer(rs[:-1], cs[:-1]).flatten() / nk
        Vr = np.diag(rs[:-1]) - np.outer(rs[:-1], rs[:-1]) / nk
        Vc = np.diag(cs[:-1]) - np.outer(cs[:-1], cs[:-1]) / nk
        s += nvec - m
        V += np.kron(Vr, Vc) / (nk - 1)
    stat = float(s @ np.linalg.solve(V, s))
    dfree = (I - 1) * (J - 1)
    return stat, dfree, st.chi2.sf(stat, dfree)


def square_to_long(tab):
    rows = []
    pid = 0
    k = tab.shape[0]
    for i in range(k):
        for j in range(k):
            for _ in range(int(tab[i, j])):
                pid += 1
                rows += [(pid, 1, i + 1), (pid, 0, j + 1)]
    return pd.DataFrame(rows, columns=["id", "time", "y"])


def cluster_sandwich(score_obs, hess, groups):
    """H^-1 B H^-1 with B = sum over clusters of (sum of scores)(sum of scores)'."""
    S = pd.DataFrame(score_obs).groupby(np.asarray(groups)).sum().values
    B = S.T @ S
    Hinv = np.linalg.inv(-hess)
    return Hinv @ B @ Hinv


from scipy.optimize import minimize
from scipy.special import expit


def _cumlogit_parts(theta, y, X, K):
    a = theta[:K - 1]
    b = theta[K - 1:]
    eta = a[None, :] + (X @ b)[:, None]                   # n x (K-1): logit P(Y <= j)
    F = np.hstack([np.zeros((len(y), 1)), expit(eta), np.ones((len(y), 1))])
    f = np.hstack([np.zeros((len(y), 1)), expit(eta) * (1 - expit(eta)), np.zeros((len(y), 1))])
    idx = np.arange(len(y))
    P = F[idx, y] - F[idx, y - 1]
    return F, f, P


def cumlogit_score_obs(theta, y, X, K):
    """Per-observation score of logit P(Y <= j) = a_j + x'b (y coded 1..K)."""
    F, f, P = _cumlogit_parts(theta, y, X, K)
    idx = np.arange(len(y))
    fu, fl = f[idx, y], f[idx, y - 1]
    S = np.zeros((len(y), K - 1 + X.shape[1]))
    for j in range(1, K):
        S[:, j - 1] = ((y == j) * fu - (y - 1 == j) * fl) / P
    S[:, K - 1:] = X * ((fu - fl) / P)[:, None]
    return S


def cumlogit_fit(y, X, K):
    # optimise over ordered cutpoints: a_1, a_j = a_{j-1} + exp(d_j); the MLE is the same point
    cum = np.array([np.mean(y <= j) for j in range(1, K)])
    a0 = np.log(cum / (1 - cum))
    start = np.concatenate([[a0[0]], np.log(np.diff(a0)), np.zeros(X.shape[1])])
    to_theta = lambda u: np.concatenate([u[0] + np.concatenate([[0], np.cumsum(np.exp(u[1:K - 1]))]), u[K - 1:]])

    def jac_map(u):
        J = np.eye(len(u))
        J[:K - 1, 0] = 1                                   # every cutpoint moves with a_1
        for j in range(1, K - 1):
            J[j:K - 1, j] = np.exp(u[j])
        return J

    nll = lambda u: -np.sum(np.log(_cumlogit_parts(to_theta(u), y, X, K)[2]))
    grad = lambda u: -cumlogit_score_obs(to_theta(u), y, X, K).sum(0) @ jac_map(u)
    res = minimize(nll, start, jac=grad, method="BFGS", options={"gtol": 1e-9, "maxiter": 10000})
    theta = to_theta(res.x)
    h = 1e-5
    H = np.zeros((len(theta), len(theta)))
    for k in range(len(theta)):
        e = np.zeros(len(theta)); e[k] = h
        H[:, k] = (cumlogit_score_obs(theta + e, y, X, K).sum(0) - cumlogit_score_obs(theta - e, y, X, K).sum(0)) / (2 * h)
    return theta, (H + H.T) / 2


def cumlogit_expected_info(theta, X, K):
    """Expected (Fisher) information: sum over observations of sum_c P(c) s(c) s(c)'."""
    n = X.shape[0]
    info = np.zeros((len(theta), len(theta)))
    for c in range(1, K + 1):
        yc = np.full(n, c)
        P = _cumlogit_parts(theta, yc, X, K)[2]
        S = cumlogit_score_obs(theta, yc, X, K)
        info += (S * P[:, None]).T @ S
    return info


def ordinal_marginal(df, xcols):
    """Cumulative logit ML (independence) + cluster-robust SE (= multgee ordLORgee, LORstr independence)."""
    y = df["y"].values.astype(int)
    X = df[xcols].values.astype(float)
    K = int(y.max())
    theta, H = cumlogit_fit(y, X, K)
    V = cluster_sandwich(cumlogit_score_obs(theta, y, X, K), H, df["id"])
    Ve = cluster_sandwich(cumlogit_score_obs(theta, y, X, K), -cumlogit_expected_info(theta, X, K), df["id"])
    print("   observed-H SE:", np.round(np.sqrt(np.diag(V))[K - 1:], 6), " expected-info SE:", np.round(np.sqrt(np.diag(Ve))[K - 1:], 6))
    return theta[K - 1:], np.sqrt(np.diag(Ve))[K - 1:]


tab81 = np.array([[227, 132], [107, 678]])
print("scoreci (book -0.00466 0.04849):", np.round(scoreci_mp(107, 132, 1144, 0.95), 5))

tab85 = np.array([[93, 17, 44, 7, 10], [9, 46, 11, 0, 9], [17, 11, 155, 9, 12], [6, 4, 9, 15, 2], [10, 4, 12, 2, 27]])
cof = square_to_long(tab85)
print("CMH (book 12.291):", np.round(generalized_cmh(cof.time.values, cof.y.values, cof.id.values)[0], 4))

tab86 = np.array([[12, 43, 163, 233], [4, 21, 99, 185], [4, 8, 77, 230], [0, 1, 18, 132]])
env = square_to_long(tab86)
b, se = ordinal_marginal(env, ["time"])
print("ordinal GEE beta, SE (book 2.75361 0.08147):", np.round(b, 5), np.round(se, 5))

# nominal: multinomial logit ML + cluster sandwich, baseline = last category (multgee)
cof["yb"] = (cof.y % 5)  # category 5 (Brim) -> 0 so it is the MNLogit baseline
X = sm.add_constant(cof[["time"]].astype(float))
mn = sm.MNLogit(cof["yb"], X)
r = mn.fit(disp=False, method="newton", maxiter=200)
V = cluster_sandwich(mn.score_obs(r.params.values.flatten(order="F")), mn.hessian(r.params.values.flatten(order="F")), cof["id"])
params = r.params.values.flatten(order="F")
names = [f"{c}:{j}" for j in range(1, 5) for c in X.columns]
se = np.sqrt(np.diag(V))
print("nominal time:1 (HighPoint) est, SE (book 0.32340 0.16830):", np.round(params[1], 5), np.round(se[1], 5))
idx = [1, 3, 5, 7]
bb = params[idx]
print("nominal Wald (book 12.4869):", np.round(float(bb @ np.linalg.solve(V[np.ix_(idx, idx)], bb)), 4))

# binary GEE exchangeable: abortion (Table 9.1)
seqs = [(1, 1, 1), (1, 1, 0), (0, 1, 1), (0, 1, 0), (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0)]
counts = {0: [342, 26, 6, 21, 11, 32, 19, 356], 1: [440, 25, 14, 18, 14, 47, 22, 457]}
rows = []
pid = 0
for g in (0, 1):
    for s, n in zip(seqs, counts[g]):
        for _ in range(n):
            pid += 1
            rows += [(pid, g, t + 1, s[t]) for t in range(3)]
ab = pd.DataFrame(rows, columns=["person", "gender", "situation", "response"])
ab["s1"] = (ab.situation == 1).astype(float)
ab["s2"] = (ab.situation == 2).astype(float)
Xa = sm.add_constant(ab[["s1", "s2", "gender"]].astype(float))
for cs in (sm.cov_struct.Exchangeable(),):
    g = sm.GEE(ab["response"], Xa, groups=ab["person"].values, time=(ab["situation"] - 1).values, family=sm.families.Binomial(), cov_struct=cs)
    rr = g.fit()
    print("GEE exch sit1, robust SE, gender, rho (book 0.14935 0.02974 0.00344 0.81733):",
          np.round(rr.params["s1"], 5), np.round(rr.bse["s1"], 5), np.round(rr.params["gender"], 5),
          np.round(cs.dep_params, 5))
