// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./NFTCollection.sol";
import "./RwdToken.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract StakeNFT is Initializable, UUPSUpgradeable, OwnableUpgradeable, IERC721Receiver {
    uint256 public totalNftStaked;
    uint256 public rewardPerBlock;
    uint256 public delayPeriod;
    uint256 public unbondingPeriod;
    

    // struct to store a stake's token, owner, and earning values
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

    modifier whenNotPaused() {
        require(!paused, "Staking is paused");
        _;
    }

    // reference to the Block NFT contract
    NFTCollection nft;
    RwdToken token;

    // maps tokenId to stake
    mapping(uint256 => Stake) public vault;

    function initialize(NFTCollection _nft, RwdToken _token, uint256 _rewardPerBlock, uint256 _delayPeriod, uint256 _unbondingPeriod) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        nft = _nft;
        token = _token;
        rewardPerBlock = _rewardPerBlock;
        delayPeriod = _delayPeriod;
        unbondingPeriod = _unbondingPeriod;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function stake(uint256[] calldata tokenIds) external whenNotPaused {
        uint256 tokenId;
        totalNftStaked += tokenIds.length;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            require(nft.ownerOf(tokenId) == msg.sender, "not your token");
            require(vault[tokenId].tokenId == 0, "already staked");

            nft.transferFrom(msg.sender, address(this), tokenId);
            emit NFTStaked(msg.sender, tokenId, block.timestamp);

            vault[tokenId] = Stake({
                owner: msg.sender,
                tokenId: uint24(tokenId),
                timestamp: uint48(block.timestamp),
                lastClaimedBlock: uint256(block.number),
                unbondingStartTime: uint256(block.number),
                stakedNFT: true
            });
        }
    }

    function _unstakeMany(
        address account,
        uint256[] calldata tokenIds
    ) internal {
        uint256 tokenId;
        totalNftStaked -= tokenIds.length;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            require(staked.owner == account, "not an owner");
            vault[tokenId] = Stake({
                owner: msg.sender,
                tokenId: uint24(tokenId),
                timestamp: uint48(block.timestamp),
                lastClaimedBlock: uint256(block.number),
                unbondingStartTime: uint256(block.number),
                stakedNFT: false
            });
            // staked.unbondingStartTime = block.number;
            // staked.stakedNFT = false;
            emit NFTUnstaked(account, tokenId, block.timestamp);
        }
    }

    function withdrawNFT(uint256[] calldata tokenIds) external {
        uint256 tokenId;
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            require(staked.owner == msg.sender, "not an owner");
            require(staked.stakedNFT == false, "Unstake NFT before withdrawing");
            require(
                block.number >= staked.unbondingStartTime + unbondingPeriod,
                "Unbonding period not over"
            );

            nft.transferFrom(address(this), msg.sender, tokenId);
            delete vault[tokenId];
        }
    }

    function claim(uint256[] calldata tokenIds) external {
        _claim(msg.sender, tokenIds, false);
    }

    function unstake(uint256[] calldata tokenIds) external whenNotPaused {
        _claim(msg.sender, tokenIds, true);
    }

    function _claim(
        address account,
        uint256[] calldata tokenIds,
        bool _unstake
    ) internal {
        uint256 tokenId;
        uint256 earned = 0;

        for (uint i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            Stake memory staked = vault[tokenId];
            
            require(staked.owner == account, "not an owner");
            require(
                block.number > staked.lastClaimedBlock + delayPeriod,
                "Claim delay period not over"
            );
            require(
                staked.stakedNFT == true,
                "Reward generation is paused for this NFT. Stake it again to generate rewards."
            );
            uint256 stakedAt = staked.lastClaimedBlock;
            earned += rewardPerBlock * (block.number - stakedAt);
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

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function updateRewardPerBlock(uint256 newRewardPerBlock) external onlyOwner {
        rewardPerBlock= newRewardPerBlock;
    }

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
