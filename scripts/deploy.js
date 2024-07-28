const { ethers, upgrades } = require('hardhat');

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying contracts with the account:', deployer.getAddress());

  // Deploy NFTCollection
  const NFTCollection = await ethers.getContractFactory('NFTCollection');
  const nftCollection = await NFTCollection.deploy();
  await nftCollection.waitForDeployment();
  console.log('NFTCollection deployed to:', await nftCollection.getAddress());

  // Deploy RwdToken
  const RwdToken = await ethers.getContractFactory('RwdToken');
  const rwdToken = await RwdToken.deploy();
  await rwdToken.waitForDeployment();
  console.log('RwdToken deployed to:',await rwdToken.getAddress());

  // Deploy StakeNFT implementation
  const StakeNFT = await ethers.getContractFactory('StakeNFT');
  const stakeNFT = await upgrades.deployProxy(
    StakeNFT,
    [await nftCollection.getAddress(),await rwdToken.getAddress(), BigInt(10 ** 16), 1, 1],
    { initializer: 'initialize' }
  );
  await stakeNFT.waitForDeployment();
  console.log('StakeNFT (proxy) deployed to:',await stakeNFT.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
