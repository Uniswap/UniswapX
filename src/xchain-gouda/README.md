# Cross Chain Gouda

## Architecture Flow

An order is equipped with 4 deadlines. 
1. `intiateDeadline:` The order settlement may not be initiated after the initiate deadline. Once passed, this means the order has expired.
2. `fillDeadline:` The order must be filled on the target chain by the fill deadline, or it is not considered a valid fill.
3. `challengeDeadline:` After this deadline, the order may be finalized optimistically if it has not been challenged. This means that the filler does not need to prove their fill. A challenger may still challenge after the challenge deadline if the order hasn't been finalized.
4. `proofDeadline:` If the order cannot be finalized optimistically, then proof must be sent by this deadline via the SettlementOracle attesting that it was filled on the target chain. Otherwise the order may be cancelled and all funds sent back to the swapper and the challenger. 


### Finalize an Order Settlement Optimistically
An order can be settled optimistically if it is never challenged. In this scenario, the filler is not required to carry out proof through the bridge and settlement oracle.
![gouda-finalizeOptimistically](https://user-images.githubusercontent.com/5539720/226055654-b733aaac-d3c4-4d27-bffe-cbb2402f618b.png)

### Finalize an Order Settlement that's been Challenged
A settlement may be challenged successfully through the challengeDeadline. After it is challenged, it may no longer be finalized optimistically, but the SettlementOracle must attest that the order has been filled. The filler will have to ensure that the corresponding cross-chain bridge calls through to the SettlementOracle which has the authority to finalize the challenged settlement on the appropriate OrderSettler contract.
![gouda-finalizeChallenged](https://user-images.githubusercontent.com/5539720/226055852-a30fecdd-0157-4e38-8b6d-516a04890440.png)
