// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @custom:security-contact joshuarpf@gmail.com
contract Meefie is ERC20, ERC20Burnable {

    address _taxWallet;
    
    uint256 _multiplier;
    uint256 _burn;
    uint256 _tax;
    

    constructor(uint256 multipliier_, address taxWallet_, uint256 burn_, uint256 tax_) ERC20("Meefie", "MTF19") {
        _mint(msg.sender, 100000000000 * 10 ** decimals());

        _taxWallet = taxWallet_;
        _multiplier = multipliier_;
        _burn = burn_;
        _tax = tax_;
    }

    function burn() public returns (address) {
        return _burn;
    }

    function multiplier()  returns (uint256) {
        return _multiplier;
    }

    function setTaxWallet(address walletAddress_) onlyOwner public {
        _taxWallet = walletAddress_;
    }

    function taxWallet() public returns (address) {
        return _taxWallet;
    }
}
