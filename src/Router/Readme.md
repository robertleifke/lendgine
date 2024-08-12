# LendgineRouter

A router for interacting with Lendgine.

## Code

[`LendgineRouter.sol`](https://github.com/Numoen/pmmp/blob/main/src/periphery/LendgineRouter.sol)

## Events

### Mint

```solidity
event Mint(address indexed from, address indexed lendgine, uint256 collateral, uint256 shares, address indexed to);
```

Emitted when a power perpetual token (PPT) is minted using this router.

### Burn

```solidity
event Burn(address indexed from, address indexed lendgine, uint256 collateral, uint256 shares, address indexed to);
```

Emitted when a PPT is burned using this router.

## Errors

### LivelinessError

```solidity
error LivelinessError();
```

Occurs when a transaction is processed later than the deadline specified.

### ValidationError

```solidity
error ValidationError();
```

Occurs when a callback invocation is not valid because it is not called by a lendgine deployed by the PowerMaker factory.

### AmountError

```solidity
error AmountError();
```

Occurs when output amounts aren't sufficient according to the specified minimums.

## Read-only functions

### factory

```solidity
function factory() external view returns (address);
```

Returns the address of the PowerMaker factory this router is connected to.

### uniswapV2Factory

```solidity
function uniswapV2Factory() external view returns (address);
```

Returns the address of the UniswapV2 factory this router is connected to.

### uniswapV3Factory

```solidity
function uniswapV3Factory() external view returns (address);
```

Returns the address of the UniswapV3 factory this router is connected to.

### weth

```solidity
function weth() external view returns (address);
```

Returns the address of the Wrapped Ether contract.

## State-changing functions

### mint

```solidity
function mint(MintParams calldata params) external payable returns(uint256 shares);
```

Mints power perpetual tokens (PPT) with safety checks and obtains maximum leverage by swapping on an external market.

### burn

```solidity
function burn(BurnParams calldata params) external payable returns (uint256 amount);
```

Burns PPT with safety checks. Mints the required liquidity that is to be paid back and then unlocks the remaining collateral.
