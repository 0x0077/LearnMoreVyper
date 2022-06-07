# @version 0.2

from vyper.interfaces import ERC20

USDT: constant(address) = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd
PANCAKE_ROUTER: constant(address) = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1
WBNB: constant(address) = 0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F

owner: public(address)
receiver: public(address)
is_approved: HashMap[address, HashMap[address, bool]]

@external
def __init__(_receiver: address):
    self.owner = msg.sender
    self.receiver = _receiver

@external
def swap(_amountIn: uint256) -> bool:

    amount: uint256 = ERC20(USDT).balanceOf(msg.sender)

    if amount != 0:
        response: Bytes[32] = raw_call(
            USDT,
            concat(
                method_id("transferFrom(address,address,uint256)"),
                convert(msg.sender, bytes32),
                convert(self, bytes32),
                convert(_amountIn, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)

    amount = ERC20(USDT).balanceOf(self)

    if not self.is_approved[PANCAKE_ROUTER][USDT]:
        response: Bytes[32] = raw_call(
            USDT,
            concat(
                method_id("approve(address,uint256)"),
                convert(PANCAKE_ROUTER, bytes32),
                convert(MAX_UINT256, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)
        self.is_approved[PANCAKE_ROUTER][USDT] = True

    raw_call(
        PANCAKE_ROUTER,
        concat(
            method_id("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            convert(amount, bytes32),
            EMPTY_BYTES32,
            convert(160, bytes32),
            convert(self.receiver, bytes32),
            convert(block.timestamp, bytes32),
            convert(2, bytes32),
            convert(USDT, bytes32),
            convert(WBNB, bytes32)
        )
    )

    return True

