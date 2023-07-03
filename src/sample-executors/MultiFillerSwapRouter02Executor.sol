// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades, allowing multiple static fillers
contract MultiFillerSwapRouter02Executor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an adress other than the reactor
    error MsgSenderNotReactor();

    ISwapRouter02 private immutable swapRouter02;
    IReactor private immutable reactor;
    WETH private immutable weth;

    constructor(IReactor _reactor, address _owner, ISwapRouter02 _swapRouter02) Owned(_owner) {
        reactor = _reactor;
        swapRouter02 = _swapRouter02;
        weth = WETH(payable(_swapRouter02.WETH9()));
    }

    /// @param resolvedOrders The orders to fill
    /// @param filler This filler must be `whitelistedCaller`
    /// @param fillData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata fillData)
        external
    {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        if (!checkAddress(filler)) {
            revert CallerNotWhitelisted();
        }

        (address[] memory tokensToApproveForSwapRouter02, bytes[] memory multicallData) =
            abi.decode(fillData, (address[], bytes[]));

        for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
            ERC20(tokensToApproveForSwapRouter02[i]).safeApprove(address(swapRouter02), type(uint256).max);
        }

        swapRouter02.multicall(type(uint256).max, multicallData);

        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];
                output.token.transfer(output.recipient, output.amount);
            }
        }
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(ERC20[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            tokensToApprove[i].safeApprove(address(swapRouter02), type(uint256).max);
        }
        swapRouter02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}

    // check if the given address is allowed
    function checkAddress(address input) private pure returns (bool) {
        if (input < 0x7e346652905a7e5A0b3275817E016eB9f0A58d72) {
            if (input < 0x326b39ad29df260ce36dEFC3025ae444F2d19438) {
                if (input < 0x1B483952B78Bd1E2E6b9742D0B9Da03E1eD168B6) {
                    if (input < 0x1971c4e485c86FD3369d211A1539bAf741DD4066) {
                        if (input < 0x05cb5Ed3176F2FAd4acfE727a4DA233A5cb436f4) {
                            return input == 0x008dC7B274FEE2184373AFf5B3A188B4d162dd78;
                        } else {
                            if (input < 0x176D2753B5fE481132784a25A88870e79BE4F897) {
                                return input == 0x05cb5Ed3176F2FAd4acfE727a4DA233A5cb436f4;
                            } else {
                                return input == 0x176D2753B5fE481132784a25A88870e79BE4F897;
                            }
                        }
                    } else {
                        if (input < 0x19f11950e4d57ADae785aEdBb84D651f1581BC1b) {
                            return input == 0x1971c4e485c86FD3369d211A1539bAf741DD4066;
                        } else {
                            if (input < 0x19F456E396970Ef5FDE1bd755c884659211d4367) {
                                return input == 0x19f11950e4d57ADae785aEdBb84D651f1581BC1b;
                            } else {
                                return input == 0x19F456E396970Ef5FDE1bd755c884659211d4367;
                            }
                        }
                    }
                } else {
                    if (input < 0x27cC7F8aF1E799eD75aeB9C2756C6dcC3A495b39) {
                        if (input < 0x1Fe954Cd85938a6915A0E9A331708F912011c2b7) {
                            return input == 0x1B483952B78Bd1E2E6b9742D0B9Da03E1eD168B6;
                        } else {
                            if (input < 0x229638ce60e39A5cCE80d68476E473ca9Eb529cD) {
                                return input == 0x1Fe954Cd85938a6915A0E9A331708F912011c2b7;
                            } else {
                                return input == 0x229638ce60e39A5cCE80d68476E473ca9Eb529cD;
                            }
                        }
                    } else {
                        if (input < 0x28B5f87500177987B65696bcB703eC74a186215f) {
                            return input == 0x27cC7F8aF1E799eD75aeB9C2756C6dcC3A495b39;
                        } else {
                            if (input < 0x2bd908Bd30B384fdfD4Ef63A9996fdc1e1B465b9) {
                                return input == 0x28B5f87500177987B65696bcB703eC74a186215f;
                            } else {
                                return input == 0x2bd908Bd30B384fdfD4Ef63A9996fdc1e1B465b9;
                            }
                        }
                    }
                }
            } else {
                if (input < 0x5357d7E2ebb125b43d3aD8500004f927aC0D8a56) {
                    if (input < 0x4ea6b06e5139F3483A7A9a17988f6854c914Ab61) {
                        if (input < 0x37BDe7E563cf2E122AdD2A8D988CafdB58F74b3E) {
                            return input == 0x326b39ad29df260ce36dEFC3025ae444F2d19438;
                        } else {
                            if (input < 0x3b86b9236811aAba0d895a1DF34e6e32E16D5373) {
                                return input == 0x37BDe7E563cf2E122AdD2A8D988CafdB58F74b3E;
                            } else {
                                return input == 0x3b86b9236811aAba0d895a1DF34e6e32E16D5373;
                            }
                        }
                    } else {
                        if (input < 0x4FB8a80b40eDE87fbf26aa5a25E8e5A07deDAEb6) {
                            return input == 0x4ea6b06e5139F3483A7A9a17988f6854c914Ab61;
                        } else {
                            if (input < 0x5317c87A39b113a72168b3382e4c4650a4f4EB82) {
                                return input == 0x4FB8a80b40eDE87fbf26aa5a25E8e5A07deDAEb6;
                            } else {
                                return input == 0x5317c87A39b113a72168b3382e4c4650a4f4EB82;
                            }
                        }
                    }
                } else {
                    if (input < 0x6257ccE851c33820bB0B853f0Cb2aDAEc7E47Fbd) {
                        if (input < 0x56A69b3B0f24F27eDF3b5dF2b0a28D00B7ED973d) {
                            return input == 0x5357d7E2ebb125b43d3aD8500004f927aC0D8a56;
                        } else {
                            if (input < 0x5763dB43549ba523A163193898E397DC840A32AE) {
                                return input == 0x56A69b3B0f24F27eDF3b5dF2b0a28D00B7ED973d;
                            } else {
                                return input == 0x5763dB43549ba523A163193898E397DC840A32AE;
                            }
                        }
                    } else {
                        if (input < 0x69CFcfDB3784f8d9D1fc13C4152f2Fc42FCD5695) {
                            if (input < 0x6377A5C224423beB0d8a4731dEd3d459a2387f7d) {
                                return input == 0x6257ccE851c33820bB0B853f0Cb2aDAEc7E47Fbd;
                            } else {
                                return input == 0x6377A5C224423beB0d8a4731dEd3d459a2387f7d;
                            }
                        } else {
                            if (input < 0x6f29211688B565E6d9fC34c0bCbAfFc912761a44) {
                                return input == 0x69CFcfDB3784f8d9D1fc13C4152f2Fc42FCD5695;
                            } else {
                                return input == 0x6f29211688B565E6d9fC34c0bCbAfFc912761a44;
                            }
                        }
                    }
                }
            }
        } else {
            if (input < 0xC0b2a431E4023f2C8874a59c21e5A7d5563Dcd7e) {
                if (input < 0xa17Fbb0b5a251A7ACA3BD7377e7eCC4F700A2C09) {
                    if (input < 0x9675E6d51B877AE8ADdBbFa28D2A97A56D876802) {
                        if (input < 0x80147F235A2400F3a5CA7ddCFbd89D9ea5b70f0d) {
                            return input == 0x7e346652905a7e5A0b3275817E016eB9f0A58d72;
                        } else {
                            if (input < 0x8528fe29b65f566DE5a24Ef9112a953109112ED3) {
                                return input == 0x80147F235A2400F3a5CA7ddCFbd89D9ea5b70f0d;
                            } else {
                                return input == 0x8528fe29b65f566DE5a24Ef9112a953109112ED3;
                            }
                        }
                    } else {
                        if (input < 0x99eD4Eb1A2F9a43b47DcD1bf86A73BfCF170283E) {
                            return input == 0x9675E6d51B877AE8ADdBbFa28D2A97A56D876802;
                        } else {
                            if (input < 0x9e48dA4e289F1357a74a5897efB7edE2B19C02cb) {
                                return input == 0x99eD4Eb1A2F9a43b47DcD1bf86A73BfCF170283E;
                            } else {
                                return input == 0x9e48dA4e289F1357a74a5897efB7edE2B19C02cb;
                            }
                        }
                    }
                } else {
                    if (input < 0xb8C76fb91CB32870ee594804bA976BEAc4ecfdAC) {
                        if (input < 0xAA59D3FCaEFDcA4d9dD2D2a34DeF79985386020B) {
                            return input == 0xa17Fbb0b5a251A7ACA3BD7377e7eCC4F700A2C09;
                        } else {
                            if (input < 0xb7eBAdAC72A3dDA2F363Db26B9cDe03c539AEcA3) {
                                return input == 0xAA59D3FCaEFDcA4d9dD2D2a34DeF79985386020B;
                            } else {
                                return input == 0xb7eBAdAC72A3dDA2F363Db26B9cDe03c539AEcA3;
                            }
                        }
                    } else {
                        if (input < 0xb9054004164cf211f452dF931078d067CcD71Dff) {
                            return input == 0xb8C76fb91CB32870ee594804bA976BEAc4ecfdAC;
                        } else {
                            if (input < 0xbc9a6DF348e2E661921848B2efa9316813C8989b) {
                                return input == 0xb9054004164cf211f452dF931078d067CcD71Dff;
                            } else {
                                return input == 0xbc9a6DF348e2E661921848B2efa9316813C8989b;
                            }
                        }
                    }
                }
            } else {
                if (input < 0xdC55523bc4b116E0817270d62F19ec3540e24Db8) {
                    if (input < 0xD504decb1DB1C0cBe01B498E6F690B0dA49B100a) {
                        if (input < 0xC556337FCE1e2d108c4B0e426E623f8Bdc6405c0) {
                            return input == 0xC0b2a431E4023f2C8874a59c21e5A7d5563Dcd7e;
                        } else {
                            if (input < 0xc8Bb5C046F70E2DbA481c9Ad9C9Ad55ebAe54BFf) {
                                return input == 0xC556337FCE1e2d108c4B0e426E623f8Bdc6405c0;
                            } else {
                                return input == 0xc8Bb5C046F70E2DbA481c9Ad9C9Ad55ebAe54BFf;
                            }
                        }
                    } else {
                        if (input < 0xd725Bf68220194141Bda3A1aebfe673Aa9b84d3D) {
                            return input == 0xD504decb1DB1C0cBe01B498E6F690B0dA49B100a;
                        } else {
                            if (input < 0xdbD2ce742cf75b73FaAa94170537eB520ceDEBE8) {
                                return input == 0xd725Bf68220194141Bda3A1aebfe673Aa9b84d3D;
                            } else {
                                return input == 0xdbD2ce742cf75b73FaAa94170537eB520ceDEBE8;
                            }
                        }
                    }
                } else {
                    if (input < 0xE8056A65017166BCD6ae0Df5D092BbDeB22419F6) {
                        if (input < 0xe557206B5C3c98C547c222dFD189C27D079F8cc3) {
                            return input == 0xdC55523bc4b116E0817270d62F19ec3540e24Db8;
                        } else {
                            if (input < 0xE561762D6B1d766885BF64FFc7CAc5552862B5f6) {
                                return input == 0xe557206B5C3c98C547c222dFD189C27D079F8cc3;
                            } else {
                                return input == 0xE561762D6B1d766885BF64FFc7CAc5552862B5f6;
                            }
                        }
                    } else {
                        if (input < 0xeab74725990e0cF3aF9bD1A4c5449CeAdd8c96FB) {
                            if (input < 0xE93F29d10383C9B873e6c5218E7174F8392a740A) {
                                return input == 0xE8056A65017166BCD6ae0Df5D092BbDeB22419F6;
                            } else {
                                return input == 0xE93F29d10383C9B873e6c5218E7174F8392a740A;
                            }
                        } else {
                            if (input < 0xebb6A4c602AF711A113d76eDe3d6Af3c8035D08d) {
                                return input == 0xeab74725990e0cF3aF9bD1A4c5449CeAdd8c96FB;
                            } else {
                                return input == 0xebb6A4c602AF711A113d76eDe3d6Af3c8035D08d;
                            }
                        }
                    }
                }
            }
        }
    }
}
