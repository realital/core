pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC721/IERC721.sol";

interface IRetaNft is IERC721 {
  function totalAbility(uint256 tokenId) external view returns (uint256);

  // function mint(
  //     address to, string memory nftName, uint quality, uint256 power, string memory res, address author
  // ) external returns(uint256 tokenId);

  // function burn(uint256 tokenId) external;

  // function getFeeToken() external view returns (address);

  // function getNft(uint256 id) external view returns (LibPart.NftInfo memory);

  // function getRoyalties(uint256 tokenId) external view returns (LibPart.Part[] memory);

  // function sumRoyalties(uint256 tokenId) external view returns(uint256);

  // function upgradeNft(uint256 nftId, uint256 materialNftId) external;

  // function getPower(uint256 tokenId) external view returns (uint256);

  // function getLevel(uint256 tokenId) external view returns (uint256);
}
