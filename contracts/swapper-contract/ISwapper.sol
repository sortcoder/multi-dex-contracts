// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ISwapper {
    function swapTokenOnUnsiwapv2(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint _amount
    ) external returns (uint256[] memory);

    function swapTokenOnUniswapv3(
        address _tokenIn,
        address _tokenOut,
        uint _amount,
        uint24 poolFee,
        address router
    ) external returns (uint);

    function exchangesTokensOnCurve(
        address _pool,
        address _from,
        address _to,
        uint256 _amount
    ) external;

}