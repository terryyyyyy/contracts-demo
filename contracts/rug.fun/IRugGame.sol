// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IRugGame {
    struct GameConfig {
        uint256 duration;
        uint256 tokensConfirmedAfter;
        uint256[] tradeTaxAmounts;
    }

    struct GameState {
        uint256 startedAt;
        uint256 endsAt;
        uint256 finalizedAt;
        uint256 newTokensDisabledAt;
        uint256 confirmedTokensAt;
        uint256 tokenLiquidity;
        uint256 rugPoolAmount;
        address[] confirmedTokens;
    }

    event GameStarted(uint256 indexed gameNumber, uint256 indexed startTime, uint256 indexed endTime);
    event GameTokensConfirmed(uint256 indexed gameNumber, address[] tokenAddresses);
    event GameFinalized(uint256 indexed gameNumber, address indexed winner, address indexed loser);
    event TokenCreated(
        uint256 indexed gameNumber, address indexed tokenAddress, string name, string symbol, string imageUri
    );
    event TokenSwapped(
        uint256 indexed gameNumber,
        address indexed fromTokenAddress,
        address indexed toTokenAddress,
        address actor,
        address account,
        uint256 inAmount,
        uint256 outAmount,
        uint256 rugPoolFee
    );
    event SupplyUpdated(uint256 indexed gameNumber, address indexed tokenAddress, uint256 indexed newSupply);
    event GameLiquidityUpdated(uint256 indexed gameNumber, uint256 indexed newLiquidity);
    event RugPoolAmountUpdated(uint256 indexed gameNumber, uint256 indexed newAmount);

    event TokenRefunded(
        uint256 indexed gameNumber, address indexed tokenAddress, address indexed to, uint256 amount, uint256 ethAmount
    );

    event GameConfigUpdated(GameConfig config);
    event RugPoolDeposited(uint256 indexed gameNumber, address indexed depositor, uint256 indexed amount);

    event PositionCreated(
        uint256 indexed gameNumber, address indexed tokenAddress, address indexed poolAddress, uint256 lpTokenId
    );

    error NoGameRunning();
    error TooFewTokensToStart();
    error TooManyTokensToStart();
    error GameTokensAlreadyConfirmed();
    error TokenAlreadyInGame();
    error TokenInWrongGame();
    error GameAlreadyFinalized();
    error InvalidGame();
    error GameTokensNotConfirmed();
    error InvalidToken();
    error TokenNotEligibleForRefund();
    error InvalidAmount();
    error InvalidRecipient();
    error GameIsOver();
    error GameIsNotOver();
    error GameNotFinalized();
    error CannotBuyUnconfirmedToken();
    error DurationTooShort();
    error DurationTooLong();
    error MustSwapDifferentTokens();
    error TokenFromWrongGame();
    error CannotSwapUnconfirmedToken();
    error NotEnoughTimeToConfirmTokens();
    error TooFewTaxValues();
    error TooManyTaxValues();
    error ConfirmTokensTimeTooShort();
    error ConfirmTokensTimeTooLong();
    error NewTokensDisabled();
    error InvalidInitParameters();
    error PoolNotFound();
    error InvalidUniswapCallbackCaller();
    error TradeTaxValueTooHigh();
    error CannotConfirmYet();
    error TaxValuesMustBeIncreasing();

    function createToken(string calldata name, string calldata symbol, string calldata imageUri)
        external
        payable
        returns (address);
    function buyToken(address tokenAddress, address to) external payable;
    function swapTokens(address fromTokenAddress, address toTokenAddress, uint256 amount) external;

    /// @dev Refunds `amount` of `tokenAddress` to the caller if the token was disqualified from the game.
    function refundToken(address tokenAddress, uint256 amount) external;

    /// @dev Finalizes the game
    function finalizeGame() external;

    function tokenConfirmed(address tokenAddress) external view returns (bool);
    function gameStateForGameNumber(uint256 gameNumber) external view returns (GameState memory);
    function tokensForGameNumber(uint256 gameNumber) external view returns (address[] memory);

    function minimumGameTokenCount() external view returns (uint256);
    function maximumGameTokenCount() external view returns (uint256);

    function depositToRugPool() external payable;
    function removeTransferRestrictionForToken(address tokenAddress) external;

    // Failsafe

    function emergencyFinalizeUnconfirmedGame() external;

    // Admin functions

    function startGame() external;
    function confirmGameTokens(address[] calldata tokenAddresses) external;
    function withdrawFees(address tokenAddress, address to) external;

    function setGameConfig(GameConfig calldata config) external;
    function gameConfig() external view returns (GameConfig memory);
}