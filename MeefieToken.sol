// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router01, IUniswapV2Router02} from './Uniswap.sol';
import {IERC20} from './ERC20.sol';
import {SafeMath} from './Safemath.sol';
import {Address} from './Address.sol';
import {Context, Ownable} from './Contracts.sol';

contract Meefie is Context, IERC20, Ownable { 
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromFee; 
    mapping (address => bool) public _isBlacklisted;

    bool public noBlackList;
   
    address payable private _taxWallet;
    address payable private _burnWallet = payable(0x000000000000000000000000000000000000dEaD); 
    address payable private _zeroWallet = payable(0x0000000000000000000000000000000000000000); 

    string private _name = "MeefieTest"; 
    string private _symbol; 
    uint8 private _decimals = 18;
    uint256 private _tTotal = 1000000000 * 10**_decimals;
    uint256 private _tFeeTotal;

    // Counter for liquify trigger
    uint8 private txCount = 0;
    uint8 private swapTrigger = 3; 

    // This is the max fee that the contract will accept, it is hard-coded to protect buyers
    // This includes the buy AND the sell fee!
    uint256 private maxPossibleFee = 100; 

    // Setting the initial fees
    uint256 private _TotalFee = 5;
    uint256 public _buyFee = 2;
    uint256 public _autoBurnTax = 1;
    uint256 public _marketingTax = 2;

    // 'Previous fees' are used to keep track of fee settings when removing and restoring fees
    uint256 private _previousTotalFee = _TotalFee; 
    uint256 private _previousBuyFee = _buyFee; 
    uint256 private _previousAutoBurnTax = _autoBurnTax; 
    uint256 private _previousMarketingTax = _marketingTax; 

    /*

        WALLET LIMITS 
    
    */

   uint256 public _walletLimitPercentage = 4;

    uint256 public _maxWalletToken = _tTotal.mul(_walletLimitPercentage).div(100);
    uint256 private _previousMaxWalletToken = _maxWalletToken;
    uint256 public _maxTxAmount = _tTotal.mul(_walletLimitPercentage).div(100); 
    uint256 private _previousMaxTxAmount = _maxTxAmount;

    /* 

        ROUTER SET UP

    */
                                     
    IUniswapV2Router02 public uniswapV2Router;
    address private _uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public uniswapV2Pair;
    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
        
    );
    
    // Prevent processing while already processing! 
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor (string memory inputSymbol, address initialSupplyWallet, address initialTaxWallet) {

        _symbol = inputSymbol;

        _tOwned[initialSupplyWallet] = _tTotal;

        updateTaxWallet(payable(initialTaxWallet));

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_uniswapRouterAddress); 
        
        // Create pair address for PancakeSwap
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_taxWallet] = true;

        emit Transfer(address(0), owner(), _tTotal);
    }


    /*

        STANDARD ERC20 COMPLIANCE FUNCTIONS

    */

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
     
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    // Set a wallet address so that it does not have to pay transaction fees
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    // Set a wallet address so that it has to pay transaction fees
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setFees(uint256 Buy_Fee, uint256 Sell_Fee, uint256 Burn_Fee, uint256 Marketing_Fee) external onlyOwner() {

        require((Buy_Fee + Sell_Fee + Burn_Fee + Marketing_Fee) <= maxPossibleFee, "Fee is too high!");
        _buyFee = Buy_Fee;
        _autoBurnTax = Burn_Fee;
        _marketingTax = Marketing_Fee;
    }

    // Update main wallet
    function updateTaxWallet(address payable wallet) public onlyOwner() {
        _taxWallet = wallet;
        _isExcludedFromFee[_taxWallet] = true;
    }

    /*
        PROCESSING TOKENS - SET UP
    */
    
    // Toggle on and off to auto process tokens to BNB wallet 
    function setSwapAndLiquifyEnabled(bool true_or_false) public onlyOwner {
        swapAndLiquifyEnabled = true_or_false;
        emit SwapAndLiquifyEnabledUpdated(true_or_false);
    }

    // This will set the number of transactions required before the 'swapAndLiquify' function triggers
    function setNumberOfTransactionsBeforeLiquifyTrigger(uint8 number_of_transactions) public onlyOwner {
        swapTrigger = number_of_transactions;
    }
    
    // This function is required so that the contract can receive BNB from pancakeswap
    receive() external payable {}

    function blacklistAddWallets(address[] calldata addresses) external onlyOwner {
       
        uint256 startGas;
        uint256 gasUsed;

        for (uint256 i; i < addresses.length; ++i) {
            if(gasUsed < gasleft()) {
                startGas = gasleft();
                if(!_isBlacklisted[addresses[i]]){
                _isBlacklisted[addresses[i]] = true;}
                gasUsed = startGas - gasleft();
            }
        }
    }

    // Blacklist - block wallets (REMOVE - COMMA SEPARATE MULTIPLE WALLETS)
    function blacklistRemoveWallets(address[] calldata addresses) external onlyOwner {
       
        uint256 startGas;
        uint256 gasUsed;

        for (uint256 i; i < addresses.length; ++i) {
            if(gasUsed < gasleft()) {
                startGas = gasleft();
            if(_isBlacklisted[addresses[i]]){
                _isBlacklisted[addresses[i]] = false;}
                gasUsed = startGas - gasleft();
            }
        }
    }

    function blacklistSwitch(bool true_or_false) public onlyOwner {
        noBlackList = true_or_false;
    } 

    bool public noFeeToTransfer = true;

    // Option to set fee or no fee for transfer (just in case the no fee transfer option is exploited in future!)
    // True = there will be no fees when moving tokens around or giving them to friends! (There will only be a fee to buy or sell)
    // False = there will be a fee when buying/selling/tranfering tokens
    // Default is true
    function setTransfersWithoutFees(bool true_or_false) external onlyOwner {
        noFeeToTransfer = true_or_false;
    }

    /*

    WALLET LIMITS

    Wallets are limited in two ways. The amount of tokens that can be purchased in one transaction
    and the total amount of tokens a wallet can buy. Limiting a wallet prevents one wallet from holding too
    many tokens, which can scare away potential buyers that worry that a whale might dump!

    IMPORTANT

    Solidity can not process decimals, so to increase flexibility, we multiple everything by 100.
    When entering the percent, you need to shift your decimal two steps to the right.

    eg: For 4% enter 400, for 1% enter 100, for 0.25% enter 25, for 0.2% enter 20 etc!

    */

    // Set the Max transaction amount (percent of total supply)
    function setMaxTransactionPercent(uint256 maxTxPercent_x100) external onlyOwner() {
        _maxTxAmount = _tTotal*maxTxPercent_x100/10000;
    }    
    
    // Set the maximum wallet holding (percent of total supply)
     function set_Max_Wallet_Percent(uint256 maxWallPercent_x100) external onlyOwner() {
        _maxWalletToken = _tTotal*maxWallPercent_x100/10000;
    }



    // Remove all fees
    function removeAllFee() private {
        if(_TotalFee == 0 && _buyFee == 0 && _autoBurnTax == 0 && _marketingTax == 0) return;

        _previousBuyFee = _buyFee; 
        _previousTotalFee = _TotalFee;
        _previousAutoBurnTax = _autoBurnTax;
        _previousMarketingTax = _marketingTax;
        _buyFee = 0;
        _TotalFee = 0;
        _autoBurnTax = 0;
        _marketingTax = 0;
    }
    
    // Restore all fees
    function restoreAllFee() private {
        _TotalFee = _previousTotalFee;
        _buyFee = _previousBuyFee; 
        _autoBurnTax = _previousAutoBurnTax;
        _marketingTax = _previousMarketingTax;
    }


    // Approve a wallet to sell tokens
    function _approve(address owner, address spender, uint256 amount) private {

        require(owner != address(0) && spender != address(0), "ERR: zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);

    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        

        /*
            TRANSACTION AND WALLET LIMITS
        */
        

        // Limit wallet total
        if (to != owner() &&
            to != _taxWallet &&
            to != address(this) &&
            to != uniswapV2Pair &&
            to != _burnWallet &&
            from != owner()){
            uint256 heldTokens = balanceOf(to);
            require((heldTokens + amount) <= _maxWalletToken,"You are trying to buy too many tokens. You have reached the limit for one wallet.");}


        // Limit the maximum number of tokens that can be bought or sold in one transaction
        if (from != owner() && to != owner())
            require(amount <= _maxTxAmount, "You are trying to buy more than the max transaction limit.");



        /*
            BLACKLIST RESTRICTIONS
        */
        
        if (noBlackList){
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "This address is blacklisted. Transaction reverted.");}


        require(from != address(0) && to != address(0), "ERR: Using 0 address!");
        require(amount > 0, "Token value must be higher than zero.");


        /*
            PROCESSING
        */


        // SwapAndLiquify is triggered after every X transactions - this number can be adjusted using swapTrigger

        if(
            txCount >= swapTrigger && 
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled 
            )
        {  
            
            txCount = 0;
            uint256 contractTokenBalance = balanceOf(address(this));
            if(contractTokenBalance > _maxTxAmount) {contractTokenBalance = _maxTxAmount;}
            if(contractTokenBalance > 0){
            swapAndLiquify(contractTokenBalance);
        }
        }


        /*
            REMOVE FEES IF REQUIRED

            Fee removed if the to or from address is excluded from fee.
            Fee removed if the transfer is NOT a buy or sell.
            Change fee amount for buy or sell.
        */

        
        bool takeFee = true;
         
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to] || (noFeeToTransfer && from != uniswapV2Pair && to != uniswapV2Pair)){
            takeFee = false;
        } else if (from == uniswapV2Pair) {
            _TotalFee = _buyFee;
        } else if (to == uniswapV2Pair) {
            _TotalFee = _marketingTax;
        }
        
        _tokenTransfer(from,to,amount,takeFee);
    }

    // Send BNB to external wallet
    function sendToWallet(address payable wallet, uint256 amount) private {
        wallet.transfer(amount);
    }

    // Processing tokens from contract
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForChainCurrency(contractTokenBalance);
        uint256 contractBNB = address(this).balance;
        sendToWallet(_taxWallet,contractBNB);
    }

    // Manual Token Process Trigger - Enter the percent of the tokens that you'd like to send to process
    function processTokensNow (uint256 percent_Of_Tokens_To_Process) public onlyOwner {
        // Do not trigger if already in swap
        require(!inSwapAndLiquify, "Currently processing, try later."); 
        if (percent_Of_Tokens_To_Process > 100){percent_Of_Tokens_To_Process == 100;}
        uint256 tokensOnContract = balanceOf(address(this));
        uint256 sendTokens = tokensOnContract*percent_Of_Tokens_To_Process/100;
        swapAndLiquify(sendTokens);
    }

    // Swapping tokens for BNB using PancakeSwap 
    function swapTokensForChainCurrency(uint256 tokenAmount) private {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }

    function taxWallet() public view onlyOwner returns(address) {
        return _taxWallet;
    }

    // Remove random tokens from the contract and send to a wallet
    function removeRandomTokens(address random_Token_Address, address send_to_wallet, uint256 number_of_tokens) public onlyOwner returns(bool _sent){
        require(random_Token_Address != address(this), "Can not remove native token");
        uint256 randomBalance = IERC20(random_Token_Address).balanceOf(address(this));
        if (number_of_tokens > randomBalance){number_of_tokens = randomBalance;}
        _sent = IERC20(random_Token_Address).transfer(send_to_wallet, number_of_tokens);
    }

    // Set new router and make the new pair address
    function setNewRouterandMakePair(address newRouter) public onlyOwner() {
        IUniswapV2Router02 _newPCSRouter = IUniswapV2Router02(newRouter);
        uniswapV2Pair = IUniswapV2Factory(_newPCSRouter.factory()).createPair(address(this), _newPCSRouter.WETH());
        uniswapV2Router = _newPCSRouter;
    }
   
    // Set new router
    function setNewRouterAddress(address newRouter) public onlyOwner() {
        IUniswapV2Router02 _newPCSRouter = IUniswapV2Router02(newRouter);
        uniswapV2Router = _newPCSRouter;
    }
    
    // Set new address - This will be the 'Cake LP' address for the token pairing
    function setNewPairAddress(address newPair) public onlyOwner() {
        uniswapV2Pair = newPair;
    }

    // Check if token transfer needs to process fees
    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!takeFee) {
            removeAllFee();
        } else {
            txCount++;
        }
        _transferTokens(sender, recipient, amount);
        _burnTokens(sender, amount);
        
        if(!takeFee) {
            restoreAllFee();
        }
    }

    // Redistributing tokens and adding the fee to the contract address
    function _transferTokens(address sender, address recipient, uint256 tAmount) private {
        (uint256 tTransferAmount, uint256 tDev) = _getValues(tAmount);

        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _tOwned[address(this)] = _tOwned[address(this)].add(tDev);   


        emit Transfer(sender, recipient, tTransferAmount);
    }

    // Calculating the fee in tokens
    function _getValues(uint256 tAmount) private view returns (uint256, uint256) {
        uint256 tDev = tAmount*_TotalFee/100;
        uint256 tTransferAmount = tAmount.sub(tDev);
        return (tTransferAmount, tDev);
    }

    // TODO: do the burn transfer
    function _burnTokens(address sender, uint256 tAmount) private {
        uint256 tBurnAmount = _getBurnValues(tAmount);

        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _tOwned[_burnWallet] = _tOwned[_burnWallet].add(tBurnAmount);

        emit Transfer(sender, _burnWallet, tBurnAmount);
    }

    function _getBurnValues(uint256 tAmount) private view returns (uint256) {
        uint256 tDev = tAmount*_autoBurnTax/100;
        uint256 tBurnAmount = tAmount.sub(tDev);
        return (tBurnAmount);
    }

    function setWalletLimitPercentage(uint256 value) public onlyOwner() {
        _walletLimitPercentage = value;
    }
}