# @version ^0.2

from vyper.interfaces import ERC20

interface UniswapFactory:
    def allPairs(input: uint256) -> address: nonpayable
    def allPairsLength() -> uint256: view

interface UniswapRouter:
    def swapExactTokensForTokens(
        amountIn: uint256,
        amountOutMin: uint256,
        path: address[3],
        to: address,
        deadline: uint256
    ) -> uint256[3]: nonpayable

interface UniswapV2Pair:
    def token0() -> address: view
    def token1() -> address: view
    def getReserves() -> uint256[3]: view

interface TokenInfo:
    def name() -> String[20]: view
    def symbol() -> String[20]: view

UNISWAP_ROUTER: constant(address) = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
UNISWAP_FACTORY: constant(address) = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
WETH: constant(address) = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
USDC: constant(address) = 0xeb8f08a975Ab53E34D8a0330E0D34de942C95926

owner: public(address)
receiver: public(address)
is_approved: HashMap[address, HashMap[address, bool]]
is_win: HashMap[uint256, bool]
start_rates: public(uint256)
end_rates: public(uint256)

@external
def __init__(_receiver: address):
    self.owner = msg.sender
    self.receiver = _receiver

@internal
@view
def getPairsLength() -> uint256:
    """
    @notice From Uniswap factory get last pair length
    @return uint256 pair length
    """
    pl: uint256 = UniswapFactory(UNISWAP_FACTORY).allPairsLength()
    return pl

@internal
@view
def getPairsResponse() -> address:
    """
    @notice From Uniswap factory get new pair address 
    @return address pairAddress 
    """

    _response: Bytes[128] = raw_call(
        UNISWAP_FACTORY,
        concat(
            method_id("allPairs(uint256)"),
            convert(self.getPairsLength()-1, bytes32)
        ),
        max_outsize=128,
        is_static_call=True
    )
    pairAddress: address = extract32(_response, 0, output_type=address)
    return pairAddress

@internal
@view
def getTokenAddress() -> (address, address, bool):
    """
    @notice From pairAddress get token0/token1 info
    @return address token0/token1
    """
    UniswapV2PairAddress: address = self.getPairsResponse()
    get_token0: address = UniswapV2Pair(UniswapV2PairAddress).token0()
    get_token1: address = UniswapV2Pair(UniswapV2PairAddress).token1()
    exact_token0: address = ZERO_ADDRESS
    exact_token1: address = ZERO_ADDRESS

    if get_token0 != WETH:
        assert get_token1 == WETH, "token1 not ETH"
        exact_token0 = get_token0
        exact_token1 = get_token1
    else:
        exact_token0 = get_token1
        exact_token1 = get_token0

    return exact_token0, exact_token1, True

@external
@view
def getTokenInfo(tokenAddress: address) -> (String[20], String[20]):
    """
    @notice get Token name/symbol
    @return string tokenName/tokenSymbol
    """
    assert self.getTokenAddress()[2] == True, "get exact address"
    tokenName: String[20] = TokenInfo(tokenAddress).name()
    tokenSymbol: String[20] = TokenInfo(tokenAddress).symbol()

    return tokenName, tokenSymbol

@external
@view
def getExactToken() -> address:
    """
    @notice get exact token address
    @return address ExactToken
    """
    return self.getTokenAddress()[0]

@internal
@view
def getTokenLiquidity(_coin: address, _amountIn: uint256) -> (uint256, uint256):
    """
    @notice get token expected amount and ETH liquidity reserves
    @return uint256 ethReserve and best_expected
    """
    UniswapPairAddress: address = self.getPairsResponse()

    getToken0: address = UniswapV2Pair(UniswapPairAddress).token0()
    getTokenReserves: uint256[3] = UniswapV2Pair(UniswapPairAddress).getReserves()
    getReserve0: uint256 = getTokenReserves[0]
    getReserve1: uint256 = getTokenReserves[1]

    best_expected: uint256 = 0
    
    # check the rates on uniswap
    _response: Bytes[128] = raw_call(
        UNISWAP_ROUTER,
        concat(
            method_id("getAmountsOut(uint256,address[])"),
            convert(_amountIn, bytes32),
            convert(64, bytes32),
            convert(3, bytes32),
            convert(USDC, bytes32),
            convert(WETH, bytes32),
            convert(_coin, bytes32)
        ),
        max_outsize=128,
        is_static_call=True
    )
    expected: uint256 = convert(slice(_response, 96, 32), uint256)
    if expected > best_expected:
        best_expected = expected

    ethReserve: uint256 = 0
    if getToken0 != WETH:
        ethReserve = getReserve1
    else:
        ethReserve = getReserve0

    return ethReserve, best_expected

@internal
@view
def getBestExpectedRates(amountIn: uint256) -> uint256:
    """
    @notice get token rates
    @return uint256 bestExpectedRates
    """
    coin: address = self.getTokenAddress()[0]
    bestExpectedRates: uint256 = self.getTokenLiquidity(coin, amountIn)[1]
    return bestExpectedRates

@external
def swapper(desiredCoin: address, amountIn: uint256) -> bool:
    """
    @notice Swaps USDC to coins using Uniswap
    @return bool success
    """
    
    amount: uint256 = ERC20(WETH).balanceOf(msg.sender)

    if amount != 0:
        response: Bytes[32] = raw_call(
            WETH,
            concat(
                method_id("transferFrom(address,address,uint256)"),
                convert(msg.sender, bytes32),
                convert(self, bytes32),
                convert(amountIn, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)

    amount = ERC20(WETH).balanceOf(self)

    if not self.is_approved[UNISWAP_ROUTER][WETH]:
        response: Bytes[32] = raw_call(
            WETH,
            concat(
                method_id("approve(address,uint256)"),
                convert(UNISWAP_ROUTER, bytes32),
                convert(MAX_UINT256, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)
        self.is_approved[UNISWAP_ROUTER][USDC] = True

    raw_call(
        UNISWAP_ROUTER,
        concat(
            method_id("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            convert(amount, bytes32),
            EMPTY_BYTES32,
            convert(160, bytes32),
            convert(self.receiver, bytes32),
            convert(block.timestamp, bytes32),
            convert(2, bytes32),
            convert(WETH, bytes32),
            convert(desiredCoin, bytes32)
        )
    )
    self.start_rates = self.getBestExpectedRates(amountIn)

    return True

@external
def sell(desiredCoin: address, amountIn: uint256) -> bool:
    """
    @notice Using expected token swap USDC
    @return bool success
    """
    # assert self.start_rates > self.getBestExpectedRates(amountIn), "Not win, only wait"
    amount: uint256 = ERC20(desiredCoin).balanceOf(msg.sender)
    
    if amount != 0:
        response: Bytes[32] = raw_call(
            desiredCoin,
            concat(
                method_id("transferFrom(address,address,uint256)"),
                convert(msg.sender, bytes32),
                convert(self, bytes32),
                convert(amountIn, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)

    amount = ERC20(desiredCoin).balanceOf(self)

    if not self.is_approved[UNISWAP_ROUTER][desiredCoin]:
        response: Bytes[32] = raw_call(
            desiredCoin,
            concat(
                method_id("approve(address,uint256)"),
                convert(UNISWAP_ROUTER, bytes32),
                convert(MAX_UINT256, bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool)
        self.is_approved[UNISWAP_ROUTER][desiredCoin] = True

    raw_call(
        UNISWAP_ROUTER,
        concat(
            method_id("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"),
            convert(amount, bytes32),
            EMPTY_BYTES32,
            convert(160, bytes32),
            convert(self.receiver, bytes32),
            convert(block.timestamp, bytes32),
            convert(2, bytes32),
            convert(desiredCoin, bytes32),
            convert(WETH, bytes32),
        )
    )

    return True