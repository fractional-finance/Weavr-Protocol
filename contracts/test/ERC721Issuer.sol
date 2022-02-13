// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

contract ERC721Issuer is ERC721 {
  constructor() {
    ERC721.initialize("NFT ERC721", "721");
  }

  function mint(address to, uint256 tokenId) public {
      _safeMint(to, tokenId);
  }
}
