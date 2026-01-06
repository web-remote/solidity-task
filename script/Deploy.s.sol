// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 引入 Foundry 标准脚本库
import "forge-std/Script.sol";
// 引入你的逻辑合约
import "../src/Auction/AuctionLogic.sol";
// 引入 OpenZeppelin 官方代理合约（无需自己写）
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";


// 部署脚本合约，继承 Script 获得广播、日志等能力
contract DeployAuction is Script {
    // ========== 配置项（替换为你的实际地址） ==========
    address public constant ADMIN_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // 管理员钱包地址
    address public constant TREASURY_ADDRESS = 0x2798B927f63cBe96236e3e03bD92f4389b23Aa97; // 平台金库地址

    function run() external {
        // 1. 启动广播（使用私钥签名交易，Foundry 会读取环境变量或命令行传入的私钥）
        vm.startBroadcast();

        // 2. 部署 AuctionLogic 逻辑合约（核心业务逻辑）
        AuctionLogic logicContract = new AuctionLogic();
        console.log("Logic contract deployed at:", address(logicContract));

        // 3. 构造初始化数据（调用 AuctionLogic 的 initialize 函数）
        // abi.encodeCall 是安全的编码方式，避免参数错位
        bytes memory initData = abi.encodeCall(
            AuctionLogic.initialize, 
            (ADMIN_ADDRESS, TREASURY_ADDRESS)
        );

        // 4. 部署 OpenZeppelin 官方的 ERC1967Proxy 代理合约
        // 构造函数参数：逻辑合约地址 + 初始化数据
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(logicContract), initData);
        console.log("Proxy contract deployed at:", address(proxyContract));

        // 5. 验证初始化结果（可选，确保参数正确）
        AuctionLogic auctionProxy = AuctionLogic(address(proxyContract));
        console.log("Treasury address:", auctionProxy.platformTreasury());
        console.log("Admin has role:", auctionProxy.hasRole(auctionProxy.ADMIN_ROLE(), ADMIN_ADDRESS));

        // 6. 停止广播
        vm.stopBroadcast();
    }
}