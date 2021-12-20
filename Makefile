.PHONY : clean-simd build-simd start-simd clean-config-simd config-simd clean-clc build-clc start-clc clean-tlc build-tlc start-tlc clean-geth build-geth start-geth clean-qt start-qt clean

clean-simd:
	rm -rf ./ibc-go 2>/dev/null
	rm -rf data 2>/dev/null

build-simd: | clean-simd
	git clone https://github.com/ChorusOne/ibc-go
	cd ibc-go && git checkout 7ae0507a974c8b7532d4ccf9ee697e8926cb608e

	cd ibc-go && make build-linux

start-simd: | clean-config-simd config-simd
	cd ibc-go && make build
	ibc-go/build/simd start --home "data/.gaiad"  --rpc.laddr tcp://0.0.0.0:26657 --trace

clean-config-simd:
	rm -rf data 2>/dev/null

config-simd: | clean-config-simd
	ibc-go/build/simd init --home "data/.gaiad" --chain-id=wormhole node || true

	# enable wasm clients
	cat data/.gaiad/config/genesis.json | jq '.app_state.ibc.client_genesis.params.allowed_clients=["10-wasm"]' -r > /tmp/genesis.json
	mv /tmp/genesis.json data/.gaiad/config/genesis.json

	yes | ibc-go/build/simd keys --home "data/.gaiad" add validator --keyring-backend test |& tail -1 > data/.gaiad/validator_mnemonic
	yes | ibc-go/build/simd keys --home "data/.gaiad" add relayer --keyring-backend test |& tail -1 > data/.gaiad/relayer_mnemonic

	ibc-go/build/simd add-genesis-account --home "data/.gaiad" $$(ibc-go/build/simd --home "data/.gaiad" keys show validator -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	ibc-go/build/simd add-genesis-account --home "data/.gaiad" $$(ibc-go/build/simd --home "data/.gaiad" keys show relayer -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	ibc-go/build/simd gentx --home "data/.gaiad" --chain-id "wormhole" validator 100000000000stake --keyring-backend test
	ibc-go/build/simd collect-gentxs --home "data/.gaiad"

	cp configs/app.toml data/.gaiad/config/app.toml
	cp configs/config.toml data/.gaiad/config/config.toml

clean-clc:
	rm -rf celo-light-client 2>/dev/null

build-clc: | clean-clc
	git clone https://github.com/ChorusOne/celo-light-client.git
	cd celo-light-client && git checkout tags/v0.2.0
	cd celo-light-client && make wasm-optimized

start-clc:
	cd celo-light-client && make wasm-optimized

	# upload light client binary to gaia via wasm-manager
	rm -f /tmp/clc.log 2>/dev/null
	ibc-go/build/simd tx ibc wasm-manager push-wasm celo-light-client/target/wasm32-unknown-unknown/release/celo_light_client.wasm --gas=80000000 --home "data/.gaiad" --node http://localhost:26657 --chain-id wormhole --from=relayer --keyring-backend test --yes | tee /tmp/clc.log

clean-geth:
	rm -rf celo-blockchain 2>/dev/null

clean-config-geth:
	cd celo-blockchain && rm -r ./dev-chain || true

config-geth:
	echo "e517af47112e4f501afb26e4f34eadc8b0ad8eadaf4962169fc04bc8ddbfe091" > /tmp/privkey
	echo "password" > /tmp/geth.password

	cd celo-blockchain && ./build/bin/geth --datadir ./dev-chain --dev --miner.validator "0" || true
	cd celo-blockchain && ./build/bin/geth --datadir ./dev-chain --dev account import /tmp/privkey --password /tmp/geth.password

	# top up account
	cd celo-blockchain && echo 'eth.sendTransaction({from: "0x47e172f6cfb6c7d01c1574fa3e2be7cc73269d95", to: "0xa89f47c6b463f74d87572b058427da0a13ec5425", value: 50000000000000000000000}); exit' | ./build/bin/geth --datadir ./dev-chain --dev --miner.validator "0" console

build-geth: | clean-geth
	curl https://github.com/celo-org/celo-blockchain/archive/v1.3.2.tar.gz -L | tar xvz
	mv celo-blockchain-1.3.2 celo-blockchain

	# uncomment this for higher gas limit
	# cd celo-blockchain && sed -i 's/DefaultGasLimit uint64 =.*/DefaultGasLimit uint64 = 80000000/g' params/protocol_params.go
	cd celo-blockchain &&  go run build/ci.go install ./cmd/geth

start-geth: | clean-config-geth config-geth
	cd celo-blockchain && ./build/bin/geth --datadir ./dev-chain --miner.validator "0" --allow-insecure-unlock --dev --rpc --ws --wsport 3334 --wsapi eth,net,web3,istanbul,txpool,db,personal,debug --rpcapi eth,net,web3,istanbul,txpool,db,personal,debug --vmdebug --minerthreads 2 --nodiscover --nousb --syncmode full --gcmode=archive console

start-geth-live: | clean-config-geth
	cd celo-blockchain && go run build/ci.go install ./cmd/geth && ./build/bin/geth --datadir ./dev-chain --maxpeers 30 --light.maxpeers 20 --syncmode lightest --rpc --ws --wsport 3334 --wsapi eth,net,web3,istanbul --alfajores --rpcapi eth,net,web3,istanbul console

clean-qt:
	rm -rf quantum-tunnel 2>/dev/null

build-qt: | clean-qt
	git clone https://github.com/ChorusOne/quantum-tunnel
	cd quantum-tunnel && git checkout v0.2.0-celo

	# point quantum tunnel to local celo-light-client crate
	cd quantum-tunnel && sed -i "/celo-light-client.git/c\celo_light_client = { path = \"../celo-light-client\", features = [\"wasm-contract\"], optional = true , default-features = false}" Cargo.toml

	cd quantum-tunnel && CHAIN=celo RUSTFLAGS=-Awarnings make build

start-qt:
	# fetch ID of the wasm light client binary (uploaded via `start-lc` command) and update quantum-tunnel config
	cat /tmp/clc.log | grep -oP "txhash: \K.*" > /tmp/clc.tx
	ibc-go/build/simd query tx $$(cat /tmp/clc.tx) | grep -oP "wasm_code_id.*value\"\:\"\K.*(?=\")" | xargs -I{} sed -i 's/"wasm_id": ".*"/"wasm_id": "{}"/g' quantum-tunnel/test_data/$(TEST_MODE).json

	# update contract addresses
	cat tendermint-sol/build/contracts/IBCHost.json | jq '.networks."1337".address' -r | xargs -I{} sed -i 's/"ibc_host_address": ".*"/"ibc_host_address": "{}"/g' quantum-tunnel/test_data/$(TEST_MODE).json
	cat tendermint-sol/build/contracts/IBCHandler.json | jq '.networks."1337".address' -r | xargs -I{} sed -i 's/"ibc_handler_address": ".*"/"ibc_handler_address": "{}"/g' quantum-tunnel/test_data/$(TEST_MODE).json

	cd quantum-tunnel && COSMOS_SIGNER_SEED=$$(cat ../data/.gaiad/relayer_mnemonic) CELO_SIGNER_SEED="flat reflect table identify forward west boat furnace similar million list wood" RUST_LOG=info RUSTFLAGS=-Awarnings cargo run --features celo -- -c test_data/$(TEST_MODE).json start

clean-tlc:
	rm -rf tendermint-sol 2>/dev/null

build-tlc: | clean-tlc
	git clone https://github.com/ChorusOne/tendermint-sol
	cd tendermint-sol && git checkout tags/v0.1.0-optimized
	cd tendermint-sol && npm install
	cd tendermint-sol && truffle compile

start-tlc:
	cd tendermint-sol && NETWORK=celo make deploy && NETWORK=celo make config

clean: | clean-geth clean-qt clean-clc clean-tlc clean-simd clean-config-simd
