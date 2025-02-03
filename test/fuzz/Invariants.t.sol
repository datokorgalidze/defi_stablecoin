// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import { Test, console } from "lib/forge-std/src/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import { Handler } from "./Handler.t.sol";



contract Invariant is StdInvariant,Test {

    DeployDSC  _deployer;
    DSCEngine  _dscEngine;
    DecentralizedStableCoin  _dsc;
    HelperConfig  _helperConfig;
    Handler _handler;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;


     function setUp() public {
          _deployer = new DeployDSC();
         (_dsc, _dscEngine, _helperConfig) = _deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = _helperConfig.activeNetworkConfig();
        _handler = new Handler(_dscEngine, _dsc);
        targetContract(address(_handler));
     }

     function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view{

        uint256 totalSupply = _dsc.totalSupply();

        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(_dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(_dscEngine));

        uint256 wethValue = _dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 btcValue = _dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("totalSupply: ", totalSupply);
        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", btcValue);
      //   console.log("times mint is called:", _handler.timesMintIsCalled());

        assert(wethValue + btcValue >= totalSupply);
     }
}