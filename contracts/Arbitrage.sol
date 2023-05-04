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

    address public immutable vault;
    address public swapper;
    address public owner;

    constructor(address _vault, address _swapper) {
        owner = msg.sender;
        vault = _vault;
        swapper = _swapper;
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

    function executeTrade(bytes calldata userData) public {
        Trade[] memory trades = abi.decode(userData, (Trade[]));

        uint256 tradeAmount = trades[0].amount;
        
        for (uint256 i = 0; i < trades.length; i++) {
            uint256 tokenOutInitialBalance = IERC20(trades[i]._tokenOut)
                .balanceOf(address(this));

            if (
                keccak256(abi.encodePacked(trades[i].exchange)) ==
                keccak256(abi.encodePacked("SUSHISWAP"))
            ) {
                ISwapper(swapper).swapTokenOnUnsiwapv2(
                    trades[i]._router,
                    trades[i]._tokenIn,
                    trades[i]._tokenOut,
                    tradeAmount
                );
            }
            if (
                keccak256(abi.encodePacked(trades[i].exchange)) ==
                keccak256(abi.encodePacked("UNISWAPV3"))
            ) {
                ISwapper(swapper).swapTokenOnUniswapv3(
                    trades[i]._tokenIn,
                    trades[i]._tokenOut,
                    tradeAmount,
                    trades[i].poolFee,
                    trades[i]._router
                );
            }
            if (
                keccak256(abi.encodePacked(trades[i].exchange)) ==
                keccak256(abi.encodePacked("CURVE"))
            ) {
                ISwapper(swapper).exchangesTokensOnCurve(
                    trades[i].pool,
                    trades[i]._tokenIn,
                    trades[i]._tokenOut,
                    tradeAmount
                );
            }

            uint256 tokenOutBalance = IERC20(trades[i]._tokenOut).balanceOf(
                address(this)
            );
            tradeAmount = tokenOutBalance - tokenOutInitialBalance;
        }
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes calldata userData
    ) external override {
        IERC20 token = tokens[0];

        // executeTrade(userData);

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
