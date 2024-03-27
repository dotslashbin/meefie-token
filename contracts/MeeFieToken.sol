// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract MeeFieToken is ERC20, Ownable, ReentrancyGuard {
    address public uniswapV2Router;
    address public uniswapV2Pair;
    address payable _taxWallet;
    
    bool public inSwapAndLiquify;

    uint256 _initialSupply = 10_000_000 * (10 ** uint256(decimals()));

    constructor(address router) ERC20("MeeFie Token Test", "MFTS07") Ownable(msg.sender) {
        _mint(msg.sender, _initialSupply);
        uniswapV2Router = router;
        // Create a Uniswap pair for this new token and set to WETH
        uniswapV2Pair = IUniswapV2Factory(IUniswapV2Router02(uniswapV2Router).factory())
            .createPair(address(this), IUniswapV2Router02(uniswapV2Router).WETH());

        // Exclude the contract itself and the Uniswap pair from fees
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[uniswapV2Pair] = true;
    }

    mapping (address => bool) private isExcludedFromFee;

    // Modifier to check for fees
    modifier taxAndBurn(address from, address to, uint256 amount) {
        uint256 fees = 0;
        uint256 burnAmount = 0;
        
        if (!isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            if (to == uniswapV2Pair) { // Sell transaction
                fees = amount * 2 / 100; // 2% sell tax
                burnAmount = amount * 1 / 100; // 1% burn on sell
            } else if (from == uniswapV2Pair) { // Buy transaction
                fees = amount * 1 / 100; // 1% buy tax
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees); // Collect fees
            }

            if (burnAmount > 0) {
                _burn(from, burnAmount); // Burn tokens
            }

            amount -= fees + burnAmount;

            // Swap for taxation
            uint256 contractTokenBalance = balanceOf(address(this));
            if (contractTokenBalance > 0) {
                swapAndLiquify(contractTokenBalance);
            }
        }
        _;
    }

    function transferWithTaxAndBurn(address from, address to, uint256 amount) public taxAndBurn(from, to, amount) {
        super._transfer(from, to, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        transferWithTaxAndBurn(_msgSender(), recipient, amount);
        return true;
    }

    // Function to exclude an account from fees
    function excludeFromFee(address account) public onlyOwner {
        isExcludedFromFee[account] = true;
    }

    // Function to include an account in fees
    function includeInFee(address account) public onlyOwner {
        isExcludedFromFee[account] = false;
    }

    // Function to withdraw collected fees in tokens from the contract
    function withdrawTokenFees(address to, uint256 amount) public onlyOwner nonReentrant {
        require(amount <= balanceOf(address(this)), "Insufficient balance");
        _transfer(address(this), to, amount);
    }

    /** Taxation Functions */

    // Swapping tokens for chain currency using the router 
    function swapTokensForChainCurrency(uint256 tokenAmount) private {

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }

    // Processing tokens from contract
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForChainCurrency(contractTokenBalance);
        uint256 contractBalanceInChainCurrency = address(this).balance;
        sendToWallet(_taxWallet, contractBalanceInChainCurrency);
    }

    // Prevent processing while already processing! 
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    // Send chain currency to external wallet
    function sendToWallet(address payable wallet, uint256 amount) private {
        wallet.transfer(amount);
    }

    /** Admin functions */
    function taxWallet() public view returns(address) {
        return _taxWallet;
    }

    function setTaxWallet(address payable inputAddress) public onlyOwner {
        _taxWallet = inputAddress;
    }

    function setNewRouter(address newRouter) public onlyOwner {
        uniswapV2Router = newRouter;
    }
}
