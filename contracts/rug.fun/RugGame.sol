// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Token} from "./Token.sol";
import {IRugGame} from "./IRugGame.sol";
import {IWETH} from "./IWETH.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

contract RugGame is IRugGame, OwnableRoles {
    uint256 public constant GAME_START_ROLE = _ROLE_0;
    uint256 public constant CONFIRM_GAME_TOKENS_ROLE = _ROLE_1;

    GameConfig private _gameConfig;

    uint256 public constant minimumGameTokenCount = 3;
    uint256 public constant maximumGameTokenCount = 20;

    uint256 public constant minimumGameDuration = 10 minutes;
    uint256 public constant maximumGameDuration = 14 days;
    uint256 public constant minimumConfirmTokensTime = 3 minutes;
    uint256 public constant minimumTimeLeftToConfirmTokens = 5 minutes;

    uint256 public constant minimumTradeTaxAmountsLength = 2;
    uint256 public constant maximumTradeTaxAmountsLength = 72;
    uint256 public constant maximumTradeTaxAmount = 90_00; // 90%

    uint256 public gameNumber;
    mapping(address => bool) private _tokenConfirmed;
    mapping(uint256 => GameState) private _gameStateForGameNumber;
    mapping(uint256 => address[]) private _tokensForGameNumber;
    mapping(address => uint256) public gameNumberForToken;

    address public immutable tokenImplementation;
    address public uniswapV3Factory;
    address public uniswapPositionManager;
    IWETH public weth;

    uint24 private constant _uniswapPoolFee = 10000;
    int24 private _tickLower;
    int24 private _tickUpper;
    address private _activeSwapAddress;

    struct PositionInfo {
        uint256 lpTokenId;
        address poolAddress;
    }

    mapping(address => PositionInfo) private _positionInfoForToken;

    constructor() {
        _initializeOwner(tx.origin);

        uint256[] memory tradeTaxAmounts = new uint256[](2);
        tradeTaxAmounts[1] = 50_00;

        _setGameConfig(
            GameConfig({duration: 24 hours, tokensConfirmedAfter: 12 hours, tradeTaxAmounts: tradeTaxAmounts})
        );

        tokenImplementation = address(new Token());
        Token(tokenImplementation).initialize("", "", address(0));
        Token(tokenImplementation).renounceOwnership();
    }

    function initialize(address _uniswapV3Factory, address _uniswapPositionManager, address _weth) external onlyOwner {
        if (address(uniswapV3Factory) != address(0)) {
            revert AlreadyInitialized();
        }
        if (_uniswapV3Factory == address(0) || _uniswapPositionManager == address(0) || _weth == address(0)) {
            revert InvalidInitParameters();
        }
        uniswapV3Factory = _uniswapV3Factory;
        uniswapPositionManager = _uniswapPositionManager;
        weth = IWETH(_weth);

        weth.approve(uniswapV3Factory, type(uint256).max);

        int24 tickSpacing = IUniswapV3Factory(uniswapV3Factory).feeAmountTickSpacing(_uniswapPoolFee);
        _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
        _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK
    }

    function createToken(string calldata name, string calldata symbol, string calldata imageUri)
        external
        payable
        override
        returns (address)
    {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        if (gameState.startedAt == 0) {
            revert NoGameRunning();
        }

        if (gameState.finalizedAt != 0) {
            revert GameAlreadyFinalized();
        }

        if (gameState.endsAt < block.timestamp) {
            revert GameIsOver();
        }

        if (gameState.newTokensDisabledAt < block.timestamp) {
            revert NewTokensDisabled();
        }

        if (gameState.confirmedTokensAt != 0) {
            revert GameTokensAlreadyConfirmed();
        }

        bytes32 cloneHash;
        unchecked {
            cloneHash = keccak256(abi.encodePacked(name, symbol, blockhash(block.number - 1), msg.sender));
        }

        address token = LibClone.cloneDeterministic(tokenImplementation, cloneHash);

        // Initialize Uniswap v3 pool with unitless 1:1 ratio
        (address address0, address address1) = token < address(weth) ? (token, address(weth)) : (address(weth), token);
        address pool = IUniswapV3Factory(uniswapV3Factory).createPool(address0, address1, _uniswapPoolFee);
        IUniswapV3Pool(pool).initialize(2 ** 96);

        Token(token).initialize(name, symbol, pool);
        gameNumberForToken[token] = gameNumber;
        _tokensForGameNumber[gameNumber].push(token);
        emit TokenCreated(gameNumber, token, name, symbol, imageUri);

        // Tax doesn't start until after tokens are confirmed, so we can skip calculating it here
        uint256 taxAmount = 0;
        uint256 amountWithoutTax = msg.value;

        // Tokens aren't confirmed yet, don't increment `gameState.tokenLiquidity`

        Token(token).protocolMint(msg.sender, amountWithoutTax);
        emit SupplyUpdated(gameNumber, token, Token(token).totalSupply());
        emit TokenSwapped(gameNumber, address(0), token, msg.sender, msg.sender, msg.value, amountWithoutTax, taxAmount);

        return token;
    }

    function buyToken(address token, address to) external payable override {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        if (to == address(0)) {
            revert InvalidRecipient();
        }

        uint256 gameNumberForThisToken = gameNumberForToken[token];
        if (gameNumberForThisToken == 0) {
            revert InvalidToken();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumberForThisToken];
        if (gameState.startedAt == 0) {
            revert NoGameRunning();
        }

        if (gameState.finalizedAt != 0) {
            revert GameAlreadyFinalized();
        }

        if (gameState.endsAt < block.timestamp) {
            revert GameIsOver();
        }

        bool tokensConfirmed = gameState.confirmedTokensAt != 0;
        if (tokensConfirmed) {
            if (!_tokenConfirmed[token]) {
                revert CannotBuyUnconfirmedToken();
            }
        }

        uint256 tradeTax = calculateTaxRate(
            gameState.confirmedTokensAt, gameState.endsAt, block.timestamp, _gameConfig.tradeTaxAmounts
        );
        uint256 taxAmount = (msg.value * tradeTax) / 10_000;
        uint256 amountWithoutTax = msg.value - taxAmount;
        if (taxAmount > 0) {
            gameState.rugPoolAmount += taxAmount;
            emit RugPoolAmountUpdated(gameNumberForThisToken, gameState.rugPoolAmount);
        }
        // If tokens are confirmed, update `gameState.tokenLiquidity`
        if (tokensConfirmed) {
            gameState.tokenLiquidity += amountWithoutTax;
            emit GameLiquidityUpdated(gameNumberForThisToken, gameState.tokenLiquidity);
        }

        Token(token).protocolMint(to, amountWithoutTax);
        emit SupplyUpdated(gameNumberForThisToken, token, Token(token).totalSupply());
        emit TokenSwapped(gameNumber, address(0), token, msg.sender, to, msg.value, amountWithoutTax, taxAmount);
    }

    function swapTokens(address fromTokenAddress, address toTokenAddress, uint256 amount) external override {
        if (amount == 0) {
            revert InvalidAmount();
        }

        if (gameNumber == 0) {
            revert InvalidGame();
        }

        if (fromTokenAddress == toTokenAddress) {
            revert MustSwapDifferentTokens();
        }

        if (gameNumberForToken[fromTokenAddress] != gameNumber || gameNumberForToken[toTokenAddress] != gameNumber) {
            revert TokenFromWrongGame();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        if (gameState.endsAt < block.timestamp) {
            revert GameIsOver();
        }

        bool tokensConfirmed = gameState.confirmedTokensAt != 0;
        if (tokensConfirmed) {
            if (!_tokenConfirmed[fromTokenAddress] || !_tokenConfirmed[toTokenAddress]) {
                revert CannotSwapUnconfirmedToken();
            }
        }

        Token(fromTokenAddress).protocolBurn(msg.sender, amount);

        uint256 tradeTax = calculateTaxRate(
            gameState.confirmedTokensAt, gameState.endsAt, block.timestamp, _gameConfig.tradeTaxAmounts
        );
        uint256 taxAmount = (amount * tradeTax) / 10_000;
        uint256 amountWithoutTax = amount - taxAmount;
        if (taxAmount > 0) {
            gameState.rugPoolAmount += taxAmount;
            emit RugPoolAmountUpdated(gameNumber, gameState.rugPoolAmount);
            if (tokensConfirmed) {
                gameState.tokenLiquidity -= taxAmount;
                emit GameLiquidityUpdated(gameNumber, gameState.tokenLiquidity);
            }
        }

        Token(toTokenAddress).protocolMint(msg.sender, amountWithoutTax);
        emit SupplyUpdated(gameNumber, fromTokenAddress, Token(fromTokenAddress).totalSupply());
        emit SupplyUpdated(gameNumber, toTokenAddress, Token(toTokenAddress).totalSupply());
        emit TokenSwapped(
            gameNumber, fromTokenAddress, toTokenAddress, msg.sender, msg.sender, amount, amountWithoutTax, taxAmount
        );
    }

    function refundToken(address tokenAddress, uint256 amount) external override {
        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 gameNumberForThisToken = gameNumberForToken[tokenAddress];
        if (gameNumberForThisToken == 0) {
            revert InvalidToken();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumberForThisToken];
        if (gameState.confirmedTokensAt == 0) {
            revert GameTokensNotConfirmed();
        }

        if (_tokenConfirmed[tokenAddress]) {
            revert TokenNotEligibleForRefund();
        }

        Token(tokenAddress).protocolBurn(msg.sender, amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function _validateFinalizeGame(GameState storage gameState) private view {
        if (gameState.startedAt == 0) {
            revert InvalidGame();
        }

        if (gameState.finalizedAt != 0) {
            revert GameAlreadyFinalized();
        }

        if (block.timestamp <= gameState.endsAt) {
            revert GameIsNotOver();
        }
    }

    function finalizeGame() external override {
        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        _validateFinalizeGame(gameState);

        (
            address highestLiquidityToken,
            uint256 tokenAmountForHighestLiquidity,
            uint256 highestLiquidityPrize,
            address lowestLiquidityToken,
            uint256 tokenAmountForLowestLiquidity,
            uint256 lowestLiquidityPrize,
            uint256 sharedPrizePoolForWethDeposit
        ) = _calculateWinners(gameState);

        // 50% goes to the liquidity pool
        {
            Token(highestLiquidityToken).protocolMint(address(this), tokenAmountForHighestLiquidity);
            Token(highestLiquidityToken).approve(address(uniswapPositionManager), tokenAmountForHighestLiquidity);
            Token(lowestLiquidityToken).protocolMint(address(this), tokenAmountForLowestLiquidity);
            Token(lowestLiquidityToken).approve(address(uniswapPositionManager), tokenAmountForLowestLiquidity);
            if (sharedPrizePoolForWethDeposit > 0) {
                weth.deposit{value: sharedPrizePoolForWethDeposit}();
            }
        }

        {
            _createLP(highestLiquidityToken, highestLiquidityPrize, tokenAmountForHighestLiquidity);
            _createLP(lowestLiquidityToken, lowestLiquidityPrize, tokenAmountForLowestLiquidity);

            Token(highestLiquidityToken).renounceOwnership();
            Token(lowestLiquidityToken).renounceOwnership();
        }

        gameState.finalizedAt = block.timestamp;
        emit GameFinalized(gameNumber, highestLiquidityToken, lowestLiquidityToken);
    }

    function _calculateWinners(GameState storage gameState)
        private
        view
        returns (
            address highestLiquidityToken,
            uint256 tokenAmountForHighestLiquidity,
            uint256 highestLiquidityPrize,
            address lowestLiquidityToken,
            uint256 tokenAmountForLowestLiquidity,
            uint256 lowestLiquidityPrize,
            uint256 sharedPrizePoolForWethDeposit
        )
    {
        address[] storage confirmedTokens = gameState.confirmedTokens;
        highestLiquidityToken = confirmedTokens[0];
        tokenAmountForHighestLiquidity = Token(highestLiquidityToken).totalSupply();
        lowestLiquidityToken = confirmedTokens[0];
        tokenAmountForLowestLiquidity = tokenAmountForHighestLiquidity;
        uint256 length = confirmedTokens.length;
        for (uint256 i = 1; i < length;) {
            address token = confirmedTokens[i];
            uint256 tokenSupply = Token(token).totalSupply();
            // highest at the start of the game has priority
            if (tokenSupply > tokenAmountForHighestLiquidity) {
                tokenAmountForHighestLiquidity = tokenSupply;
                highestLiquidityToken = token;
            }
            // lowest at the start of the game has priority
            if (tokenSupply <= tokenAmountForLowestLiquidity) {
                tokenAmountForLowestLiquidity = tokenSupply;
                lowestLiquidityToken = token;
            }

            unchecked {
                ++i;
            }
        }

        sharedPrizePoolForWethDeposit = gameState.tokenLiquidity + gameState.rugPoolAmount
            - tokenAmountForHighestLiquidity - tokenAmountForLowestLiquidity;

        highestLiquidityPrize = sharedPrizePoolForWethDeposit / 2;
        lowestLiquidityPrize = sharedPrizePoolForWethDeposit - highestLiquidityPrize;

        if (tokenAmountForLowestLiquidity == 0) {
            // Special case - lowest liquidity token has 0 liquidity
            // In this case, we will take the prize pool amount and use 10% for the LP
            // and the rest for the market buy
            tokenAmountForLowestLiquidity = sharedPrizePoolForWethDeposit / 10;
            lowestLiquidityPrize -= tokenAmountForLowestLiquidity;
            sharedPrizePoolForWethDeposit -= tokenAmountForLowestLiquidity;
        }

        return (
            highestLiquidityToken,
            tokenAmountForHighestLiquidity,
            highestLiquidityPrize,
            lowestLiquidityToken,
            tokenAmountForLowestLiquidity,
            lowestLiquidityPrize,
            sharedPrizePoolForWethDeposit
        );
    }

    function _createLP(address token, uint256 extraEth, uint256 tokenAmount) internal {
        if (tokenAmount == 0) {
            return;
        }

        (address address0, address address1) = token < address(weth) ? (token, address(weth)) : (address(weth), token);

        Token(token).removeTransferRestriction();

        address poolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(address0, address1, _uniswapPoolFee);
        if (poolAddress == address(0)) {
            revert PoolNotFound();
        }

        (uint256 lpTokenId,,,) = INonfungiblePositionManager(uniswapPositionManager).mint{value: tokenAmount}(
            INonfungiblePositionManager.MintParams({
                token0: address0,
                token1: address1,
                fee: _uniswapPoolFee,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: tokenAmount,
                amount1Desired: tokenAmount,
                amount0Min: tokenAmount,
                amount1Min: tokenAmount,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        _positionInfoForToken[token] = PositionInfo({lpTokenId: lpTokenId, poolAddress: poolAddress});
        emit PositionCreated(gameNumber, token, poolAddress, lpTokenId);

        if (extraEth == 0) {
            return;
        }

        bool zeroForOne = address(weth) < token;
        _activeSwapAddress = poolAddress;
        (int256 amount0Swap, int256 amount1Swap) = IUniswapV3Pool(poolAddress).swap(
            address(this),
            zeroForOne,
            int256(extraEth),
            zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341, // TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1
            ""
        );
        delete _activeSwapAddress;

        uint256 amountToBurn = zeroForOne ? uint256(-amount1Swap) : uint256(-amount0Swap);
        Token(token).protocolBurn(address(this), amountToBurn);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory) external {
        if (msg.sender != _activeSwapAddress) {
            revert InvalidUniswapCallbackCaller();
        }

        weth.transfer(msg.sender, amount0Delta > amount1Delta ? uint256(amount0Delta) : uint256(amount1Delta));
    }

    function emergencyFinalizeUnconfirmedGame() external override {
        if (gameNumber == 0) {
            revert InvalidGame();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        if (gameState.endsAt > block.timestamp) {
            revert GameIsNotOver();
        }

        if (gameState.confirmedTokensAt != 0) {
            revert GameTokensAlreadyConfirmed();
        }

        if (gameState.finalizedAt != 0) {
            revert GameAlreadyFinalized();
        }

        // Mark game as confirmed with 0 tokens and finalize it
        // This makes all tokens refundable
        gameState.confirmedTokensAt = block.timestamp;
        gameState.finalizedAt = block.timestamp;
        emit GameTokensConfirmed(gameNumber, new address[](0));
        emit GameFinalized(gameNumber, address(0), address(0));
    }

    function startGame() external override onlyRoles(GAME_START_ROLE) {
        if (gameNumber != 0 && _gameStateForGameNumber[gameNumber].finalizedAt == 0) {
            revert GameNotFinalized();
        }

        gameNumber++;
        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        gameState.startedAt = block.timestamp;
        gameState.newTokensDisabledAt = block.timestamp + _gameConfig.tokensConfirmedAfter;
        uint256 endsAt = block.timestamp + _gameConfig.duration;
        gameState.endsAt = endsAt;
        emit GameStarted(gameNumber, block.timestamp, endsAt);
    }

    function confirmGameTokens(address[] calldata tokenAddresses)
        external
        override
        onlyRoles(CONFIRM_GAME_TOKENS_ROLE)
    {
        if (tokenAddresses.length < minimumGameTokenCount) {
            revert TooFewTokensToStart();
        }

        if (tokenAddresses.length > maximumGameTokenCount) {
            revert TooManyTokensToStart();
        }

        if (gameNumber == 0) {
            revert InvalidGame();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        if (gameState.confirmedTokensAt != 0) {
            revert GameTokensAlreadyConfirmed();
        }

        if (gameState.endsAt < block.timestamp) {
            revert GameIsOver();
        }

        if (gameState.endsAt - block.timestamp < minimumTimeLeftToConfirmTokens) {
            revert NotEnoughTimeToConfirmTokens();
        }

        if (block.timestamp < gameState.newTokensDisabledAt) {
            revert CannotConfirmYet();
        }

        uint256 tokenLiquidity;
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address token = tokenAddresses[i];
            if (_tokenConfirmed[token]) {
                revert TokenAlreadyInGame();
            }

            if (gameNumberForToken[token] != gameNumber) {
                revert TokenInWrongGame();
            }

            _tokenConfirmed[token] = true;
            tokenLiquidity += Token(token).totalSupply();
        }
        emit GameLiquidityUpdated(gameNumber, tokenLiquidity);

        gameState.confirmedTokensAt = block.timestamp;
        gameState.confirmedTokens = tokenAddresses;
        gameState.tokenLiquidity = tokenLiquidity;
        emit GameTokensConfirmed(gameNumber, tokenAddresses);
    }

    /// @dev Calculate the tax rate based on the current time and a set of tax values
    /// @param confirmedAt The time when the game tokens were confirmed
    /// @param endTime The end time of the tax rate calculation. Must be greater than startTime
    /// @param currentTime The current time to calculate the tax rate for. Must be between startTime and endTime
    /// @param taxValues An array of tax values to interpolate between over the time period. Must have at least 2 values
    function calculateTaxRate(uint256 confirmedAt, uint256 endTime, uint256 currentTime, uint256[] memory taxValues)
        public
        pure
        returns (uint256)
    {
        if (confirmedAt == 0) {
            return 0;
        }

        uint256 scale = 10_000; // Basis points scale for precision
        uint256 totalDuration = endTime - confirmedAt;
        uint256 elapsedTime = currentTime - confirmedAt;
        uint256 progress = (elapsedTime * scale) / totalDuration;
        uint256 intervals = taxValues.length - 1;
        uint256 intervalWidth = scale / intervals;
        uint256 currentIntervalIndex = progress / intervalWidth;

        if (currentIntervalIndex < intervals) {
            uint256 startTax = taxValues[currentIntervalIndex];
            uint256 endTax = taxValues[currentIntervalIndex + 1];
            uint256 fraction = ((progress % intervalWidth) * scale) / intervalWidth;
            return startTax + (endTax - startTax) * fraction / scale;
        }

        return taxValues[taxValues.length - 1];
    }

    function setGameConfig(GameConfig calldata newConfig) external override onlyOwner {
        _setGameConfig(newConfig);
    }

    function _setGameConfig(GameConfig memory newConfig) internal {
        if (newConfig.duration < minimumGameDuration) {
            revert DurationTooShort();
        }
        if (newConfig.duration > maximumGameDuration) {
            revert DurationTooLong();
        }

        if (newConfig.tokensConfirmedAfter < minimumConfirmTokensTime) {
            revert ConfirmTokensTimeTooShort();
        }
        if (newConfig.tokensConfirmedAfter >= newConfig.duration - minimumTimeLeftToConfirmTokens) {
            revert ConfirmTokensTimeTooLong();
        }

        if (newConfig.tradeTaxAmounts.length < minimumTradeTaxAmountsLength) {
            revert TooFewTaxValues();
        }
        if (newConfig.tradeTaxAmounts.length > maximumTradeTaxAmountsLength) {
            revert TooManyTaxValues();
        }

        for (uint256 i = 0; i < newConfig.tradeTaxAmounts.length; i++) {
            uint256 amount = newConfig.tradeTaxAmounts[i];
            if (amount > maximumTradeTaxAmount) {
                revert TradeTaxValueTooHigh();
            }

            if (i > 0) {
                if (amount <= newConfig.tradeTaxAmounts[i - 1]) {
                    revert TaxValuesMustBeIncreasing();
                }
            }
        }

        _gameConfig = newConfig;
        emit GameConfigUpdated(newConfig);
    }

    function removeTransferRestrictionForToken(address tokenAddress) external override {
        uint256 tokenGameNumber = gameNumberForToken[tokenAddress];
        if (gameNumber == 0) {
            revert InvalidToken();
        }

        GameState storage gameState = _gameStateForGameNumber[tokenGameNumber];
        if (gameState.startedAt == 0) {
            revert NoGameRunning();
        }

        if (gameState.finalizedAt == 0) {
            revert GameNotFinalized();
        }

        Token(tokenAddress).removeTransferRestriction();
    }

    function depositToRugPool() external payable override {
        if (msg.value == 0) {
            revert InvalidAmount();
        }

        GameState storage gameState = _gameStateForGameNumber[gameNumber];
        if (gameState.startedAt == 0) {
            revert NoGameRunning();
        }

        if (gameState.finalizedAt != 0) {
            revert GameAlreadyFinalized();
        }

        if (gameState.endsAt < block.timestamp) {
            revert GameIsOver();
        }

        gameState.rugPoolAmount += msg.value;
        emit RugPoolDeposited(gameNumber, msg.sender, msg.value);
        emit RugPoolAmountUpdated(gameNumber, gameState.rugPoolAmount);
    }

    function gameConfig() external view override returns (GameConfig memory) {
        return _gameConfig;
    }

    function tokenConfirmed(address tokenAddress) external view override returns (bool) {
        return _tokenConfirmed[tokenAddress];
    }

    function gameStateForGameNumber(uint256 _gameNumber) external view override returns (GameState memory) {
        return _gameStateForGameNumber[_gameNumber];
    }

    function tokensForGameNumber(uint256 _gameNumber) external view override returns (address[] memory) {
        return _tokensForGameNumber[_gameNumber];
    }

    function withdrawFees(address tokenAddress, address to) external override onlyOwner {
        PositionInfo memory positionInfo = _positionInfoForToken[tokenAddress];
        if (positionInfo.poolAddress == address(0)) {
            revert PoolNotFound();
        }

        INonfungiblePositionManager(uniswapPositionManager).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionInfo.lpTokenId,
                recipient: to,
                amount0Max: address(weth) < tokenAddress ? type(uint128).max : 0,
                amount1Max: address(weth) < tokenAddress ? 0 : type(uint128).max
            })
        );
    }
}