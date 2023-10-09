pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./crossspace_user_v2.sol";

// 0x75ac7ada4d345952f6e759778be1cfebcb8a20ae 
contract CrossSpaceShareContentV2 is Ownable, ReentrancyGuard {
    address public parentProtocolAddress;

    address public protocolFeeDestination;
    uint256 public protocolFeePercent = 500;
    uint256 public subjectFeePercent = 500;
    uint256 public PRICE_DIVIDER = 32000;
    bool public allowAuthorSellLastShare = false;

    uint256 public constant PERCENT_BASE = 10000;
    uint256 public constant MAX_FEE_PERCENT = 1000; // 10% cap

    event TradeContent(address trader, address author, string subject, bool isBuy, uint256 shareAmount, uint256 maticAmount, uint256 protocolMaticAmount, uint256 subjectMaticAmount, uint256 supply);
    event ParentProtocolAddressUpdated(address parentProtocolAddress);
    event ProtocolFeeDestinationUpdated(address protocolFeeDestination);
    event ProtocolFeePercentUpdated(uint256 protocolFeePercent);
    event SubjectFeePercentUpdated(uint256 subjectFeePercent);


    constructor(uint256 _priceDivider, bool _allowAuthorSellLastShare) {
        protocolFeeDestination = _msgSender();
        allowAuthorSellLastShare = _allowAuthorSellLastShare;
        PRICE_DIVIDER = _priceDivider;
    }

    // Author => Subject => (Holder => Balance)
    mapping(address => mapping(string => mapping(address => uint256))) public sharesBalance;

    // Author => Subject => Supply
    mapping(address => mapping(string => uint256)) public sharesSupply;

    function setParentProtocolAddress(address _parentProtocolAddress) public onlyOwner {
        parentProtocolAddress = _parentProtocolAddress;
        emit ParentProtocolAddressUpdated(_parentProtocolAddress);
    }

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
        emit ProtocolFeeDestinationUpdated(_feeDestination);
    }

    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        // Requie the fee percent to be less than or equal to 10%
        require(_feePercent <= MAX_FEE_PERCENT, "Fee percent is greater than 10%");

        protocolFeePercent = _feePercent;
        emit ProtocolFeePercentUpdated(_feePercent);
    }

    function setSubjectFeePercent(uint256 _feePercent) public onlyOwner {
        // Requie the fee percent to be less than or equal to 10%
        require(_feePercent <= MAX_FEE_PERCENT, "Fee percent is greater than 10%");

        subjectFeePercent = _feePercent;
        emit SubjectFeePercentUpdated(_feePercent);
    }

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply)* (supply+1) * (2 * supply + 1) / 6;
        uint256 sum2 =  (supply + amount) * (supply + amount + 1) * (2 * (supply + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / PRICE_DIVIDER;
    }

    function getBuyPrice(address author, string calldata subject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[author][subject], amount);
    }

    function getSellPrice(address author, string calldata subject, uint256 amount) public view returns (uint256) {
        return getPrice(sharesSupply[author][subject] - amount, amount);
    }

    function getBuyPriceAfterFee(address author, string calldata subject, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(author, subject, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        return price + protocolFee + subjectFee;
    }

    function getSellPriceAfterFee(address author, string calldata subject, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(author, subject, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        return price - protocolFee - subjectFee;
    }

    function buyShares(address author, string calldata subject, address sender, uint256 amount) public payable nonReentrant {
         // Require the caller to be the parent protocol
        require(msg.sender == parentProtocolAddress, "Caller is not the parent protocol");
        require(tx.origin == sender, "sender is not the original sender");

        uint256 supply = sharesSupply[author][subject];
        require(supply > 0 || author == sender, "Only the shares' subject owner can buy the first share");
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        
        // Buy the shares for the content
        sharesBalance[author][subject][sender] = sharesBalance[author][subject][sender] + amount;
        sharesSupply[author][subject] = supply + amount;
        emit TradeContent(sender, author, subject, true, amount, price, protocolFee, subjectFee, supply + amount);
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = author.call{value: subjectFee}("");
        // If the sender send any extra money, send it back
        if (msg.value > price + protocolFee + subjectFee) {
            (bool success3, ) = sender.call{value: msg.value - price - protocolFee - subjectFee}("");
            require(success3, "Unable to send funds");
        }
        require(success1 && success2, "Unable to send funds");
    }

    function sellShares(address author, string calldata subject, address sender, uint256 amount) public nonReentrant{
         // Require the caller to be the parent protocol and the original sender to be the sender
        require(msg.sender == parentProtocolAddress, "Caller is not the parent protocol");
        require(tx.origin == sender, "sender is not the original sender");

        uint256 supply = sharesSupply[author][subject];
        require(supply >= amount, "Cannot sell more than the shares supply");
        require(author != sender || supply > amount || allowAuthorSellLastShare, "Author cannot sell the last share");
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        require(sharesBalance[author][subject][sender] >= amount, "Insufficient shares");

        // Sell the shares for the content
        sharesBalance[author][subject][sender] = sharesBalance[author][subject][sender] - amount;
        sharesSupply[author][subject] = supply - amount;
        emit TradeContent(sender, author, subject, false, amount, price, protocolFee, subjectFee, supply - amount);
        (bool success1, ) = sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3, ) = author.call{value: subjectFee}("");
        require(success1 && success2 && success3, "Unable to send funds");
    }
}