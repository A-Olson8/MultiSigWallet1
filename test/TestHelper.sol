// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./mocks/MockERC20.sol";
import "./mocks/MockERC721.sol";

interface IMultiSig {
    function depositERC20(address _tokenAddress, uint _amount) external;
    function depositNFT(address _tokenAddress, uint _tokenId) external;
    function approveTransaction(uint128 _txIndex) external;
    function revokeApproval(uint128 _txIndex) external;
    function requestEthTransfer(address _to, uint _value, bytes memory _data) external;
    function requestErc20Transfer(address _to, address _contractAddress, uint _value) external;
    function requestNFTTransfer(address _to, address _contractAddress, uint _tokenId) external;
    function executeEthTransaction(uint128 _txIndex) external;
    function executeErc20Transaction(uint128 _txIndex) external;
    function executeNFTTransaction(uint128 _txIndex) external;
}

contract MultiSigTest2 { 

    // used to transfer NFT token to mulitSig wallet
    function transferNFT(address _nftContract, address _receiver, uint _tokenId) public {
        IERC721(_nftContract).approve(_receiver, _tokenId);
        IMultiSig(_receiver).depositNFT(_nftContract, _tokenId);
    }

    // The two functions below are for approving and revoking transfers
    function approveTransfer(address _wallet, uint128 _index) public {
        IMultiSig(_wallet).approveTransaction(_index);
    }

    function revokeApproveTransfer(address _wallet, uint128 _index) public {
        IMultiSig(_wallet).revokeApproval(_index);
    }

    // The three functions below are for reqeusting transfers
    function requestEthTransfer(address _wallet, address _to, uint _value) external {
        IMultiSig(_wallet).requestEthTransfer(_to, _value, "");
    }

    function requestNFTTransfer(address _wallet, address _contractAddress, address _to, uint _tokenId) external{
        IMultiSig(_wallet).requestNFTTransfer(_to, _contractAddress, _tokenId);
    }

    function requestERC20Transfer(address _wallet, address _contractAddress, address _to, uint _value) external{
        IMultiSig(_wallet).requestErc20Transfer(_to, _contractAddress, _value);
    }

    // The three functions below are for executing transfers (within multiSig wallet)
    function executeEthTransaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeEthTransaction(_txIndex);
    }

    function executeErc20Transaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeErc20Transaction(_txIndex);
    }

    function executeNFTTransaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeNFTTransaction(_txIndex);
    }

    // used to receive nft
    function onERC721Received(
        address operator, 
        address from, 
        uint256 tokenId, 
        bytes calldata data) 
        external pure
        returns (bytes4){  
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

contract MultiSigTest3 {

    // used to transfer Erc20 token to mulitSig wallet
    function transferERC20(address _tokenContract, address _receiver, uint _amount) external {
        IERC20(_tokenContract).approve(_receiver, _amount);
        IMultiSig(_receiver).depositERC20(_tokenContract, _amount);
    }

    // The two functions below are for approving and revoking transfers
    function approveTransfer(address _wallet, uint128 _index) public {
        IMultiSig(_wallet).approveTransaction(_index);
    }

    function revokeApproveTransfer(address _wallet, uint128 _index) public {
        IMultiSig(_wallet).revokeApproval(_index);
    }

    // The three functions below are for reqeusting transfers
    function requestEthTransfer(address _wallet, address _to, uint _value) external {
        IMultiSig(_wallet).requestEthTransfer(_to, _value, "");
    }

    function requestNFTTransfer(address _wallet, address _contractAddress, address _to, uint _tokenId) external{
        IMultiSig(_wallet).requestNFTTransfer(_to, _contractAddress, _tokenId);
    }

    function requestERC20Transfer(address _wallet, address _contractAddress, address _to, uint _value) external{
        IMultiSig(_wallet).requestErc20Transfer(_to, _contractAddress, _value);
    }

    // The three functions below are for executing transfers (within multiSig wallet)
    function executeEthTransaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeEthTransaction(_txIndex);
    }

    function executeErc20Transaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeErc20Transaction(_txIndex);
    }

    function executeNFTTransaction(address _wallet, uint128 _txIndex) external {
        IMultiSig(_wallet).executeNFTTransaction(_txIndex);
    }

    receive() external payable {}
}

contract MultiSigTest4 {

    function checkOnlyOwner(address _wallet, uint128 _index) public {
        IMultiSig(_wallet).approveTransaction(_index);
    }
}