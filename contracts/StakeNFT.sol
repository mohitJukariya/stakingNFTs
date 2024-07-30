// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./NFTCollection.sol";
import "./RwdToken.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StakeNFT is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, IERC721Receiver {
    uint256 public totalNftStaked;
    uint256 public rewardPerBlock;
    uint256 public delayPeriod;
    uint256 public unbondingPeriod;
    

    // struct to store a stake's tokenId, owner, record timestamp, lastClaimedBlock to implement logic of 
    // delay period for Reward claiming after a certain time period after claiming rewards, unbondingStartTime to implement logic 
    // of waiting for a certain period of time for withdrawing NFTs from StakeNFT Contract after Unstaking them,
    // stakedNFT is used to check if any NFT is staked or not.
    struct Stake {
        uint24 tokenId;
        uint48 timestamp;
        address owner;
        uint256 lastClaimedBlock;
        uint256 unbondingStartTime;
        bool stakedNFT;
    }

    bool public paused;
    event NFTStaked(address owner, uint256 tokenId, uint256 value);
    event NFTUnstaked(address owner, uint256 tokenId, uint256 value);
    event Claimed(address owner, uint256 amount);
    event TokensBurned(address burnFrom, uint256 amount);


    modifier whenNotPaused() {
        require(!paused, "Staking is paused");
        _;
    }

    // reference to the Block NFT contract
    NFTCollection nft;
    RwdToken token;

    // maps tokenId to stake. Keeps track of the all the information mentioned in Struct Stake{...}
    mapping(uint256 => Stake) public vault;

    // Since we are using Upgradeable contracts here, therefore,Iniitializer is used in place of constructer.
    function initialize(NFTCollection _nft, RwdToken _token, uint256 _rewardPerBlock, uint256 _delayPeriod, uint256 _unbondingPeriod) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        nft = _nft;
        token = _token;
        rewardPerBlock = _rewardPerBlock;
        delayPeriod = _delayPeriod;
        unbondingPeriod = _unbondingPeriod;
    }

    constructor() {
   _disableInitializers();
}

    // Used to implement new Implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    //Used to stake NFTs to the staking contract.
    function stake(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
        uint256 tokenId;
        totalNftStaked += tokenIds.length;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            require(nft.ownerOf(tokenId) == msg.sender, "not your token"); // reverts if non-owner tries to use this function.
            require(vault[tokenId].tokenId == 0, "already staked");// reverts if user tries to stake same NFT again
            

            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            emit NFTStaked(msg.sender, tokenId, block.timestamp);

            vault[tokenId] = Stake({                                // Update all the information in vault mapping to implement 
                owner: msg.sender,                                  // delayPeriod and UunbondingPeriod logic
                tokenId: uint24(tokenId),
                timestamp: uint48(block.timestamp),
                lastClaimedBlock: uint256(block.number),
                unbondingStartTime: uint256(block.number),
                stakedNFT: true
            });
        }
    }

    // Used to unstake Tokens
    function _unstakeMany(
        address account,
        uint256[] calldata tokenIds
    ) internal nonReentrant {
        uint256 tokenId;
        totalNftStaked -= tokenIds.length;
        for (uint i = 0; i < tokenIds.length; i++) {            // loop to implement logic for multiple NFTs in a single txn
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            require(staked.owner == account, "not an owner");       // reverts when non-owner performs this txn.
            vault[tokenId] = Stake({                                // records information for implementing delayPeriod and 
                owner: msg.sender,                                  // unbondingPeriod logic
                tokenId: uint24(tokenId),
                timestamp: uint48(block.timestamp),
                lastClaimedBlock: uint256(block.number),
                unbondingStartTime: uint256(block.number),
                stakedNFT: false
            });
            
            emit NFTUnstaked(account, tokenId, block.timestamp);
        }
    }

// used to withdraw NFTs
    function withdrawNFT(uint256[] calldata tokenIds) external nonReentrant {
        uint256 tokenId;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            require(staked.owner == msg.sender, "not an owner");
            require(staked.stakedNFT == false, "Unstake NFT before withdrawing"); // reverts if withdrawal request is made before 
            require(                                                              // is made before unstaking of NFTs
                block.number >= staked.unbondingStartTime + unbondingPeriod,      // reverts if unbondingPeriod is not over
                "Unbonding period not over"
            );

            nft.safeTransferFrom(address(this), msg.sender, tokenId);
            delete vault[tokenId];
        }
    }

// used to claim rewards
    function claim(uint256[] calldata tokenIds) external  nonReentrant {
        _claim(msg.sender, tokenIds, false);
    }

    function unstake(uint256[] calldata tokenIds) external whenNotPaused  nonReentrant {
        _claim(msg.sender, tokenIds, true);
    }

// used to implment claim function logic
    function _claim(
        address account,
        uint256[] calldata tokenIds,
        bool _unstake
    ) internal {
        uint256 tokenId;
        uint256 earned = 0;

        for (uint i = 0; i < tokenIds.length; i++) {                            // loop to claim rewards for multiple NFTs
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            
            require(staked.owner == account, "not an owner");
            require(
                block.number > staked.lastClaimedBlock + delayPeriod,           //reverts if delayPeriod is not over
                "Claim delay period not over"
            );
            require(
                staked.stakedNFT == true,                                       // reverts if claim function is used after unstaking
                "Reward generation is paused for this NFT. Stake it again to generate rewards."
            );
            uint256 stakedAt = staked.lastClaimedBlock;
            earned += rewardPerBlock * (block.number - stakedAt);               // logic for rewards generation
            staked.lastClaimedBlock = block.number;
        }
        if (earned > 0) {
            token.mint(account, earned);
        }
        if (_unstake) {
            _unstakeMany(account, tokenIds);
        }
        emit Claimed(account, earned);
    }

// function to burn reward tokens
    function burnRewardTokens(address burnFrom, uint256 amount) external onlyOwner nonReentrant {
        token.burnFrom(burnFrom, amount);
        emit TokensBurned(msg.sender, amount);
    }

// return accumulated rewards for NFTs
    function earningInfo(
    uint256[] calldata tokenIds
) external view returns (uint256) {
    uint256 tokenId;
    uint256 earned = 0;
    for (uint i = 0; i < tokenIds.length; i++) {
        tokenId = tokenIds[i];
        Stake memory staked = vault[tokenId];
        require(staked.stakedNFT == true, "NFT is not staked");
        uint256 stakedAt = staked.lastClaimedBlock;
        earned += rewardPerBlock * (block.number - stakedAt);
    }

    return earned;
}

// used to pause staking contract. Only owner can do this.
    function pause() external onlyOwner {
        paused = true;
    }

// used to unpause staking contract. Only owner can do this.
    function unpause() external onlyOwner {
        paused = false;
    }

// used to update amount of rewards generating per Block
    function updateRewardPerBlock(uint256 newRewardPerBlock) external onlyOwner {
        rewardPerBlock= newRewardPerBlock;
    }

// used to update delayPeriod and unbondingPeriod
    function upgradeStakingConfig(uint256 newDelayPeriod, uint256 newUnbondingPeriod) external onlyOwner {
        delayPeriod = newDelayPeriod;
        unbondingPeriod = newUnbondingPeriod;
    }

    
    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send nfts to Vault directly");
        return IERC721Receiver.onERC721Received.selector;
    }
}
