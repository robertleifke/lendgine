// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

// import { ERC20 } from "./ERC20.sol";
// import { JumpRate } from "./JumpRate.sol";

import {PrimitiveEngine} from "lib/rmm-core/contracts/PrimitiveEngine.sol";

import {ILendgine} from "./interfaces/ILendgine.sol";
import {IMintCallback} from "./interfaces/callback/IMintCallback.sol";
import {IPairMintCallback} from "./interfaces/callback/IPairMintCallback.sol";


contract Lendgine is ERC20, JumpRate, RMM, ILendgine, IMintCallback, IPairMintCallback, Payment {
  using Position for mapping(address => Position.Info);
  using Position for Position.Info;

  /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

  event Mint(address indexed sender, uint256 collateral, uint256 shares, uint256 liquidity, address indexed to);
  event Burn(address indexed sender, uint256 collateral, uint256 shares, uint256 liquidity, address indexed to);
  event Deposit(address indexed sender, uint256 size, uint256 liquidity, address indexed to);
  event Withdraw(address indexed sender, uint256 size, uint256 liquidity, address indexed to);
  event AccrueInterest(uint256 timeElapsed, uint256 collateral, uint256 liquidity);
  event AccruePositionInterest(address indexed owner, uint256 rewardPerPosition);
  event Collect(address indexed owner, address indexed to, uint256 amount);
  event AddLiquidity(
    address indexed from,
    address indexed lendgine,
    uint256 liquidity,
    uint256 size,
    uint256 amount0,
    uint256 amount1,
    address indexed to
  );
  event RemoveLiquidity(
    address indexed from,
    address indexed lendgine,
    uint256 liquidity,
    uint256 size,
    uint256 amountX,
    uint256 amountY,
    address indexed to
  );

  /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

  error InputError();
  error CompleteUtilizationError();
  error InsufficientInputError();
  error InsufficientPositionError();
  error AmountError();
  error ValidationError();
  error CollectError();

  /*//////////////////////////////////////////////////////////////
                          LENDGINE STORAGE
    //////////////////////////////////////////////////////////////*/

  mapping(address => Position.Info) public override positions;
  mapping(address => mapping(address => Position.Info)) public userPositions;

  uint256 public override totalPositionSize;
  uint256 public override totalLiquidityBorrowed;
  uint256 public override rewardPerPositionStored;
  uint256 public override lastUpdate;

  /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

  constructor(address _factory, address _weth) Payment(_weth) {
    factory = _factory;
    weth = _weth;
  }

  /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

  modifier checkDeadline(uint256 deadline) {
    if (deadline < block.timestamp) revert InputError();
    _;
  }

  /*//////////////////////////////////////////////////////////////
                                CALLBACK
    //////////////////////////////////////////////////////////////*/

  struct PairMintCallbackData {
    address tokenX;
    address tokenY;
    uint256 strike;
    uint256 sigma;
    uint256 tau;
    uint256 amountX;
    uint256 amountY;
    address payer;
  }

  function pairMintCallback(uint256, bytes calldata data) external override {
    PairMintCallbackData memory decoded = abi.decode(data, (PairMintCallbackData));

    address lendgine = LendgineAddress.computeAddress(factory, decoded.token0, decoded.token1, decoded.strike);
    if (lendgine != msg.sender) revert ValidationError();

    if (decoded.amount0 > 0) Payment.pay(decoded.token0, decoded.payer, msg.sender, decoded.amount0);
    if (decoded.amount1 > 0) Payment.pay(decoded.token1, decoded.payer, msg.sender, decoded.amount1);
  }

  /*//////////////////////////////////////////////////////////////
                           LIQUIDITY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

  struct AddLiquidityParams {
    address tokenY;
    address tokenX;
    uint256 strike;
    uint256 sigma;
    uint256 tau;
    uint256 liquidity;
    uint256 amountYMin;
    uint256 amountXMin;
    uint256 sizeMin;
    address recipient;
    uint256 deadline;
  }

  function addLiquidity(AddLiquidityParams calldata params) external payable checkDeadline(params.deadline) {
    address lendgine = LendgineAddress.computeAddress(factory, params.token0, params.token1, params.strike);

    uint256 r0 = ILendgine(lendgine).reserve0();
    uint256 r1 = ILendgine(lendgine).reserve1();
    uint256 totalLiquidity = ILendgine(lendgine).totalLiquidity();

    uint256 amount0;
    uint256 amount1;

    if (totalLiquidity == 0) {
      amount0 = params.amount0Min;
      amount1 = params.amount1Min;
    } else {
      amount0 = FullMath.mulDivRoundingUp(params.liquidity, r0, totalLiquidity);
      amount1 = FullMath.mulDivRoundingUp(params.liquidity, r1, totalLiquidity);
    }

    if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert AmountError();

    uint256 size = ILendgine(lendgine).deposit(
      address(this),
      params.liquidity,
      abi.encode(
        PairMintCallbackData({
          token0: params.token0,
          token1: params.token1,
          strike: params.strike,
          amount0: amount0,
          amount1: amount1,
          payer: msg.sender
        })
      )
    );
    if (size < params.sizeMin) revert AmountError();

    Position.Info memory position = userPositions[params.recipient][lendgine];

    (, uint256 rewardPerPositionPaid, ) = ILendgine(lendgine).positions(address(this));
    position.tokensOwed += FullMath.mulDiv(position.size, rewardPerPositionPaid - position.rewardPerPositionPaid, 1e18);
    position.rewardPerPositionPaid = rewardPerPositionPaid;
    position.size += size;

    userPositions[params.recipient][lendgine] = position;

    emit AddLiquidity(msg.sender, lendgine, params.liquidity, size, amount0, amount1, params.recipient);
  }

  struct RemoveLiquidityParams {
    address token0;
    address token1;
    uint256 strike;
    uint256 size;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
  }

  function removeLiquidity(RemoveLiquidityParams calldata params) external checkDeadline(params.deadline) {
    address lendgine = LendgineAddress.computeAddress(factory, params.token0, params.token1, params.strike);

    address recipient = params.recipient == address(0) ? address(this) : params.recipient;

    (uint256 amount0, uint256 amount1, uint256 liquidity) = ILendgine(lendgine).withdraw(recipient, params.size);
    if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert AmountError();

    Position.Info memory position = userPositions[msg.sender][lendgine];

    (, uint256 rewardPerPositionPaid, ) = ILendgine(lendgine).positions(address(this));
    position.tokensOwed += FullMath.mulDiv(position.size, rewardPerPositionPaid - position.rewardPerPositionPaid, 1e18);
    position.rewardPerPositionPaid = rewardPerPositionPaid;
    position.size -= params.size;

    userPositions[msg.sender][lendgine] = position;

    emit RemoveLiquidity(msg.sender, lendgine, liquidity, params.size, amount0, amount1, recipient);
  }

  struct CollectParams {
    address lendgine;
    address recipient;
    uint256 amountRequested;
  }

  function collect(CollectParams calldata params) external returns (uint256 amount) {
    ILendgine(params.lendgine).accruePositionInterest();

    address recipient = params.recipient == address(0) ? address(this) : params.recipient;

    Position.Info memory position = userPositions[msg.sender][params.lendgine];

    (, uint256 rewardPerPositionPaid, ) = ILendgine(params.lendgine).positions(address(this));
    position.tokensOwed += FullMath.mulDiv(position.size, rewardPerPositionPaid - position.rewardPerPositionPaid, 1e18);
    position.rewardPerPositionPaid = rewardPerPositionPaid;

    amount = params.amountRequested > position.tokensOwed ? position.tokensOwed : params.amountRequested;
    position.tokensOwed -= amount;

    userPositions[msg.sender][params.lendgine] = position;

    uint256 collectAmount = ILendgine(params.lendgine).collect(recipient, amount);
    if (collectAmount != amount) revert CollectError();

    emit Collect(msg.sender, recipient, amount);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  function convertLiquidityToShare(uint256 liquidity) public view override returns (uint256) {
    uint256 _totalLiquidityBorrowed = totalLiquidityBorrowed; // SLOAD
    if (_totalLiquidityBorrowed == 0) {
      return liquidity;
    } else {
      UD60x18 udLiquidity = ud(liquidity);
      UD60x18 udTotalSupply = ud(totalSupply);
      UD60x18 udTotalLiquidityBorrowed = ud(_totalLiquidityBorrowed);

      UD60x18 result = mul(udLiquidity, div(udTotalSupply, udTotalLiquidityBorrowed));

      return result.unwrap();
    }
  }

  function convertShareToLiquidity(uint256 shares) public view override returns (uint256) {
    UD60x18 udShares = ud(shares);
    UD60x18 udTotalSupply = ud(totalSupply);
    UD60x18 udTotalLiquidityBorrowed = ud(totalLiquidityBorrowed);

    UD60x18 result = mul(udTotalLiquidityBorrowed, div(udShares, udTotalSupply));

    return result.unwrap();
  }

  function convertCollateralToLiquidity(uint256 collateral) public view override returns (uint256) {
    UD60x18 udCollateral = ud(collateral);
    UD60x18 udStrike = ud(strike);
    UD60x18 two = ud(2e18);

    UD60x18 result = div(udCollateral, mul(two, udStrike));

    return result.unwrap();
  }

  function convertLiquidityToCollateral(uint256 liquidity) public view override returns (uint256) {
    UD60x18 udLiquidity = ud(liquidity);
    UD60x18 udStrike = ud(strike);
    UD60x18 two = ud(2e18);

    UD60x18 result = mul(udLiquidity, mul(two, udStrike));

    return result.unwrap();
  }

  /*//////////////////////////////////////////////////////////////
                         INTERNAL INTEREST LOGIC
    //////////////////////////////////////////////////////////////*/

  function _accrueInterest() private {
    if (totalSupply == 0 || totalLiquidityBorrowed == 0) {
      lastUpdate = block.timestamp;
      return;
    }

    uint256 timeElapsed = block.timestamp - lastUpdate;
    if (timeElapsed == 0) return;

    uint256 _totalLiquidityBorrowed = totalLiquidityBorrowed; // SLOAD
    uint256 totalLiquiditySupplied = totalLiquidity + _totalLiquidityBorrowed; // SLOAD

    uint256 borrowRate = getBorrowRate(_totalLiquidityBorrowed, totalLiquiditySupplied);

    uint256 dilutionLPRequested = (FullMath.mulDiv(borrowRate * timeElapsed, _totalLiquidityBorrowed, 1e18)) / 365 days;
    uint256 dilutionLP = dilutionLPRequested > _totalLiquidityBorrowed ? _totalLiquidityBorrowed : dilutionLPRequested;
    uint256 dilutionSpeculative = convertLiquidityToCollateral(dilutionLP);

    totalLiquidityBorrowed = _totalLiquidityBorrowed - dilutionLP;
    rewardPerPositionStored += FullMath.mulDiv(dilutionSpeculative, 1e18, totalPositionSize);
    lastUpdate = block.timestamp;

    emit AccrueInterest(timeElapsed, dilutionSpeculative, dilutionLP);
  }

  function _accruePositionInterest(address owner) private {
    uint256 _rewardPerPositionStored = rewardPerPositionStored; // SLOAD

    positions.update(owner, 0, _rewardPerPositionStored);

    emit AccruePositionInterest(owner, _rewardPerPositionStored);
  }

  // constructor() payable override(ERC20, ImmutableState, Payment) {}

  // function kink() external view override returns (uint256 kink) {}

  // function multiplier() external view override returns (uint256 multiplier) {}

  // function jumpMultiplier() external view override returns (uint256 jumpMultiplier) {}

  // function factory() external view override returns (address) {}

  // function token0() external view override returns (address) {}

  // function token1() external view override returns (address) {}

  // function strike() external view override returns (uint256) {}

  // function reserve0() external view override returns (uint120) {}

  // function reserve1() external view override returns (uint120) {}

  // function totalLiquidity() external view override returns (uint256) {}

  // function positions(address) external view override returns (uint256, uint256, uint256) {}

  // function totalPositionSize() external view override returns (uint256) {}

  // function totalLiquidityBorrowed() external view override returns (uint256) {}

  // function rewardPerPositionStored() external view override returns (uint256) {}

  // function lastUpdate() external view override returns (uint256) {}

  function mint(address to, uint256 collateral, bytes calldata data) external override returns (uint256 shares) {}

  function burn(address to, bytes calldata data) external override returns (uint256 collateral) {}

  function deposit(address to, uint256 liquidity, bytes calldata data) external override returns (uint256 size) {}

  function withdraw(
    address to,
    uint256 size
  ) external override returns (uint256 amount0, uint256 amount1, uint256 liquidity) {}

  function accrueInterest() external override {}

  function accruePositionInterest() external override {}

  function collect(address to, uint256 collateralRequested) external override returns (uint256 collateral) {}

  function mintCallback(
    uint256 collateral,
    uint256 amount0,
    uint256 amount1,
    uint256 liquidity,
    bytes calldata data
  ) external override {}
}
