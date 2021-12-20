.PHONY : clean-gaia build-gaia start-gaia clean-config-gaia config-gaia clean-lc build-lc start-lc clean-geth build-geth start-geth clean-qt start-qt clean

clean-gaia:
	rm -rf ./cosmos-sdk ./gaia 2>/dev/null
	rm -rf data 2>/dev/null

build-gaia: | clean-gaia
	git clone https://github.com/ChorusOne/cosmos-sdk
	cd cosmos-sdk && git checkout add-wasm-management

	git clone https://github.com/cosmos/gaia
	cd gaia/ && git checkout e9d6d7f8cbba0bb3bf1ed531260b913824e3a117
	
	# point gaia to local cosmos-sdk repository
	cd gaia && echo "replace github.com/cosmos/cosmos-sdk => ../cosmos-sdk" >> go.mod
	cd gaia && sed -i "s/-mod=readonly//g" Makefile
	
	cd gaia && go mod tidy && make build

start-gaia: | clean-config-gaia config-gaia
	cd gaia && make build
	gaia/build/gaiad start --home "data/.gaiad"  --rpc.laddr tcp://0.0.0.0:26657 --trace

clean-config-gaia:
	rm -rf data 2>/dev/null

config-gaia: | clean-config-gaia
	gaia/build/gaiad init --home "data/.gaiad" --chain-id=wormhole node || true
	yes | gaia/build/gaiad keys --home "data/.gaiad" add validator --keyring-backend test |& tail -1 > data/.gaiad/validator_mnemonic
	yes | gaia/build/gaiad keys --home "data/.gaiad" add relayer --keyring-backend test |& tail -1 > data/.gaiad/relayer_mnemonic

	gaia/build/gaiad add-genesis-account --home "data/.gaiad" $$(gaia/build/gaiad --home "data/.gaiad" keys show validator -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	gaia/build/gaiad add-genesis-account --home "data/.gaiad" $$(gaia/build/gaiad --home "data/.gaiad" keys show relayer -a --keyring-backend test) 100000000000stake,100000000000validatortoken
	gaia/build/gaiad gentx --home "data/.gaiad" --chain-id "wormhole" validator 100000000000stake --keyring-backend test
	gaia/build/gaiad collect-gentxs --home "data/.gaiad"

	cp configs/app.toml data/.gaiad/config/app.toml
	cp configs/config.toml data/.gaiad/config/config.toml

clean-lc:
	rm -rf celo-light-client 2>/dev/null

build-lc: | clean-lc
	git clone https://github.com/ChorusOne/celo-light-client.git
	cd celo-light-client && git checkout main
	cd celo-light-client && make wasm-optimized

start-lc:
	cd celo-light-client && make wasm-optimized

	# upload light client binary to gaia via wasm-manager
	gaia/build/gaiad tx ibc wasm-manager push_wasm wormhole celo-light-client/target/wasm32-unknown-unknown/release/celo_light_client.wasm --gas=80000000 --home "data/.gaiad" --node http://localhost:26657 --chain-id wormhole --from=relayer --keyring-backend test --yes

clean-geth:
	rm -rf celo-blockchain 2>/dev/null

build-geth: | clean-geth
	curl https://github.com/celo-org/celo-blockchain/archive/v1.2.4.tar.gz -L | tar xvz
	mv celo-blockchain-1.2.4 celo-blockchain

	cd celo-blockchain &&  go run build/ci.go install ./cmd/geth

start-geth:
	cd celo-blockchain && go run build/ci.go install ./cmd/geth && ./build/bin/geth  --maxpeers 50 --light.maxpeers 20 --syncmode lightest --rpc  --ws --wsport 3334 --wsapi eth,net,web3,istanbul --rpcapi eth,net,web3,istanbul console 

clean-qt:
	rm -rf quantum-tunnel 2>/dev/null

build-qt: | clean-qt
	git clone https://github.com/ChorusOne/quantum-tunnel
	cd quantum-tunnel && git checkout tags/v0.1.0-celo

	# point quantum tunnel to local celo-light-client crate
	cd quantum-tunnel && sed -i "/celo-light-client.git/c\celo_light_client = { path = \"../celo-light-client\", features = [\"wasm-contract\"], optional = true , default-features = false}" Cargo.toml

	cd quantum-tunnel && CHAIN=celo RUSTFLAGS=-Awarnings make build

start-qt:
	# fetch ID of the wasm light client binary (uploaded via `start-lc` command) and update quantum-tunnel config
	gaia/build/gaiad --home "data/.gaiad" query ibc wasm-manager wasm_code_entry wormhole | grep -oP "code_id: \K.*" | head -n1 | xargs -I{} sed -i 's/"wasm_id": ".*"/"wasm_id": "{}"/g' quantum-tunnel/test_data/$(TEST_MODE).json

	cd quantum-tunnel && COSMOS_SIGNER_SEED=$$(cat ../data/.gaiad/relayer_mnemonic) CELO_SIGNER_SEED="flat reflect table identify forward west boat furnace similar million list wood" RUST_LOG=info RUSTFLAGS=-Awarnings cargo run --features celo -- -c test_data/$(TEST_MODE).json start

clean: | clean-geth clean-qt clean-lc clean-gaia clean-config-gaia
