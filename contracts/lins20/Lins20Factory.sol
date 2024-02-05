// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Lins20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


contract Lins20Factory is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {
    struct Parameters {
        string tick;         // inscription tick
        uint256 limit;       // limit per mint
        uint256 totalSupply; // total supply
        uint256 burnsRate;   // transfer burns rate  10000 = 100%
        uint256 fee;         // mint fee
    }

    Parameters public parameters;
    mapping(string => address) public inscriptions;
    event InscribeDeploy(address indexed from, string content);
    event AddInscription(string tick, address indexed addr);


    function initialize() public initializer {
        __Pausable_init();
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
    }

    /*
     * create new inscription
     * @param tick Tick
     * @param limit Limit per mint
     * @param totalSupply Total supply
     * @param burnsRate transfer burns rate  10000 = 100%
     * @param fee Fee
     */
    function createLins20(
        string memory tick,
        uint256 limit,
        uint256 totalSupply,
        uint256 burnsRate,
        uint256 fee
    ) external whenNotPaused returns (address lins20) {
        require(burnsRate < 10000, "burns out of range");
        require(limit < totalSupply, "limit out of range");
        require(inscriptions[tick] == address(0), "tick exists");
        require(totalSupply % limit == 0, "limit incorrect");

        parameters = Parameters({tick: tick, limit: limit, totalSupply: totalSupply, burnsRate: burnsRate, fee: fee});
        lins20 = address(new Lins20{salt: keccak256(abi.encode(tick, limit, totalSupply, burnsRate, fee))}());
        inscriptions[tick] = lins20;

        uint256 decimals = 10 ** 18;
        delete parameters;
        string memory ins = string.concat('data:,{"p":"lins20","op":"deploy","tick":"', tick, '","max":"', Strings.toString(totalSupply / decimals), '","lim":"', Strings.toString(limit / decimals), '"}');
        emit InscribeDeploy(msg.sender, ins);
    }


    /**
     * @notice Pause (admin only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause (admin only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

}