// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ArunikaVault — guard-railed autonomous trading vault for HSKSwap (Uniswap V3 fork)
/// @notice Holds USDT + WHSK (and allowlisted tokens). Only the designated off-chain
///         agent key may call executeTrade, and every trade must pass the on-chain
///         guards: pause, agent-only, token/fee allowlist, per-trade size cap,
///         cooldown between trades, per-position stop-loss and a daily-loss cap.
///         Prices for the guards are read on-chain from HSKSwap QuoterV2, so the
///         agent cannot lie to the vault about the price — a bad signal can lose
///         at most what the guards permit.
/// @dev    Accounting is normalised to 18 decimals ("usd18") so USDT (6 dec on
///         mainnet, 18 dec on testnet) and WHSK (18 dec) share one unit.
///         HSK Chain mainnet (177) / testnet (133). See NETWORK.md for verified addresses.
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }
    function quoteExactInputSingle(QuoteExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

contract ArunikaVault {
    // ---- Roles ----
    address public owner;
    address public agent;
    bool public paused;

    // ---- External contracts (immutable after deploy) ----
    ISwapRouter02 public immutable router;
    IQuoterV2 public immutable quoter;
    address public immutable usdt; // stablecoin used as the accounting / quote currency

    // ---- Guards (owner-configurable) ----
    uint256 public cooldownSeconds = 60; // min seconds between trades
    uint256 public maxDailyLossUsd18 = 5 ether; // max realised loss per UTC day (18-dec USD)
    uint256 public stopLossBps = 500; // 5% below entry price blocks further buys of that token
    uint256 public lastTradeAt;

    struct TokenConfig {
        bool allowed;
        uint8 decimals;
        uint256 maxTradeSize; // max amountIn per trade, in the token's own smallest units
        uint24 fee; // pool fee tier used for quotes + swaps against USDT
    }
    mapping(address => TokenConfig) public tokenConfigs;

    // ---- Positions & daily accounting ----
    struct Position {
        uint256 balance; // tokens currently held (smallest units)
        uint256 costUsd18; // USDT spent to acquire the current balance (18-dec)
        uint256 entryPriceUsd18; // USDT per 1 whole token at last buy (18-dec)
        bool open;
    }
    mapping(address => Position) public positions;

    uint256 public currentDay; // block.timestamp / 1 days
    uint256 public dailyLossUsd18; // realised losses accumulated today (18-dec USD)

    // ---- Events ----
    event TradeExecuted(
        uint256 indexed signalId,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceUsd18,
        uint256 timestamp
    );
    event GuardConfigUpdated(string what, uint256 value);
    event TokenAllowlistUpdated(address indexed token, bool allowed, uint24 fee);
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event DailyLossReset(uint256 indexed day);

    error NotOwner();
    error NotAgent();
    error IsPaused();
    error TokenNotAllowed(address token);
    error TradeTooLarge(uint256 amountIn, uint256 maxTradeSize);
    error CooldownActive(uint256 secondsLeft);
    error StopLossBreached(address token, uint256 priceUsd18, uint256 entryPriceUsd18);
    error DailyLossCapReached(uint256 dailyLossUsd18, uint256 maxDailyLossUsd18);
    error SlippageTooHigh(uint256 amountOut, uint256 amountOutMinimum);
    error ZeroAmount();
    error InsufficientBalance(uint256 have, uint256 want);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }
    modifier whenNotPaused() {
        if (paused) revert IsPaused();
        _;
    }

    constructor(address _owner, address _agent, address _router, address _quoter, address _usdt) {
        owner = _owner;
        agent = _agent;
        router = ISwapRouter02(_router);
        quoter = IQuoterV2(_quoter);
        usdt = _usdt;
        currentDay = block.timestamp / 1 days;
    }

    receive() external payable {}

    // ---- Owner config ----
    function setAgent(address _agent) external onlyOwner {
        emit AgentUpdated(agent, _agent);
        agent = _agent;
    }

    function transferOwnership(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setTokenConfig(address token, bool allowed, uint8 decimals_, uint256 maxTradeSize, uint24 fee)
        external
        onlyOwner
    {
        tokenConfigs[token] = TokenConfig(allowed, decimals_, maxTradeSize, fee);
        emit TokenAllowlistUpdated(token, allowed, fee);
    }

    function setCooldown(uint256 seconds_) external onlyOwner {
        cooldownSeconds = seconds_;
        emit GuardConfigUpdated("cooldownSeconds", seconds_);
    }

    function setMaxDailyLoss(uint256 usd18) external onlyOwner {
        maxDailyLossUsd18 = usd18;
        emit GuardConfigUpdated("maxDailyLossUsd18", usd18);
    }

    function setStopLossBps(uint256 bps) external onlyOwner {
        require(bps <= 10000, "bps>10000");
        stopLossBps = bps;
        emit GuardConfigUpdated("stopLossBps", bps);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function withdraw(address token, uint256 amount, address to) external onlyOwner {
        if (token == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "native withdraw failed");
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (amount > bal) revert InsufficientBalance(bal, amount);
            require(IERC20(token).transfer(to, amount), "withdraw failed");
        }
        emit Withdrawn(token, to, amount);
    }

    // ---- Views ----
    /// @notice Current USDT price of 1 whole `token`, read on-chain from QuoterV2.
    function priceOf(address token) public returns (uint256 priceUsd18) {
        if (token == usdt) return 1 ether;
        TokenConfig memory cfg = tokenConfigs[token];
        if (!cfg.allowed) revert TokenNotAllowed(token);
        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: token,
                tokenOut: usdt,
                amountIn: 10 ** cfg.decimals,
                fee: cfg.fee,
                sqrtPriceLimitX96: 0
            })
        );
        // amountOut is in USDT smallest units -> normalise to 18 decimals
        uint8 usdtDec = tokenConfigs[usdt].decimals;
        priceUsd18 = _to18(amountOut, usdtDec);
    }

    function getPosition(address token) external view returns (Position memory) {
        return positions[token];
    }

    function _to18(uint256 amount, uint8 dec) internal pure returns (uint256) {
        if (dec == 18) return amount;
        if (dec < 18) return amount * (10 ** (18 - dec));
        return amount / (10 ** (dec - 18));
    }

    function _maybeResetDay() internal {
        uint256 day = block.timestamp / 1 days;
        if (day != currentDay) {
            currentDay = day;
            dailyLossUsd18 = 0;
            emit DailyLossReset(day);
        }
    }

    // ---- Trading ----
    struct TradeParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
        uint256 signalId;
    }

    /// @notice Execute one swap through HSKSwap SwapRouter02, enforcing all guards.
    /// @dev Guards, in order: pause, agent, allowlist, size, cooldown, daily-loss
    ///      cap, stop-loss (buys blocked while the position is beyond stop-loss),
    ///      slippage (amountOutMinimum). Accounting updates after a successful swap.
    function executeTrade(TradeParams calldata p) external onlyAgent whenNotPaused returns (uint256 amountOut) {
        if (p.amountIn == 0) revert ZeroAmount();
        TokenConfig memory cfgIn = tokenConfigs[p.tokenIn];
        TokenConfig memory cfgOut = tokenConfigs[p.tokenOut];
        if (!cfgIn.allowed) revert TokenNotAllowed(p.tokenIn);
        if (!cfgOut.allowed) revert TokenNotAllowed(p.tokenOut);
        if (p.fee != cfgIn.fee && p.fee != cfgOut.fee) revert TokenNotAllowed(p.tokenIn); // fee tier must match an allowlisted pool
        if (p.amountIn > cfgIn.maxTradeSize) revert TradeTooLarge(p.amountIn, cfgIn.maxTradeSize);
        if (lastTradeAt != 0 && block.timestamp < lastTradeAt + cooldownSeconds) {
            revert CooldownActive(lastTradeAt + cooldownSeconds - block.timestamp);
        }

        _maybeResetDay();
        if (dailyLossUsd18 >= maxDailyLossUsd18) {
            revert DailyLossCapReached(dailyLossUsd18, maxDailyLossUsd18);
        }

        uint256 vaultBal = IERC20(p.tokenIn).balanceOf(address(this));
        if (p.amountIn > vaultBal) revert InsufficientBalance(vaultBal, p.amountIn);

        bool buying = (p.tokenIn == usdt); // USDT -> token
        bool selling = (p.tokenOut == usdt); // token -> USDT
        require(buying || selling, "one side must be USDT");

        // --- Stop-loss guard (on-chain price, not the agent's word) ---
        uint256 priceUsd18;
        if (buying) {
            priceUsd18 = priceOf(p.tokenOut);
            Position storage pos = positions[p.tokenOut];
            if (pos.open && pos.entryPriceUsd18 > 0) {
                uint256 floor_ = (pos.entryPriceUsd18 * (10000 - stopLossBps)) / 10000;
                if (priceUsd18 < floor_) {
                    revert StopLossBreached(p.tokenOut, priceUsd18, pos.entryPriceUsd18);
                }
            }
        } else if (selling) {
            priceUsd18 = priceOf(p.tokenIn);
        }

        // --- Execute the swap ---
        require(IERC20(p.tokenIn).approve(address(router), p.amountIn), "approve failed");
        amountOut = router.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: p.tokenIn,
                tokenOut: p.tokenOut,
                fee: p.fee,
                recipient: address(this),
                amountIn: p.amountIn,
                amountOutMinimum: p.amountOutMinimum,
                sqrtPriceLimitX96: p.sqrtPriceLimitX96
            })
        );
        if (amountOut < p.amountOutMinimum) revert SlippageTooHigh(amountOut, p.amountOutMinimum);

        // --- Accounting (18-dec USD) ---
        if (buying) {
            uint256 spentUsd18 = _to18(p.amountIn, cfgIn.decimals);
            Position storage pos = positions[p.tokenOut];
            uint256 newBal = pos.balance + amountOut;
            // volume-weighted entry price
            uint256 newCost = pos.costUsd18 + spentUsd18;
            pos.entryPriceUsd18 = newBal > 0 ? (newCost * (10 ** cfgOut.decimals)) / newBal : priceUsd18;
            pos.balance = newBal;
            pos.costUsd18 = newCost;
            pos.open = true;
        } else if (selling) {
            Position storage pos = positions[p.tokenIn];
            uint256 proceedsUsd18 = _to18(amountOut, tokenConfigs[usdt].decimals);
            if (pos.balance > 0) {
                uint256 soldShare = (p.amountIn * 1 ether) / pos.balance; // 18-dec fraction
                uint256 costOfSold = (pos.costUsd18 * soldShare) / 1 ether;
                if (proceedsUsd18 < costOfSold) {
                    dailyLossUsd18 += (costOfSold - proceedsUsd18);
                }
                pos.costUsd18 = pos.costUsd18 > costOfSold ? pos.costUsd18 - costOfSold : 0;
                pos.balance = pos.balance > p.amountIn ? pos.balance - p.amountIn : 0;
                if (pos.balance == 0) {
                    pos.open = false;
                    pos.entryPriceUsd18 = 0;
                    pos.costUsd18 = 0;
                }
            }
        }

        lastTradeAt = block.timestamp;
        emit TradeExecuted(p.signalId, p.tokenIn, p.tokenOut, p.amountIn, amountOut, priceUsd18, block.timestamp);
    }
}
