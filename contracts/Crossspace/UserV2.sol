pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../math.sol";

// 0xd42d47815c862914a0b2d4b35b30fe535f3a66b5
contract CrossSpaceShareUserV2 is Ownable, ReentrancyGuard {

    address public parentProtocolAddress;
    address public protocolFeeDestination;
    uint256 public protocolFeePercent = 500;
    uint256 public subjectFeePercent = 500;
    uint256 public PRICE_DIVIDER = 32000;
    bool public allowAuthorSellLastShare = false;
    uint256 public constant PERCENT_BASE = 10000;
    uint256 public constant MAX_FEE_PERCENT = 1000;

    constructor(uint256 _priceDivider, bool _allowAuthorSellLastShare) {
        protocolFeeDestination = _msgSender();
        allowAuthorSellLastShare = _allowAuthorSellLastShare;
        PRICE_DIVIDER = _priceDivider;
    }

    event TradeUser(address trader, address author, bool isBuy, uint256 shareAmountInWei, uint256 maticAmount, uint256 protocolMaticAmount, uint256 subjectMaticAmount, uint256 supplyInWei);
    event ParentProtocolAddressUpdated(address parentProtocolAddress);
    event ProtocolFeeDestinationUpdated(address protocolFeeDestination);
    event ProtocolFeePercentUpdated(uint256 protocolFeePercent);
    event SubjectFeePercentUpdated(uint256 subjectFeePercent);

    // Author => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public sharesBalanceInWei;

    // Author => SupplyInWei
    mapping(address => uint256) public sharesSupplyInWei;

    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
        emit ProtocolFeeDestinationUpdated(_feeDestination);
    }

    function setParentProtocolAddress(address _parentProtocolAddress) public onlyOwner {
        parentProtocolAddress = _parentProtocolAddress;
        emit ParentProtocolAddressUpdated(_parentProtocolAddress);
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

    function getPrice(uint256 supplyInWei, uint256 amountInWei) public view returns (uint256) {
        uint256 price = (amountInWei * (amountInWei*amountInWei + 3*amountInWei* supplyInWei + 3*supplyInWei*supplyInWei));
        uint256 normalizedPrice = price / PRICE_DIVIDER / 3e36;
        return normalizedPrice;
    }

    function getBuyPrice(address author, uint256 amountInWei) public view returns (uint256) {
        return getPrice(sharesSupplyInWei[author], amountInWei);
    }

    function getSellPrice(address author, uint256 amountInWei) public view returns (uint256) {
        return getPrice(sharesSupplyInWei[author] - amountInWei, amountInWei);
    }

    function getAmountInWeiByValue(uint256 supplyInWei, uint256 priceInWei) public view returns (uint256) {
        uint256 np =priceInWei* 3e36 * PRICE_DIVIDER;
        uint256 a = math.floorCbrt(np + supplyInWei * supplyInWei * supplyInWei) - supplyInWei;

        return a;
    }

     function getBuyPriceAfterFee(address author, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(author, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        return price + protocolFee + subjectFee;
    }

    function getSellPriceAfterFee(address author, uint256 amount) public view returns (uint256) {
        uint256 price = getSellPrice(author, amount);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        return price - protocolFee - subjectFee;
    }

    function getBuyAmountInWeiByValue(address author, uint256 priceInWei) public view returns (uint256) {
        return getAmountInWeiByValue(sharesSupplyInWei[author], priceInWei); 
    }

    function buyShares(address author, address sender, uint256 amountInWei) public payable nonReentrant {
        // Require the caller to be the parent protocol
        require(msg.sender == parentProtocolAddress, "Caller is not the parent protocol");
        require(tx.origin == sender, "sender is not the original sender");

        uint256 supplyInWei = sharesSupplyInWei[author];
        require(supplyInWei > 0 || author == sender, "Only the shares' subject owner can buy the first share");
        uint256 price = getPrice(supplyInWei, amountInWei);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        sharesBalanceInWei[author][sender] = sharesBalanceInWei[author][sender] + amountInWei;
        sharesSupplyInWei[author] = supplyInWei + amountInWei;
        emit TradeUser(sender, author, true, amountInWei, price, protocolFee, subjectFee, supplyInWei + amountInWei);
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = author.call{value: subjectFee}("");

        // Return the excess payment
        if (msg.value > price + protocolFee + subjectFee) {
            (bool success3, ) = sender.call{value: msg.value - price - protocolFee - subjectFee}("");
            require(success3, "Unable to send funds");
        }
        require(success1 && success2, "Unable to send funds");
    }

    function sellShares(address author, address sender, uint256 amountInWei) public nonReentrant {
         // Require the caller to be the parent protocol
        require(msg.sender == parentProtocolAddress, "Caller is not the parent protocol");
        require(tx.origin == sender, "sender is not the original sender");

        uint256 supplyInWei = sharesSupplyInWei[author];
        require(supplyInWei >= amountInWei, "Cannot sell exceeding shares supply");
        require(author != sender || supplyInWei > amountInWei || allowAuthorSellLastShare, "Author cannot sell the last share");
        uint256 price = getPrice(supplyInWei - amountInWei, amountInWei);
        uint256 protocolFee = price * protocolFeePercent / PERCENT_BASE;
        uint256 subjectFee = price * subjectFeePercent / PERCENT_BASE;
        require(sharesBalanceInWei[author][sender] >= amountInWei, "Insufficient shares");
        sharesBalanceInWei[author][sender] = sharesBalanceInWei[author][sender] - amountInWei;
        sharesSupplyInWei[author] = supplyInWei - amountInWei;
        emit TradeUser(sender, author, false, amountInWei, price, protocolFee, subjectFee, supplyInWei - amountInWei);
        (bool success1, ) = sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3, ) = author.call{value: subjectFee}("");
        require(success1 && success2 && success3, "Unable to send funds");
    }
}