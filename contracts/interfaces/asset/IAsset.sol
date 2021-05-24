// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../lists/IScoreList.sol";
import "../dao/IDao.sol";
import "./IAssetERC20.sol";

interface IAsset is IScoreList, IDao, IAssetERC20 {

}
