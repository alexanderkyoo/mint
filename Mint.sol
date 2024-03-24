// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IMint.sol";
import "./sAsset.sol";
import "./EUSD.sol";

contract Mint is Ownable, IMint {

    struct Asset {
        address token;
        uint minCollateralRatio;
        address priceFeed;
    }

    struct Position {
        uint idx;
        address owner;
        uint collateralAmount;
        address assetToken;
        uint assetAmount;
    }

    mapping(address => Asset) _assetMap;
    uint _currentPositionIndex;
    mapping(uint => Position) _idxPositionMap;
    address public collateralToken;
    

    constructor(address collateral) {
        collateralToken = collateral;
    }

    function registerAsset(address assetToken, uint minCollateralRatio, address priceFeed) external override onlyOwner {
        require(assetToken != address(0), "Invalid assetToken address");
        require(minCollateralRatio >= 1, "minCollateralRatio must be greater than 100%");
        require(_assetMap[assetToken].token == address(0), "Asset was already registered");
        
        _assetMap[assetToken] = Asset(assetToken, minCollateralRatio, priceFeed);
    }

    function getPosition(uint positionIndex) external view returns (address, uint, address, uint) {
        require(positionIndex < _currentPositionIndex, "Invalid index");
        Position storage position = _idxPositionMap[positionIndex];
        return (position.owner, position.collateralAmount, position.assetToken, position.assetAmount);
    }

    function getMintAmount(uint collateralAmount, address assetToken, uint collateralRatio) public view returns (uint) {
        Asset storage asset = _assetMap[assetToken];
        (int relativeAssetPrice, ) = IPriceFeed(asset.priceFeed).getLatestPrice();
        uint8 decimal = sAsset(assetToken).decimals();
        uint mintAmount = collateralAmount * (10 ** uint256(decimal)) / uint(relativeAssetPrice) / collateralRatio ;
        return mintAmount;
    }

    function checkRegistered(address assetToken) public view returns (bool) {
        return _assetMap[assetToken].token == assetToken;
    }

    function getCollateralRatio(uint collateralAmount, uint assetAmount, address assetToken) public view returns (uint) {
        Asset storage asset = _assetMap[assetToken];
        (int relativeAssetPrice, ) = IPriceFeed(asset.priceFeed).getLatestPrice();
        uint8 decimal = sAsset(assetToken).decimals();
        return collateralAmount * (10 ** uint256(decimal)) / uint(relativeAssetPrice) / assetAmount;
    }
    
    /* TODO: implement your functions here */
    function openPosition(uint collateralAmount, address assetToken, uint collateralRatio) external override {
        require(checkRegistered(assetToken) == true);
        require(collateralRatio >= _assetMap[assetToken].minCollateralRatio);

        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        uint mintAmount = getMintAmount(collateralAmount, assetToken, collateralRatio);
        sAsset(assetToken).mint(msg.sender, mintAmount);
        _idxPositionMap[_currentPositionIndex] = Position(_currentPositionIndex, msg.sender, collateralAmount, assetToken, mintAmount);
        _currentPositionIndex += 1;
    }

    function closePosition(uint positionIndex) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        address assetToken = pos.assetToken;
        uint collateralAmount = pos.collateralAmount;
        sAsset(assetToken).burn(msg.sender, pos.assetAmount);
        IERC20(collateralToken).transferFrom(address(this), msg.sender, collateralAmount);

        delete _idxPositionMap[positionIndex];
    }

    function deposit(uint positionIndex, uint collateralAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender);
        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        pos.collateralAmount += collateralAmount;
    }


    function withdraw(uint positionIndex, uint withdrawAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender); 
        require(getCollateralRatio(pos.collateralAmount - withdrawAmount, pos.assetAmount, pos.assetToken) >= _assetMap[pos.assetToken].minCollateralRatio, "Poor colltaeral Ratio");
        IERC20(collateralToken).transfer(msg.sender, withdrawAmount);
        pos.collateralAmount -= withdrawAmount;
    }

    function mint(uint positionIndex, uint mintAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender); 
        uint assetAmount = getMintAmount(mintAmount, pos.assetToken, getCollateralRatio(pos.collateralAmount, pos.assetAmount, pos.assetToken));
        require(getCollateralRatio(pos.collateralAmount - mintAmount, pos.assetAmount + assetAmount, pos.assetToken) >= _assetMap[pos.assetToken].minCollateralRatio);
        pos.collateralAmount -= mintAmount;
        pos.assetAmount += assetAmount; 

        sAsset(pos.assetToken).mint(msg.sender, assetAmount);
    }

    function burn(uint positionIndex, uint burnAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender); 
        pos.assetAmount -= burnAmount;
        sAsset(pos.assetToken).burn(msg.sender, burnAmount);
    }
    
}
