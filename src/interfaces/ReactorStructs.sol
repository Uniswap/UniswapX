// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct TokenAmount {
    address token;
    uint256 amount;
}

struct OrderInfo {
    address reactor;
    address offerer;
    address validationContract;
    bytes validationData;
    uint256 counter;
    uint256 deadline;
}
