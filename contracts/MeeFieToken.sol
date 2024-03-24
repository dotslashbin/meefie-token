// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract MeeFieToken is ERC20, Ownable {
    uint256 public buyTaxPercentage = 5;
    uint256 public sellTaxPercentage = 5;
    address public taxWallet;
    IUniswapV2Router02 public uniswapRouter;
    address public uniswapPair;

    constructor(
        uint256 initialSupply,
        address _uniswapRouter,
        address _taxWallet
    ) ERC20("MeeFieToken", "MTST101") Ownable(msg.sender){
        _mint(msg.sender, initialSupply);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        taxWallet = _taxWallet;
    }

    function setUniswapPair(address _uniswapPair) external onlyOwner {
        uniswapPair = _uniswapPair;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 taxAmount = 0;
        if (recipient == uniswapPair) { // Sell transaction
            taxAmount = (amount * sellTaxPercentage) / 100;
        }

        if (taxAmount > 0) {
            uint256 taxedAmount = amount - taxAmount;
            super.transfer(taxWallet, taxAmount);
            swapTokensForEth(taxAmount);
            return super.transfer(recipient, taxedAmount);
        } else {
            return super.transfer(recipient, amount);
        }
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 taxAmount = 0;
        if (sender == uniswapPair) { // Buy transaction
            taxAmount = (amount * buyTaxPercentage) / 100;
        }

        if (taxAmount > 0) {
            uint256 taxedAmount = amount - taxAmount;
            super.transferFrom(sender, taxWallet, taxAmount);
            swapTokensForEth(taxAmount);
            return super.transferFrom(sender, recipient, taxedAmount);
        } else {
            return super.transferFrom(sender, recipient, amount);
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();

        _approve(address(this), address(uniswapRouter), tokenAmount);

        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH
            path,
            taxWallet, // ETH goes to the tax wallet
            block.timestamp
        );
    }

    // To receive ETH from uniswapRouter when swapping
    receive() external payable {}
}
