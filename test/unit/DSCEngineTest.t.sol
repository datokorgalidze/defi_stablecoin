// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import { Test, console } from "lib/forge-std/src/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";




contract DSCEngineTest is Test {

     DeployDSC  _deployer;
     DSCEngine  _dscEngine;
     DecentralizedStableCoin  _dsc;
     HelperConfig  _helperConfig;

     address  _weth;
     address  _ethUsdPriceFeed;
     address  _wbtc;
     address  _btcUsdPriceFeed;
     
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    address public user = makeAddr("user");
    // address public user = address(1);
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public amountToMint = 100 ether;

     function setUp() public {
         _deployer = new DeployDSC ();
         (_dsc, _dscEngine, _helperConfig) = _deployer.run();
         (_ethUsdPriceFeed,_btcUsdPriceFeed, _weth,_wbtc,) = _helperConfig.activeNetworkConfig();
        //  vm.deal(user, STARTING_ERC20_BALANCE);
         ERC20Mock(_weth).mint(user, STARTING_ERC20_BALANCE);
     }
      
     address[] public tokenAddresses;
     address[] public priceFeedAddresses;

       modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
        _dscEngine.depositCollaterAndMintDsc(_weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    } 


      modifier depositedCollateral (){
         vm.startPrank(user);
         ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
         _dscEngine.depositCollateral(_weth, AMOUNT_COLLATERAL);
         vm.stopPrank();
         _;
     }

    function testDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
        _dscEngine.depositCollateral(_weth, AMOUNT_COLLATERAL);

        // Check the collateral deposited, not the DSC balance
        uint256 collateralBalance = _dscEngine.getCollateralBalance(user, _weth);
        console.log("Collateral balance after deposit:", collateralBalance);
        
        assertEq(collateralBalance, AMOUNT_COLLATERAL, "Collateral balance should match the deposited amount");

        vm.stopPrank();
    }


     function testRevertsIfTokenLengthDoesntMatchPriceFeeds () public {
            tokenAddresses.push(_weth);
            priceFeedAddresses.push(_ethUsdPriceFeed);
            priceFeedAddresses.push(_btcUsdPriceFeed);
            vm.expectRevert(
            DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
            new DSCEngine (tokenAddresses, priceFeedAddresses, address(_dsc));
     }

     function testGetTokenAmountFromUsd () public view {
           uint256 usdAmount = 100 ether;
           uint256 expectedWeth = 0.05 ether;
           uint256 amountWeth =_dscEngine.getTokenAmountFromUsd(_weth , usdAmount);
           console.log(expectedWeth);
           console.log(amountWeth);
           assertEq(expectedWeth, amountWeth);
     }





     function testGetUsdValue () public view {
         uint256 ethAmount = 15e8;
         uint256 expectedUsd = 30000e8;
         uint256 actualUsd = _dscEngine.getUsdValue(_weth, ethAmount);
         assertEq(expectedUsd, actualUsd); 
     }

     function testRevertsIfCollateralZero () public {
          vm.startPrank(user);

          ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
           vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);  
          _dscEngine.depositCollateral(_weth, 0);      
          vm.stopPrank(); 
     }


     function testRevertsWithUnapprovedCollateral () public {
          ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user,AMOUNT_COLLATERAL );
          vm.startPrank(user);
          vm.expectRevert(  abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, randomToken));
          _dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
          vm.stopPrank();
     }

   

     function testCanDepositedCollateralAndGetAccountInfo () public depositedCollateral {
           (uint256 totalDscMinted, uint256 collateralValueInUsd) = _dscEngine.getAccountInformation(user);

           uint256 expectedDscMinted = 0;
           uint256 expectedDepostAmount = _dscEngine.getTokenAmountFromUsd(_weth, collateralValueInUsd);
           assertEq(expectedDscMinted, totalDscMinted);
           assertEq(AMOUNT_COLLATERAL, expectedDepostAmount);
     }

     function testGetCollateralTokenPriceFeed () public view {
             address priceFeed =_dscEngine.getCollateralTokenPriceFeed(_weth);
             assertEq(priceFeed, _ethUsdPriceFeed);
     }


     function testGetCollateralTokens() public view {
         address[] memory collateralTokens = _dscEngine.getCollateralTokens();
         assertEq(collateralTokens[0], _weth);
     }

     function testGetMinHealthFactor () public view {
         uint256 minHealthFactor = _dscEngine.getMinHealthFactor();
         assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
     }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = _dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }


    function testGetCollateralBalanceOfUser () public depositedCollateral {
          uint256 collateralBalance = _dscEngine.getCollateralBalanceOfUser(user, _weth);
          assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue () public depositedCollateral{
            uint256 collateralValue = _dscEngine.getAccountCollateralValue(user);
            uint256 expectedCollateralValue = _dscEngine.getUsdValue(_weth,  AMOUNT_COLLATERAL);
            assertEq(collateralValue, expectedCollateralValue);
    }


    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = _dscEngine.getAccountInformation(user);
        uint256 expectedCollateralValue = _dscEngine.getUsdValue(_weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc () public view{
         address dscAddress = _dscEngine.getDsc();
         assertEq(dscAddress, address(_dsc));
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = _dsc.balanceOf(user);
        console.log("balanse:",userBalance);
         console.log(amountToMint);
        assertEq(userBalance, amountToMint);
    }

    function testRevertsIfMintAmountIsZero () public {
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
        _dscEngine.depositCollaterAndMintDsc(_weth, AMOUNT_COLLATERAL, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        _dscEngine.mintDsc(0);
        vm.stopPrank(); 
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        _dscEngine.mintDsc(amountToMint);

        uint256 userBalance = _dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    function testRevertsIfMintedDscBreaksHealthFactor () public {
        (, int256 price,,,) = MockV3Aggregator(_ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * _dscEngine.getAdditionalFeedPrecision()))
        / _dscEngine.getPrecision();
        vm.startPrank(user);
        ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = 
        _dscEngine.calculateHealthFactor(amountToMint, _dscEngine.getUsdValue(_weth,AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        _dscEngine.depositCollaterAndMintDsc(_weth, AMOUNT_COLLATERAL, amountToMint);
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(_ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * _dscEngine.getAdditionalFeedPrecision())) / _dscEngine.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor =
            _dscEngine.calculateHealthFactor(amountToMint, _dscEngine.getUsdValue(_weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        _dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }


    function testCantBurnMoreThanUserHas () public {
         vm.prank(user);
         vm.expectRevert();
         _dscEngine.burnDsc(1);
    }  

        


    function testCanRedeemCollateral () public depositedCollateral{
        vm.startPrank(user);
        _dscEngine.redeemCollateral(_weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(_weth).balanceOf(user);
        assertEq(AMOUNT_COLLATERAL, userBalance);
        vm.stopPrank();
    }

    
    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(_dscEngine));
        emit CollateralRedeemed(user, user, _weth, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        _dscEngine.redeemCollateral(_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
     




    function testRevertsIfRedeemAmountIsZero () public {
         vm.startPrank(user);
         ERC20Mock(_weth).approve(address(_dscEngine), AMOUNT_COLLATERAL);
         _dscEngine.depositCollaterAndMintDsc(_weth, AMOUNT_COLLATERAL, amountToMint);
         vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
         _dscEngine.redeemCollateral(_weth, 0);
         vm.stopPrank();
    }

    

}

