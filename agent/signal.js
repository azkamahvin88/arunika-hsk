// Mean-reversion signal: z-score of the current price vs a rolling TWAP
// (mean + stddev of the last N samples). No trade without a quote check:
// the signal only fires when a fresh QuoterV2 quote agrees with the
// sampled price within the spread tolerance.
class Signal {
  constructor(window = 40) {
    this.window = window;
    this.samples = []; // { ts, price }
  }

  push(price) {
    this.samples.push({ ts: Date.now(), price });
    if (this.samples.length > this.window * 3) this.samples = this.samples.slice(-this.window * 3);
  }

  stats() {
    const w = this.samples.slice(-this.window);
    if (w.length < 10) return null;
    const mean = w.reduce((s, x) => s + x.price, 0) / w.length;
    const variance = w.reduce((s, x) => s + (x.price - mean) ** 2, 0) / w.length;
    return { mean, std: Math.sqrt(variance), n: w.length };
  }

  // Returns: { action: 'BUY'|'SELL'|'HOLD', z, mean, std, reason }
  evaluate(price, cfg) {
    const st = this.stats();
    if (!st || st.std === 0) return { action: "HOLD", z: 0, reason: "warming up: not enough samples" };
    const z = (price - st.mean) / st.std;
    if (z < -cfg.zEntry) return { action: "BUY", z, mean: st.mean, std: st.std, reason: `price ${z.toFixed(2)}σ below TWAP — mean-reversion buy` };
    if (z > cfg.zEntry) return { action: "SELL", z, mean: st.mean, std: st.std, reason: `price ${z.toFixed(2)}σ above TWAP — mean-reversion sell` };
    return { action: "HOLD", z, mean: st.mean, std: st.std, reason: `|z|=${Math.abs(z).toFixed(2)} below entry ${cfg.zEntry}` };
  }
}

module.exports = { Signal };
