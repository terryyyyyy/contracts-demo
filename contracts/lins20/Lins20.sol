// SPDX-License-Identifier: MIT

// https://www.lins20.com/mintList

pragma solidity ^0.8.20;

import "./Lins20Factory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IEthscription.sol";

/**
 * @title Lins20
 * @dev Lins20 is a ERC20 token with inscription.
 */
contract Lins20 is ERC20, Pausable, Ownable, IEthscription {
    uint256 public limit;     // limit per mint
    uint256 public burnsRate; // transfer burns rate 10000 = 100%
    uint256 public fee;       // fee
    uint256 public maxMint;   // max mint， total supply
    string public tick;       // inscription tick
    uint256 public maxMintTimes; // max mint times size for each account
    mapping(address => uint16) public mintTimes; // mint times of each address

    uint256 public current = 0; // current mint
    string public _mintInscription = ""; // mint inscription

    event InscribeMint(address indexed from, string content);
    event InscribeTransfer(address indexed from, string content);

    modifier notContract() {
        require(tx.origin == msg.sender);
        _;
    }

    constructor() ERC20("", "") Ownable(tx.origin) {
        string memory _tick;
        (_tick, limit, maxMint, burnsRate, fee) = Lins20Factory(msg.sender).parameters();
        require(limit != 0, "limit incorrect");
        require(maxMint != 0, "maxMint incorrect");
        require(burnsRate < 10000, "burns out of range");
        require(maxMint % limit == 0, "limit incorrect");

        maxMintTimes = 50;
        tick = _tick;
        _mintInscription = string.concat('data:,{"p":"lins20","op":"mint","tick":"', tick, '","amt":"', Strings.toString(limit/(10 ** decimals())), '"}');
    }

    function symbol() public view override returns (string memory) {
        return tick;
    }

    function name() public view override returns (string memory) {
        return string.concat("inscription ", tick);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    receive() external payable {
        _doMint();
    }

    function mint() external payable {
        _doMint();
    }

    function mintV2(string memory content)  external payable {
        require(Strings.equal(content, _mintInscription), "inscription incorrect");
        _doMint();
    }

    function _doMint() internal whenNotPaused notContract {
        require(msg.value >= fee, "fee not enough");
        require(limit + current <= maxMint, "mint over");
        require(mintTimes[msg.sender] < maxMintTimes, "max mint times reached");

        _mint(msg.sender, limit);
        current += limit;
        mintTimes[msg.sender] += 1;
        emit InscribeMint(msg.sender, _mintInscription);
        emit ethscriptions_protocol_CreateEthscription(msg.sender, _mintInscription);
    }

    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        uint256 destory = 0;
        if(burnsRate != 0) {
            destory = Math.mulDiv(amount, burnsRate, 10000);
        }
        require(balanceOf(msg.sender) >= amount, "insufficient balance");

        if(destory != 0) {
            _burn(msg.sender, destory);
        }
        _transfer(msg.sender, to, amount - destory);

        uint256 denominator = 10 ** decimals();
        uint256 fraction = amount % denominator;
        uint256 integer  = amount / denominator;
        string memory value = Strings.toString(integer);
        if(fraction != 0) {
           fraction = fraction / (10 ** (decimals() - 4));
           value = string.concat(value, ".", Strings.toString(fraction));
        }
        string memory ins = string.concat('data:,{"p":"lins20","op":"transfer","tick":"', tick, '","amt":"', value, '","to":"', Strings.toHexString(to), '"}');
        emit InscribeTransfer(msg.sender, ins);
        emit ethscriptions_protocol_TransferEthscriptionForPreviousOwner(msg.sender, to, bytes32(abi.encodePacked(tick)));
        return true;
    }

    function setMaxMintTimes(uint256 times) public onlyOwner {
        maxMintTimes = times;
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
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
}