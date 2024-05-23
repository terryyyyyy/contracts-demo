// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IToken} from "./IToken.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract Token is IToken, ERC20, Ownable {
    string private _name;
    string private _symbol;
    address public transferRestrictedTo;

    function initialize(string memory name_, string memory symbol_, address poolAddress_) public {
        _initializeOwner(msg.sender);
        _name = name_;
        _symbol = symbol_;
        transferRestrictedTo = poolAddress_;
    }

    function protocolMint(address to, uint256 amount) public override onlyOwner {
        _mint(to, amount);
    }

    function protocolBurn(address from, uint256 amount) public override onlyOwner {
        _burn(from, amount);
    }

    function burn(uint256 amount) public override {
        if (owner() != address(0)) {
            revert CannotBurnUntilOwnerIsRenounced();
        }

        _burn(msg.sender, amount);
    }

    function removeTransferRestriction() public onlyOwner {
        transferRestrictedTo = address(0);
    }

    function _beforeTokenTransfer(address, address to, uint256) internal view override {
        if (transferRestrictedTo != address(0) && to == transferRestrictedTo) {
            revert CannotInteractWithPoolDuringGame();
        }
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 11;
    }

    function _guardInitializeOwner() internal pure virtual override returns (bool) {
        return true;
    }
}