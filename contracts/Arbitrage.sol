// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./curve-contracts/ISwap.sol";
import "./uniswapv2-contracts/ISwapRouterV2.sol";
import "./uniswapv3-contracts/ISwapRouter.sol";
import "./curve-contracts/IProvider.sol";
import "./balancer-contracts/IBalancerVault.sol";
import "./balancer-contracts/IFlashLoanRecipient.sol";
import "./swapper-contract/ISwapper.sol";

contract FlashLoanArbitrage is IFlashLoanRecipient {
    using SafeMath for uint256;

    event TradeAmount(uint256 tradeAmount);

    address public immutable vault;
    address public swapper;
    address public owner;
    address public addressProviderCurve;

    constructor(address _vault, address _addressProviderCurve) {
        owner = msg.sender;
        vault = _vault;
        addressProviderCurve = _addressProviderCurve;
    }

    struct Trade {
        address _router;
        address _tokenIn;
        address _tokenOut;
        uint256 amount;
        address pool;
        uint24 poolFee;
        string exchange;
    }

    function getAmountOutMin(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) public view returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory amountOutMins = ISwapRouterV2(router).getAmountsOut(
            _amount,
            path
        );
        return amountOutMins[path.length - 1];
    }

    function swapTokenOnUnsiwapv2(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) public returns (uint256[] memory) {
        IERC20(_tokenIn).approve(router, _amount);
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256 deadline = block.timestamp + 300;
        uint256 minAmount = getAmountOutMin(
            router,
            _tokenIn,
            _tokenOut,
            _amount
        );
        uint256[] memory amountOut = ISwapRouterV2(router)
            .swapExactTokensForTokens(
                _amount,
                minAmount,
                path,
                address(this),
                deadline
            );
        return amountOut;
    }

    function swapTokenOnUniswapv3(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        uint24 poolFee,
        address router
    ) public returns (uint256) {
        IERC20(_tokenIn).approve(router, _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: _amount,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(router).exactInputSingle(params);
        return amountOut;
    }

    function returnsExchangeAddress(uint256 _id) public view returns (address) {
        return IProvider(addressProviderCurve).get_address(_id);
    }

    function exchangesTokensOnCurve(
        address _pool,
        address _from,
        address _to,
        uint256 _amount
    ) public {
        address exchangeContract = returnsExchangeAddress(2);
        IERC20(_from).approve(exchangeContract, _amount);

        uint256 expected = ISwap(exchangeContract).get_exchange_amount(
            _pool,
            _from,
            _to,
            _amount
        );

        ISwap(exchangeContract).exchange(
            _pool,
            _from,
            _to,
            _amount,
            expected,
            address(this)
        );
    }

    function executeTrade(Trade memory trade) public {
        uint256 tradeAmount = trade.amount;

        uint256 tokenOutInitialBalance = IERC20(trade._tokenOut).balanceOf(
            address(this)
        );

        if (
            keccak256(abi.encodePacked(trade.exchange)) ==
            keccak256(abi.encodePacked("SUSHISWAP"))
        ) {
            swapTokenOnUnsiwapv2(
                trade._router,
                trade._tokenIn,
                trade._tokenOut,
                tradeAmount
            );
        }
        if (
            keccak256(abi.encodePacked(trade.exchange)) ==
            keccak256(abi.encodePacked("UNISWAPV3"))
        ) {
            swapTokenOnUniswapv3(
                trade._tokenIn,
                trade._tokenOut,
                trade.amount,
                trade.poolFee,
                trade._router
            );
        }
        if (
            keccak256(abi.encodePacked(trade.exchange)) ==
            keccak256(abi.encodePacked("CURVE"))
        ) {
            exchangesTokensOnCurve(
                trade.pool,
                trade._tokenIn,
                trade._tokenOut,
                tradeAmount
            );
        }
        uint256 tokenOutBalance = IERC20(trade._tokenOut).balanceOf(
            address(this)
        );
        tradeAmount = tokenOutBalance - tokenOutInitialBalance;
    }

    // function executeTrade(Trade[] memory trades) public {
    //     uint256 tradeAmount = trades[0].amount;

    //     for (uint256 i = 0; i < trades.length; i++) {
    //         uint256 tokenOutInitialBalance = IERC20(trades[i]._tokenOut).balanceOf(
    //             address(this)
    //         );

    //         if (
    //             keccak256(abi.encodePacked(trades[i].exchange)) ==
    //             keccak256(abi.encodePacked("SUSHISWAP"))
    //         ) {
    //             swapTokenOnUnsiwapv2(
    //                 trades[i]._router,
    //                 trades[i]._tokenIn,
    //                 trades[i]._tokenOut,
    //                 tradeAmount
    //             );
    //         }
    //         if (
    //             keccak256(abi.encodePacked(trades[i].exchange)) ==
    //             keccak256(abi.encodePacked("UNISWAPV3"))
    //         ) {
    //             swapTokenOnUniswapv3(
    //                 trades[i]._tokenIn,
    //                 trades[i]._tokenOut,
    //                 trades[i].amount,
    //                 trades[i].poolFee,
    //                 trades[i]._router
    //             );
    //         }
    //         if (
    //             keccak256(abi.encodePacked(trades[i].exchange)) ==
    //             keccak256(abi.encodePacked("CURVE"))
    //         ) {
    //             exchangesTokensOnCurve(
    //                 trades[i].pool,
    //                 trades[i]._tokenIn,
    //                 trades[i]._tokenOut,
    //                 tradeAmount
    //             );
    //         }
    //         uint256 tokenOutBalance = IERC20(trades[i]._tokenOut).balanceOf(
    //             address(this)
    //         );
    //         tradeAmount = tokenOutBalance - tokenOutInitialBalance;
    //     }

    //     emit TradeAmount(tradeAmount);
    // }

    function calculateTradeAmount(uint256 initialBalance, address token)
        internal
        view
        returns (uint256)
    {
        uint256 tokenOutBalance = IERC20(token).balanceOf(address(this));
        uint256 tradeAmount = tokenOutBalance - initialBalance;
        return tradeAmount;
    }

    function executeTriTrade(
        Trade memory trade1,
        Trade memory trade2,
        Trade memory trade3
    ) public {
        //Trade 1
        uint256 tradeAmount = trade1.amount;
        uint256 token2InitialBalance = IERC20(trade2._tokenIn).balanceOf(
            address(this)
        );
        executeTrade(trade1);

        //Trade 2
        tradeAmount = calculateTradeAmount(token2InitialBalance, trade2._tokenIn);
        uint256 token3InitialBalance = IERC20(trade3._tokenIn).balanceOf(
            address(this)
        );
        executeTrade(trade2);

        //Trade 3
        tradeAmount = calculateTradeAmount(token3InitialBalance, trade3._tokenIn);
        executeTrade(trade3);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes calldata userData
    ) external override {
        IERC20 token = tokens[0];
        (Trade memory trade1, Trade memory trade2, Trade memory trade3) = abi
            .decode(userData, (Trade, Trade, Trade));

        executeTriTrade(trade1, trade2, trade3);

        // Return loan
        token.transfer(vault, amounts[0]);
    }

    function flashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes calldata userData
    ) external {
        IBalancerVault(vault).flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            amounts,
            userData
        );
    }

    function withdraw(address _tokenAddress) external {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function getBalance(address _tokenContractAddress)
        external
        view
        returns (uint256)
    {
        uint256 balance = IERC20(_tokenContractAddress).balanceOf(
            address(this)
        );
        return balance;
    }
}
