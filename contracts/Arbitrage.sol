// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./curve-contracts/ISwap.sol";
import "./uniswapv2-contracts/ISwapRouterV2.sol";
import "./uniswapv3-contracts/ISwapRouter.sol";
import "./curve-contracts/IProvider.sol";

contract FlashLoanArbitrage {
    address addressProviderCurve;
    address owner;

    constructor(
        address _addressProviderCurve
    ) {
        addressProviderCurve = _addressProviderCurve;
        owner = msg.sender;
    }

    struct Trade {
        address _router;
        address _tokenIn;
        address _tokenOut;
        uint amount;
        address pool;
        uint poolFee;
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
    
    function returnsExchangeAddress(uint256 _id)
        internal
        view
        returns (address)
    {
        return IProvider(addressProviderCurve).get_address(_id);
    }

    function exchangesTokensOnCurve(
        address _pool,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _expected,
        address _receiver
    ) internal {
        address exchangeContract = returnsExchangeAddress(2);
        IERC20(_from).approve(exchangeContract, _amount);

        ISwap(exchangeContract).exchange(
            _pool,
            _from,
            _to,
            _amount,
            _expected,
            _receiver
        );
    }

    // function executeTrade(
    //     Trade[] memory trades
    // ) public {
    //     for(uint i=0; i < trades.length; i++){
    //         Trade memory trade = trades[i];
    //         if (keccak256(abi.encodePacked(trade.exchange)) == keccak256(abi.encodePacked("UNISWAPV2"))){
    //             swapTokenOnUnsiwapv2(trade._router, trade._tokenIn, trade._tokenOut, trade.amount);
    //         }       
    //     }
    // }
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

