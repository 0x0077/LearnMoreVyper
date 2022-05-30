# @version >=0.2

from vyper.interfaces import ERC20

@external
@view
def bytes32ToUint256(b: bytes32) -> uint256:
    return convert(b, uint256)

@external
@view
def bytes32ToAddress(b: bytes32) -> address:
    return convert(b, address)

@external
@view
def uint256ToBytes32(u: uint256) -> bytes32:
    return convert(u, bytes32)

@external
@view
def addressToBytes32(a: address) -> bytes32:
    return convert(a, bytes32)
