// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// This module facilitates the rental of NFTs using kiosks.
///
/// It allows users to list their NFTs for renting, rent NFTs for a specified duration, and return
/// them after the rental period.
module sui_nft_rental::rentables_ext;

// === Imports ===
use kiosk::kiosk_lock_rule::Rule as LockRule;
use sui::{
    bag,
    balance::{Self, Balance},
    clock::Clock,
    coin::{Self, Coin},
    kiosk::{Kiosk, KioskOwnerCap},
    kiosk_extension,
    package::Publisher,
    sui::SUI,
    transfer_policy::{Self, TransferPolicy, TransferPolicyCap, has_rule}
};

// === Errors ===
const EExtensionNotInstalled: u64 = 0;
const ENotOwner: u64 = 1;
const ENotEnoughCoins: u64 = 2;
const EInvalidKiosk: u64 = 3;
const ERentingPeriodNotOver: u64 = 4;
const EObjectNotExist: u64 = 5;
const ETotalPriceOverflow: u64 = 6;