// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AuctionLogic is 
    Initializable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    struct Auction {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 endTime;
        address paymentToken; // address(0) for ETH
        uint256 highestBidAmount;
        uint256 highestBidUsd;
        address highestBidder;
        bool settled;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionCount;
    
    mapping(address => AggregatorV3Interface) public tokenToPriceFeed;
    address public platformTreasury;
    uint256 public platformFeePercent = 500; // 5% in basis points (500 = 5%)
    
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address nftAddress, uint256 tokenId);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount, uint256 usdValue);
    event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _treasury) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        
        platformTreasury = _treasury;
    }

    // 创建拍卖（需NFT所有权验证）
    function createAuction(
        address nftAddress,
        uint256 tokenId,
        uint256 duration, // 持续时间（秒）
        address paymentToken
    ) external {
        require(IERC721(nftAddress).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(IERC721(nftAddress).getApproved(tokenId) == address(this) || 
                IERC721(nftAddress).isApprovedForAll(msg.sender, address(this)), 
                "NFT not approved");
        
        auctionCount++;
        auctions[auctionCount] = Auction({
            seller: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            endTime: block.timestamp + duration,
            paymentToken: paymentToken,
            highestBidAmount: 0,
            highestBidUsd: 0,
            highestBidder: address(0),
            settled: false
        });
        
        // 转移NFT到合约托管
        IERC721(nftAddress).transferFrom(msg.sender, address(this), tokenId);
        
        emit AuctionCreated(auctionCount, msg.sender, nftAddress, tokenId);
    }

    // 出价函数（支持ETH/ERC20）
    function bid(uint256 auctionId, uint256 amount) external payable {
        Auction storage auction = auctions[auctionId];
        require(!auction.settled, "Auction settled");
        require(block.timestamp < auction.endTime, "Auction ended");
        
        // 计算美元价值
        uint256 usdValue = _calculateUsdValue(auction.paymentToken, amount);
        require(usdValue > auction.highestBidUsd, "Bid too low");
        
        // 退还先前出价者
        if (auction.highestBidder != address(0)) {
            _refundPreviousBidder(auction);
        }
        
        // 处理新出价
        if (auction.paymentToken == address(0)) {
            require(msg.value == amount, "ETH amount mismatch");
        } else {
            IERC20(auction.paymentToken).transferFrom(msg.sender, address(this), amount);
        }
        
        // 更新出价记录
        auction.highestBidAmount = amount;
        auction.highestBidUsd = usdValue;
        auction.highestBidder = msg.sender;
        
        emit BidPlaced(auctionId, msg.sender, amount, usdValue);
    }

    // 结束拍卖（任何人可调用）
    function settleAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(!auction.settled, "Already settled");
        require(block.timestamp >= auction.endTime, "Auction not ended");
        
        auction.settled = true;
        
        // 转移NFT给赢家
        IERC721(auction.nftAddress).transferFrom(
            address(this), 
            auction.highestBidder, 
            auction.tokenId
        );
        
        // 计算分配金额
        uint256 sellerAmount = (auction.highestBidAmount * (10000 - platformFeePercent)) / 10000;
        uint256 feeAmount = auction.highestBidAmount - sellerAmount;
        
        // 转移资金
        if (auction.paymentToken == address(0)) {
            payable(auction.seller).transfer(sellerAmount);
            payable(platformTreasury).transfer(feeAmount);
        } else {
            IERC20(auction.paymentToken).transfer(auction.seller, sellerAmount);
            IERC20(auction.paymentToken).transfer(platformTreasury, feeAmount);
        }
        
        emit AuctionSettled(auctionId, auction.highestBidder, auction.highestBidAmount);
    }

    // 内部函数：计算USD价值
    function _calculateUsdValue(address token, uint256 amount) internal view returns (uint256) {
        if (token == address(0)) {
            AggregatorV3Interface feed = tokenToPriceFeed[address(0)];
            (, int256 price,,,) = feed.latestRoundData();
            return amount * uint256(price) / 1e18; // ETH/USD
        } else {
            AggregatorV3Interface feed = tokenToPriceFeed[token];
            (, int256 price,,,) = feed.latestRoundData();
            return amount * uint256(price) / 1e18; // Token/USD
        }
    }

    // 内部函数：退还先前出价者
    function _refundPreviousBidder(Auction storage auction) internal {
        if (auction.paymentToken == address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBidAmount);
        } else {
            IERC20(auction.paymentToken).transfer(auction.highestBidder, auction.highestBidAmount);
        }
    }

    // 管理函数
    function setPriceFeed(address token, address feed) external onlyRole(ADMIN_ROLE) {
        tokenToPriceFeed[token] = AggregatorV3Interface(feed);
    }
    
    function setPlatformTreasury(address treasury) external onlyRole(ADMIN_ROLE) {
        platformTreasury = treasury;
    }
    
    function setPlatformFee(uint256 basisPoints) external onlyRole(ADMIN_ROLE) {
        require(basisPoints <= 1000, "Max 10% fee"); // 上限10%
        platformFeePercent = basisPoints;
    }

    // UUPS升级授权
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // 接收ETH备用函数
    receive() external payable {}
}