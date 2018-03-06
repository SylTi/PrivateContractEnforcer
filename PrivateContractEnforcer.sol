pragma solidity ^0.4.18;


import "../ECRecovery.sol";
import "../math/SafeMath.sol";

/**
 * @title PrivateContractEnforcer
 * @author SylTi
 * @dev This kind of construct allows for a smart contract between two entities to remains private as long as they cooperate with each other. 
 *      Cooperation is incentived by the use of a collateral
 */

contract PrivateContractEnforcer {
  
  using ECRecovery for bytes32;
  using SafeMath for uint256;
  address user1;
  address user2;
  uint amountToMatch;
  uint collateralPercentage = 1; //percentage of bet used as collateral. This is necessary to incentivize voluntary release of funds
  bool finalized;

  event LogContractSettlement(uint balance, address deployedAddress);
  event LogDeposit(address depositer, uint amount);

  modifier isUser() {
    require(msg.sender == user1 || msg.sender == user2);
    _;
  }

  function executeContract(bytes32 hashed, bytes signature, bytes code) public isUser {

    require(isContractValid(hashed, signature, code));
    address deployedAddress;
    //create contract in assembly, and jump if deployment failed: no code at address
    assembly {
      deployedAddress := create(0, add(code, 0x20), mload(code))
      switch iszero(extcodesize(deployedAddress))
        case 1 { revert(0, 0) } // throw if contract failed to deploy
    }
    LogContractSettlement(this.balance, deployedAddress);
    assert(deployedAddress.call.gas(200000).value(this.balance)(bytes4(keccak256("execute()"))));
    finalized = true;
  }

  function isContractValid(bytes32 hashed, bytes signature, bytes code) public view returns (bool) {
    address signer;
    bytes32 proof;
    
    signer = hashed.recover(signature);
    if (signer != user1 && signer != user2) revert();
    proof = keccak256(code);
    return (proof == hashed);
  }

  function releasePayment() public isUser {
    if (msg.sender == user1) {
      assert(user2.send(this.balance.sub(this.balance.div(100).mul(collateralPercentage))));
      assert(user1.send(this.balance));
    }
    else if (msg.sender == user2) {
      assert(user1.send(this.balance.sub(this.balance.div(100).mul(collateralPercentage))));
      assert(user2.send(this.balance));
    }
    finalized = true;
  }

  function resetContract() public isUser {
    require(finalized);
    amountToMatch = 0;
    user1 = address(0);
    user2 = address(0);
  }

  function () public payable {
    require(user1 == address(0) || user2 == address(0));
    require(msg.value > 0);
    if (user1 == address(0)) {
      user1 = msg.sender;
      amountToMatch = msg.value;
    }
    else {
      require(msg.value == amountToMatch);
      require(msg.sender != user1);
      user2 = msg.sender;
      assert(this.balance == amountToMatch.mul(2));
    }
    LogDeposit(msg.sender, msg.value);
  }
}
