// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IToken {
    error CannotBurnUntilOwnerIsRenounced();
    error CannotInteractWithPoolDuringGame();

    function initialize(string memory name_, string memory symbol_, address poolAddress) external;

    function protocolMint(address to, uint256 amount) external;
    function protocolBurn(address from, uint256 amount) external;
    function removeTransferRestriction() external;

    /// @dev Burn tokens from the caller's balance.
    /// @dev This function can only be called after the owner has been renounced.
    function burn(uint256 amount) external;
}