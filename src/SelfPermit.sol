// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/external/IERC20Permit.sol";
import "./interfaces/external/IERC20PermitAllowed.sol";
import "./interfaces/ISelfPermit.sol";

/// @author Muffin (https://github.com/muffinfi/muffin/blob/master/contracts/periphery/base/SelfPermit.sol)
/// @dev Widened solidity version from 0.8.10
abstract contract SelfPermit is ISelfPermit {
  /// @notice Permits this contract to spend a given token from `msg.sender`
  /// @dev The `owner` is always msg.sender and the `spender` is always address(this).
  /// @param token The address of the token spent
  /// @param value The amount that can be spent of token
  /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
  /// @param v Must produce valid secp256k1 signature from the holder along with `r` and `s`
  /// @param r Must produce valid secp256k1 signature from the holder along with `v` and `s`
  /// @param s Must produce valid secp256k1 signature from the holder along with `r` and `v`
  function selfPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
  }

  /// @notice Permits this contract to spend the sender's tokens for permit signatures that have the `allowed` parameter
  /// @dev The `owner` is always msg.sender and the `spender` is always address(this)
  /// @param token The address of the token spent
  /// @param nonce The current nonce of the owner
  /// @param expiry The timestamp at which the permit is no longer valid
  /// @param v Must produce valid secp256k1 signature from the holder along with `r` and `s`
  /// @param r Must produce valid secp256k1 signature from the holder along with `v` and `s`
  /// @param s Must produce valid secp256k1 signature from the holder along with `r` and `v`
  function selfPermitAllowed(
    address token,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
  {
    IERC20PermitAllowed(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
  }
}