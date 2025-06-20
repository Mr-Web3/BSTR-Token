// SPDX-License-Identifier: MIT

//  ____       ____       ____        _____       ____       
// /\  _\    /\  _\    /\  _\     /\  __\    /\  _\     
// \ \ \/\ \  \ \ \L\ \  \ \ \L\ \   \ \ \/\ \   \ \,\L\_\   
//  \ \ \ \ \  \ \  _ <'  \ \ ,  /    \ \ \ \ \   \/_\__ \   
//   \ \ \_\ \  \ \ \L\ \  \ \ \\ \    \ \ \_\ \    /\ \L\ \ 
//    \ \____/   \ \____/   \ \_\ \_\   \ \_____\   \ \____\
//     \/___/     \/___/     \/_/\/ /    \/_____/    \/_____/

pragma solidity ^0.8.20;

import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TaxDistributor.sol";

/*
 * TaxableToken: Add a tax on buy, sell or transfer
 */
abstract contract TaxableToken is ERC20, TaxDistributor {
    struct FeeConfiguration {
        bool feesInToken;
        uint16 buyFees;
        uint16 sellFees;
        uint16 transferFees;
        uint16 burnFeeRatio;
        uint16 liquidityFeeRatio;
        uint16 collectorsFeeRatio;
    }

    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);
    uint16 public constant MAX_FEE = 2000;
    uint16 public constant FEE_PRECISION = 10000;

    IUniswapV2Router02 public swapRouter;
    address public swapPair;
    address public liquidityOwner;

    bool private _processingFees;
    bool public autoProcessFees;
    uint256 public numTokensToSwap;
    FeeConfiguration public feeConfiguration;

    mapping(address => bool) private _excludedFromFees;
    mapping(address => bool) private _lpPools;

    event FeeConfigurationUpdated(FeeConfiguration configuration);
    event SwapRouterUpdated(address indexed router, address indexed pair);
    event ExcludedFromFees(address indexed account, bool excluded);
    event SetLpPool(address indexed pairAddress, bool isLp);

    modifier lockTheSwap() {
        _processingFees = true;
        _;
        _processingFees = false;
    }

    constructor(
        bool autoProcessFees_,
        uint256 numTokensToSwap_,
        address swapRouter_,
        FeeConfiguration memory feeConfiguration_
    ) {
        numTokensToSwap = numTokensToSwap_;
        autoProcessFees = autoProcessFees_;

        liquidityOwner = _msgSender();

        swapRouter = IUniswapV2Router02(swapRouter_);
        swapPair = _pairFor(swapRouter.factory(), address(this), swapRouter.WETH());
        _lpPools[swapPair] = true;

        _setIsExcludedFromFees(address(0), true);
        _setIsExcludedFromFees(BURN_ADDRESS, true);
        _setIsExcludedFromFees(address(this), true);
        _setIsExcludedFromFees(_msgSender(), true);

        _setFeeConfiguration(feeConfiguration_);
    }

    receive() external payable {}

    function isExcludedFromFees(address account) public view returns (bool) {
        return _excludedFromFees[account];
    }

    function _setIsExcludedFromFees(address account, bool excluded) internal {
        require(_excludedFromFees[account] != excluded, "Already set");
        _excludedFromFees[account] = excluded;
        emit ExcludedFromFees(account, excluded);
    }

    function _setIsLpPool(address pairAddress, bool isLp) internal {
        require(_lpPools[pairAddress] != isLp, "Already set");
        _lpPools[pairAddress] = isLp;
        emit SetLpPool(pairAddress, isLp);
    }

    function isLpPool(address pairAddress) public view returns (bool) {
        return _lpPools[pairAddress];
    }

    function _setSwapRouter(address _newRouter) internal {
        require(_newRouter != address(0), "Invalid router");

        swapRouter = IUniswapV2Router02(_newRouter);
        IUniswapV2Factory factory = IUniswapV2Factory(swapRouter.factory());
        require(address(factory) != address(0), "Invalid factory");

        address weth = swapRouter.WETH();
        swapPair = factory.getPair(address(this), weth);
        if (swapPair == address(0)) {
            swapPair = factory.createPair(address(this), weth);
        }

        require(swapPair != address(0), "Invalid pair address.");
        emit SwapRouterUpdated(address(swapRouter), swapPair);
    }

    function _setFeeConfiguration(FeeConfiguration memory configuration) internal {
        require(configuration.buyFees <= MAX_FEE, "Invalid buy fee");
        require(configuration.sellFees <= MAX_FEE, "Invalid sell fee");
        require(configuration.transferFees <= MAX_FEE, "Invalid transfer fee");

        uint16 totalShare = configuration.burnFeeRatio + configuration.liquidityFeeRatio + configuration.collectorsFeeRatio;
        require(totalShare == 0 || totalShare == FEE_PRECISION, "Invalid fee share");

        feeConfiguration = configuration;
        emit FeeConfigurationUpdated(configuration);
    }

    function _processFees(uint256 tokenAmount, uint256 minAmountOut) internal lockTheSwap {
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= tokenAmount) {
            uint256 liquidityAmount = (tokenAmount * feeConfiguration.liquidityFeeRatio) / (FEE_PRECISION - feeConfiguration.burnFeeRatio);
            uint256 liquidityTokens = liquidityAmount / 2;

            uint256 collectorsAmount = tokenAmount - liquidityAmount;
            uint256 liquifyAmount = liquidityAmount - liquidityTokens;

            if (!feeConfiguration.feesInToken) {
                liquifyAmount += collectorsAmount;
            }

            if (liquifyAmount > 0) {
                if (balanceOf(swapPair) == 0) return;

                uint256 initialBalance = address(this).balance;

                _swapTokensForEth(liquifyAmount, minAmountOut);

                uint256 swapBalance = address(this).balance - initialBalance;

                uint256 liquidityETH = (swapBalance * liquidityTokens) / liquifyAmount;
                if (liquidityETH > 0) {
                    _addLiquidity(liquidityTokens, liquidityETH);
                }
            }

            if (feeConfiguration.feesInToken) {
                _distributeFees(address(this), collectorsAmount, true);
            } else {
                _distributeFees(address(this), address(this).balance, false);
            }
        }
    }

    function _swapTokensForEth(uint256 tokenAmount, uint256 minAmountOut) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = swapRouter.WETH();

        _approve(address(this), address(swapRouter), tokenAmount);

        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            minAmountOut,
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(swapRouter), tokenAmount);

        swapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityOwner,
            block.timestamp
        );
    }

    function _pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(
            uint160(
                uint(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                        )
                    )
                )
            )
        );
    }

    function _update(address from, address to, uint256 amount) internal virtual {
        require(amount > 0, "Transfer <= 0");

        uint256 taxFee = 0;
        bool processFee = !_processingFees && autoProcessFees;

        bool fromLP = isLpPool(from);
        bool toLP = isLpPool(to);

        if (!_processingFees) {
            bool fromExcluded = isExcludedFromFees(from);
            bool toExcluded = isExcludedFromFees(to);

            if (fromLP && !toLP && !toExcluded && to != address(swapRouter)) {
                taxFee = feeConfiguration.buyFees;
            } else if (toLP && !fromExcluded && !toExcluded) {
                taxFee = feeConfiguration.sellFees;
            } else if (!fromLP && !toLP && from != address(swapRouter) && !fromExcluded) {
                taxFee = feeConfiguration.transferFees;
            }
        }

        if (processFee && taxFee > 0 && toLP) {
            uint256 contractTokenBalance = balanceOf(address(this));
            if (contractTokenBalance >= numTokensToSwap) {
                _processFees(contractTokenBalance, 0);
            }
        }

        if (taxFee > 0) {
            uint256 taxAmount = (amount * taxFee) / FEE_PRECISION;
            uint256 sendAmount = amount - taxAmount;
            uint256 burnAmount = (taxAmount * feeConfiguration.burnFeeRatio) / FEE_PRECISION;

            if (burnAmount > 0) {
                taxAmount -= burnAmount;
                super._transfer(from, BURN_ADDRESS, burnAmount);
            }

            if (taxAmount > 0) {
                super._transfer(from, address(this), taxAmount);
            }

            if (sendAmount > 0) {
                super._transfer(from, to, sendAmount);
            }
        } else {
            super._transfer(from, to, amount);
        }
    }


    function setAutoprocessFees(bool autoProcess) external virtual;
    function setIsLpPool(address pairAddress, bool isLp) external virtual;
    function setIsExcludedFromFees(address account, bool excluded) external virtual;
    function processFees(uint256 amount, uint256 minAmountOut) external virtual;
    function setLiquidityOwner(address newOwner) external virtual;
    function setNumTokensToSwap(uint256 amount) external virtual;
    function setFeeConfiguration(FeeConfiguration calldata configuration) external virtual;
    function setSwapRouter(address newRouter) external virtual;
}
