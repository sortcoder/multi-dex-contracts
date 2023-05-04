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

contract FlashLoanArbitrage is IFlashLoanRecipient {
    using SafeMath for uint256;

    address public immutable vault;
    address public addressProviderCurve;
    address public owner;

    constructor(address _addressProviderCurve, address _vault) {
        addressProviderCurve = _addressProviderCurve;
        owner = msg.sender;
        vault = _vault;
    }

    struct Trade {
        address _router;
        address _tokenIn;
        address _tokenOut;
        uint amount;
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
        uint _amount
    ) public returns (uint256[] memory) {
        IERC20(_tokenIn).approve(router, _amount);
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint deadline = block.timestamp + 300;
        uint minAmount = getAmountOutMin(router, _tokenIn, _tokenOut, _amount);
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
        uint _amount,
        uint24 poolFee,
        address router
    ) public returns (uint) {
        IERC20(_tokenIn).approve(router, _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 120,
                amountIn: _amount,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(router).exactInputSingle(params);
        return amountOut;
    }

    function returnsExchangeAddress(
        uint256 _id
    ) internal view returns (address) {
        return IProvider(addressProviderCurve).get_address(_id);
    }

    function exchangesTokensOnCurve(
        address _pool,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        address exchangeContract = returnsExchangeAddress(2);
        IERC20(_from).approve(exchangeContract, _amount);

        uint expected = ISwap(exchangeContract).get_exchange_amount(
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

    function executeTrade(Trade[] memory trades) public {
        uint tradeAmount = trades[0].amount;
        uint tokenInInitialBalance = IERC20(trades[0]._tokenIn).balanceOf(
            address(this)
        );

        for (uint i = 0; i < trades.length; i++) {
            Trade memory trade = trades[i];

            uint tokenOutInitialBalance = IERC20(trades[i]._tokenOut).balanceOf(
                address(this)
            );

            if (
                keccak256(abi.encodePacked(trade.exchange)) ==
                keccak256(abi.encodePacked("UNISWAPV2"))
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
                    tradeAmount,
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

            uint tokenOutBalance = IERC20(trades[i]._tokenOut).balanceOf(
                address(this)
            );
            tradeAmount = tokenOutBalance - tokenOutInitialBalance;
        }

        uint tokenInFinalBalance = IERC20(trades[0]._tokenIn).balanceOf(
            address(this)
        );
        // require(tokenInFinalBalance > tokenInInitialBalance, "Trade Not Profitable")
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];
            uint256 feeAmount = feeAmounts[i];

            (Trade[] memory trades) = abi.decode(userData, (Trade[]));
            executeTrade(trades);

            // Return loan
            token.transfer(vault, amount);
        }
    }

    function flashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
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

    function getBalance(
        address _tokenContractAddress
    ) external view returns (uint256) {
        uint balance = IERC20(_tokenContractAddress).balanceOf(address(this));
        return balance;
    }

}
// struct Trade {
//     address _router;
//     address _tokenIn;
//     address _tokenOut;
//     uint amount;
//     address pool;
//     uint poolFee;
//     string exchange;
// }
