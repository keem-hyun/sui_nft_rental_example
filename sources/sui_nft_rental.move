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

// === Constants ===
const PERMISSIONS: u128 = 11;
const SECONDS_IN_A_DAY: u64 = 86400;
const MAX_BASIS_POINTS: u16 = 10_000;
const MAX_VALUE_U64: u64 = 0xff_ff_ff_ff__ff_ff_ff_ff;

// === Structs ===
public struct Rentables has drop {}

public struct Rented has store, copy, drop { id: ID }

public struct Listed has store, copy, drop { id: ID }

public struct Promise {
  item: Rented,
  duration: u64,
  start_date: u64,
  price_per_day: u64,
  renter_kiosk: address,
  borrower_kiosk: ID
}

public struct Rentable<T: key + store> has store {
  object: T,
  duration: u64,
  start_date: Option<u64>,
  price_per_day: u64,
  kiosk_id: ID
}

public struct RentalPolicy<phantom T> has key, store {
  id: UID,
  balance: Balance<SUI>,
  amount_bp: u64
}

public struct ProtectedTP<phantom T> has key, store {
  id: UID,
  transfer_policy: TransferPolicy<T>,
  policy_cap: TransferPolicyCap<T>
}
