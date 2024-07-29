##Follow the following steps to setup the contracts for testing.

###**In RemixIDE**
Note - I have used Sepolia testnet for this.
1) simple copy paste the code of all three contracts in 3 different files in Remix.
2) Start with deploying NFTCollection.sol, then RwdToken.sol
3) Then open StakeNFT. for deployement. Select thet option deploy proxy to create an ERC1967 proxy contract also. Give all the initializer values.
         _nft = address of NFTCollection contract
         _token = address of RwdToken contract
         _rewardPerBlock = 10000000000000000 (here we are giving 10 ** 16 tokens per block as a reward to the user since the token contract uses decimal value of 18)
         _delayPeriod = 1
         _unbondingPeriod = ( we are using 1 for _delayPeriod and _unbondingPeriod for testing purpose to avoid waiting for long time.)

4) Now, we need to setup StakeNFT contract as a controller of RwdToken to perform minting functionality.
5) Therefore, copy the address of proxy contract ( since it is our storage contract) and paste it in the addController function of RwdToken and then run it. Now, StakeNFT contract can mint new tokens.
6) Now, use your Buyer address to mint new NFTs from NFTCollection contract. After minting, copy and paste StakeNFT proxy contract address to setApproval for all method and allow StakeNFT Contract to perform transactions with Buyer's NFT tokens in behalf of Buyer.
7) Now, contracts are setup and you can use StakeNFT contract.

###**On Ethereum Testnet directly from the terminal**
Note- I have done this using hardhat's local ethereum node.
1) Run npx hardhat node on your terminal. It will show you address of different accounts and start a local ethereum testnet on your computer.
2) Now, Run this -   npx hardhat run scripts/deploy.js --network localhost 
   This will deploy the script written in script/deploy.js
3) Address of the owner and all 3 contracts will be shown at your screen.
4) And now you are ready and can do all your testing directly from Hardhat terminal.


###**Running Hardhat Tests**
1) Run npx hardhat test.
