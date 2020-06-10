import json
import os

from web3 import Web3, HTTPProvider

from solcx import install_solc, set_solc_version
install_solc('v0.4.26')
set_solc_version('v0.4.26')

from solcx import compile_standard

def compile_source_file(file_path, name):

    input = {
        'language': 'Solidity',
        'sources' : {
            name: {'urls': [file_path+"/"+name]}},
        'settings':{
            'outputSelection': {
                '*': {
                    '*': ["metadata", "evm.bytecode", "evm.bytecode.sourceMap"],
                },
                    'def': {name: [ "abi", "evm.bytecode.opcodes" ]},
            }
            }
    }

    output = compile_standard(input, allow_paths=file_path)

    contracts = output["contracts"]
    contract = contracts[list(contracts.keys())[0]]
    bytecode = contract[list(contract.keys())[0]]["evm"]["bytecode"]["object"]

    metadata = contract[list(contract.keys())[0]]["metadata"]
    metadata = json.loads(metadata)
    abi = metadata["output"]["abi"]

    return bytecode, abi


def deploy_contract(w3, bytecode, abi, params=None):
    contract = w3.eth.contract( abi=abi, bytecode=bytecode)

    if(params):
        tx_hash = contract.constructor(params).transact()
    else:
        tx_hash = contract.constructor().transact()

    receipt = w3.eth.waitForTransactionReceipt(tx_hash)
    address = receipt['contractAddress']
    return address

w3 = Web3( HTTPProvider("http://127.0.0.1:8545") )

w3.eth.defaultAccount = w3.eth.accounts[0]

# deploy mediator contract
bytecode, abi = compile_source_file('.', 'mediator.sol')

address = deploy_contract(w3, bytecode, abi)
print("Deployed mediator smart contract to: {0}".format(address))


f = open("mediator.abi", "w")
json.dump(abi, f)
f.close()

f = open("mediator.addr", "w")
f.write(address)
f.close()

#deploy atomic swap verifier contract
bytecode, abi = compile_source_file('.', 'atomicswap.sol')

address = deploy_contract(w3, bytecode, abi, params=address)
print("Deployed atomic swap verifier to: {0}".format( address))

f = open("atomic-swap-verifier.abi", "w")
json.dump(abi, f)
f.close()

f = open("atomic-swap-verifier.addr", "w")
f.write(address)
f.close()