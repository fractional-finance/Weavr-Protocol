// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../asset/IntegratedLimitOrderDex.sol";

contract StubbedDex is ERC721 {

  constructor() ERC721("NFT ERC721", "FFTKN") {}

  function mint(address to, uint256 tokenId) public {
      _safeMint(to, tokenId);
  }
}