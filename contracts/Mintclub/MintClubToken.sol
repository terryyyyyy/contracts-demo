// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./lib/ERC20Initializable.sol";

contract MintClubToken is ERC20Initializable {
    bool private _initialized; // false by default
    address private _owner; // Ownable is implemented manually to meke it compatible with `initializable`

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function init(string memory name_, string memory symbol_) external {
        require(_initialized == false, "CONTRACT_ALREADY_INITIALIZED");

        _name = name_;
        _symbol = symbol_;
        _owner = _msgSender();

        _initialized = true;

        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // NOTE:
    // Disable direct burn function call because it can affect on bonding curve
    // Users can just send the tokens to the token contract address
    // for the same burning effect without changing the totalSupply
    function burnFrom(address account, uint256 amount) public onlyOwner {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }
}