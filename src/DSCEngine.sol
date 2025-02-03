// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;



/*
 * @title DSCEngine
 * @author Dvid Korgalidze
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { console } from "lib/forge-std/src/console.sol";
import { OracleLib } from "./librarie/OracleLib.sol";


contract DSCEngine is ReentrancyGuard {

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InsufficientCollateral();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant _ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _LIQUIDATION_THRESHOLD = 50;
    uint256 private constant _LIQUIDATION_PRECISION = 100;
    uint256 private constant _MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant _LIQUIDATION_BONUS = 10;


  



    DecentralizedStableCoin private immutable _iDsc;

    mapping (address token => address priceFeed) private _sPriceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private _sCollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private _sDSCMinted;
    address[] private _sCollateralTokens;
    
    
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);
    

    modifier moreThanZero ( uint256 amount) {
        if( amount == 0 ){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    } 

    modifier isAllowedToken (address token) {
         if (_sPriceFeeds[token] == address(0) ){
            revert DSCEngine__TokenNotAllowed(token);
         }
         _;
    }

    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses,
        address dscAddress
         ){
            if (tokenAddresses.length != priceFeedAddresses.length){
                revert  DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
            }
            for (uint256 i = 0; i < tokenAddresses.length; i++){
                _sPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
                _sCollateralTokens.push(tokenAddresses[i]);
            }
            _iDsc = DecentralizedStableCoin(dscAddress);
         }

   

         

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
        ) public
         moreThanZero (amountCollateral)
         isAllowedToken(tokenCollateralAddress)
         nonReentrant
        {
          _sCollateralDeposited[msg.sender][tokenCollateralAddress] +=amountCollateral;
          emit CollateralDeposited(msg.sender, tokenCollateralAddress,amountCollateral );
          bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this),amountCollateral );

          if(!success) {
            revert DSCEngine__TransferFailed();
          }
        }

        

    function depositCollaterAndMintDsc(
           address tokenCollateralAddress,
           uint256 amountCollateral,
           uint256 amountDscToMint
    ) external {
         depositCollateral(tokenCollateralAddress, amountCollateral);
         mintDsc(amountDscToMint);
    }

    function redeemCollateralForDsc(
          address tokenCollateralAddress,
          uint256 amountCollateral,
          uint256 amountDscToBurn
    ) external {
         burnDsc(amountDscToBurn);
         redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) moreThanZero(amountCollateral) nonReentrant public  isAllowedToken(tokenCollateralAddress) {
         _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
         revertIfHealthFactorIsBroken(msg.sender);
    }


        function _redeemCollateral(  
            address from, 
            address to,
            address tokenCollateralAddress,
            uint256 amountCollateral 
        ) private {
            uint256 currentBalance = _sCollateralDeposited[from][tokenCollateralAddress];
          
            require(currentBalance >= amountCollateral, "Insufficient collateral balance");
            
            _sCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
            emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

            bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
            
            if (!success) {
                revert DSCEngine__TransferFailed();
            } 
        }




    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant{
         _sDSCMinted[msg.sender] += amountDscToMint;
          revertIfHealthFactorIsBroken(msg.sender);
         bool minted = _iDsc.mint(msg.sender, amountDscToMint);
         if (!minted){
            revert DSCEngine__MintFailed();
         }

    }


    function _healthFactor (address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);

        // uint256 collateralAdjustedForThreshold = (collateralValueInUsd * _LIQUIDATION_THRESHOLD) / _LIQUIDATION_PRECISION;
        // return (collateralAdjustedForThreshold * _PRECISION) / totalDscMinted;
    }


  
    

    function _calculateHealthFactor (
         uint256 totalDscMinted,
         uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
         if (totalDscMinted == 0 ) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * _LIQUIDATION_THRESHOLD) / _LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * _PRECISION) / totalDscMinted;
    }


    
    function revertIfHealthFactorIsBroken (address user) public view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < _MIN_HEALTH_FACTOR){
        revert DSCEngine__BreaksHealthFactor(userHealthFactor);
      }

    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd){
        for(uint256 i = 0; i < _sCollateralTokens.length; i++){
            address token = _sCollateralTokens[i];
            uint256 amount = _sCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
    }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_sPriceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * _ADDITIONAL_FEED_PRECISION) * amount) / _PRECISION;
    }

    function _getAccountInformation (address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
            totalDscMinted = _sDSCMinted[user];
            collateralValueInUsd = getAccountCollateralValue(user);
        }
    



    function burnDsc(uint256 amount) moreThanZero(amount) public {
         _burnDsc(amount, msg.sender, msg.sender);
          revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(
        address collateral, address user, uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if ( startingUserHealthFactor >= _MIN_HEALTH_FACTOR){
             revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * _LIQUIDATION_BONUS) / _LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral (collateral, user, msg.sender,  totalCollateralRedeemed );
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
          if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }


    function getTokenAmountFromUsd (address token, uint256 usdAmountInWei) public view returns (uint256){
         AggregatorV3Interface priceFeed = AggregatorV3Interface(_sPriceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
          return (usdAmountInWei * _PRECISION) / (uint256(price) * _ADDITIONAL_FEED_PRECISION);
    }

  



    function _burnDsc (
        uint256 amountDscToBurn, 
        address onBehalfOf, 
        address dscFrom
        ) private {
            _sDSCMinted[onBehalfOf] -= amountDscToBurn;
            bool success = _iDsc.transferFrom(dscFrom, address(this), amountDscToBurn);
            if(!success) {
                revert DSCEngine__TransferFailed();
            }
            _iDsc.burn(amountDscToBurn);
        }


          function calculateHealthFactor(
                uint256 totalDscMinted,
                uint256 collateralValueInUsd
            )
                external
                pure
                returns (uint256)
            {
                return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
            }


     //getter functions//   

    function getHealthFactor(address user) external view returns(uint256){
         return _healthFactor(user);
    }

    function getAccountInformation(address user) external view returns (
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ){
        (totalDscMinted, collateralValueInUsd ) = _getAccountInformation(user);
    }

    function getCollateralTokenPriceFeed 
       (address token) 
       external view returns(address){
        return _sPriceFeeds[token];
    }

    function getCollateralTokens () external view returns (address[] memory){
        return _sCollateralTokens;
    }

    function getMinHealthFactor () external pure returns (uint256) {
         return _MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold () external pure returns(uint256) {
        return _LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser (
        address user,
        address token
    ) external view returns(uint256){
        return _sCollateralDeposited[user][token];
    }

    function getDsc () external view returns (address) {
         return address(_iDsc);
    } 

    function getPrecision () external pure returns (uint256) {
         return _PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return _ADDITIONAL_FEED_PRECISION; 
    }

    function getCollateralBalance(address user, address token) external view returns (uint256) {
      return _sCollateralDeposited[user][token];
   }

}
    