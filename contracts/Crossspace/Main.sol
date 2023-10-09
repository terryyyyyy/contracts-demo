pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../math.sol";
import "./crossspace_content_v2.sol";
import "./crossspace_user_v2.sol";
// 0x49c6201bd9560aC4A86F8606A520276b23Fca5dC
contract CrossSpaceTradingMain is Ownable, ReentrancyGuard {
    address public contentContractAddress;
    address public userContractAddress;
    bool public isPaused;

    // Author => Subject => (Holder => User Contract Balance)
    mapping(address => mapping(string => mapping(address => uint256))) public userContractBalance;

    event TradingPaused(bool isPaused);

    constructor(address _contentContractAddress, address _userContractAddress) {
        contentContractAddress = _contentContractAddress;
        userContractAddress = _userContractAddress;
        isPaused = true;
    }

    function setPaused(bool _isPaused) public onlyOwner {
        isPaused = _isPaused;
        emit TradingPaused(_isPaused);
    }

    function getTotalBuyPriceDetails(address author, string calldata subject, uint256 amount) public view returns (uint256[] memory) {
         // Assert that the contract addresses are not null
        require(contentContractAddress != address(0), "Content contract address is null");
        require(userContractAddress != address(0), "User contract address is null");

        // Convert the contract address to the proper contract type
        CrossSpaceShareContentV2 contentContract = CrossSpaceShareContentV2(contentContractAddress);
        CrossSpaceShareUserV2 shareUserContract = CrossSpaceShareUserV2(userContractAddress);

        // We will calculate the fees for both contract and add them to the total price
        uint256 contentTotalBeforeFee = contentContract.getBuyPrice(author, subject, amount);
        uint256 contentTotalAfterFee = contentContract.getBuyPriceAfterFee(author, subject, amount);

         // We call the contract to get the amount of shares from the price and the total cost
        uint256 userShareAmountInWei = shareUserContract.getBuyAmountInWeiByValue(author, contentTotalBeforeFee); // We will use the same price to buy user share
        uint256 userShareFeeBeforeFee = shareUserContract.getBuyPrice(author, userShareAmountInWei);
        uint256 userShareFeeAfterFee = shareUserContract.getBuyPriceAfterFee(author, userShareAmountInWei);

        uint256 grandTotal = contentTotalAfterFee + userShareFeeAfterFee;

        uint256[] memory result = new uint256[](6);
        result[0] = contentTotalBeforeFee;
        result[1] = contentTotalAfterFee;
        result[2] = userShareAmountInWei;
        result[3] = userShareFeeBeforeFee;
        result[4] = userShareFeeAfterFee;
        result[5] = grandTotal;
        return result;
    }

    function _getUserAmountToSell(address author, string calldata subject, address holder, uint256 totalAmount) private view returns (uint256) {
        // Assert that the contract addresses are not null
        require(contentContractAddress != address(0), "Content contract address is null");
        CrossSpaceShareContentV2 contentContract = CrossSpaceShareContentV2(contentContractAddress);

        // Let's calculate the amount of user shares to sell for later
        uint256 userTotalShare = userContractBalance[author][subject][holder];
        uint256 contentTotalBalance = contentContract.sharesBalance(author,subject,holder);
        require(contentTotalBalance >= totalAmount, "Insufficient shares");
        uint256 userShareToSell = totalAmount * userTotalShare / contentTotalBalance;

        return userShareToSell;
    }

    function getTotalSellPriceDetails(address author, string calldata subject, address holder, uint256 amount) public view returns (uint256[] memory) {
        // Assert that the contract addresses are not null
        require(contentContractAddress != address(0), "Content contract address is null");
        require(userContractAddress != address(0), "User contract address is null");

        // Convert the contract address to the proper contract type
        CrossSpaceShareContentV2 contentContract = CrossSpaceShareContentV2(contentContractAddress);
        CrossSpaceShareUserV2 shareUserContract = CrossSpaceShareUserV2(userContractAddress);

         // Let's calculate the amount of user shares to sell for later
        uint256 userShareToSell = _getUserAmountToSell(author, subject, holder, amount);

        // Let's calculate the fees for content
        uint256 contentTotalBeforeFee = contentContract.getSellPrice(author, subject, amount);
        uint256 contentTotalAfterFee = contentContract.getSellPriceAfterFee(author, subject, amount);

        // Let's calculate the fees for user
        uint256 userShareFeeBeforeFee = shareUserContract.getSellPrice(author, userShareToSell);
        uint256 userShareFeeAfterFee = shareUserContract.getSellPriceAfterFee(author, userShareToSell);

        uint256 grandTotal = contentTotalAfterFee + userShareFeeAfterFee;

        uint256[] memory result = new uint256[](6);
        result[0] = contentTotalBeforeFee;
        result[1] = contentTotalAfterFee;
        result[2] = userShareToSell;
        result[3] = userShareFeeBeforeFee;
        result[4] = userShareFeeAfterFee;
        result[5] = grandTotal;
        return result;
    }

     function buyShares(address author, string calldata subject, uint256 amount) public payable nonReentrant {
        // Require not paused
        require(!isPaused, "Contract is paused");

        // Assert that the contract addresses are not null
        require(contentContractAddress != address(0), "Content contract address is null");
        require(userContractAddress != address(0), "User contract address is null");

        // Convert the contract address to the proper contract type
        CrossSpaceShareContentV2 contentContract = CrossSpaceShareContentV2(contentContractAddress);
        CrossSpaceShareUserV2 shareUserContract = CrossSpaceShareUserV2(userContractAddress);

        // We will calculate the fees for both contract and add them to the total price
        uint256 contentTotalBeforeFee = contentContract.getBuyPrice(author, subject, amount);
        uint256 contentTotalAfterFee = contentContract.getBuyPriceAfterFee(author, subject, amount);

         // We call the contract to get the amount of shares from the price and the total cost
        uint256 userShareAmountInWei = shareUserContract.getBuyAmountInWeiByValue(author, contentTotalBeforeFee); // We will use the same price to buy user share
        uint256 userShareFeeAfterFee = shareUserContract.getBuyPriceAfterFee(author, userShareAmountInWei);

        uint256 grandTotal = contentTotalAfterFee + userShareFeeAfterFee;

        // Assert that the user sent enough funds
        require(msg.value >= grandTotal, "Not enough funds");

        // Buy the shares for the user contract
        // Save the amount of shares in the mapping
        userContractBalance[author][subject][msg.sender] = userContractBalance[author][subject][msg.sender] + userShareAmountInWei;

        // Buy the shares for the content contract
        contentContract.buyShares{value: contentTotalAfterFee}(author, subject, msg.sender, amount);
        // Transfer the funds to the user contract and call the buy shares function
        shareUserContract.buyShares{value: userShareFeeAfterFee}(author, msg.sender, userShareAmountInWei);

        // Return the excess payment
        if (msg.value > grandTotal) {
            (bool success, ) = msg.sender.call{value: msg.value - grandTotal}("");
            require(success, "Unable to send funds");
        }
     }

     function sellShares(address author, string calldata subject, uint256 amount) public nonReentrant {
        // Require not paused
        require(!isPaused, "Contract is paused");

        // Assert that the contract addresses are not null
        require(contentContractAddress != address(0), "Content contract address is null");
        require(userContractAddress != address(0), "User contract address is null");

        // Convert the contract address to the proper contract type
        CrossSpaceShareContentV2 contentContract = CrossSpaceShareContentV2(contentContractAddress);
        CrossSpaceShareUserV2 shareUserContract = CrossSpaceShareUserV2(userContractAddress);

         // Let's calculate the amount of user shares to sell for later
        uint256 userTotalShare = userContractBalance[author][subject][msg.sender];
        uint256 contentTotalBalance = contentContract.sharesBalance(author,subject,msg.sender);
        require(contentTotalBalance >= amount, "Insufficient shares");
        uint256 userShareToSell = amount * userTotalShare / contentTotalBalance;
        require(userShareToSell <= userTotalShare, "Insufficient user shares");
        userContractBalance[author][subject][msg.sender] = userContractBalance[author][subject][msg.sender] - userShareToSell;

        // Sell
        contentContract.sellShares(author, subject, msg.sender, amount);
        shareUserContract.sellShares(author, msg.sender, userShareToSell);
     }

     function getUserContractBalance(address author, string calldata subject, address holder) public view returns (uint256) {
         return userContractBalance[author][subject][holder];
     }
}