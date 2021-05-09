# A Cosmos-Celo bridge

## Overview
This is a bridge connecting a Celo blockchain to a Cosmos-SDK based blockchain. Specifically it connects
celo light client running inside cosmos chain to celo chain and cosmos light client running inside celo chain to cosmos chain (the latter is still under construction).

## Architecture
The cosmos-celo bridge, comprises three major components, with two light clients as subcomponents:
  - [A fork of cosmos-sdk](https://github.com/ChorusOne/cosmos-sdk/tree/add-wasm-management), with an additional module to allow execution of wasm-based light clients.
  - [Celo geth](https://github.com/celo-org/celo-blockchain), an Ethereum based blockchain with Istanbul BFT consensus
  - [Quantum-tunnel](https://github.com/ChorusOne/quantum-tunnel/tree/celo), a simple relayer, written in rust.
  - Tendermint light client (TBD), written in solidity and deployed on the Celo blockchain
  - [Celo light client](https://github.com/ChorusOne/celo-light-client), written in rust as CosmWasm contract. Its wasm bytecode need to be uploaded to Gaia fork as part of bridge setup.
  
![Architecture](architecture.png)

## Integration tests
A single `Makefile` orchiestrates setup of all compontents. You should run the following commands in to execute selected integration test:
```
# Setup Celo geth node
$ make build-geth
$ make start-geth

# Setup gaia node with the ChorusOne fork of cosmos-sdk (adds wasm-manager functionality)
$ make build-gaia
$ make start-gaia

# Build and upload Celo Light Client to gaia node (via wasm-manager interface)
$ make build-lc
$ make start-lc

# Setup Quantum Tunnel relayer (pick your integration test at this step)
$ make build-qt
$ TEST_MODE=... make start-qt
```

**Why don't you use docker-compose?**

While docker is great for setting up reproducable work envirionment, it's not the fastest solution ever. In practice it's much easier to use a single Makefile for development work, without the need to care about isolated volumes or lengthly build times.

### Live
Both chains are live. To run this variant you need to execute `TEST_MODE=live_config_celo_cosmos make start-qt` in project directory.

### Simulated celo
Celo chain is simulated with a text file and headers are fed into celo light client running in cosmos chain. To run this variant you need to execute `TEST_MODE=simulated_celo_chain_config make start-qt`. If the test is successful, make will exit with zero exit code.

### Faulty simulated celo
Same as simulated celo but with faulty data to test failure scenario. To run this variant you need to execute `TEST_MODE=faulty_simulated_celo_chain_config make start-qt`. If the test is successful, make will exit with zero exit code.

## Credit and Attribution
- Celo - Celo foundation
- Cosmos-SDK - All in Bits, Tendermint Inc., Interchain.io, Interchain Foundation
- Cosmwasm - Confio, Ethan Frey and Simon Warta
- Tendermint-rs / ibc-rs - Informal Systems
- Concept of Wasm-based light client - Zaki Manian, Iqclusion

## Demo
[![asciicast](https://asciinema.org/a/413008.svg)](https://asciinema.org/a/413008)
