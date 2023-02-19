# @version 0.3.7
"""
@title ApeX Exchange V1 Router
@author 0x0077
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC165
from vyper.interfaces import ERC721

MAX_SIZE: constant(uint256) = 30

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

interface IERC721Enumerable:
    def totalSupply() -> uint256: view
    def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256: view
    def tokenByIndex(index: uint256) -> uint256: view
    def supportsInterface(interfaceId: bytes4) -> bool: view

interface ApeXExchangeV1Pair:
    def token0() -> address: view
    def token1() -> address: view
    def controller() -> address: view
    def currentPrice() -> uint256: view
    def swapFee() -> uint256: view
    def riseType() -> uint256: view
    def riseCurve() -> uint256: view
    def pairType() -> uint256: view
    def is_trade() -> bool: view

interface ApeXExchangeV1Libray:
    def pairBuyBasicInfo(_pair: address, _numberItems: uint256) -> (uint256, uint256, uint256): view
    def pairSellBasicInfo(_pair: address, _numberItems: uint256) -> (uint256, uint256, uint256): view
    def getInputValue(
        _riseType: uint256,
        _pair: address,
        _numberItems: uint256,
        _currentPrice: uint256,
        _riseCurve: uint256,
        _swapFee: uint256) -> (uint256, uint256, uint256): view
    def getOutputValue(
        _riseType: uint256,
        _pair: address,
        _numberItems: uint256,
        _currentPrice: uint256,
        _riseCurve: uint256,
        _swapFee: uint256) -> (uint256, uint256, uint256): view

event SwapETHForNFT:
    pair: indexed(address)
    token0: indexed(address)
    recipient: indexed(address)
    buyAmount: uint256
    tokenIds: DynArray[uint256, MAX_SIZE]
    
event SwapNFTForETH:
    pair: indexed(address)
    token0: indexed(address)
    recipient: indexed(address)
    tokenIds: DynArray[uint256, MAX_SIZE]

event SwapERC20TokenForERC721:
    pair: indexed(address)
    sender: address
    numberItems: uint256
    tokenIds: DynArray[uint256, MAX_SIZE]

event SwapERC721ForERC20Token:
    pair: indexed(address)
    sender: address
    numberItems: uint256
    tokenIds: DynArray[uint256, MAX_SIZE]

event AddLiquidity:
    pair: indexed(address)
    token0: indexed(address)
    sender: indexed(address)
    amountIn: uint256
    tokenId: uint256

event AddLiquidityEN:
    pair: indexed(address)
    token0: indexed(address)
    token1: address
    sender: indexed(address)
    amountIn: uint256
    tokenId: uint256

event AddLiquidityETH:
    pair: indexed(address)
    sender: indexed(address)
    amountIn: uint256

event AddLiquidityERC20:
    pair: indexed(address)
    sender: indexed(address)
    amountIn: uint256

event AddLiquidityERC721NFT:
    pair: indexed(address)
    token0: indexed(address)
    sender: indexed(address)
    tokenId: uint256

event RemoveLiquidity:
    pair: indexed(address)
    token0: indexed(address)
    sender: indexed(address)
    amountIn: uint256
    tokenId: uint256

event RemoveLiquidityEN:
    pair: indexed(address)
    token0: indexed(address)
    token1: address
    sender: indexed(address)
    amountIn: uint256
    tokenId: uint256

event RemoveLiquidityETH:
    pair: indexed(address)
    sender: indexed(address)
    amountIn: uint256

event RemoveLiquidityERC20:
    pair: indexed(address)
    sender: indexed(address)
    amountIn: uint256

event RemoveLiquidityERC721NFT:
    pair: indexed(address)
    token0: indexed(address)
    sender: indexed(address)
    tokenId: uint256

event UpdateNewFactory:
    sender: indexed(address)
    oldFactory: indexed(address)
    newFactory: indexed(address)  

event UpdateNewLibrary:
    sender: indexed(address)
    oldLibrary: indexed(address)
    newLibrary: indexed(address)  

event UpdateNewFund:
    sender: indexed(address)
    oldFund: indexed(address)
    newFund: indexed(address) 

event UpdateNewFee:
    sender: indexed(address)
    oldFee: uint256
    newFee: uint256

is_approved: HashMap[address, HashMap[address, bool]]
pairForItems: HashMap[address, uint256]

apeFee: public(uint256)
factory: public(address)
owner: public(address)
apeFund: public(address)
library: public(address)

a: public(uint256)
b: public(address)

@external
def __init__(_fee: uint256, _library: address):
    self.owner = msg.sender
    self.factory = empty(address)
    self.apeFee = _fee
    self.apeFund = msg.sender
    self.library = _library


@view
@internal
def checkDeadline(_deadline: uint256) -> bool:
    assert block.timestamp <= _deadline, "APEX:: DEADLINE PASSED"

    return True


@internal
def _safeTransferERC721NFT(_pair: address, _sender: address, _recipient: address, _tokenId: uint256) -> bool:

    _nftContract: address = ApeXExchangeV1Pair(_pair).token0()

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
def _safeTransferERC20Token(_tokenAddress: address, _sender: address, _recipient: address, amountIn: uint256) -> bool:
    
    if not self.is_approved[self][_tokenAddress]:
        _response: Bytes[32] = raw_call(
            _tokenAddress,
            concat(
                method_id("approve(address,uint256)"),
                convert(self, bytes32),
                convert(max_value(uint256), bytes32)
            ),
            max_outsize=32
        )
        if len(_response) != 0:
            assert convert(_response, bool)
        self.is_approved[self][_tokenAddress] = True

    raw_call(
        _tokenAddress,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(_sender, bytes32),
            convert(_recipient, bytes32),
            convert(amountIn, bytes32)
        )
    )

    return True



@internal
def _swapETHForNFT(
    _pair: address,
    _numberItems: uint256) -> (bool, uint256, uint256, uint256):
    assert _numberItems != 0, "APEX:: UNVALID ITEMS"

    _newCurrentPrice: uint256 = 0
    _inputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _newCurrentPrice, _inputValue, _protocolFee = ApeXExchangeV1Libray(self.library).pairBuyBasicInfo(_pair, _numberItems)

    return True, _newCurrentPrice, _inputValue, _protocolFee


@internal
def _swapNFTForETH(
    _pair: address,
    _recipient: address, 
    _numberItems: uint256, 
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> (bool, uint256, uint256):
    assert _numberItems == len(_tokenIds), "APEX:: UNVALID ITEMS"

    _newCurrentPrice: uint256 = 0
    _outputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _newCurrentPrice, _outputValue, _protocolFee = ApeXExchangeV1Libray(self.library).pairSellBasicInfo(_pair, _numberItems)

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            _transferSuccessful: bool = self._safeTransferERC721NFT(
                _pair,
                _recipient,
                _pair,
                _tokenIds[i]
            )
            assert _transferSuccessful, "APEX:: UNVALID TRANSFER"

    return True, _outputValue, _newCurrentPrice


@internal
def _swapERC20ForERC721(
    _pair: address,
    _tokenAddress: address,
    _sender: address,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> bool:

    _newCurrentPrice: uint256 = 0
    _inputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _newCurrentPrice, _inputValue, _protocolFee = ApeXExchangeV1Libray(self.library).pairBuyBasicInfo(_pair, _numberItems)

    _transferERC20Successful: bool = self._safeTransferERC20Token(_tokenAddress, _sender, _pair, _inputValue)
    assert _transferERC20Successful, "APEX:: UNVALID TRANSFER FOR SEND"

    _transferERC20ForApeFundSuccessful: bool = self._safeTransferERC20Token(_tokenAddress, _sender, self.apeFund, _protocolFee)
    assert _transferERC20ForApeFundSuccessful, "APEX:: UNVALID TRANSFER FOR APE"

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _pair,
                concat(
                    method_id("safeTransferERC721NFT(address,uint256,uint256)"),
                    convert(_sender, bytes32),
                    convert(_tokenIds[i], bytes32),
                    convert(_newCurrentPrice, bytes32)
                )
            )

    return True
    

@internal
def _swapERC721ForERC20(
    _pair: address,
    _sender: address,
    _numberItems: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE]) -> bool:

    _newCurrentPrice: uint256 = 0
    _outputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _newCurrentPrice, _outputValue, _protocolFee = ApeXExchangeV1Libray(self.library).pairSellBasicInfo(_pair, _numberItems)

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            _transferSuccessful: bool = self._safeTransferERC721NFT(
                _pair,
                _sender,
                _pair,
                _tokenIds[i]
            )
            assert _transferSuccessful, "APEX:: UNVALID TRANSFER"

    raw_call(
        _pair,
        concat(
            method_id("safeTransferERC20(address,uint256,uint256)"),
            convert(_sender, bytes32),
            convert(_outputValue, bytes32),
            convert(_newCurrentPrice, bytes32)
        )
    )

    return True


@payable
@external
@nonreentrant('lock')
def apeAggregatorSwapETHForERC721(
    _nftAddress: address,
    _nftRecipient: address,
    _inputAmount: uint256,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256):

    assert _nftAddress != empty(address) and _nftRecipient != empty(address), "APEX:: UNVALID ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID ITEMS"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"
    assert msg.value == _inputAmount, "APEX:: INSUFFICIENT BALANCE"

    _numberItems: uint256 = len(_tokenIds)
    _swapSuccessful: bool = False
    _inputValue: uint256 = 0
    _newCurrentPrice: uint256 = 0
    _protocolFee: uint256 = 0
    _pairList: DynArray[address, MAX_SIZE] = []

    for ids in _tokenIds:
        _pairOf: address = IERC721Metadata(_nftAddress).ownerOf(ids)
        if _pairOf not in _pairList:
            _pairList.append(_pairOf)
        self.pairForItems[_pairOf] += 1

    _payValue: uint256 = 0

    for pl in _pairList:
        _num: uint256 = self.pairForItems[pl]

        _swapSuccessful, _newCurrentPrice, _inputValue, _protocolFee = self._swapETHForNFT(pl, _num)
        assert _swapSuccessful, "APEX:: UNVALID SWAP"
        assert msg.value >= _inputValue, "APEX:: UNVALID PAY"
        
        _payValue += _inputValue
        _exactValue: uint256 = _inputValue - _protocolFee

        send(self.apeFund, _protocolFee)
        raw_call(
            pl,
            concat(
                method_id("apeAggregatorAddLiquidityETH(uint256)"),
                convert(_newCurrentPrice, bytes32) 
            ),
            value=_exactValue
        )

        self.pairForItems[pl] = 0

        log SwapETHForNFT(pl, _nftAddress, _nftRecipient, _inputValue, _tokenIds)

    for ids in _tokenIds:
        _pairOf: address = IERC721Metadata(_nftAddress).ownerOf(ids)

        _response: Bytes[32] = raw_call(
            _pairOf,
            concat(
                method_id("apeAggregatorSafeTransferERC721NFT(address,uint256)"),
                convert(msg.sender, bytes32),
                convert(ids, bytes32)
            ),
            max_outsize=32
        )
        if len(_response) != 0:
            assert convert(_response, bool), "E"
    
    if _inputAmount > _payValue:
        _slippage: uint256 = _inputAmount - _payValue
        assert _slippage > 0, "APEX:: UNVALID SLIPPAGE"
        send(_nftRecipient, _slippage)


@payable
@external
@nonreentrant('lock')
def swapETHForERC721(
    _pair: address,
    _nftAddress: address, 
    _nftRecipient: address,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert msg.sender != empty(address) and _pair != empty(address) and _nftRecipient != empty(address), "APEX:: UNVALIE ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID ITEMS"
    assert ApeXExchangeV1Pair(_pair).pairType() != 1, "APEX:: PAIR TRADE TYPE"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _numberItems: uint256 = len(_tokenIds)
    _swapSuccessful: bool = False
    _inputValue: uint256 = 0
    _newCurrentPrice: uint256 = 0
    _protocolFee: uint256 = 0
    _swapSuccessful, _newCurrentPrice, _inputValue, _protocolFee = self._swapETHForNFT(_pair, _numberItems)
    assert _swapSuccessful, "APEX:: UNVALID SWAP"
    assert msg.value >= _inputValue, "APEX:: UNVALID PAY"

    _exactValue: uint256 = _inputValue - _protocolFee

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _pair,
                concat(
                    method_id("safeTransferERC721NFT(address,uint256,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(_tokenIds[i], bytes32),
                    convert(_newCurrentPrice, bytes32)
                )
            )

    send(self.apeFund, _protocolFee)
    raw_call(_pair, method_id("addLiquidityETH()"), value=_exactValue)
    
    # Slippage value
    # Return the extra amount
    if msg.value > _inputValue:
        _slippage: uint256 = msg.value - _inputValue
        assert _slippage > 0, "APEX:: UNVALID SLIPPAGE"
        send(_nftRecipient, _slippage)

    log SwapETHForNFT(_pair, _nftAddress, _nftRecipient, _inputValue, _tokenIds)
    return True


@external
@nonreentrant('lock')
def swapERC721ForETH(
    _pair: address, 
    _nftAddress: address,
    _ethRecipient: address, 
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert msg.sender != empty(address) and _ethRecipient != empty(address) and _pair != empty(address) and _nftAddress != empty(address), "APEX:: UNVALIE ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID ITEMS"
    assert ApeXExchangeV1Pair(_pair).pairType() != 2, "APEX:: PAIR TRADE TYPE"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _outputValue: uint256 = 0
    _newCurrentPrice: uint256 = 0
    _swapSuccessful: bool = False
    _numberItems: uint256 = len(_tokenIds)

    _swapSuccessful, _outputValue, _newCurrentPrice = self._swapNFTForETH(_pair, msg.sender, _numberItems, _tokenIds)
    assert _swapSuccessful, "APEX:: UNVALID SWAP"

    raw_call(
        _pair,
        concat(
            method_id("safeTransferETH(address,address,uint256,uint256)"),
            convert(_ethRecipient, bytes32),
            convert(self.apeFund, bytes32),
            convert(_outputValue, bytes32),
            convert(_newCurrentPrice, bytes32)
        )
    )

    log SwapNFTForETH(_pair, _nftAddress, _ethRecipient, _tokenIds)
    return True


@external
@nonreentrant('lock')
def swapERC20TokenForERC721(
    _pair: address,
    _tokenAddress: address,
    _nftRecipient: address,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256):
    '''
    @dev Deflationary tokens are not supported
    '''
    assert msg.sender != empty(address) and _pair != empty(address), "APEX:: UNVALIE ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID ITEMS"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _numberItems: uint256 = len(_tokenIds)

    _transferSucessful: bool = self._swapERC20ForERC721(_pair, _tokenAddress, msg.sender, _numberItems, _tokenIds)
    assert _transferSucessful, "APEX:: UNVALID TRANSFER"

    log SwapERC20TokenForERC721(_pair, _nftRecipient, _numberItems, _tokenIds)


@external
@nonreentrant('lock')
def swapERC721ForERC20Token(
    _pair: address,
    _tokenRecipient: address,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256):
    '''
    @dev Deflationary tokens are not supported
    '''
    assert msg.sender != empty(address) and _pair != empty(address), "APEX:: UNVALIE ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID ITEMS"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _numberItems: uint256 = len(_tokenIds)

    transferSucessful: bool = self._swapERC721ForERC20(_pair, msg.sender, _numberItems, _tokenIds)
    assert transferSucessful, "APEX:: UNVALID TRANSFER"

    log SwapERC721ForERC20Token(_pair, _tokenRecipient, _numberItems, _tokenIds)


@payable
@external
@nonreentrant('lock')
def addLiquidity(
    _nftAddress: address,
    _from: address,
    _to: address,
    _inputAmount: uint256, 
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _nftAddress != empty(address) and _from != empty(address) and _to != empty(address) and msg.sender != empty(address),"APEX:: UNVALID PAIR"
    assert ApeXExchangeV1Pair(_to).pairType() == 0, "APEX:: PAIR TRADE TYPE"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_to).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(_to, method_id("addLiquidityETH()"), value=msg.value)

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            self._safeTransferERC721NFT(_to, msg.sender, _to, _tokenIds[i])

            log AddLiquidity(_to, _nftAddress, _from, _inputAmount, _tokenIds[i])

    return True



@external
@nonreentrant('lock')
def addLiquidityEN(
    _nftAddress: address,
    _tokenAddress: address,
    _from: address,
    _to: address,
    _inputAmount: uint256, 
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _to != empty(address) and _nftAddress != empty(address) and _tokenAddress != empty(address) and _from != empty(address) and msg.sender != empty(address),"APEX:: UNVALID PAIR"
    assert ApeXExchangeV1Pair(_to).pairType() == 0, "APEX:: PAIR TRADE TYPE"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_to).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _to,
        concat(
            method_id("addLiquidityERC20Token(uint256)"),
            convert(_inputAmount, bytes32)
        )
    )
    
    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            self._safeTransferERC721NFT(_to, msg.sender, _to, _tokenIds[i])

            log AddLiquidityEN(_to, _nftAddress, _tokenAddress, _from, _inputAmount, _tokenIds[i])

    return True


@payable
@external
@nonreentrant('lock')
def addLiquidityETH(
    _from: address,
    _to: address,
    _inputAmount: uint256,
    _deadline: uint256) -> bool:
    assert _from != empty(address) and _to != empty(address) and msg.sender != empty(address),"APEX:: UNVALID PAIR"
    assert ApeXExchangeV1Pair(_to).pairType() == 1, "APEX:: PAIR TRADE TYPE"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_to).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(_to, method_id("addLiquidityETH()"), value=msg.value)
    log AddLiquidityETH(_to, _from, _inputAmount)

    return True


@external
@nonreentrant('lock')
def addLiquidityERC20(
    _from: address, 
    _to: address,
    _inputAmount: uint256,
    _deadline: uint256) -> bool:
    assert _from != empty(address) and _to != empty(address) and msg.sender != empty(address),"APEX:: UNVALID PAIR"
    assert _inputAmount != 0,"APEX:: UNVALID AMOUNT"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_to).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _to,
        concat(
            method_id("addLiquidityERC20Token(uint256)"),
            convert(_inputAmount, bytes32)
        )
    )
    
    log AddLiquidityERC20(_to, _from, _inputAmount)
    return True
    

@external
@nonreentrant('lock')
def addLiquidityERC721NFT(
    _nftAddress: address,
    _from: address,
    _to: address,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _from != empty(address) and _to != empty(address) and msg.sender != empty(address) and _nftAddress != empty(address),"APEX:: UNVALID ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert ApeXExchangeV1Pair(_to).pairType() == 2, "APEX:: PAIR TRADE TYPE"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_to).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            self._safeTransferERC721NFT(_to, msg.sender, _to, _tokenIds[i])

            log AddLiquidityERC721NFT(_to, _nftAddress, _from, _tokenIds[i])

    return True


@external
@nonreentrant('lock')
def removeLiquidity(
    _pair: address, 
    _nftAddress: address,
    _ethRecipient: address,
    _inputAmount: uint256, 
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _pair != empty(address),"APEX:: UNVALID PAIR"
    assert _inputAmount != 0, "APEX:: UNVALID AMOUNT R"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_pair).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _pair,
        concat(
            method_id("removeLiquidityETH(uint256)"),
            convert(_inputAmount, bytes32)
        )
    )

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _pair,
                concat(
                    method_id("removeLiquidityERC721NFT(uint256)"),
                    convert(_tokenIds[i], bytes32)
                )
            )
            log RemoveLiquidity(_pair, _nftAddress, _ethRecipient, _inputAmount, _tokenIds[i])

    return True


@external
@nonreentrant('lock')
def removeLiquidityEN(
    _pair: address, 
    _nftAddress: address,
    _tokenAddress: address,
    _tokenRecipient: address,
    _inputAmount: uint256, 
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _pair != empty(address) and _nftAddress != empty(address) and _tokenAddress != empty(address) and _tokenRecipient != empty(address) and msg.sender != empty(address),"APEX:: UNVALID PAIR"
    assert _inputAmount != 0, "APEX:: UNVALID AMOUNT"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_pair).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _pair,
        concat(
            method_id("removeLiquidityERC20(uint256)"),
            convert(_inputAmount, bytes32),
        )
    )

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _pair,
                concat(
                    method_id("removeLiquidityERC721NFT(uint256,uint256)"),
                    convert(_tokenIds[i], bytes32)
                )
            )
            log RemoveLiquidityEN(_pair, _nftAddress, _tokenAddress, _tokenRecipient, _inputAmount, _tokenIds[i])

    return True


@external
@nonreentrant('lock')
def removeLiquidityETH(
    _pair: address, 
    _ethRecipient: address,
    _inputAmount: uint256,
    _deadline: uint256) -> bool:
    assert _pair != empty(address) and _ethRecipient != empty(address),"APEX:: UNVALID PAIR"
    assert _inputAmount != 0, "APEX:: UNVALID AMOUNT"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_pair).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _pair,
        concat(
            method_id("removeLiquidityETH(uint256)"),
            convert(_inputAmount, bytes32)
        )
    )
    log RemoveLiquidityETH(_pair, _ethRecipient, _inputAmount)

    return True


@external
@nonreentrant('lock')
def removeLiquidityERC20(
    _pair: address, 
    _tokenRecipient: address,
    _inputAmount: uint256,
    _deadline: uint256) -> bool:
    assert _pair != empty(address) and _tokenRecipient != empty(address) and msg.sender != empty(address),"APEX:: UNVALID ADDRESS"
    assert _inputAmount != 0, "APEX:: UNVALID AMOUNT"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_pair).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    raw_call(
        _pair,
        concat(
            method_id("removeLiquidityERC20(uint256)"),
            convert(_inputAmount, bytes32)
        )
    )

    log RemoveLiquidityERC20(_pair, _tokenRecipient, _inputAmount)
    return True


@external
@nonreentrant('lock')
def removeLiquidityERC721NFT(
    _pair: address, 
    _nftAddress: address,
    _nftRecipient: address,
    _tokenIds: DynArray[uint256, MAX_SIZE],
    _deadline: uint256) -> bool:
    assert _pair != empty(address) and _nftAddress != empty(address) and msg.sender != empty(address) and _nftRecipient != empty(address),"APEX:: UNVALID ADDRESS"
    assert len(_tokenIds) != 0, "APEX:: UNVALID TOKEN ID"
    assert self.checkDeadline(_deadline), "APEX:: DEADLINE PASSED"

    _sender: address = ApeXExchangeV1Pair(_pair).controller()
    assert msg.sender == _sender, "APEX:: ONLY PAIR CONTROLLER"

    for i in range(MAX_SIZE):
        if i >= len(_tokenIds):
            break
        else:
            raw_call(
                _pair,
                concat(
                    method_id("removeLiquidityERC721NFT(uint256)"),
                    convert(_tokenIds[i], bytes32)
                )
            )
            log RemoveLiquidityERC721NFT(_pair, _nftAddress, _nftRecipient, _tokenIds[i])

    return True


@external
def updateApefee(_newFee: uint256):
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"

    _oldFee: uint256 = self.apeFee
    self.apeFee = _newFee
    log UpdateNewFee(msg.sender, _oldFee, _newFee)

@external
def updateFactory(_newFactory: address):
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"
    
    _oldFactory: address = self.factory
    self.factory = _newFactory
    log UpdateNewFactory(msg.sender, _oldFactory, _newFactory)


@external
def updateLibrary(_newLibrary: address):
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"

    _oldLibrary: address = self.library
    self.library = _newLibrary
    log UpdateNewLibrary(msg.sender, _oldLibrary, _newLibrary)


@external
def updateFund(_newFund: address):
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"

    _oldFund: address = self.apeFund
    self.apeFund = _newFund
    log UpdateNewFund(msg.sender, _oldFund, _newFund)


@view
@external
def getApeFee(_amountIn: uint256) -> uint256:
    return _amountIn * self.apeFee / 1000


