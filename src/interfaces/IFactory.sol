// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

/// @notice Manages the recording and creation of Numo markets
/// @dev Modified from Uniswap (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol)
/// and Primitive (https://github.com/primitivefinance/rmm-core/blob/main/contracts/PrimitiveFactory.sol)
interface IFactory {
    /// @notice Returns the lendgine address for a given pair of tokens and upper bound
    /// @dev returns address 0 if it doesn't exist
    function getLendgine(
        address token0,
        address token1,
        uint256 strike
    )
        external
        view
        returns (address lendgine);

    /// @notice Get the parameters to be used in constructing the lendgine, set
    /// transiently during lendgine creation
    /// @dev Called by the immutable state constructor to fetch the parameters of the lendgine
    function parameters()
        external
        view
        returns (address token0, address token1, uint256 strike);

    /// @notice Deploys a lendgine contract by transiently setting the parameters storage slots
    /// and clearing it after the lendgine has been deployed
    function createLendgine(
        address token0,
        address token1,
        uint256 strike
    )
        external
        returns (address);
}
