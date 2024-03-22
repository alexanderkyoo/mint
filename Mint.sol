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
        _currentPositionIndex = 0;
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

    /* TODO: implement your functions here */

    function openPosition(uint collateralAmount, address assetToken, uint collateralRatio) external override {
        require(checkRegistered(assetToken) == true);
        require(collateralRatio >= _assetMap[assetToken].minCollateralRatio);

        IERC20(collateralToken).transferFrom(msg.sender, address(this) , collateralAmount);

        _idxPositionMap[_currentPositionIndex] = Position(_currentPositionIndex, msg.sender, collateralAmount, assetToken, 0);

        _currentPositionIndex += 1;
    }

    function closePosition(uint positionIndex) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        address assetToken = pos.assetToken;
        uint assetAmount = pos.assetAmount;
        uint collateralAmount = pos.collateralAmount;
        sAsset(assetToken).burn(address(this), assetAmount);
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
        if (pos.assetAmount != 0) {
            uint collateralRatio = (pos.collateralAmount - withdrawAmount) / pos.assetAmount;
            require(collateralRatio >= _assetMap[pos.assetToken].minCollateralRatio);
        }
        IERC20(collateralToken).transferFrom(address(this), msg.sender, withdrawAmount);
        pos.collateralAmount -= withdrawAmount;
    }

    function mint(uint positionIndex, uint mintAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender); 
        /* uint assetAmount = getMintAmount(mintAmount, pos.assetToken, pos.collateralAmount / pos.assetAmount)

        uint collateralAmount = getCollateralAmount(mintAmount, pos.assetToken, pos.collateralAmount / pos.assetAmount);
        uint collateralRatio = (pos.collateralAmount - collateralAmount) / pos.assetAmount;
        require(collateralRatio >= _assetMap[pos.assetToken].minCollateralRatio);
        pos.collateralAmount -= collateralAmount;
        pos.assetAmount += mintAmount; */

        sAsset(pos.assetToken).mint(address(this), mintAmount);
    }

    function burn(uint positionIndex, uint burnAmount) external override {
        Position storage pos = _idxPositionMap[positionIndex];
        require(pos.owner == msg.sender); 
        pos.assetAmount -= burnAmount;
        sAsset(pos.assetToken).burn(address(this), burnAmount);
    }
    
}
