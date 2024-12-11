// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {INonfungiblePositionManager, IUniswapV3Factory, ILockerFactory, ILocker, ExactInputSingleParams, ISwapRouter} from "./interface.sol";
import {Bytes32AddressLib} from "./Bytes32AddressLib.sol";

contract Token is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    address private _deployer;
    uint256 private _fid;
    string private _image;
    string private _castHash;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address deployer_,
        uint256 fid_,
        string memory image_,
        string memory castHash_
    ) ERC20(name_, symbol_) {
        _deployer = deployer_;
        _fid = fid_;
        _image = image_;
        _castHash = castHash_;
        _mint(msg.sender, maxSupply_);
    }

    function fid() public view returns (uint256) {
        return _fid;
    }

    function deployer() public view returns (address) {
        return _deployer;
    }

    function image() public view returns (string memory) {
        return _image;
    }

    function castHash() public view returns (string memory) {
        return _castHash;
    }
}

contract Clanker is Ownable {
    using TickMath for int24;
    using Bytes32AddressLib for bytes32;

    error Deprecated();

    address public taxCollector;
    uint64 public defaultLockingPeriod = 33275115461;
    uint8 public taxRate = 25; // 25 / 1000 -> 2.5 %
    uint8 public lpFeesCut = 50; // 5 / 100 -> 5%
    uint8 public protocolCut = 30; // 3 / 100 -> 3%
    ILockerFactory public liquidityLocker;

    address public weth;
    IUniswapV3Factory public uniswapV3Factory;
    INonfungiblePositionManager public positionManager;
    address public swapRouter;

    bool public deprecated;
    bool public bundleFeeSwitch;

    event TokenCreated(
        address tokenAddress,
        uint256 lpNftId,
        address deployer,
        uint256 fid,
        string name,
        string symbol,
        uint256 supply,
        address lockerAddress,
        string castHash
    );

    constructor(
        address taxCollector_,
        address weth_,
        address locker_,
        address uniswapV3Factory_,
        address positionManager_,
        uint64 defaultLockingPeriod_,
        address swapRouter_,
        address owner_
    ) Ownable(owner_) {
        taxCollector = taxCollector_;
        weth = weth_;
        liquidityLocker = ILockerFactory(locker_);
        uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
        positionManager = INonfungiblePositionManager(positionManager_);
        defaultLockingPeriod = defaultLockingPeriod_;
        swapRouter = swapRouter_;
    }

    function deployToken(
        string calldata _name,
        string calldata _symbol,
        uint256 _supply,
        int24 _initialTick,
        uint24 _fee,
        bytes32 _salt,
        address _deployer,
        uint256 _fid,
        string memory _image,
        string memory _castHash
    ) external payable onlyOwner returns (Token token, uint256 tokenId) {
        if (deprecated) revert Deprecated();

        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_fee);

        require(
            tickSpacing != 0 && _initialTick % tickSpacing == 0,
            "Invalid tick"
        );

        token = new Token{salt: keccak256(abi.encode(_deployer, _salt))}(
            _name,
            _symbol,
            _supply,
            _deployer,
            _fid,
            _image,
            _castHash
        );

        // Makes sure that the token address is less than the WETH address. This is so that the token
        // is first in the pool. Just makes things consistent.
        require(address(token) < weth, "Invalid salt");

        uint160 sqrtPriceX96 = _initialTick.getSqrtRatioAtTick();
        address pool = uniswapV3Factory.createPool(address(token), weth, _fee);
        IUniswapV3Factory(pool).initialize(sqrtPriceX96);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams(
                address(token),
                weth,
                _fee,
                _initialTick,
                maxUsableTick(tickSpacing),
                _supply,
                0,
                0,
                0,
                address(this),
                block.timestamp
            );

        token.approve(address(positionManager), _supply);
        (tokenId, , , ) = positionManager.mint(params);

        address lockerAddress = liquidityLocker.deploy(
            address(positionManager),
            _deployer,
            defaultLockingPeriod,
            tokenId,
            lpFeesCut
        );

        positionManager.safeTransferFrom(address(this), lockerAddress, tokenId);

        ILocker(lockerAddress).initializer(tokenId);

        if (msg.value > 0) {
            uint256 remainingFundsToBuyTokens = msg.value;
            if (bundleFeeSwitch) {
                uint256 protocolFees = (msg.value * taxRate) / 1000;
                remainingFundsToBuyTokens = msg.value - protocolFees;

                (bool success, ) = payable(taxCollector).call{
                    value: protocolFees
                }("");

                if (!success) {
                    revert("Failed to send protocol fees");
                }
            }

            ExactInputSingleParams memory swapParams = ExactInputSingleParams({
                tokenIn: weth, // The token we are exchanging from (ETH wrapped as WETH)
                tokenOut: address(token), // The token we are exchanging to
                fee: _fee, // The pool fee
                recipient: _deployer, // The recipient address
                amountIn: remainingFundsToBuyTokens, // The amount of ETH (WETH) to be swapped
                amountOutMinimum: 0, // Minimum amount to receive
                sqrtPriceLimitX96: 0 // No price limit
            });

            // The call to `exactInputSingle` executes the swap.
            ISwapRouter(swapRouter).exactInputSingle{
                value: remainingFundsToBuyTokens
            }(swapParams);
        }

        emit TokenCreated(
            address(token),
            tokenId,
            _deployer,
            _fid,
            _name,
            _symbol,
            _supply,
            lockerAddress,
            _castHash
        );
    }

    function initialSwapTokens(address token, uint24 _fee) public payable {
        ExactInputSingleParams memory swapParams = ExactInputSingleParams({
            tokenIn: weth, // The token we are exchanging from (ETH wrapped as WETH)
            tokenOut: address(token), // The token we are exchanging to
            fee: _fee, // The pool fee
            recipient: msg.sender, // The recipient address
            amountIn: msg.value, // The amount of ETH (WETH) to be swapped
            amountOutMinimum: 0, // Minimum amount of DAI to receive
            sqrtPriceLimitX96: 0 // No price limit
        });

        // The call to `exactInputSingle` executes the swap.
        ISwapRouter(swapRouter).exactInputSingle{value: msg.value}(swapParams);
    }

    function predictToken(
        address deployer,
        uint256 fid,
        string calldata name,
        string calldata symbol,
        string calldata image,
        string calldata castHash,
        uint256 supply,
        bytes32 salt
    ) public view returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(deployer, salt));
        return
            keccak256(
                abi.encodePacked(
                    bytes1(0xFF),
                    address(this),
                    create2Salt,
                    keccak256(
                        abi.encodePacked(
                            type(Token).creationCode,
                            abi.encode(
                                name,
                                symbol,
                                supply,
                                deployer,
                                fid,
                                image,
                                castHash
                            )
                        )
                    )
                )
            ).fromLast20Bytes();
    }

    function generateSalt(
        address deployer,
        uint256 fid,
        string calldata name,
        string calldata symbol,
        string calldata image,
        string calldata castHash,
        uint256 supply
    ) external view returns (bytes32 salt, address token) {
        for (uint256 i; ; i++) {
            salt = bytes32(i);
            token = predictToken(
                deployer,
                fid,
                name,
                symbol,
                image,
                castHash,
                supply,
                salt
            );
            if (token < weth && token.code.length == 0) {
                break;
            }
        }
    }

    function toggleBundleFeeSwitch(bool _enabled) external onlyOwner {
        bundleFeeSwitch = _enabled;
    }

    function setDeprecated(bool _deprecated) external onlyOwner {
        deprecated = _deprecated;
    }

    function updateTaxCollector(address newCollector) external onlyOwner {
        taxCollector = newCollector;
    }

    function updateLiquidityLocker(address newLocker) external onlyOwner {
        liquidityLocker = ILockerFactory(newLocker);
    }

    function updateDefaultLockingPeriod(uint64 newPeriod) external onlyOwner {
        defaultLockingPeriod = newPeriod;
    }

    function updateProtocolFees(uint8 newFee) external onlyOwner {
        lpFeesCut = newFee;
    }

    function updateTaxRate(uint8 newRate) external onlyOwner {
        taxRate = newRate;
    }
}

/// @notice Given a tickSpacing, compute the maximum usable tick
function maxUsableTick(int24 tickSpacing) pure returns (int24) {
    unchecked {
        return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    }
}