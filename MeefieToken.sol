// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @custom:security-contact joshuarpf@gmail.com
contract Meefie is ERC20, ERC20Burnable {

    address _taxWallet;
    
    uint256 _buyTax;
    uint256 _sellTax;

    uint256 taxAmount;

    mapping(address => uint256) private _balances;

    constructor(address taxWallet_, uint256 buyTax_, uint256 sellTax_) ERC20("Meefie", "MTF27") {
        _mint(msg.sender, 100000000000 * 10 ** decimals());

        _taxWallet = taxWallet_;
        _buyTax = buyTax_;
        _sellTax = sellTax_;
    }

    // Event emitted when taxes are collected
    event TaxCollected(address indexed from, uint256 value);

    function taxWallet() public view returns (address) {
        return _taxWallet;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        
        require(to != address(0), "Transfer to the zero address is not allowed");
        require(_balances[msg.sender] >= value, "Insufficient balance");

         // Calculate taxes

         // Sell
         if(msg.sender == tx.origin) {
            taxAmount = (value * _sellTax) / 100; // Apply sell tax only to external transactions
         } else {
            taxAmount = (value * _buyTax) / 100; // Apply buy tax only to external transactions
         }

        uint256 netValue = value - taxAmount;

        _balances[msg.sender] -= value;
        _balances[to] += netValue;

        emit Transfer(msg.sender, to, netValue);
        emit TaxCollected(msg.sender, taxAmount);

        return super.transfer(to, value);
    }
}
