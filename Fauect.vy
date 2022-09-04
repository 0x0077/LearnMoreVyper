# @version >=0.3

from vyper.interfaces import ERC20

USDT: constant(address) = 0x46384918127fBd1679C757DF7b495C3F61481467 # 6
BUSD: constant(address) = 0x3c027273b160eF29C9b5Bce641881B9e96245C92
USDC: constant(address) = 0x54a14D7559BAF2C8e8Fa504E019d32479739018c # 6
AAVE: constant(address) = 0x455FFfa180D50D8a1AdaaA46Eb2bfb4C1bb28602
RENBTC: constant(address) = 0x55A853462862d54Ef6Fce380CE83dFd60494cf7a # 8
CRV: constant(address) = 0x61Bafc2f483cdb6C6710426d15Cf11fb6acF49f7
DAI: constant(address) = 0xE9f4149276E8a4F8DB89E0E3bb78fD853F01e87D
WBTC: constant(address) = 0x98DDd69B2443Fc67755f0901aEb9828a8A62cc65 # 8
LINK: constant(address) = 0x4732C03B2CF6eDe46500e799DE79a15Df44929eB
SHIB: constant(address) = 0x0f6e27007e257e74c86522387BD071D561ba3C97
MLTT: constant(address) = 0x9012C7CE4d1f677aaf9241CF7d4D05fC596556e8 # 10
MKR: constant(address) = 0x305B2e800C2B32198F46091cE0d98B89E767A383
STETH: constant(address) = 0x7339B33F149B51616a01966Ba23bE63F11226b77



is_approved: HashMap[address, HashMap[address, bool]]
is_claimed: HashMap[address, bool]

owner: public(address)

@external
def __init__():
    self.owner = msg.sender


@internal
def _transfer_erc20_token(_token: address, _spender: address, _amountIn: uint256):
    
    if not self.is_approved[self][_token]:
        _response: Bytes[32] = raw_call(
            _token,
            _abi_encode(self, max_value(uint256), method_id=method_id("approve(address,uint256)")), 
            max_outsize=32
        )
        if len(_response) != 0:
            assert convert(_response, bool)
        self.is_approved[self][_token] = True

    raw_call(
        _token,
        _abi_encode(self, self, _amountIn, method_id=method_id("transferFrom(address,address,uint256)"))
        )


@external
@nonreentrant('lock')
def claimAllFauectToken():
    assert not self.is_claimed[msg.sender], "CLAIMED"
    # claim amount
    seth: uint256 = 5000000000000000 # 0.005 ETH
    susdt: uint256 = 100000000 # 100 USDT
    sbusd: uint256 = 10000000000000000000000 # 10k BUSD
    susdc: uint256 = 10000000000 # 10k USDC
    saave: uint256 = 1000000000000000000 # 100 AAVE
    srenbtc: uint256 = 1000000000 # 10 renBTC
    scrv: uint256 = 10000000000000000000000 # 10k CRV
    sdai: uint256 = 10000000000000000000000 # 10k DAI
    swbtc: uint256 = 1000000000 # 10 wBTC
    slink: uint256 = 10000000000000000000000 # 10k LINK
    sshib: uint256 = 10000000000000000000000 # 10k SHIB
    smltt: uint256 = 1000000000000 # 100 MLTT
    smkr: uint256 = 10000000000000000000 # 10 MKR
    ssteth: uint256 = 10000000000000000000 # 10 stETH

    send(msg.sender, seth)
    self._transfer_erc20_token(USDT, msg.sender, susdt)
    self._transfer_erc20_token(BUSD, msg.sender, sbusd)
    self._transfer_erc20_token(USDC, msg.sender, susdc)
    self._transfer_erc20_token(AAVE, msg.sender, saave)
    self._transfer_erc20_token(RENBTC, msg.sender, srenbtc)
    self._transfer_erc20_token(CRV, msg.sender, scrv)
    self._transfer_erc20_token(DAI, msg.sender, sdai)
    self._transfer_erc20_token(WBTC, msg.sender, swbtc)
    self._transfer_erc20_token(LINK, msg.sender, slink)
    self._transfer_erc20_token(SHIB, msg.sender, sshib)
    self._transfer_erc20_token(MLTT, msg.sender, smltt)
    self._transfer_erc20_token(MKR, msg.sender, smkr)
    self._transfer_erc20_token(STETH, msg.sender, ssteth)

    self.is_claimed[msg.sender] = True


@external
def withdrawETH():
    assert msg.sender == self.owner, "ONLY OWNER"
    send(msg.sender, self.balance)


    