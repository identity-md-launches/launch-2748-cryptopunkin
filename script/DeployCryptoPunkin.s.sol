// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "../test/utils/TestBase.sol";
import {CryptoPunkin} from "../src/CryptoPunkin.sol";

/// @notice Reviewable deployment of CryptoPunkin. The token has no constructor arguments and no
/// configuration: whoever sends the deployment transaction receives the whole supply.
/// @dev The launch itself is performed by IMD's deployer through the factory, from the built
/// bytecode; this script exists so the deployment can be read and reproduced on a fork. It reads no
/// environment variables. `deploy()` is the function tests call directly.
contract DeployCryptoPunkin {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Deploys the token and returns it. The caller of this function is the deployer and
    /// receives the supply when called from a test; under `run()` the broadcasting account does.
    function deploy() public returns (CryptoPunkin token) {
        token = new CryptoPunkin();
    }

    /// @notice Broadcasts the deployment with the account `forge script` was given.
    function run() external returns (CryptoPunkin token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
