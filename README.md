# CryptoPunkin (PUNKINS)

A fixed-supply ERC-20 token for Ethereum mainnet, built with Foundry.

| Property | Value |
|---|---|
| Solidity contract | `CryptoPunkin` (`src/CryptoPunkin.sol`) |
| Token name | `CryptoPunkin` |
| Symbol | `PUNKINS` |
| Decimals | 18 |
| Total supply | 1,000,000,000 PUNKINS = `1_000_000_000 * 10**18` minor units |
| Mint | Once, in the constructor, to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None |
| Dependencies | None (no OpenZeppelin, no forge-std) |

## Behaviour

- The constructor credits the whole supply to `msg.sender` and emits `Transfer(address(0), deployer, supply)`.
  Deployed through the launch factory, the factory is `msg.sender` and so holds the supply, as the
  custom-token floor requires.
- `totalSupply()` is a compile-time constant. There is no mint, no burn, no `burnFrom`, and no storage
  variable the supply could drift from, so it can neither grow nor shrink after deployment.
- `transfer`, `approve`, `transferFrom`, `allowance` and `balanceOf` follow ERC-20 exactly, with no
  fee, no tax, no pause, no blocklist and no exempt list. Every transfer moves exactly the amount
  requested, so the launch flows (factory to distributor, distributor to claimants, seeding and
  swapping through the pool manager) arrive whole.
- `transferFrom` spends only the caller's own allowance from `from`. An allowance of
  `type(uint256).max` is treated as unlimited and is not decremented.
- Zero-value transfers succeed and emit, as the standard requires. Transfers to or from
  `address(0)` revert, as does an approval naming `address(0)` as spender.
- Reverts use OpenZeppelin v5's custom error names so explorers and wallets decode them:
  `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver`,
  `ERC20InvalidSender`, `ERC20InvalidSpender`.
- The contract has no `receive` or `fallback`: ether and unknown calls are refused.
- No `delegatecall`, `callcode` or `selfdestruct`; no proxies; no upgrade path; no external calls at all.

## Assumptions

- The brief asks for a plain token: name, symbol, supply and a one-time mint to the deployer. No
  tax, burn, vesting, governance or permit was requested, so none is implemented.
- The deployer is whoever runs the constructor. For the IMD launch that is the ProjectFactory,
  which forwards the swarm's 10% to the MerkleDistributor, seeds the pool with 80% and sends the
  remaining 10% to the requester's address from the launch economics. The token does not know about
  or depend on any of those addresses.
- The ERC-20 `approve` race is inherent to the standard. Holders changing a non-zero allowance may
  set it to zero first; integrators should use allowance-aware patterns.
- Numbers left open by the brief: none. Supply, decimals, name and symbol are all given. There is
  no fee, price or rate to choose.

## Deployment parameters

- Constructor arguments: none. The launch manifest's `constructorArgs` for the token is an empty list.
- `token.totalSupply` in the manifest, in minor units: `1000000000000000000000000000` (1e27).
- `token.decimals`: 18.
- Compiler: `solc 0.8.26`, optimizer on at 200 runs, `via_ir = false`, `evm_version = "cancun"`,
  `bytecode_hash = "none"` so the built bytecode is reproducible and matches what is deployed.
- `script/DeployCryptoPunkin.s.sol` is a reviewable deployment for forks or other environments.
  Its `deploy()` function takes no configuration and is what the tests call. `run()` wraps it in a
  broadcast. Nothing in this repository deploys, signs or broadcasts anything on its own.

## After launch

Nothing to set. The token has no owner, no setter and no configuration.

## Operational responsibilities

- Whoever receives the supply (the factory at launch, then the distributor, the pool and the
  requester's `remainderTo` address) is responsible for custody of what they hold. The contract
  cannot recover tokens sent to a wrong address, including its own address or `address(0)`.
- There is no admin key to protect, rotate or hand to a multisig, and no pause to invoke in an
  incident. The trade-off is that nothing can be frozen or fixed after deployment either.
- Explorer source verification after deployment belongs to the launch's deployer. The pinned
  compiler settings above are everything needed to reproduce the bytecode.

## Layout

```
foundry.toml                     compiler pins and profile
src/CryptoPunkin.sol             the token
src/interfaces/IERC20.sol        ERC-20 interface with metadata
script/DeployCryptoPunkin.s.sol  reviewable deployment, deploy() tested directly
test/utils/TestBase.sol          dependency-free cheatcode handle and assertions
test/CryptoPunkin.t.sol          behaviour, failure modes, privilege checks, fuzz
test/DeployCryptoPunkin.t.sol    the deploy function
```

The test base declares only the cheatcodes it uses (`prank`, `expectRevert`, `expectEmit`,
`assume`, `label`, broadcast) against forge's cheatcode address, so the project builds and tests
offline with nothing vendored.

## Checks

```
forge build
forge test
forge fmt --check
```

Tests read no environment variables, use no `ffi` and no filesystem access, and pass in any order
and in parallel. Fuzz tests map every input into range with modular `bound` rather than rejecting,
so they hold for any seed.

Tests passing are not a security audit. The contract holds no funds and has no privileged paths,
but an independent review before the launch is still the policy's final step.
