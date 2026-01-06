// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;
    string private _baseTokenURI;
    
    // 事件记录铸造和转移
    event Minted(address indexed to, uint256 indexed tokenId);
    event BaseURIChanged(string newBaseURI);

    constructor() ERC721("NFT Auction", "NAU") Ownable(msg.sender) {
        _baseTokenURI = "https://example.com/nft/";
    }

    // 设置基础URI（仅合约所有者）
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
        emit BaseURIChanged(baseURI);
    }

    // 获取基础URI
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // 单NFT铸造（仅合约所有者）
    function mint(address to, uint256 tokenId) public onlyOwner {
        require(!_exists(tokenId), "Token ID already exists");
        _mint(to, tokenId);
        emit Minted(to, tokenId);
    }

    // 自动ID铸造（仅合约所有者）
    function mintAuto(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _mint(to, tokenId);
        emit Minted(to, tokenId);
        return tokenId;
    }

    // 批量铸造（仅合约所有者）
    function mintBatch(address[] calldata recipients, uint256[] calldata tokenIds) external onlyOwner {
        require(recipients.length == tokenIds.length, "Array length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(!_exists(tokenIds[i]), "Token ID already exists");
            _mint(recipients[i], tokenIds[i]);
            emit Minted(recipients[i], tokenIds[i]);
        }
    }

    // 安全转移封装（可选）
    function safeTransfer(address from, address to, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender || getApproved(tokenId) == msg.sender, "Not authorized");
        safeTransferFrom(from, to, tokenId, "");
    }

    // 获取下一个可用的tokenId
    function nextTokenId() public view returns (uint256) {
        return _tokenIdCounter.current();
    }
}