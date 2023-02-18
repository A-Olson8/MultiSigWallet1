// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("Orf Token", "ORF") {

    }

    function safeMint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }

    
}