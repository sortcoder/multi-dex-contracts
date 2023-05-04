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

contract Swapper {
    address public addressProviderCurve;

    constructor(address _addressProviderCurve) {
        addressProviderCurve = _addressProviderCurve;
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
    ) external returns (uint256[] memory) {
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
    ) external returns (uint) {
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
    ) public view returns (address) {
        return IProvider(addressProviderCurve).get_address(_id);
    }

    function exchangesTokensOnCurve(
        address _pool,
        address _from,
        address _to,
        uint256 _amount
    ) external  {
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
}