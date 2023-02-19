# @version 0.3.7
"""
@title ApeX Exchange V1 Pair
@author 0x0077
"""


from vyper.interfaces import ERC20
from vyper.interfaces import ERC165
from vyper.interfaces import ERC721

interface IERC721Metadata:
    def name() -> String[100]: view
    def symbol()-> String[100]: view
    def tokenURI(tokenId: uint256) -> String[300]: view
    def balanceOf(owner: address) -> uint256: view
    def ownerOf(tokenId: uint256) -> address: view
    def getApproved(tokenId: uint256) -> address: view
    def isApprovedForAll(owner: address, operator: address) -> bool: view
    def baseURI() -> String[300]: view
    def owner() -> address: view
    def setApprovalForAll(operator: address, approved: bool): nonpayable


interface IERC721Enumerable:
    def totalSupply() -> uint256: view
    def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256: view
    def tokenByIndex(index: uint256) -> uint256: view


interface IERC20Metadata:
    def name() -> String[100]: view
    def symbol()-> String[100]: view 
    def balanceOf(owner: address) -> uint256: view


interface ApeXExchangeV1Factory:
    def getPairDynamicInfo(pair: address) -> (uint256, uint256, uint256, uint256): view


interface ApeXExchangeV1Router:
    def getApeFee(_amountIn: uint256) -> uint256: view
    def apeFund() -> address: view


event Setup:
    state: bool
    router: address
    factory: address
    controller: indexed(address)
    nftContract: indexed(address)
    erc20Contract: indexed(address)

event SafeTransferETH:
    recipient: indexed(address)
    amount: uint256

event SafeTransferERC721NFT:
    recipient: indexed(address)
    nftContract: indexed(address)
    tokenId: uint256

event SafeTransferERC20:
    recipient: indexed(address)
    ERC20Contract: indexed(address)
    amount: uint256

event SetPrice:
    controller: indexed(address)
    oldPrice: uint256
    newPrice: uint256

event SetRiseCurve:
    controller: indexed(address)
    oldRise: uint256
    newRise: uint256

event SetSwapFee:
    controller: indexed(address)
    oldFee: uint256
    newFee: uint256

event AddLiquidity:
    sender: indexed(address)
    amount: uint256
    tokenId: uint256

event AddLiquidityETH:
    sender: indexed(address)
    amount: uint256

event AddLiquidityERC721NFT:
    sender: indexed(address)
    tokenId: uint256

event AddLiquidityEN:
    sender: indexed(address)
    amount: uint256
    tokenId: uint256

event AddLiquidityERC20Token:
    sender: indexed(address)
    amount: uint256

event RemoveLiquidity:
    sender: indexed(address)
    amount: uint256
    tokenId: uint256

event RemoveLiquidityEN:
    sender: indexed(address)
    amount: uint256
    tokenId: uint256

event RemoveLiquidityETH:
    sender: indexed(address)
    amount: uint256

event RemoveLiquidityERC20Token:
    sender: indexed(address)
    amount: uint256

event RemoveLiquidityERC721NFT:
    sender: indexed(address)
    tokenId: uint256

# Initialize contract
initialized: bool

MAX_SIZE: constant(uint256) = 30

router: public(address)
factory: public(address)
token0: public(address)
token1: public(address)
riseType: public(uint256)
riseCurve: public(uint256)
swapFee: public(uint256)
currentPrice: public(uint256)

# pair type
# 0: trade type
# 1: ETH type
# 2: ERC721 type
pairType: public(uint256)

blockTimestampLast: uint256
is_approved: HashMap[address, HashMap[address, bool]]
is_trade: public(bool)

owner: public(address)
controller: public(address)


@external
def __init__():
    self.owner = msg.sender


@view
@external
def getReserves() -> (uint256, uint256, uint256):
    token0Reserve: uint256 = IERC721Metadata(self.token0).balanceOf(self)
    token1Reserve: uint256 = 0
    if self.token1 == empty(address):
        token1Reserve = self.balance
    else:
        token1Reserve = IERC20Metadata(self.token1).balanceOf(self)
    
    return token0Reserve, token1Reserve, self.blockTimestampLast


@view
@external
def getTokenURI(_index: uint256) -> String[300]:
    tokenId: uint256 = IERC721Enumerable(self.token0).tokenOfOwnerByIndex(self, _index)
    tokenUri: String[300] = IERC721Metadata(self.token0).tokenURI(tokenId)
    return tokenUri


@view
@external
def getNftBalance() -> uint256:
    tokenBalanceOf: uint256 = IERC721Metadata(self.token0).balanceOf(self)
    return tokenBalanceOf
    

@view
@external
def getNftTokenIds(_index: uint256) -> uint256:
    tokenId: uint256 = IERC721Enumerable(self.token0).tokenOfOwnerByIndex(self, _index)
    return tokenId


@internal
def _safeTransferERC721NFT(_sender: address, _recipient: address, _tokenId: uint256) -> bool:

    _nftContract: address = self.token0

    raw_call(
        _nftContract,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(_sender, bytes32),
            convert(_recipient, bytes32),
            convert(_tokenId, bytes32)
        )
    )

    return True


@internal
def _safeTransferERC20Token(_sender: address, _recipient: address, _amountIn: uint256) -> bool:
    _seaRouter: address = self.router
    _erc20Token: address = self.token1

    if not self.is_approved[_seaRouter][_erc20Token]:
        response: Bytes[32] = raw_call(
            _erc20Token,
            concat(
                method_id("approve(address,uint256)"),
                convert(_seaRouter, bytes32),
                convert(max_value(uint256), bytes32)
            ),
            max_outsize=32
        )
        if len(response) != 0:
            assert convert(response, bool), " APEX:: UNVALID CONVERT"
        self.is_approved[_seaRouter][_erc20Token] = True
    
    raw_call(
        _erc20Token,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(_sender, bytes32),
            convert(_recipient, bytes32),
            convert(_amountIn, bytes32)
        )
    )

    return True


@external
@nonreentrant('lock')
def safeTransferETH(_recipient: address, _apeFeeFund: address, _amountIn: uint256, _newCurrentPrice: uint256):
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER"
    assert _recipient != empty(address), "APEX:: CAN ONLY BE A VALID ADDRESS"
    assert _amountIn > 0 and _amountIn <= self.balance, "APEX:: CANNOT SEND 0 AMOUNT"
    
    _apeFee: uint256 = ApeXExchangeV1Router(self.router).getApeFee(_amountIn)
    
    send(_recipient, _amountIn-_apeFee)
    send(_apeFeeFund, _apeFee)

    self.blockTimestampLast = block.timestamp
    self.currentPrice = _newCurrentPrice

    log SafeTransferETH(_recipient, _amountIn-_apeFee)


@external
@nonreentrant('lock')
def safeTransferERC721NFT(_recipient: address, _tokenId: uint256, _newCurrentPrice: uint256):
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER"
    assert _recipient != empty(address), "APEX:: CAN ONLY BE A VALID ADDRESS"

    successful: bool = self._safeTransferERC721NFT(self, _recipient, _tokenId)
    assert successful, "APEX:: UNVALID TRANSFER"
    self.blockTimestampLast = block.timestamp
    self.currentPrice = _newCurrentPrice

    log SafeTransferERC721NFT(_recipient, self.token0, _tokenId)


@external
@nonreentrant('lock')
def apeAggregatorSafeTransferERC721NFT(_recipient: address, _tokenId: uint256):
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER"
    assert _recipient != empty(address), "APEX:: CAN ONLY BE A VALID ADDRESS"

    successful: bool = self._safeTransferERC721NFT(self, _recipient, _tokenId)
    assert successful, "APEX:: UNVALID TRANSFER"
    self.blockTimestampLast = block.timestamp

    log SafeTransferERC721NFT(_recipient, self.token0, _tokenId)



@external
@nonreentrant('lock')
def safeBatchTransferERC721NFT(_recipient: address, _tokenIds: DynArray[uint256, MAX_SIZE], _newCurrentPrice: uint256):
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _recipient != empty(address), "APEX:: CAN ONLY BE A VALID ADDRESS"

    nftContract: address = self.token0
    bal: uint256 = IERC721Metadata(nftContract).balanceOf(self)
    assert bal >= len(_tokenIds), "APEX:: INSUFFICIENT BALANCE"

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            sucessful: bool = self._safeTransferERC721NFT(self, _recipient, _tokenIds[i])
            assert sucessful, "APEX:: UNVALID TRANSFER"
            self.blockTimestampLast = block.timestamp
            self.currentPrice = _newCurrentPrice
            log SafeTransferERC721NFT(_recipient, nftContract, _tokenIds[i])


@external
@nonreentrant('lock')
def safeTransferERC20(_recipient: address, _amountIn: uint256, _newCurrentPrice: uint256):
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _recipient != empty(address), "APEX:: CAN ONLY BE A VALID ADDRESS"
    assert _amountIn != 0, "APEX:: UNVALID AMOUNT"

    apeFee: uint256 = ApeXExchangeV1Router(self.router).getApeFee(_amountIn)
    fund: address = ApeXExchangeV1Router(self.router).apeFund()

    seaRouter: address = self.router
    erc20Token: address = self.token1
    assert erc20Token != empty(address), "APEX:: UNVALID TOKEN1 ADDRESS"

    exactValue: uint256 = _amountIn - apeFee

    transferSucessful: bool = self._safeTransferERC20Token(self, _recipient, exactValue)
    assert transferSucessful, "APEX:: UNVALID TRANSFER"
    
    transferForApeFundSucessful: bool = self._safeTransferERC20Token(self, fund, apeFee)
    assert transferForApeFundSucessful, "APEX:: UNVALID TRANSFER"


    self.blockTimestampLast = block.timestamp
    self.currentPrice = _newCurrentPrice
    log SafeTransferERC20(_recipient, erc20Token, _amountIn)


@payable
@external
def setup(
    _pairType: uint256,
    _router: address, 
    _factory: address, 
    _controller: address, 
    _token0: address, 
    _token1: address,
    _trade: bool) -> bool:
    assert not self.initialized, "APEX:: INVALID CALL"
    self.pairType = _pairType
    self.controller = _controller
    self.router = _router
    self.factory = _factory
    self.token0 = _token0
    self.token1 = _token1
    self.riseType, self.riseCurve, self.swapFee, self.currentPrice = ApeXExchangeV1Factory(_factory).getPairDynamicInfo(self)

    self.is_trade = _trade
    self.initialized = True

    IERC721Metadata(_token0).setApprovalForAll(_router, True)

    log Setup(self.initialized, _router, _factory, _controller, _token0, _token1)

    return True


@internal
def _updatePrice(_sender: address, _newPrice: uint256):

    oldPrice: uint256 = self.currentPrice
    self.currentPrice = _newPrice
    log SetPrice(_sender, oldPrice, _newPrice)


@internal
def _updateRiseCurve(_sender: address, _newRiseCurve: uint256):

    oldRiseCurve: uint256 = self.riseCurve
    self.riseCurve = _newRiseCurve
    log SetRiseCurve(_sender, oldRiseCurve, _newRiseCurve)


@internal
def _updateSwapFee(_sender: address, _newSwapFee: uint256):

    oldSwapFee: uint256 = self.swapFee
    self.swapFee = _newSwapFee
    log SetSwapFee(_sender, oldSwapFee, _newSwapFee)


@external
def updatePool(_newPrice: uint256, _newRiseCurve: uint256, _newSwapFee: uint256):
    assert self.controller == msg.sender, "APEX:: UNVALID CONTROLLER"
    assert _newPrice != 0, "APEX:: ENTER VALID AMOUNT"    
    assert _newRiseCurve != 0, "APEX:: ENTER VALID AMOUNT"   
    assert _newSwapFee != 0, "APEX:: ENTER VALID AMOUNT"   
    self._updatePrice(msg.sender, _newPrice)
    self._updateRiseCurve(msg.sender, _newRiseCurve)
    self._updateSwapFee(msg.sender, _newSwapFee)


@payable
@external
def addLiquidity(_tokenId: uint256) -> bool:
    assert msg.sender == self.router, "APEX:: UNVALID CONTROLLER"
    assert msg.value != 0, "APEX:: ENTER VALID AMOUNT"

    nftOwner: address = IERC721Metadata(self.token0).ownerOf(_tokenId)
    assert nftOwner == self.controller, "APEX:: FORK OWNER"
    depositSuceesful: bool = self._safeTransferERC721NFT(nftOwner, self, _tokenId)
    assert depositSuceesful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log AddLiquidity(self.controller, msg.value, _tokenId)
    return True


@payable
@external
def addLiquidityETH() -> bool:
    assert msg.sender == self.router, "APEX:: UNVALID CONTROLLER"
    assert msg.value != 0, "APEX:: ENTER VALID AMOUNT"

    self.blockTimestampLast = block.timestamp
    log AddLiquidityETH(self.controller, msg.value)
    return True


@payable
@external
def apeAggregatorAddLiquidityETH(_newCurrentPrice: uint256) -> bool:
    assert msg.sender == self.router, "APEX:: UNVALID CONTROLLER"
    assert msg.value != 0, "APEX:: ENTER VALID AMOUNT"

    self.blockTimestampLast = block.timestamp
    self.currentPrice = _newCurrentPrice
    log AddLiquidityETH(self.controller, msg.value)
    return True


@external
def apeAggregatorAddLiquidityERC20Token(_amountIn: uint256, _newCurrentPrice: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert self.token1 != empty(address), "APEX:: UNVALID ERC20 TOKEN"
    assert _amountIn != 0, "APEX:: ENTER UNVALID AMOUNT"

    transferSucessful: bool = self._safeTransferERC20Token(msg.sender, self, _amountIn)
    assert transferSucessful, "APEX:: UNVALID DEPOSIT"
    self.currentPrice = _newCurrentPrice
    self.blockTimestampLast = block.timestamp

    log AddLiquidityERC20Token(self.controller, _amountIn)
    return True


@external
def addLiquidityERC721NFT(_tokenId: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 

    nftOwner: address = IERC721Metadata(self.token0).ownerOf(_tokenId)
    assert nftOwner == self.controller, "APEX:: FORK OWNER"
    depositSuceesful: bool = self._safeTransferERC721NFT(self.controller, self, _tokenId)
    assert depositSuceesful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log AddLiquidityERC721NFT(self.controller, _tokenId)
    return True


@external
def addLiquidityEN(_amountIn: uint256, _tokenId: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert self.token1 != empty(address), "APEX:: UNVALID ERC20 TOKEN"
    assert _amountIn != 0, "APEX:: ENTER UNVALID AMOUNT"

    transferSucessful: bool = self._safeTransferERC20Token(msg.sender, self, _amountIn)
    assert transferSucessful, "APEX:: UNVALID DEPOSIT"
    nftOwner: address = IERC721Metadata(self.token0).ownerOf(_tokenId)
    assert nftOwner == self.controller, "APEX:: FORK OWNER"
    depositSuceesful: bool = self._safeTransferERC721NFT(self.controller, self, _tokenId)
    assert depositSuceesful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log AddLiquidityEN(self.controller, _amountIn, _tokenId)
    return True


@external
def addLiquidityERC20Token(_amountIn: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert self.token1 != empty(address), "APEX:: UNVALID ERC20 TOKEN"
    assert _amountIn != 0, "APEX:: ENTER UNVALID AMOUNT"

    transferSucessful: bool = self._safeTransferERC20Token(msg.sender, self, _amountIn)
    assert transferSucessful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log AddLiquidityERC20Token(self.controller, _amountIn)
    return True


@external
def removeLiquidity(_amountIn: uint256, _tokenId: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _amountIn <= self.balance, "APEX:: UNVALID AMOUNT P"

    removeSuceesful: bool = self._safeTransferERC721NFT(self, self.controller, _tokenId)
    assert removeSuceesful, "APEX:: UNVALID DEPOSIT"
    send(self.controller, _amountIn)
    self.blockTimestampLast = block.timestamp
    log RemoveLiquidity(self.controller, _amountIn, _tokenId)
    return True


@external
def removeLiquidityEN(_amountIn: uint256, _tokenId: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, " APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _amountIn <= self.balance, "APEX:: UNVALID AMOUNT"

    transferSucessful: bool = self._safeTransferERC20Token(self, self.controller, _amountIn)
    assert transferSucessful, "APEX:: UNVALID DEPOSIT"
    removeSuceesful: bool = self._safeTransferERC721NFT(self, self.controller, _tokenId)
    assert removeSuceesful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log RemoveLiquidityEN(self.controller, _amountIn, _tokenId)
    return True


@external
def removeLiquidityETH(_amountIn: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _amountIn <= self.balance, "APEX:: UNVALID AMOUNT"
    send(self.controller, _amountIn)
    self.blockTimestampLast = block.timestamp

    log RemoveLiquidityETH(self.controller, _amountIn)
    return True


@external
def removeLiquidityERC20(_amountIn: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 
    assert _amountIn != 0, "APEX:: UNVALID AMOUNT"
    
    transferSucessful: bool = self._safeTransferERC20Token(self, self.controller, _amountIn)
    assert transferSucessful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log RemoveLiquidityERC20Token(self.controller, _amountIn)
    return True


@external
def removeLiquidityERC721NFT(_tokenId: uint256) -> bool:
    assert msg.sender != empty(address) and msg.sender == self.router, "APEX:: CAN ONLY BE CALLED BY ROUTER" 

    removeSuceesful: bool = self._safeTransferERC721NFT(self, self.controller, _tokenId)
    assert removeSuceesful, "APEX:: UNVALID DEPOSIT"
    self.blockTimestampLast = block.timestamp

    log RemoveLiquidityERC721NFT(self.controller, _tokenId)
    return True
