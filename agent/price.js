// Price feeds: HSKSwap QuoterV2 (on-chain, struct params — the HSKSwap
// deployment uses the new QuoterV2 ABI) + the HSKSwap subgraph for history.
const { ethers } = require("ethers");

const QUOTER_ABI = [
  "function quoteExactInputSingle((address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, uint160 sqrtPriceLimitX96) params) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)",
];
const ERC20_ABI = ["function decimals() view returns (uint8)", "function balanceOf(address) view returns (uint256)", "function symbol() view returns (string)"];

async function quoteUsdtPerToken(provider, net, token, tokenDecimals) {
  const quoter = new ethers.Contract(net.quoter, QUOTER_ABI, provider);
  const oneToken = 10n ** BigInt(tokenDecimals);
  // QuoterV2 quotes revert internally and return the value; ethers handles the
  // static call fine. Use callStatic-equivalent: plain call on a view-less fn
  // via .quoteExactInputSingle.staticCall().
  const [amountOut] = await quoter.quoteExactInputSingle.staticCall({
    tokenIn: token,
    tokenOut: net.usdt,
    amountIn: oneToken,
    fee: net.pools[Object.keys(net.pools).find((k) => net.pools[k].token.toLowerCase() === token.toLowerCase())]?.fee ?? 3000,
    sqrtPriceLimitX96: 0,
  });
  // amountOut is USDT smallest units -> USD value of 1 whole token
  return Number(amountOut) / 10 ** net.usdtDecimals;
}

async function quoteTokenOut(provider, net, tokenIn, tokenOut, amountIn, fee) {
  const quoter = new ethers.Contract(net.quoter, QUOTER_ABI, provider);
  const [amountOut] = await quoter.quoteExactInputSingle.staticCall({
    tokenIn, tokenOut, amountIn, fee, sqrtPriceLimitX96: 0,
  });
  return amountOut;
}

async function subgraphPoolPrice(net, poolId) {
  const query = JSON.stringify({
    query: `{ pool(id: "${poolId.toLowerCase()}") { token0Price token1Price token0 { symbol } token1 { symbol } liquidity totalValueLockedUSD } }`,
  });
  const res = await fetch(net.subgraph, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: query,
  });
  const json = await res.json();
  return json?.data?.pool ?? null;
}

module.exports = { quoteUsdtPerToken, quoteTokenOut, subgraphPoolPrice, QUOTER_ABI, ERC20_ABI };
