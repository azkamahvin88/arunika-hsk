// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../ArunikaVault.sol";
import "./Mocks.sol";

/// @notice Guard tests for ArunikaVault, using mock HSKSwap contracts.
///         Prices: WHSK starts at $0.08 (8e16 usd18). USDT is 6 decimals,
///         WHSK 18 decimals — mirroring HSK mainnet (177).
contract ArunikaVaultTest is Test {
    ArunikaVault vault;
    MockERC20 usdt;
    MockERC20 whsk;
    MockQuoter quoter;
    MockRouter router;

    address owner = address(0xA11CE);
    address agent = address(0xA6E17);
    address stranger = address(0xBEEF);
    uint24 constant FEE = 3000;

    function setUp() public {
        vm.startPrank(owner);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        whsk = new MockERC20("Wrapped HSK", "WHSK", 18);
        quoter = new MockQuoter(address(usdt));
        quoter.setPrice(address(whsk), 0.08 ether, 18);
        quoter.setPrice(address(usdt), 1 ether, 6);
        router = new MockRouter(quoter);

        vault = new ArunikaVault(owner, agent, address(router), address(quoter), address(usdt));
        vault.setTokenConfig(address(usdt), true, 6, 10_000 * 1e6, FEE);
        vault.setTokenConfig(address(whsk), true, 18, 100_000 ether, FEE);
        vault.setCooldown(60);
        vault.setMaxDailyLoss(5 ether);
        vault.setStopLossBps(500); // 5%

        // Fund the vault: 1,000 USDT + 1,000 WHSK. Fund the mock router so it can pay out.
        usdt.mint(address(vault), 1_000 * 1e6);
        whsk.mint(address(vault), 1_000 ether);
        usdt.mint(address(router), 1_000_000 * 1e6);
        whsk.mint(address(router), 1_000_000 ether);
        vm.stopPrank();
    }

    function _buyParams(uint256 amountIn, uint256 minOut, uint256 signalId)
        internal
        view
        returns (ArunikaVault.TradeParams memory)
    {
        return ArunikaVault.TradeParams({
            tokenIn: address(usdt),
            tokenOut: address(whsk),
            amountIn: amountIn,
            amountOutMinimum: minOut,
            fee: FEE,
            sqrtPriceLimitX96: 0,
            signalId: signalId
        });
    }

    function _sellParams(uint256 amountIn, uint256 minOut, uint256 signalId)
        internal
        view
        returns (ArunikaVault.TradeParams memory)
    {
        return ArunikaVault.TradeParams({
            tokenIn: address(whsk),
            tokenOut: address(usdt),
            amountIn: amountIn,
            amountOutMinimum: minOut,
            fee: FEE,
            sqrtPriceLimitX96: 0,
            signalId: signalId
        });
    }

    // ---- Happy path ----
    function testHappyPathBuyAndSell() public {
        // Buy 100 USDT -> 1,250 WHSK at $0.08
        vm.prank(agent);
        uint256 out = vault.executeTrade(_buyParams(100 * 1e6, 0, 1));
        assertEq(out, 1250 ether, "buy output");
        assertEq(whsk.balanceOf(address(vault)), 1000 ether + 1250 ether);
        ArunikaVault.Position memory pos = vault.getPosition(address(whsk));
        assertTrue(pos.open);
        assertEq(pos.balance, 1250 ether);

        // Sell half the position back at the same price -> no loss, no gain
        vm.warp(block.timestamp + 61);
        vm.prank(agent);
        uint256 back = vault.executeTrade(_sellParams(625 ether, 0, 2));
        assertEq(back, 50 * 1e6, "sell output");
        assertEq(vault.dailyLossUsd18(), 0, "no loss at flat price");
    }

    // ---- Guards ----
    function testNonAgentReverts() public {
        vm.prank(stranger);
        vm.expectRevert(ArunikaVault.NotAgent.selector);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 1));
    }

    function testOwnerCannotTradeEither() public {
        vm.prank(owner);
        vm.expectRevert(ArunikaVault.NotAgent.selector);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 1));
    }

    function testOversizeTradeReverts() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(ArunikaVault.TradeTooLarge.selector, 10_001 * 1e6, 10_000 * 1e6)
        );
        vault.executeTrade(_buyParams(10_001 * 1e6, 0, 1));
    }

    function testPauseBlocksAndUnpauseWorks() public {
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(agent);
        vm.expectRevert(ArunikaVault.IsPaused.selector);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 1));

        vm.prank(owner);
        vault.unpause();
        vm.prank(agent);
        uint256 out = vault.executeTrade(_buyParams(10 * 1e6, 0, 1));
        assertEq(out, 125 ether);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(stranger);
        vm.expectRevert(ArunikaVault.NotOwner.selector);
        vault.pause();
    }

    function testUnallowlistedTokenReverts() public {
        MockERC20 scam = new MockERC20("Scam", "SCAM", 18);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(ArunikaVault.TokenNotAllowed.selector, address(scam)));
        vault.executeTrade(
            ArunikaVault.TradeParams({
                tokenIn: address(scam),
                tokenOut: address(usdt),
                amountIn: 1 ether,
                amountOutMinimum: 0,
                fee: FEE,
                sqrtPriceLimitX96: 0,
                signalId: 9
            })
        );
    }

    function testCooldownReverts() public {
        vm.prank(agent);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 1));
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(ArunikaVault.CooldownActive.selector, 60)
        );
        vault.executeTrade(_buyParams(10 * 1e6, 0, 2));

        vm.warp(block.timestamp + 60);
        vm.prank(agent);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 3)); // works after cooldown
    }

    function testSlippageReverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(ArunikaVault.SlippageTooHigh.selector, 125 ether, 126 ether));
        vault.executeTrade(_buyParams(10 * 1e6, 126 ether, 1));
    }

    function testStopLossBlocksBuysWhenUnderwater() public {
        // Buy at $0.08
        vm.prank(agent);
        vault.executeTrade(_buyParams(100 * 1e6, 0, 1));
        // Price crashes to $0.07 (-12.5%, beyond the 5% stop)
        vm.prank(owner);
        quoter.setPrice(address(whsk), 0.07 ether, 18);
        vm.warp(block.timestamp + 61);
        // Further buys are blocked...
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArunikaVault.StopLossBreached.selector, address(whsk), 0.07 ether, 0.08 ether
            )
        );
        vault.executeTrade(_buyParams(10 * 1e6, 0, 2));
        // ...but selling out still works (the stop-loss exit)
        vm.prank(agent);
        uint256 back = vault.executeTrade(_sellParams(1250 ether, 0, 3));
        assertEq(back, 875 * 1e5, "sell at $0.07"); // 1250 * 0.07 = $87.50
    }

    function testDailyLossCapBlocks() public {
        // Buy 100 USDT of WHSK at $0.08, then crash the price and sell at a $12.50 loss
        vm.prank(agent);
        vault.executeTrade(_buyParams(100 * 1e6, 0, 1));
        vm.prank(owner);
        quoter.setPrice(address(whsk), 0.07 ether, 18);
        vm.warp(block.timestamp + 61);
        vm.prank(agent);
        vault.executeTrade(_sellParams(1250 ether, 0, 2));
        assertEq(vault.dailyLossUsd18(), 12.5 ether, "daily loss recorded");

        // Shrink the cap below the realised loss -> next trade is blocked
        vm.prank(owner);
        vault.setMaxDailyLoss(10 ether);
        vm.warp(block.timestamp + 61);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(ArunikaVault.DailyLossCapReached.selector, 12.5 ether, 10 ether)
        );
        vault.executeTrade(_buyParams(10 * 1e6, 0, 3));

        // Next UTC day the cap resets and trading resumes
        vm.warp(block.timestamp + 1 days);
        vm.prank(agent);
        vault.executeTrade(_buyParams(10 * 1e6, 0, 4));
        assertEq(vault.dailyLossUsd18(), 0, "loss reset next day");
    }

    function testWithdrawOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(ArunikaVault.NotOwner.selector);
        vault.withdraw(address(usdt), 1 * 1e6, stranger);

        vm.prank(owner);
        vault.withdraw(address(usdt), 100 * 1e6, owner);
        assertEq(usdt.balanceOf(owner), 100 * 1e6);
    }
}
