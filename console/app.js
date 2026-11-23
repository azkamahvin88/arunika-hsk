// ARUNIKA console app — reads the agent decision log + vault state via the
// public HSK RPC. No keys, no writes to the chain from this page.
// Serve this folder AND the agent folder's decisions.jsonl:
//   cd console && python3 -m http.server 8080
// (decisions.jsonl is fetched from ../agent/decisions.jsonl — copy or symlink
//  it into console/ when serving, or point DECISIONS_URL at your agent host.)
const RPC = "https://testnet.hsk.xyz";
const EXPLORER = "https://testnet-explorer.hskchain.net";
const DECISIONS_URL = "decisions.jsonl";
const VAULT_ABI = [
  "function getPosition(address token) view returns (uint256 balance, uint256 costUsd18, uint256 entryPriceUsd18, bool open)",
  "function dailyLossUsd18() view returns (uint256)",
  "function paused() view returns (bool)",
  "function maxDailyLossUsd18() view returns (uint256)",
];
// Fill in after testnet deploy (see DEPLOYMENTS.md). Empty = paper mode view.
const VAULT_ADDRESS = "";
const TOKENS = {
  WHSK: { address: "0xca8aaceec5db1e91b9ed3a344ba026c4a2b3ebf6", decimals: 18 },
  USDT: { address: "0x98b6173a8b7dfc52ce8bc88f1184a918a1ccaa4f", decimals: 18 },
};

let decisions = [];
const chatEl = document.getElementById("chat");
const logEl = document.getElementById("log");

function say(who, text) {
  const div = document.createElement("div");
  div.className = "msg";
  div.innerHTML = `<b>${who}</b>`;
  div.appendChild(document.createTextNode(text));
  chatEl.appendChild(div);
  chatEl.scrollTop = chatEl.scrollHeight;
}

async function loadDecisions() {
  try {
    const res = await fetch(DECISIONS_URL + "?t=" + Date.now());
    if (!res.ok) throw new Error("HTTP " + res.status);
    const text = await res.text();
    decisions = text.trim() ? text.trim().split("\n").map((l) => JSON.parse(l)) : [];
    const rows = decisions.slice(-30).reverse();
    logEl.textContent = rows.map((d) => JSON.stringify(d)).join("\n") || "(no decisions yet — start the agent)";
  } catch (e) {
    logEl.textContent = "Could not load decisions.jsonl (" + e.message + "). Copy agent/decisions.jsonl into console/ when serving.";
  }
}

async function loadPositions() {
  const el = document.getElementById("positions");
  if (!VAULT_ADDRESS) {
    el.innerHTML = "<p>Vault not deployed yet — paper mode. Positions will appear here after the testnet deploy (see DEPLOYMENTS.md).</p>";
    return;
  }
  try {
    const { ethers } = await import("https://cdn.jsdelivr.net/npm/ethers@6.13.0/dist/ethers.min.js");
    const provider = new ethers.JsonRpcProvider(RPC);
    const vault = new ethers.Contract(VAULT_ADDRESS, VAULT_ABI, provider);
    const [paused, dailyLoss, maxLoss] = await Promise.all([
      vault.paused(), vault.dailyLossUsd18(), vault.maxDailyLossUsd18(),
    ]);
    let html = `<p>Vault <code>${VAULT_ADDRESS}</code> · <a href="${EXPLORER}/address/${VAULT_ADDRESS}" target="_blank">explorer</a><br>`
      + `Status: ${paused ? "⏸ PAUSED" : "▶ live"} · Daily loss: $${(Number(dailyLoss) / 1e18).toFixed(2)} / $${(Number(maxLoss) / 1e18).toFixed(2)}</p>`;
    for (const [sym, t] of Object.entries(TOKENS)) {
      const pos = await vault.getPosition(t.address);
      const bal = Number(pos.balance) / 10 ** t.decimals;
      const cost = Number(pos.costUsd18) / 1e18;
      const entry = Number(pos.entryPriceUsd18) / 1e18;
      html += `<p><b>${sym}</b>: ${bal.toFixed(4)} held · cost $${cost.toFixed(2)} · entry $${entry.toFixed(4)} · ${pos.open ? "OPEN" : "flat"}</p>`;
    }
    el.innerHTML = html;
  } catch (e) {
    el.textContent = "Failed to read vault: " + e.message;
  }
}

function answer(q) {
  const s = q.toLowerCase();
  const last = decisions.filter((d) => d.kind === "signal").slice(-1)[0];
  const trades = decisions.filter((d) => d.executed);
  if (/(position|posisi)/.test(s)) {
    const open = decisions.filter((d) => d.kind === "signal").slice(-5).map((d) => `${d.asset} @ $${d.priceUsd?.toFixed(4)} (${d.action})`).join("; ");
    return open ? `Latest signals: ${open}. Full positions are in the panel on the right (live on-chain).` : "No signals yet — the agent is still warming up its TWAP window.";
  }
  if (/(pnl|p&l|profit|loss|rugi|untung)/.test(s)) {
    return trades.length
      ? `${trades.length} live trade(s) executed so far. Realised P&L is tracked on-chain in the vault (dailyLossUsd18) — see the panel. Paper trades don't move P&L.`
      : "No live trades yet, so realised P&L is $0. Paper signals are logged, not executed.";
  }
  if (/(why|kenapa|alasan)/.test(s)) {
    return last ? `Last signal #${last.signalId}: ${last.action} ${last.asset} at $${last.priceUsd?.toFixed(4)} — ${last.reason}. Quote checked first; vault guards enforced on-chain.` : "No signal yet — still collecting prices for the TWAP window.";
  }
  if (/(status|apa kabar|jalan)/.test(s)) {
    return last ? `Running in ${last.mode} mode on chain ${last.chainId}. Last tick: signal #${last.signalId}, ${last.asset} $${last.priceUsd?.toFixed(4)}, action ${last.action}.` : "Agent starting — waiting for the first price samples.";
  }
  return "I can answer: positions? / pnl? / why did you buy? / status? — and the controls on the right tune size, frequency, risk and assets.";
}

document.getElementById("ask").onclick = () => {
  const q = document.getElementById("q");
  if (!q.value.trim()) return;
  say("You", q.value);
  say("Arunika", answer(q.value));
  q.value = "";
};
document.getElementById("q").addEventListener("keydown", (e) => { if (e.key === "Enter") document.getElementById("ask").click(); });

document.getElementById("apply").onclick = async () => {
  const size = parseFloat(document.getElementById("ctl-size").value);
  const poll = parseInt(document.getElementById("ctl-poll").value, 10);
  const risk = document.getElementById("ctl-risk").value;
  const assets = [...document.getElementById("ctl-assets").selectedOptions].map((o) => o.value);
  const zEntry = risk === "low" ? 2.0 : risk === "high" ? 1.0 : 1.5;
  const cfg = { tradeSizeUsdt: size * (risk === "low" ? 0.5 : risk === "high" ? 2 : 1), pollSeconds: poll, zEntry, assets };
  // The agent watches agent/config.json and applies it on the next cycle.
  // This static demo writes the JSON for you to save as agent/config.json.
  document.getElementById("ctl-status").textContent =
    "Save this as agent/config.json (the agent picks it up on its next cycle): " + JSON.stringify(cfg);
};

document.getElementById("refresh").onclick = () => { loadDecisions(); loadPositions(); };

say("Arunika", "Morning sun is up 🌅 — ask me about positions, P&L, or why I traded.");
loadDecisions();
loadPositions();
setInterval(loadDecisions, 30000);
