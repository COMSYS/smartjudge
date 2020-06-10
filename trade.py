from web3 import Web3, HTTPProvider
import web3
import json

def printBalances(w3, alice, bob):
    balance = w3.fromWei(w3.eth.getBalance(alice), 'ether' );
    print("Alice: {} Eth".format(balance))
    balance = w3.fromWei(w3.eth.getBalance(bob), 'ether' );
    print("Bob: {} Eth".format(balance))

w3 = Web3( HTTPProvider("http://127.0.0.1:8545") )

alice = w3.eth.accounts[0]
bob = w3.eth.accounts[1]

f = open("./mediator.abi", "r")
mediator_abi = json.load(f)
f.close()
f = open("./mediator.addr", "r")
mediator_addr = f.read()
f.close()
mediator = w3.eth.contract( address=mediator_addr, abi=mediator_abi)

f = open("./atomic-swap-verifier.abi", "r")
verifier_abi = json.load(f)
f.close()
f = open("./atomic-swap-verifier.addr", "r")
verifier_addr = f.read()
f.close()
verifier = w3.eth.contract( address=verifier_addr, abi=verifier_abi)


worst_case_cost_atomic_swap = 1343000
tx_hash = mediator.functions.register_verifier( verifier_addr, worst_case_cost_atomic_swap ).transact({'from':alice})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
verifier_id = int(receipt['logs'][0]['data'], 16 )
print("Registered BTC atomic swap verifier")

# WE SHOWCASE THREE SCENARIOS FOR HOW AN ATOMIC SWAP CAN PROCEED WHEN USING SMARTJUDGE:
#   1) BOTH PARTIES REMAIN HONEST
#   2) ALICE CLAIM BOB'S CLAIMED CHAIN IS INCORRECT WHICH IS NOT THE CASE
#   3) BOB DID NOT TRANSFER BITCOINS TO ALICE
print("")
printBalances(w3,alice,bob)



# 1) BOTH PARTIES REMAIN HONEST
print("\n----------------------- Scenario 1 -----------------------\n")

btc_address = "0x1b17143000000000" # Alice's BTC address
btc_amount =  "0x659c2a9bc407f28b3f44caaeb01c6ead271d76aa" # Amount of coins that Alice desires
btc_header =  "0xbc4aceb11443ae1576bf38888fc9c660c950fdfb644921000000000000000000" # Current header of the BTC blockchain
btc_difficulty = "0x0000000000000000000000000000000000000000002945010000000000000000" # Block difficulty

eth_price = 1000000000000000000
gas_price = w3.eth.gasPrice
security_deposit = 400000*gas_price

trade_conditions = Web3.soliditySha3(['bytes8', 'bytes20', 'bytes32', 'bytes32'],[Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty)])
agreement = Web3.soliditySha3(['uint32','bytes32'],[verifier_id, trade_conditions])

tx_hash = mediator.functions.create( agreement ).transact({'from':alice, 'value':eth_price+security_deposit})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
trade_id = int(receipt['logs'][0]['data'], 16 )
print("Alice created new trade")

tx_hash = mediator.functions.accept( trade_id ).transact({'from':bob, 'value':security_deposit})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob accepted the trade")

# BOB IS EXPECTED TO TRANSFER HIS BTC NOW, IN ORDER TO GENERATE THE PROOF THAT ALLOWS HIM TO UNLOCKS ALICE'S ETH

tx_hash = mediator.functions.finish( trade_id ).transact({'from':alice})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice concludes the trade by confirming that Bob's BTC arrived")
print("")
printBalances(w3,alice,bob)


# 2.1) ALICE CLAIM BOB'S CLAIMED CHAIN IS INCORRECT WHICH IS NOT THE CASE
print("\n----------------------- Scenario 2.1 -----------------------\n")

btc_address = "0x659c2a9bc407f28b3f44caaeb01c6ead271d76aa" # Alice's BTC address
btc_amount =  "0x1b17143000000000" # Amount of coins that Alice desires
btc_header =  "0xbc4aceb11443ae1576bf38888fc9c660c950fdfb644921000000000000000000" # Current header of the BTC blockchain
btc_difficulty = "0x0000000000000000000000000000000000000000002945010000000000000000" # Block difficulty

eth_price = 1000000000000000000
gas_price = w3.eth.gasPrice
security_deposit = 400000*gas_price

trade_conditions = Web3.soliditySha3(['bytes8','bytes20', 'bytes32', 'bytes32'],[Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty)])
agreement = Web3.soliditySha3(['uint32','bytes32'],[verifier_id, trade_conditions])

# we can reuse the storage allocated for previous concluded trades
tx_hash = mediator.functions.create( trade_id, agreement ).transact({'from':alice, 'value':eth_price+security_deposit})
print("Alice created new trade")

tx_hash = mediator.functions.accept( trade_id ).transact({'from':bob, 'value':security_deposit})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob accepted the trade")

# BOB IS EXPECTED TO TRANSFER HIS BTC NOW, IN ORDER TO GENERATE THE PROOF THAT ALLOWS HIM TO UNLOCKS ALICE'S ETH

# WE NOW ASSUME: BOB SEND HIS BTC, BUT ALICE REFUSES TO ACKNOWLEDGE THIS

btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
btc_mined_blocks = 20
witness = Web3.soliditySha3(['uint16','bytes32'],[btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash)])
tx_hash = mediator.functions.contest( trade_id, witness ).transact({'from':bob, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob contented the trade")

btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
tx_hash = mediator.functions.init_verification( trade_id, trade_id, trade_conditions ).transact({'from':alice, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice disagrees with the contention and starts the verification")

btc_tx_hash = "0x10ae727d9ec0e6312c7e47e567d6049b95886e00ca564f000000000000000000"
tx_hash = verifier.functions.verify_agreement( trade_id, Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty), btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash), Web3.toBytes(hexstr=btc_tx_hash) ).transact({'from':bob})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob uploades the terms of the trade agreement")

# IN THIS FIRST EXAMPLE, ALICE DISAGREES WITH BOB'S CLAIMED CHAIN
tx_hash = verifier.functions.search_start(trade_id).transact({'from':alice})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice disagrees with Bob's claimed chain hashes and starts the search for the first block of contention")

btc_block_hashes = [
    Web3.toBytes(0xbc4aceb11443ae1576bf38888fc9c660c950fdfb644921000000000000000000), # accepted by both in agreement
    Web3.toBytes(0x1109167878b86431bd67ec48ebe57debf0d6a4d0cc6444000000000000000000), # first potential block of contention
    Web3.toBytes(0x481de872c181bf3e06eb3a9865f08404da7303863c5108000000000000000000),
    Web3.toBytes(0xdde268a3a319fbb8a0f5bf8b5f81209a5156c72dbc2f17000000000000000000),
    Web3.toBytes(0x0dea3f1ed3030b5359cfc2310580e568a1e57e5621ee11000000000000000000),
    Web3.toBytes(0x4109b7052e342be39ace20154603846426103d27360e2f000000000000000000),
    Web3.toBytes(0x9fad83f8127d8f07ff1e38099cdfb6dd16e7b0a00eb041000000000000000000),
    Web3.toBytes(0x38d2cb65b11704d1d9de68b9d8533a66c09680baf0844a000000000000000000),
    Web3.toBytes(0x15cd4c17cc4953eced1999cc2a8af87706185304d50134000000000000000000),
    Web3.toBytes(0x907f51a765ce2946c13150018fdaa26553b28cebd3c512000000000000000000),
    Web3.toBytes(0xddbe7177db5cad346c027a8c7fd7874dd74b41940bf214000000000000000000),
    Web3.toBytes(0x1c1cea4bd3c4f831654fb2dd05f3a9d7b395c2e177f238000000000000000000),
    Web3.toBytes(0x10c1b06fde1801b57a739571bffa7521c18ab83287f901000000000000000000),
    Web3.toBytes(0x29a33dc340ed946ab839d749a29f59e4d8e1b330dc0907000000000000000000), 
    Web3.toBytes(0x10ae727d9ec0e6312c7e47e567d6049b95886e00ca564f000000000000000000), # btc_tx_hash
    Web3.toBytes(0x05f888915d6e3760853bd05be15f4f20b210c5bb605626000000000000000000),
    Web3.toBytes(0x783506fd20bd89c7689fed5c02e0838fbcbb2b1596aa26000000000000000000),
    Web3.toBytes(0xfe614b7701b58ee0d1985cae09e24e799e6f16c5672826000000000000000000),
    Web3.toBytes(0xe19c553283bb81c9ddb79de098d6fb650455626faaaf12000000000000000000),
    Web3.toBytes(0x1be2f7dc7242d749aec76db01d5de42c632946bf728447000000000000000000),
    Web3.toBytes(0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000)  # btc_last_hash
]
left_index = 0
right_index = btc_mined_blocks

while(left_index + 1 != right_index):

    print( "Range for potential block of contention: [{},{}]".format(left_index,right_index) )

    mid_index = left_index + ((right_index - left_index) // 2);

    tx_hash = verifier.functions.search_claim(trade_id, btc_block_hashes[mid_index]).transact({'from':bob})
    receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print("Bob uploades block number {}".format(mid_index))

    if( mid_index >= 13 ): # without loss of generality, we assume that Alice disagrees with Bob block number 13 (3 blocks before the supposed BTC transaction from Bob to Alice)
        tx_hash = verifier.functions.search_partition(trade_id, False).transact({'from':alice})
        receipt = w3.eth.waitForTransactionReceipt(tx_hash)
        right_index = mid_index 
        print("Alice indicates that the mismatch happens in left partition {}".format(mid_index))
    else:    
        tx_hash = verifier.functions.search_partition(trade_id, True).transact({'from':alice})
        receipt = w3.eth.waitForTransactionReceipt(tx_hash)
        left_index = mid_index
        print("Alice indicates that the mismatch happens in right partition")

print( "Range for potential block of contention: [{},{}]".format(left_index,right_index) )
print( "First block of contention: {}".format(right_index) )


btc_block_headers = [
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x00000000000000000001f98732b88ac12175fabf7195737ab50118de6fb0c110)[::-1], # previous hash
        Web3.toBytes(0xe2a246f5d7373df599a35ccee1320fef0964d00fe3effc7eede8fdb10d24f647)[::-1], # merkle root
        Web3.toBytes(1521619158)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(113658764)[::-1]  # nonce
    ], # 13th block header (first block of contention)
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x0000000000000000000709dc30b3e1d8e4599fa249d739b86a94ed40c33da329)[::-1], # previous hash
        Web3.toBytes(0x002da939303e1612302aec5722f5e8895a8bbbd117c368b03c27eef025d5beac)[::-1], # merkle root
        Web3.toBytes(1521619443)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(3180606387)[::-1]  # nonce
    ], # tx block header
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x0000000000000000004f56ca006e88959b04d667e5477e2c31e6c09e7d72ae10)[::-1], # previous hash
        Web3.toBytes(0x6a719a3fcce54f89c2862ed86702bb9ea44eef748317fda93cc63d9475bdcf14)[::-1], # merkle root
        Web3.toBytes(1521620512)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(1534751392)[::-1]  # nonce
    ],
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x000000000000000000265660bbc510b2204f5fe15bd03b8560376e5d9188f805)[::-1], # previous hash
        Web3.toBytes(0x18f1fe16b78971897d70baffe5fbbf7f8c7452ce67be609e7f908ff3c02fa2c3)[::-1], # merkle root
        Web3.toBytes(1521620611)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(177043474)[::-1]  # nonce
    ],
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x00000000000000000026aa96152bbbbc8f83e0025ced9f68c789bd20fd063578)[::-1], # previous hash
        Web3.toBytes(0xa91ad050327adc682f7be838537e91c28d9f9a2eafa1f7449967a6d42ad8f8b2)[::-1], # merkle root
        Web3.toBytes(1521621718)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(258240744)[::-1]  # nonce
    ],
    [   Web3.toBytes(536870912)[::-1], # version
        Web3.toBytes(0x000000000000000000262867c5166f9e794ee209ae5c98d1e08eb501774b61fe)[::-1], # previous hash
        Web3.toBytes(0x64e48d65ad2acec628ea0a95e36e729fffd2b0d975ff574159bdba8cd1ac7983)[::-1], # merkle root
        Web3.toBytes(1521622521)[::-1], # timestamp
        Web3.toBytes(391203401)[::-1], # difficulty
        Web3.toBytes(177504166)[::-1]  # nonce
    ],
]

for i in range(6):

    tx_hash = verifier.functions.resolve_header_mismatch(trade_id, btc_block_headers[i][0], btc_block_headers[i][1], btc_block_headers[i][2], btc_block_headers[i][3], btc_block_headers[i][4], btc_block_headers[i][5] ).transact({'from':bob})
    receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    print("Bob uploades block header {}".format(right_index+i))


print("")
printBalances(w3,alice,bob)

# 2.1) ALICE CLAIM BOB'S CLAIMED CHAIN IS INCORRECT WHICH IS NOT THE CASE
print("\n----------------------- Scenario 2.2 -----------------------\n")

btc_address = "0x659c2a9bc407f28b3f44caaeb01c6ead271d76aa" # Alice's BTC address
btc_amount =  "0x1b17143000000000" # Amount of coins that Alice desires
btc_header =  "0xbc4aceb11443ae1576bf38888fc9c660c950fdfb644921000000000000000000" # Current header of the BTC blockchain
btc_difficulty = "0x0000000000000000000000000000000000000000002945010000000000000000" # Block difficulty

eth_price = 1000000000000000000
gas_price = w3.eth.gasPrice
security_deposit = 400000*gas_price

trade_conditions = Web3.soliditySha3(['bytes8','bytes20', 'bytes32', 'bytes32'],[Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty)])
agreement = Web3.soliditySha3(['uint32','bytes32'],[verifier_id, trade_conditions])

# we can reuse the storage allocated for previous concluded trades
tx_hash = mediator.functions.create( trade_id, agreement ).transact({'from':alice, 'value':eth_price+security_deposit})
print("Alice created new trade")

tx_hash = mediator.functions.accept( trade_id ).transact({'from':bob, 'value':security_deposit})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob accepted the trade")

# BOB IS EXPECTED TO TRANSFER HIS BTC NOW, IN ORDER TO GENERATE THE PROOF THAT ALLOWS HIM TO UNLOCKS ALICE'S ETH

# WE NOW ASSUME: BOB SEND HIS BTC, BUT ALICE REFUSES TO ACKNOWLEDGE THIS

btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
btc_mined_blocks = 20
witness = Web3.soliditySha3(['uint16','bytes32'],[btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash)])
tx_hash = mediator.functions.contest( trade_id, witness ).transact({'from':bob, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob contented the trade")


btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
tx_hash = mediator.functions.init_verification( trade_id, trade_id, trade_conditions ).transact({'from':alice, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice disagrees with the contention and starts the verification")

btc_tx_hash = "0x10ae727d9ec0e6312c7e47e567d6049b95886e00ca564f000000000000000000"
tx_hash = verifier.functions.verify_agreement( trade_id, Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty), btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash), Web3.toBytes(hexstr=btc_tx_hash) ).transact({'from':bob})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob uploades the terms of the trade agreement")

# THIS TIME, ALICE ACCEPTS THE BITCOIN CHAIN BUT CLAIMS THAT BOB'S TRANSACTION IS NOT INCLUDED

tx_hash = verifier.functions.hashes_ok( trade_id ).transact({'from':alice})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice agrees with Bob's block hashes")


btc_tx_block_version = Web3.toBytes(536870912)[::-1]
btc_tx_block_prev_hash = Web3.toBytes(0x0000000000000000000709dc30b3e1d8e4599fa249d739b86a94ed40c33da329)[::-1]
btc_tx_block_merkle_root = Web3.toBytes(0x002da939303e1612302aec5722f5e8895a8bbbd117c368b03c27eef025d5beac)[::-1]
btc_tx_block_timestamp = Web3.toBytes(1521619443)[::-1]
btc_tx_block_difficulty = Web3.toBytes(391203401)[::-1]
btc_tx_block_nonce = Web3.toBytes(3180606387)[::-1]
btc_transaction = Web3.toBytes(0x010000000121db4fcde1243a9c3cecd91d45556e0e9c15c5b9c965413e49f770a9c6e7b99a000000008b483045022100b43a3dc94d81d7f6477d097e51a98b2cab0981007fcf09d6534a53124debcf8402205ba38ef0fc3419d99cbd311a44ca30d8a4df3210cc6cc30704928200c7935b290141046ec7c6856f209256fda8c55aaadbaa5d280274c178874e4da1be6ea45d2c64d6bc74fbf8b96b5330b6988807f442ad82dab358140ceb682b3756bf5f9a7397d8ffffffff01b17143000000000017a914659c2a9bc407f28b3f44caaeb01c6ead271d76aa8700000000);
btc_block_merkle_indices = 0b1001111111000000
btc_merkle_hashes = [
    Web3.toBytes(0xa9ff7f6a2c3745b330a480eb3e3b5f4f106f5ae286a3e5ac52ef951e652346d1),
    Web3.toBytes(0x5a88aa3d2aad819c2dc1503df4b5a98b7c7aaef36f72fae65f18a74e80ea3c51),
    Web3.toBytes(0x6c20eae2a329bf1103f8e2cf3873f3835b6da52abefe61adf7596464959196f6),
    Web3.toBytes(0xe0460f35f06f321a0b2c1eaad850712b19168e722da5b0b3c81e3f18715c7c78),
    Web3.toBytes(0x932b2cb99353a3d027402d522ed39b1763d094d0f5fa691e99408bf5f3470342),
    Web3.toBytes(0xf0264f1615d6f8856598b56fb4b8620c63cf4076558d69196132508465888773),
    Web3.toBytes(0xbe7b324c475ff854da6ae287710597ccf6f5c43512e77b1b4ec48032887106fe),
    Web3.toBytes(0x36545ca326d521ab6696bdb84a070361acddcf1274b98eb3c202d215adaed5be),
    Web3.toBytes(0xd47048113175109ce3164c7bf985c9102702582652eccdcecf1338df1c8eee2a),
    Web3.toBytes(0xf0ba16cc553a3aab5328bf0b29bdc922dd28fea2ee29e9e9a581dc626d3f3640)
]

tx_hash = verifier.functions.verify_tx( trade_id, btc_tx_block_version, btc_tx_block_prev_hash, 
    btc_tx_block_merkle_root, btc_tx_block_timestamp, btc_tx_block_difficulty, btc_tx_block_nonce, 
    btc_transaction, btc_block_merkle_indices, btc_merkle_hashes ).transact({'from':bob})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob uploads the SPV for his transaction")

print("")
printBalances(w3,alice,bob)



# 3) BOB DID NOT TRANSFER BITCOINS TO ALICE
print("\n----------------------- Scenario 3 -----------------------\n")

btc_address = "0x659c2a9bc407f28b3f44caaeb01c6ead271d76aa" # Alice's BTC address
btc_amount =  "0x1b17143000000000" # Amount of coins that Alice desires
btc_header =  "0xbc4aceb11443ae1576bf38888fc9c660c950fdfb644921000000000000000000" # Current header of the BTC blockchain
btc_difficulty = "0x0000000000000000000000000000000000000000002945010000000000000000" # Block difficulty

eth_price = 1000000000000000000
gas_price = w3.eth.gasPrice
security_deposit = 400000*gas_price

trade_conditions = Web3.soliditySha3(['bytes8','bytes20', 'bytes32', 'bytes32'],[Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty)])
agreement = Web3.soliditySha3(['uint32','bytes32'],[verifier_id, trade_conditions])

# we can reuse the storage allocated for previous concluded trades
tx_hash = mediator.functions.create( trade_id, agreement ).transact({'from':alice, 'value':eth_price+security_deposit})
print("Alice created new trade")

tx_hash = mediator.functions.accept( trade_id ).transact({'from':bob, 'value':security_deposit})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob accepted the trade")

# BOB IS EXPECTED TO TRANSFER HIS BTC NOW, IN ORDER TO GENERATE THE PROOF THAT ALLOWS HIM TO UNLOCKS ALICE'S ETH

# WE NOW ASSUME: BOB SEND HIS BTC, BUT ALICE REFUSES TO ACKNOWLEDGE THIS

btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
btc_mined_blocks = 20
witness = Web3.soliditySha3(['uint16','bytes32'],[btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash)])
tx_hash = mediator.functions.contest( trade_id, witness ).transact({'from':bob, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob contented the trade")


btc_last_hash = "0x0202ac4d3ac56a5102f265b77ecdf1c011b8463f6d720a000000000000000000"
tx_hash = mediator.functions.init_verification( trade_id, trade_id, trade_conditions ).transact({'from':alice, 'value':gas_price*worst_case_cost_atomic_swap})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice disagrees with the contention and starts the verification")

btc_tx_hash = "0x10ae727d9ec0e6312c7e47e567d6049b95886e00ca564f000000000000000000"
tx_hash = verifier.functions.verify_agreement( trade_id, Web3.toBytes(hexstr=btc_amount), Web3.toBytes(hexstr=btc_address), Web3.toBytes(hexstr=btc_header), Web3.toBytes(hexstr=btc_difficulty), btc_mined_blocks, Web3.toBytes(hexstr=btc_last_hash), Web3.toBytes(hexstr=btc_tx_hash) ).transact({'from':bob})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob uploades the terms of the trade agreement")

# WE ASSUME BOB'S UPLOADS KNOWN BLOCK HASH AND ALICE THUS INDICATES THAT THE BITCOIN TRANSACTION IS NOT INCLUDED (OTHERWISE ALICE CAN CONTENT THE CLAIMED CHAIN)

tx_hash = verifier.functions.hashes_ok( trade_id ).transact({'from':alice})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Alice agrees with Bob's block hashes")


btc_tx_block_version = Web3.toBytes(536870912)[::-1]
btc_tx_block_prev_hash = Web3.toBytes(0x0000000000000000000709dc30b3e1d8e4599fa249d739b86a94ed40c33da329)[::-1]
btc_tx_block_merkle_root = Web3.toBytes(0x002da939303e1612302aec5722f5e8895a8bbbd117c368b03c27eef025d5beac)[::-1]
btc_tx_block_timestamp = Web3.toBytes(1521619443)[::-1]
btc_tx_block_difficulty = Web3.toBytes(391203401)[::-1]
btc_tx_block_nonce = Web3.toBytes(3180606387)[::-1]
btc_transaction = Web3.toBytes(0x010000000121db4fcde1243a9c3cecd91d45556e0e9c15c5b9c965413e49f770a9c6e7b99a000000008b483045022100b43a3dc94d81d7f6477d097e51a98b2cab0981007fcf09d6534a53124debcf8402205ba38ef0fc3419d99cbd311a44ca30d8a4df3210cc6cc30704928200c7935b290141046ec7c6856f209256fda8c55aaadbaa5d280274c178874e4da1be6ea45d2c64d6bc74fbf8b96b5330b6988807f442ad82dab358140ceb682b3756bf5f9a7397d8ffffffff01b17143000000000017a914659c2a9bc407f28b3f44caaeb01c6ead271d76aa8700000000);
btc_block_merkle_indices = 0b1001111111000000
btc_merkle_hashes = [
    Web3.toBytes(0xa9ff7f6a2c3745b330a480eb3e3b5f4f106f5ae286a3e5ac52ef951fDEADC0DE), # manipulated
    Web3.toBytes(0x5a88aa3d2aad819c2dc1503df4b5a98b7c7aaef36f72fae65f18a74e80ea3c51),
    Web3.toBytes(0x6c20eae2a329bf1103f8e2cf3873f3835b6da52abefe61adf7596464959196f6),
    Web3.toBytes(0xe0460f35f06f321a0b2c1eaad850712b19168e722da5b0b3c81e3f18715c7c78),
    Web3.toBytes(0x932b2cb99353a3d027402d522ed39b1763d094d0f5fa691e99408bf5f3470342),
    Web3.toBytes(0xf0264f1615d6f8856598b56fb4b8620c63cf4076558d69196132508465888773),
    Web3.toBytes(0xbe7b324c475ff854da6ae287710597ccf6f5c43512e77b1b4ec48032887106fe),
    Web3.toBytes(0x36545ca326d521ab6696bdb84a070361acddcf1274b98eb3c202d215adaed5be),
    Web3.toBytes(0xd47048113175109ce3164c7bf985c9102702582652eccdcecf1338df1c8eee2a),
    Web3.toBytes(0xf0ba16cc553a3aab5328bf0b29bdc922dd28fea2ee29e9e9a581dc626d3f3640)
]

tx_hash = verifier.functions.verify_tx( trade_id, btc_tx_block_version, btc_tx_block_prev_hash, 
    btc_tx_block_merkle_root, btc_tx_block_timestamp, btc_tx_block_difficulty, btc_tx_block_nonce, 
    btc_transaction, btc_block_merkle_indices, btc_merkle_hashes ).transact({'from':bob})
receipt = w3.eth.waitForTransactionReceipt(tx_hash)
print("Bob uploads the SPV for his transaction (which is wrong because the transaction does not exist)")

print("")
printBalances(w3,alice,bob)