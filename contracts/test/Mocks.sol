// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal mintable ERC20 used by the vault tests.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "bal");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "bal");
        require(allowance[from][msg.sender] >= amount, "allow");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Mock QuoterV2: price is "USDT per 1 whole token", 18 decimals.
///         quoteExactInputSingle(tokenIn -> tokenOut) uses the price of tokenIn
///         when tokenOut is USDT, and 1/price when tokenIn is USDT.
contract MockQuoter {
    address public usdt;
    mapping(address => uint256) public priceUsd18; // USDT per 1 whole token, 18-dec
    mapping(address => uint8) public dec;

    constructor(address _usdt) {
        usdt = _usdt;
    }

    function setPrice(address token, uint256 price, uint8 decimals_) external {
        priceUsd18[token] = price;
        dec[token] = decimals_;
    }

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams calldata p)
        external
        view
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountOut = _quote(p.tokenIn, p.tokenOut, p.amountIn);
        return (amountOut, 0, 0, 0);
    }

    function _quote(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        if (tokenIn == tokenOut) return amountIn;
        if (tokenOut == usdt) {
            // token -> USDT: amountIn * price / 10^decIn, then into USDT decimals
            uint256 usd18 = (amountIn * priceUsd18[tokenIn]) / (10 ** dec[tokenIn]);
            return _from18(usd18, dec[usdt]);
        }
        if (tokenIn == usdt) {
            // USDT -> token: usd18 / price, into token decimals
            uint256 usd18 = _to18(amountIn, dec[usdt]);
            uint256 wholeTokens18 = (usd18 * 1 ether) / priceUsd18[tokenOut];
            return (wholeTokens18 * (10 ** dec[tokenOut])) / 1 ether;
        }
        revert("mock quoter: one side must be USDT");
    }

    function _to18(uint256 a, uint8 d) internal pure returns (uint256) {
        if (d == 18) return a;
        return a * (10 ** (18 - d));
    }

    function _from18(uint256 a, uint8 d) internal pure returns (uint256) {
        if (d == 18) return a;
        return a / (10 ** (18 - d));
    }
}

/// @notice Mock SwapRouter02: swaps at the MockQuoter price, holding inventory
///         funded by the test setup. Pulls tokenIn via transferFrom.
contract MockRouter {
    MockQuoter public quoter;

    constructor(MockQuoter _quoter) {
        quoter = _quoter;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata p) external payable returns (uint256 amountOut) {
        MockQuoter.QuoteExactInputSingleParams memory qp = MockQuoter.QuoteExactInputSingleParams({
            tokenIn: p.tokenIn,
            tokenOut: p.tokenOut,
            amountIn: p.amountIn,
            fee: p.fee,
            sqrtPriceLimitX96: p.sqrtPriceLimitX96
        });
        (amountOut,,,) = quoter.quoteExactInputSingle(qp);
        // NOTE: intentionally NOT enforcing amountOutMinimum here — the real
        // SwapRouter02 enforces it, and the vault enforces it again as a backstop.
        // Leaving it out lets the vault-level SlippageTooHigh check be tested.
        require(MockERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn), "pull failed");
        require(MockERC20(p.tokenOut).transfer(p.recipient, amountOut), "pay failed");
    }
}
