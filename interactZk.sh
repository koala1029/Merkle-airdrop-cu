#!/bin/bash

# Define constants
DEFAULT_ZKSYNC_LOCAL_KEY="0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110"
DEFAULT_ANVIL_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEFAULT_ZKSYNC_ADDRESS="0x36615Cf349d7F6344891B1e7CA7C72883F5dc049"
ROOT="0x474d994c58e37b12085fdb7bc6bbcd046cf1907b90de3b7fb083cf3636c8ebfb"
PROOF_1="0xd1445c931158119b00449ffcac3c947d028c0c359c34a6646d95962b3b55c6ad"
PROOF_2="0x46f4c7c1c21e8a90c03949beda51d2d02d1ec75b55dd97a999d3edbafa5a1e2f"


# Compile and deploy BagelToken contract
make zk-anvil
echo "Deploying token contract..."
TOKEN_ADDRESS=$(forge create src/BagelToken.sol:BagelToken --rpc-url http://127.0.0.1:8011 --private-key ${DEFAULT_ZKSYNC_LOCAL_KEY} --legacy --zksync | awk '/Deployed to:/ {print $3}' )
echo "Token contract deployed at: $TOKEN_ADDRESS"
echo "TOKEN_ADDRESS=$TOKEN_ADDRESS" >> constants.env

# Deploy MerkleAirdrop contract
echo "Deploying MerkleAirdrop contract..."
AIRDROP_ADDRESS=$(forge create src/MerkleAirdrop.sol:MerkleAirdrop --rpc-url http://127.0.0.1:8011 --private-key ${DEFAULT_ZKSYNC_LOCAL_KEY} --constructor-args ${ROOT} ${TOKEN_ADDRESS} --legacy --zksync | awk '/Deployed to:/ {print $3}' )
echo "MerkleAirdrop contract deployed at: $AIRDROP_ADDRESS"
echo "AIRDROP_ADDRESS=$AIRDROP_ADDRESS" >> constants.env

# Get message hash
MESSAGE_HASH=$(cast call ${AIRDROP_ADDRESS} "getMessageHash(address,uint256)" ${DEFAULT_ANVIL_ADDRESS} 25000000000000000000 --rpc-url http://127.0.0.1:8011)
echo -n "$MESSAGE_HASH" >> digest.txt

# Run SignZkSync script
echo "Signing message..."
SIGN_OUTPUT=$(forge script script/SignZkSync.s.sol:SignMessage)

V=$(echo "$SIGN_OUTPUT" | grep -A 1 "v value:" | tail -n 1 | xargs)
R=$(echo "$SIGN_OUTPUT" | grep -A 1 "r value:" | tail -n 1 | xargs)
S=$(echo "$SIGN_OUTPUT" | grep -A 1 "s value:" | tail -n 1 | xargs)

# Save V, R, S values
echo "V=$V" >> constants.env
echo "R=$R" >> constants.env
echo "S=$S" >> constants.env

# Execute remaining steps
echo "Sending tokens to the token contract owner..."
cast send ${TOKEN_ADDRESS} 'mint(address,uint256)' ${DEFAULT_ZKSYNC_ADDRESS} 100000000000000000000 --private-key ${DEFAULT_ZKSYNC_LOCAL_KEY} --rpc-url http://127.0.0.1:8011 > /dev/null
echo "Sending tokens to the airdrop contract..."
cast send ${TOKEN_ADDRESS} 'transfer(address,uint256)' ${AIRDROP_ADDRESS} 100000000000000000000 --private-key ${DEFAULT_ZKSYNC_LOCAL_KEY} --rpc-url http://127.0.0.1:8011 > /dev/null
echo "Claiming tokens on behalf of 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266..."
cast send ${AIRDROP_ADDRESS} 'claim(address,uint256,bytes32[],uint8,bytes32,bytes32)' ${DEFAULT_ANVIL_ADDRESS} 25000000000000000000 "[${PROOF_1},${PROOF_2}]" ${V} ${R} ${S} --private-key ${DEFAULT_ZKSYNC_LOCAL_KEY} --rpc-url http://127.0.0.1:8011 > /dev/null

HEX_BALANCE=$(cast call ${TOKEN_ADDRESS} 'balanceOf(address)' ${DEFAULT_ANVIL_ADDRESS} --rpc-url http://127.0.0.1:8011)

# Assuming OUTPUT is defined somewhere in your process or script
echo "Balance of the claiming address (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266): $(cast --to-dec ${HEX_BALANCE})"

# Clean up
rm digest.txt
rm constants.env
