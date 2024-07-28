const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');

describe('stakeNFT', function () {
  let nftCollection;
  let rwdToken;
  let stakeNFT;
  let owner;
  let Buyer;
  let NonOwner
  let tokenId = 1;
  let tokenIds = [2, 3, 4, 5];

  beforeEach(async function () {
    [owner, Buyer, NonOwner] = await ethers.getSigners();

    // Deploy NFTCollection
    const NFTCollection = await ethers.getContractFactory('NFTCollection');
    nftCollection = await NFTCollection.deploy();
    await nftCollection.waitForDeployment();

    // Mint single NFT to Buyer
    await nftCollection.mint(await Buyer.getAddress(), tokenId);

    // Mint multiple NFTs to Buyer
    for(const token of tokenIds){
        await nftCollection.mint(await Buyer.getAddress(), token)
    }

    // Deploy rwdToken
    const RwdToken = await ethers.getContractFactory('RwdToken');
    rwdToken = await RwdToken.deploy();
    await rwdToken.waitForDeployment();

    // Deploy stakeNFT with UUPS Proxy
    const StakeNFT = await ethers.getContractFactory('StakeNFT');
    stakeNFT = await upgrades.deployProxy(
      StakeNFT,
      [await nftCollection.getAddress(),await rwdToken.getAddress(), BigInt(10 ** 16), 1, 1],
      { initializer: 'initialize' }
    );
    await stakeNFT.waitForDeployment();
    rwdToken.connect(owner).addController(await stakeNFT.getAddress());
  });

  // Test to check contracts are deployed properly
  it('should be able to deploy contracts correctly', async function () {
    expect(await nftCollection.getAddress()).to.properAddress;
    expect(await rwdToken.getAddress()).to.properAddress;
    expect(await stakeNFT.getAddress()).to.properAddress;
  });

  // Test to stake a single NFT
  it('should allow staking of single NFT', async function () {
    await nftCollection.connect(Buyer).approve(await stakeNFT.getAddress(), tokenId);
    await stakeNFT.connect(Buyer).stake([tokenId]);

    const stakedToken = await stakeNFT.vault(tokenId);
    expect(stakedToken.owner).to.equal(await Buyer.getAddress());
    expect(stakedToken.tokenId).to.equal(BigInt(tokenId));
  });

  // Test to stake multiple NFTs in a single transaction
  it('should allow staking of multiple NFTs in a single transaction', async function () {
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    for (const token of tokenIds) {
      const stakedToken = await stakeNFT.vault(token);
      expect(stakedToken.owner).to.equal(await Buyer.getAddress());
      expect(stakedToken.tokenId).to.equal(BigInt(token));
    }
  });

  // Test to check rewards claiming for single NFT
  it('should allow claiming of rewards for single NFT', async function () {
    await nftCollection.connect(Buyer).approve(await stakeNFT.getAddress(), tokenId);
    await stakeNFT.connect(Buyer).stake([tokenId]);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).claim([tokenId]);
    const balance = await rwdToken.balanceOf(await Buyer.getAddress());
    expect(balance).to.be.gt(0);
  });

  // Test to check rewards claiming of Multiple NFTs in a single transaction
  it('should allow claiming rewards for multiple NFTs in a single transaction', async function () {
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block
    
    const earningInfo = await stakeNFT.earningInfo(tokenIds);
    expect(earningInfo).to.be.gt((0));

    await stakeNFT.connect(Buyer).claim(tokenIds);
    const balance = await rwdToken.balanceOf(await Buyer.getAddress());

    expect(balance).to.be.gt((0));
  });

  // Test to unstake single NFT
  it('should allow unstaking of 1 NFT', async function () {
    await nftCollection.connect(Buyer).approve(await stakeNFT.getAddress(), tokenId);
    await stakeNFT.connect(Buyer).stake([tokenId]);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).unstake([tokenId]);
    const stakedToken = await stakeNFT.vault(tokenId);
    expect(stakedToken.stakedNFT).to.be.false;
  });

  //Test to unstake multiple NFTs in a single transaction
  it('should allow unstaking of multiple NFTs', async function () {
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).unstake(tokenIds);

    for (const tokenId of tokenIds) {
      const stakedToken = await stakeNFT.vault(tokenId);
      expect(stakedToken.stakedNFT).to.be.false;
    }
  });

  // Test to check if there are any rewards generating after unstaking the tokens
  // Can be implemented for MultipleNFTs also just like above
  it('should prevent claiming rewards after unstaking', async function () {
    await nftCollection.connect(Buyer).approve(await stakeNFT.getAddress(), tokenId);
    await stakeNFT.connect(Buyer).stake([tokenId]);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).unstake([tokenId]);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block
    
    // const stakedToken = await stakeNFT.vault(tokenId);
    // expect(stakedToken.stakedNFT).to.be.false;
    await expect(stakeNFT.connect(Buyer).claim([tokenId])).to.be.revertedWith('Reward generation is paused for this NFT. Stake it again to generate rewards.');


  });

  // Test to withdraw a NFT 
  it('should allow withdrawal of NFTs after unbonding period', async function () {
    await nftCollection.connect(Buyer).approve(await stakeNFT.getAddress(), tokenId);
    await stakeNFT.connect(Buyer).stake([tokenId]);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).unstake([tokenId]);

    // Move forward in time to complete unbonding period
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).withdrawNFT([tokenId]);
    const newOwner = await nftCollection.ownerOf(tokenId);
    expect(newOwner).to.equal(await Buyer.getAddress());
  });

  // Test to withdraw multiple NFTs in a single transaction
  it('should allow withdrawal of multiple NFTs after unbonding period', async function () {
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    // Move forward in time to allow rewards to accumulate
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).unstake(tokenIds);

    // Move forward in time to complete unbonding period
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    await stakeNFT.connect(Buyer).withdrawNFT(tokenIds);

    for (const tokenId of tokenIds) {
      const newOwner = await nftCollection.ownerOf(tokenId);
      expect(newOwner).to.equal(await Buyer.getAddress());
    }
  });

  // Test to check what happens when any non-owner user tries to claim rewards and Unstake multiple NFTs
  it('should revert when non-owner tries to claim rewards or unstake', async function () {
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    // Try to claim rewards from another account i.e., from NonOwner
    await expect(stakeNFT.connect(NonOwner).claim(tokenIds)).to.be.revertedWith('not an owner');

    // Try to unstake from another account i.e., from NonOwner
    await expect(stakeNFT.connect(NonOwner).unstake(tokenIds)).to.be.revertedWith('not an owner');
  });

  // Test to check pause and unpause functions
  it('should allow pausing and unpausing staking', async function () {
    await stakeNFT.connect(owner).pause();
    await expect(stakeNFT.connect(Buyer).stake(tokenIds)).to.be.revertedWith('Staking is paused');

    await stakeNFT.connect(owner).unpause();
    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await expect(stakeNFT.connect(Buyer).stake(tokenIds)).to.not.be.reverted;
  });

  // Test to check if rewards per block can be updated directly from the contract or not
  it('should update reward per block', async function () {
    const newRewardPerBlock = BigInt(20 ** 16);
    await stakeNFT.connect(owner).updateRewardPerBlock(newRewardPerBlock);

    await nftCollection.connect(Buyer).setApprovalForAll(await stakeNFT.getAddress(), true);
    await stakeNFT.connect(Buyer).stake(tokenIds);

    // Move forward in time to allow rewards to accrue
    await ethers.provider.send('evm_increaseTime', [100]); // increase time by 100 seconds
    await ethers.provider.send('evm_mine'); // mine a new block

    const earningInfo = await stakeNFT.earningInfo(tokenIds);
    expect(earningInfo).to.be.gt(0);
  });

});
