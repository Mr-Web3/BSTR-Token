// SPDX-License-Identifier: MIT

//  ____       ____       ____        _____       ____       
// /\  _\    /\  _\    /\  _\     /\  __\    /\  _\     
// \ \ \/\ \  \ \ \L\ \  \ \ \L\ \   \ \ \/\ \   \ \,\L\_\   
//  \ \ \ \ \  \ \  _ <'  \ \ ,  /    \ \ \ \ \   \/_\__ \   
//   \ \ \_\ \  \ \ \L\ \  \ \ \\ \    \ \ \_\ \    /\ \L\ \ 
//    \ \____/   \ \____/   \ \_\ \_\   \ \_____\   \ \____\
//     \/___/     \/___/     \/_/\/ /    \/_____/    \/_____/

pragma solidity ^0.8.20;

/**
 * [Audit Note - IVotes Integration]
 * Added `ERC20Permit` and `ERC20Votes` extensions from OpenZeppelin
 * to support governance capabilities and gasless vote delegation.
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./libraries/TaxableToken.sol";
import "./libraries/TaxDistributor.sol";

/**
 * [Audit Note - IVotes Integration]
 * Extended from ERC20Votes and ERC20Permit for snapshot-based voting
 * and off-chain vote delegation support (EIP-2612 compliant).
 */
contract BSTRToken is ERC20, ERC20Permit, ERC20Votes, TaxableToken, Ownable, ReentrancyGuard {
    address public taxRateUpdater;
    uint8 private constant CUSTOM_DECIMALS = 9;

    event TaxRateUpdaterChanged(address indexed updater);

    constructor(
        uint256 initialSupply_,
        address feeReceiver_,
        address swapRouter_,
        address[] memory collectors_,
        uint256[] memory shares_
    )
        payable
        ERC20("Buster", "BSTR")
        ERC20Permit("Buster") // [Audit Note] Enables permit() for off-chain approvals
        TaxableToken(
            true,
            initialSupply_ / 10000,
            swapRouter_,
            FeeConfiguration({
                feesInToken: true,
                buyFees: 500,
                sellFees: 500,
                transferFees: 0,
                burnFeeRatio: 0,
                liquidityFeeRatio: 5000,
                collectorsFeeRatio: 5000
            })
        )
        TaxDistributor(collectors_, shares_)
    {
        /**
         * [Audit Fix - Compilation & Ownership Init]
         * Removed constructor argument from Ownable as OZ v4 Ownable() sets owner = msg.sender
         */

        require(initialSupply_ > 0, "Initial supply cannot be zero");
        require(collectors_.length <= 50, "Too many collectors"); // [Audit Fix] Cap fee collectors to avoid gas DoS

        /**
         * [Audit Fix - Safe ETH Transfer]
         * Used .call{value: ...}("") with success check instead of .transfer
         */
        (bool success, ) = payable(feeReceiver_).call{value: msg.value}("");
        require(success, "ETH transfer to feeReceiver failed");

        _mint(_msgSender(), initialSupply_);

        /**
         * [Audit Fix - Role Delegation]
         * Added logic to utilize `taxRateUpdater` for rate control
         */
        taxRateUpdater = _msgSender();
    }

    modifier onlyTaxRateUpdater() {
        require(msg.sender == taxRateUpdater, "Not taxRateUpdater");
        _;
    }

    function setTaxRateUpdater(address updater) external onlyOwner nonReentrant {
        taxRateUpdater = updater;
        emit TaxRateUpdaterChanged(updater);
    }

    function setTaxRates(uint256 buyRate, uint256 sellRate) external onlyTaxRateUpdater nonReentrant {
        require(buyRate <= MAX_FEE && sellRate <= MAX_FEE, "Tax too high");
        feeConfiguration.buyFees = uint16(buyRate);
        feeConfiguration.sellFees = uint16(sellRate);
        emit FeeConfigurationUpdated(feeConfiguration);
    }

    function decimals() public pure override returns (uint8) {
        return CUSTOM_DECIMALS;
    }

    function _update(address from, address to, uint256 amount) internal virtual override(TaxableToken) {
        super._update(from, to, amount);
    }

    /**
     * [Audit Note - IVotes Integration]
     * Overrides required by ERC20Votes to sync vote balances with token transfers.
     */
    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

    // Wrapped setters with access control
    function setAutoprocessFees(bool autoProcess) external override onlyOwner nonReentrant {
        require(autoProcessFees != autoProcess, "Already set");
        autoProcessFees = autoProcess;
    }

    function addFeeCollector(address account, uint256 share) external override onlyOwner nonReentrant {
        _addFeeCollector(account, share);
    }

    function removeFeeCollector(address account) external override onlyOwner nonReentrant {
        _removeFeeCollector(account);
    }

    function updateFeeCollectorShare(address account, uint256 share) external override onlyOwner nonReentrant {
        _updateFeeCollectorShare(account, share);
    }

    function distributeFees(uint256 amount, bool inToken) external override onlyOwner nonReentrant {
        if (inToken) {
            require(balanceOf(address(this)) >= amount, "Not enough token balance");
        } else {
            require(address(this).balance >= amount, "Not enough ETH balance");
        }
        _distributeFees(address(this), amount, inToken);
    }

    function processFees(uint256 amount, uint256 minAmountOut) external override onlyOwner nonReentrant {
        require(amount <= balanceOf(address(this)), "Amount too high");
        _processFees(amount, minAmountOut);
    }

    function setIsLpPool(address pairAddress, bool isLp) external override onlyOwner nonReentrant {
        _setIsLpPool(pairAddress, isLp);
    }

    function setIsExcludedFromFees(address account, bool excluded) external override onlyOwner nonReentrant {
        _setIsExcludedFromFees(account, excluded);
    }

    function setLiquidityOwner(address newOwner) external override onlyOwner nonReentrant {
        liquidityOwner = newOwner;
    }

    function setNumTokensToSwap(uint256 amount) external override onlyOwner nonReentrant {
        numTokensToSwap = amount;
    }

    function setFeeConfiguration(FeeConfiguration calldata configuration) external override onlyOwner nonReentrant {
        _setFeeConfiguration(configuration);
    }

    function setSwapRouter(address newRouter) external override onlyOwner nonReentrant {
        _setSwapRouter(newRouter);
    }
}