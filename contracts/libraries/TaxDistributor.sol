// SPDX-License-Identifier: MIT

//  ____       ____       ____        _____       ____       
// /\  _\    /\  _\    /\  _\     /\  __\    /\  _\     
// \ \ \/\ \  \ \ \L\ \  \ \ \L\ \   \ \ \/\ \   \ \,\L\_\   
//  \ \ \ \ \  \ \  _ <'  \ \ ,  /    \ \ \ \ \   \/_\__ \   
//   \ \ \_\ \  \ \ \L\ \  \ \ \\ \    \ \ \_\ \    /\ \L\ \ 
//    \ \____/   \ \____/   \ \_\ \_\   \ \_____\   \ \____\
//     \/___/     \/___/     \/_/\/ /    \/_____/    \/_____/

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract TaxDistributor {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _collectors;
    mapping(address => uint256) private _shares;
    uint256 public totalFeeCollectorsShares;

    uint256 public constant MAX_COLLECTORS = 50;

    event FeeCollectorAdded(address indexed account, uint256 share);
    event FeeCollectorUpdated(address indexed account, uint256 oldShare, uint256 newShare);
    event FeeCollectorRemoved(address indexed account);
    event FeeCollected(address indexed receiver, uint256 amount);

    constructor(address[] memory collectors_, uint256[] memory shares_) {
        require(collectors_.length == shares_.length, "Mismatched input");
        require(collectors_.length <= MAX_COLLECTORS, "Too many collectors");
        for (uint256 i = 0; i < collectors_.length; i++) {
            _addFeeCollector(collectors_[i], shares_[i]);
        }
    }

    function isFeeCollector(address account) public view returns (bool) {
        return _collectors.contains(account);
    }

    function feeCollectorShare(address account) public view returns (uint256) {
        return _shares[account];
    }

    function feeCollectors(uint256 startIndex, uint256 count) external view returns (address[] memory) {
        uint256 length = count;
        if (length > _collectors.length() - startIndex) {
            length = _collectors.length() - startIndex;
        }

        address[] memory values = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = _collectors.at(startIndex + i);
        }

        return values;
    }

    function _addFeeCollector(address account, uint256 share) internal {
        require(!_collectors.contains(account), "Already collector");
        require(_collectors.length() < MAX_COLLECTORS, "Max collectors reached");
        require(share > 0, "Invalid share");

        _collectors.add(account);
        _shares[account] = share;
        totalFeeCollectorsShares += share;

        emit FeeCollectorAdded(account, share);
    }

    function _removeFeeCollector(address account) internal {
        require(_collectors.contains(account), "Not a collector");

        _collectors.remove(account);
        totalFeeCollectorsShares -= _shares[account];
        delete _shares[account];

        emit FeeCollectorRemoved(account);
    }

    function _updateFeeCollectorShare(address account, uint256 share) internal {
        require(_collectors.contains(account), "Not a collector");
        require(share > 0, "Invalid share");

        uint256 oldShare = _shares[account];
        totalFeeCollectorsShares -= oldShare;

        _shares[account] = share;
        totalFeeCollectorsShares += share;

        emit FeeCollectorUpdated(account, oldShare, share);
    }

    function _distributeFees(address token, uint256 amount, bool inToken) internal returns (bool) {
        if (amount == 0 || totalFeeCollectorsShares == 0) return false;

        uint256 distributed = 0;
        uint256 len = _collectors.length();
        for (uint256 i = 0; i < len; i++) {
            address collector = _collectors.at(i);
            uint256 share = i == len - 1
                ? amount - distributed
                : (amount * _shares[collector]) / totalFeeCollectorsShares;

            if (inToken) {
                (bool sent, ) = token.call(abi.encodeWithSignature("transfer(address,uint256)", collector, share));
                require(sent, "Token transfer failed");
            } else {
                payable(collector).transfer(share);
            }

            emit FeeCollected(collector, share);
            distributed += share;
        }

        return true;
    }

    function addFeeCollector(address account, uint256 share) external virtual;
    function removeFeeCollector(address account) external virtual;
    function updateFeeCollectorShare(address account, uint256 share) external virtual;
    function distributeFees(uint256 amount, bool inToken) external virtual;
}