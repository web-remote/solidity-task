// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library PriceFeedHelper {
    /**
     * @notice 获取代币的美元价值（以18位小数表示）
     * @param priceFeed Chainlink价格预言机接口
     * @param amount 代币数量（以最小单位表示，如wei）
     * @return 美元价值（1e18 = 1 USD）
     */
    function getUsdPrice(
        AggregatorV3Interface priceFeed,
        uint256 amount
    ) internal view returns (uint256) {
        // 获取价格数据和精度
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        
        // 验证价格有效性
        require(price > 0, "PriceFeed: invalid price");
        require(updatedAt > 0, "PriceFeed: round not complete");
        
        // 计算时间衰减因子（超过24小时的数据视为过期）
        require(block.timestamp - updatedAt < 24 hours, "PriceFeed: stale data");
        
        // 处理价格精度转换
        uint256 adjustedPrice = uint256(price) * 1e18 / (10 ** uint256(decimals));
        
        // 计算美元价值（防止溢出）
        require(amount <= type(uint256).max / adjustedPrice, "PriceFeed: amount overflow");
        uint256 rawValue = adjustedPrice * amount;
        
        // 标准化为18位小数格式
        return rawValue / 1e18;
    }

    /**
     * @notice 获取代币的美元价值（原始精度）
     * @dev 适用于不需要标准化精度的场景
     */
    function getRawUsdValue(
        AggregatorV3Interface priceFeed,
        uint256 amount
    ) internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        
        require(price > 0, "PriceFeed: invalid price");
        return uint256(price) * amount / (10 ** uint256(decimals));
    }
}