// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import { Test, console } from "lib/forge-std/src/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import { ERC20Mock } from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";



contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    // uint256  public timesMintCalled;
    // address[] usersWithCollateralDeposited;

    constructor (DSCEngine  _dscEngine,  DecentralizedStableCoin  _dsc ) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }



    function mintAndDepositCollateral (uint256 collateralSeed, uint256 amountCollateral ) public{
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // usersWithCollateralDeposited.push(msg.sender);
    }


    function redeemCollateral (uint256 collateralSeed, uint256 amountCollateral) public {
           ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
           uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
           amountCollateral = bound(amountCollateral, 0, maxCollateral);
           if (amountCollateral == 0 ){
              return;
           }
           vm.prank(msg.sender);
           dscEngine.redeemCollateral(address(collateral), amountCollateral);
    } 





    function _getCollateralFromSeed (uint256 collateralSeed) private view returns (ERC20Mock){
          if(collateralSeed % 2 == 0 ){
            return weth;
          }
          return wbtc;
    }
}


