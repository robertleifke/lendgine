// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Lendgine } from "../src/Lendgine.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is LendgineScript {
    function run() public broadcast returns (Lendgine lendgine) {
        foo = new Lendgine();
    }
}
