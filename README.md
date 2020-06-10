# SmartJudge - Dispute Resolution for Smart Contracts

## About

SmartJudge [1] is a framework for private, trustless, and efficient trades between two parties. 
Exemplary use cases are the selling of digital files and atomic exchanges of cryptocurrencies.
SmartJudge works via blinded trade agreements and optimic trade excutions, which allows to keep the trade agreement and save costly verifications of the trading partnes' honesty.
If the receiver of the traded good does not acknowledge the reception of its goods, a on-chain identification of the misbehaving party is launched.
Through small, yet sufficient security deposits, SmartJudge ensures that an honest party is reimboursed all fees in case an on-chain verification is necessary.


## Presentation of the Accompayning Paper at IEEE ICBC 2019

[![IMAGE ALT TEXT](https://i.imgur.com/yUlWk7O.png)](https://youtu.be/ilWwCqGA-_Y?t=2599 "IEEE ICBC Technical Session - 9 190517")


## Examplary Use Case: Privacy-preserving ETH-BTC Atomic Swaps


**DISCLAIMER: THIS IS A PROOF-OF-CONCEPT, DO NOT USE FOR TRADING VALUABLE ASSETS!**

This repository contains two major smart contracts; First, the SmartJudge framework that generalizes the optimistic trade of any asset for which the exchange verifiable on the Ethereum blockchain. 
Secondly, we provide a use-case-specific verifier for the atomic exchange of Ether and Bitcoins that does not require a trusted third party.
To get started, you first deploy the `meditor.sol` smart contract.
Afterward, you deploy the `atomic-swap-verifier.sol` smart contract and indicate the address of the mediator during deployment.
Finally, you have to register the new verifier with the mediator (you can register multiple verifiers with one mediator).

We provide two Python scripts that take care of deploying the smart contracts (`deploy.py`) and showing the execution of trades between honest and between dishonest trading partners (`trade.py`).
For our example trades, we assume that Alice wants to exchange her Ether for Bitcoins and that both trading partners regard the Bitcoin block number 514490 as included in the Bitcoin chain (e.g., six blocks have been mined on top of it).
The transaction [0xab95a18c...ef3e9735](https://www.blockchain.com/btc/tx/ab95a18c001454c361d70a0cd26df1b124498e5b4444ef4ca5f77725ef3e9735) is in our example the payment by Bob to Alice's Bitcoin address, whose existence and correctness is proven by the verifier if necessary (i.e., if Alice refuses to conclude the trade gracefully).

## License

This work is licensed under the MIT license.


## Links

\[1\]&ensp;Eric Wagner, Achim Völker, Frederik Fuhrmann, Roman Matzutt and Klaus Wehrle.  
&ensp;&ensp;&ensp;&thinsp;&thinsp;[Dispute Resolution for Smart-contract bases Two-Party Protocols](https://roman-matzutt.de/paper/2019-icbc-wagner-dispute-resolution.pdf)  
&ensp;&ensp;&ensp;&thinsp;&thinsp;IEEE International Conference on Blockchain and Cryptocurrency 2019 (ICBC 2019)
