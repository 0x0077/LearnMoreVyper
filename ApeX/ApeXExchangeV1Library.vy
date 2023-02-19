# @version >=0.3
"""
@title zkApe Decentralization Exchange V1 Library
@author zkApe
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
    def getReserves() -> (uint256, uint256, uint256): view

interface ApeXExchangeV1Router:
    def getApeFee(_amountIn: uint256) -> uint256: view
    def apeFund() -> address: view
    def apeFee() -> uint256: view

event UpdateRouter:
    oldRouter: indexed(address)
    newRouter: indexed(address)

owner: public(address)
router: public(address)

@external
def __init__():
    self.owner = msg.sender
    self.router = ZERO_ADDRESS


@external
def updateRouter(_newRouter: address) -> bool:
    assert msg.sender == self.owner, "APEX:: ONLY OWNER"
    _oldRouter: address = self.router
    self.router = _newRouter

    log UpdateRouter(_oldRouter, _newRouter)
    return True


@pure
@internal
def _linearRiseBuyInfo(
    _pair: address,
    _numberItems: uint256,
    _currentPrice: uint256,
    _riseCurve: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0, "APEX:: UNVALID ITEMS"

    # 购买完所有的NFT后的价格
    _newCurrentPrice: uint256 = _currentPrice + _numberItems * _riseCurve
    assert _newCurrentPrice <= MAX_UINT256, "APEX:: UNVALID PRICE"

    # 购买所有的NFT需要花费多少ETH
    _inputValue: uint256 = _numberItems * _currentPrice + (_numberItems * (_numberItems - 1) * _riseCurve) / 2
    # 避免机器人套利 向上加一个单位
    _inputValue += _riseCurve

    if ApeXExchangeV1Pair(_pair).is_trade():
        _addSwapFee: uint256 = _inputValue * _swapFee / 1000
        _inputValue += _addSwapFee

    _protocolFee: uint256 = _inputValue * _apeFee / 1000
    _inputValue += _protocolFee

    return _newCurrentPrice, _inputValue, _protocolFee


@pure
@internal
def _linearRiseSellInfo(
    _pair: address,
    _numberItems: uint256,
    _currentPrice: uint256,
    _riseCurve: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0, "APEX:: UNVALID ITEMS"

    _priceChange: uint256 = _numberItems * _riseCurve
    _newCurrentPrice: uint256 = 0
    _newNumItems: uint256 = _numberItems

    if _priceChange > _currentPrice:
        _newCurrentPrice = 0
        # 当价格为0时需要卖出多少个NFT
        _newNumItems = _currentPrice / _riseCurve + 1
    else:
        _newCurrentPrice = _currentPrice - _priceChange
    
    _outputValue: uint256 = _newNumItems * _currentPrice - (_newNumItems * (_newNumItems - 1) * _riseCurve) / 2

    # 避免机器人套利 向下减一个单位
    _outputValue -= _riseCurve

    if ApeXExchangeV1Pair(_pair).is_trade():
        # 仅适用于双向流动池
        _addSwapFee: uint256 = _outputValue * _swapFee / 1000
        _outputValue -= _addSwapFee

    _protocolFee: uint256 = _outputValue * _apeFee / 1000
    _outputValue -= _protocolFee

    return _newCurrentPrice, _outputValue, _protocolFee
  

@pure
@internal
def _exponentialRiseBuyInfo(
    _pair: address,
    _numberItems: uint256,
    _currentPrice: uint256,
    _riseCurve: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0 and _numberItems <= 15, "APEX:: UNVALID ITEMS"

    # 购买所有的NFT需要花费多少ETH
    # 最多计算购买30个总金额
    _newCurrentPrice: uint256 = _currentPrice
    _inputValue: uint256 = 0
    _t: uint256 = 0

    for i in range(MAX_SIZE):
        if i >= _numberItems:
            break
        else:
            _t = _newCurrentPrice * (_riseCurve+ 10 ** 18) / 10 ** 18
            _newCurrentPrice = _t
            _inputValue += _t
    
    assert _newCurrentPrice <= MAX_UINT256, "APEX:: UNVALID PRICE"

    # 避免机器人套利 往上加一个点位
    _inputValue += ((_newCurrentPrice * _riseCurve) / 10 ** 18)

    if ApeXExchangeV1Pair(_pair).is_trade():
        _addSwapFee: uint256 = _inputValue * _swapFee / 1000
        _inputValue += _addSwapFee

    _protocolFee: uint256 = _inputValue * _apeFee / 1000
    _inputValue += _protocolFee

    return _newCurrentPrice, _inputValue, _protocolFee


@pure
@internal
def _exponentialRiseSellInfo(
    _pair: address,
    _numberItems: uint256,
    _currentPrice: uint256,
    _riseCurve: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0, "APEX:: UNVALID ITEMS"

    _newCurrentPrice: uint256 = _currentPrice
    _outputValue: uint256 = 0
    _t: uint256 = 0

    for i in range(MAX_SIZE):
        if i >= _numberItems:
            break
        else:
            _t = _newCurrentPrice * (10 ** 18 - _riseCurve) / 10 ** 18
            _newCurrentPrice = _t
            _outputValue += _t
    
    assert _newCurrentPrice > 0, "APEX:: UNVALID PRICE"

    # 避免机器人套利 往下减一个点位
    _outputValue -= ((_newCurrentPrice * _riseCurve) / 10 ** 18)

    if ApeXExchangeV1Pair(_pair).is_trade():
        _addSwapFee: uint256 = _outputValue * _swapFee / 1000
        _outputValue -= _addSwapFee

    _protocolFee: uint256 = _outputValue * _apeFee / 1000
    _outputValue -= _protocolFee

    return _newCurrentPrice, _outputValue, _protocolFee


@pure
@internal
def _xykRiseBuyInfo(
    _pair: address,
    _nftBalance: uint256,
    _tokenBalance: uint256,
    _numberItems: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0 and _tokenBalance >= _numberItems, "APEX:: UNVALID ITEMS"
    
    _inputValueWithoutFee: uint256 = (_numberItems * _tokenBalance) / (_nftBalance - _numberItems)
    
    _fee: uint256 = _inputValueWithoutFee * _swapFee / 1000
    _protocolFee: uint256 = _inputValueWithoutFee * _apeFee / 1000

    _inputValue: uint256 = _inputValueWithoutFee + _fee + _protocolFee
    _newCurrentPrice: uint256 = (_tokenBalance + _inputValueWithoutFee + _fee) / (_nftBalance - _numberItems)

    return _newCurrentPrice, _inputValue, _protocolFee


@pure
@internal
def _xykRiseSellInfo(
    _pair: address,
    _nftBalance: uint256,
    _tokenBalance: uint256,
    _numberItems: uint256,
    _swapFee: uint256,
    _apeFee: uint256) -> (uint256, uint256, uint256):
    assert _numberItems != 0 and _tokenBalance >= _numberItems, "APEX:: UNVALID ITEMS"
    
    _outputValueWithoutFee: uint256 = (_numberItems * _tokenBalance) / (_nftBalance + _numberItems)
    
    _fee: uint256 = _outputValueWithoutFee * _swapFee / 1000
    _protocolFee: uint256 = _outputValueWithoutFee * _apeFee / 1000

    _outputValue: uint256 = _outputValueWithoutFee - _fee - _protocolFee
    _newCurrentPrice: uint256 = (_tokenBalance + _outputValueWithoutFee + _fee) / (_nftBalance - _numberItems)

    return _newCurrentPrice, _outputValue, _protocolFee



@view
@external
def pairBuyBasicInfo(_pair: address, _numberItems: uint256) -> (uint256, uint256, uint256):
    _currentPrice: uint256 = ApeXExchangeV1Pair(_pair).currentPrice()
    _riseType: uint256 = ApeXExchangeV1Pair(_pair).riseType()
    _riseCurve: uint256 = ApeXExchangeV1Pair(_pair).riseCurve()
    _swapFee: uint256 = ApeXExchangeV1Pair(_pair).swapFee()

    _newCurrentPrice: uint256 = 0
    _inputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _tokenBalance: uint256 = 0
    _nftBalance: uint256 = 0
    _t : uint256 = 0

    _apeFee: uint256 = ApeXExchangeV1Router(self.router).apeFee()

    assert _riseType in [0, 1, 2], "APEX:: UNVALID TYPE"

    if _riseType == 0:
        _newCurrentPrice, _inputValue, _protocolFee = self._linearRiseBuyInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 1:
        _newCurrentPrice, _inputValue, _protocolFee = self._exponentialRiseBuyInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 2:
        _nftBalance, _tokenBalance, _t = ApeXExchangeV1Pair(_pair).getReserves()
        _newCurrentPrice, _inputValue, _protocolFee = self._xykRiseBuyInfo(_pair, _nftBalance, _tokenBalance, _numberItems, _swapFee, _apeFee)

    return _newCurrentPrice, _inputValue, _protocolFee


@view
@external
def pairSellBasicInfo(_pair: address, _numberItems: uint256) -> (uint256, uint256, uint256):
    _currentPrice: uint256 = ApeXExchangeV1Pair(_pair).currentPrice()
    _riseType: uint256 = ApeXExchangeV1Pair(_pair).riseType()
    _riseCurve: uint256 = ApeXExchangeV1Pair(_pair).riseCurve()
    _swapFee: uint256 = ApeXExchangeV1Pair(_pair).swapFee()

    _newCurrentPrice: uint256 = 0
    _outputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _tokenBalance: uint256 = 0
    _nftBalance: uint256 = 0
    _t : uint256 = 0

    _apeFee: uint256 = ApeXExchangeV1Router(self.router).apeFee()

    assert _riseType in [0, 1, 2], "APEX:: UNVALID TYPE"

    if _riseType == 0:
        _newCurrentPrice, _outputValue, _protocolFee = self._linearRiseSellInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 1:
        _newCurrentPrice, _outputValue, _protocolFee = self._exponentialRiseSellInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 2:
        _nftBalance, _tokenBalance, _t = ApeXExchangeV1Pair(_pair).getReserves()
        _newCurrentPrice, _outputValue, _protocolFee = self._xykRiseSellInfo(_pair, _nftBalance, _tokenBalance, _numberItems, _swapFee, _apeFee)

    return _newCurrentPrice, _outputValue, _protocolFee


@view
@external
def getInputValue(
    _riseType: uint256, 
    _pair: address, 
    _numberItems: uint256, 
    _currentPrice: uint256, 
    _riseCurve: uint256, 
    _swapFee: uint256) -> (uint256, uint256, uint256):

    _newCurrentPrice: uint256 = 0
    _inputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _tokenBalance: uint256 = 0
    _nftBalance: uint256 = 0
    _t : uint256 = 0

    _apeFee: uint256 = ApeXExchangeV1Router(self.router).apeFee()

    if _riseType == 0:
        _newCurrentPrice, _inputValue, _protocolFee = self._linearRiseBuyInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 1:
        _newCurrentPrice, _inputValue, _protocolFee = self._exponentialRiseBuyInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 2:
        _nftBalance, _tokenBalance, _t = ApeXExchangeV1Pair(_pair).getReserves()
        _newCurrentPrice, _inputValue, _protocolFee = self._xykRiseBuyInfo(_pair, _nftBalance, _tokenBalance, _numberItems, _swapFee, _apeFee)

    return _newCurrentPrice, _inputValue, _protocolFee


@view
@external
def getOutputValue(
    _riseType: uint256, 
    _pair: address, 
    _numberItems: uint256, 
    _currentPrice: uint256, 
    _riseCurve: uint256, 
    _swapFee: uint256) -> (uint256, uint256, uint256):

    _newCurrentPrice: uint256 = 0
    _outputValue: uint256 = 0
    _protocolFee: uint256 = 0
    _tokenBalance: uint256 = 0
    _nftBalance: uint256 = 0
    _t : uint256 = 0

    _apeFee: uint256 = ApeXExchangeV1Router(self.router).apeFee()

    if _riseType == 0:
        _newCurrentPrice, _outputValue, _protocolFee = self._linearRiseSellInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 1:
        _newCurrentPrice, _outputValue, _protocolFee = self._exponentialRiseSellInfo(_pair, _numberItems, _currentPrice, _riseCurve, _swapFee, _apeFee)
    elif _riseType == 2:
        _nftBalance, _tokenBalance, _t = ApeXExchangeV1Pair(_pair).getReserves()
        _newCurrentPrice, _outputValue, _protocolFee = self._xykRiseSellInfo(_pair, _nftBalance, _tokenBalance, _numberItems, _swapFee, _apeFee)

    return _newCurrentPrice, _outputValue, _protocolFee