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

// === Public Functions ===
public fun install(
  kiosk: &mut Kiosk,
  cap: $KioskOwnerCap,
  ctx: &mut TxContext
) {
  kiosk_extension::add(Rentables {}, kiosk, cap, PERMISSIONS, ctx);
}

public fun remove(
  kiosk: &mut Kiosk,
  cap: &KioskOwnerCap,
  &mut: TxContext
) {
  kiosk_extension::remove<Rentables>(kiosk, cap);
}

public fun setup_renting<T>(publisher: &Publisher, amount_bp: u64, ctx: &mut TxContext) {
  let (transfer_policy, policy_cap) = transfer_policy::new<T>(publisher, ctx);

  let protected_tp = ProtectedTP {
    id: object::new(ctx),
    transfer_policy,
    policy_cap
  };

  let rental_policy = RentalPolicy<T> {
    id: object::new(ctx),
    balance: balance::zero<SUI>(),
    amount_bp,
  };

  transfer::share_object(protected_tp);
  transfer::share_object(rental_policy);
}

public fun list<T: key + store> (
  kiosk: &mut Kiosk,
  cap: &KioskOwnerCap,
  protected_tp: &ProtectedTP<T>,
  item_id: ID,
  duration: u64,
  price_per_day: u64,
  ctx: &mut TxContext
) {
  assert!(kiosk_extension::is_installed<Rentables>(kiosk), EExtensionNotInstalled);
  kiosk.set_owner(cap, ctx);
  kiosk.list<T>(cap, item_id, 0);
  let coin = coin::zero<SUI>(ctx);
  let (object, request) = kiosk.purchase<T>(item_id, coin);
  let (_item, _paid, _from) = protected_tp.transfer_policy.confirm_request(request);
  let rentable = Rentable {
    object,
    duration,
    start_date: option::none<u64>(),
    price_per_day,
    kiosk_id: object::id(kiosk)
  };

  place_in_bag<T, Listed>(kiosk, Listed { id: item_id }, rentable);
}

public fun delist<T: key + store> (
  kiosk: &mut Kiosk,
  cap: &KioskOwnerCap,
  transfer_policy: &TransferPolicy<T>,
  item_id: ID,
  _ctx: &mut TxContext
) {
  assert!(kiosk.has_access(cap), ENotOwner);
  let rentable = take_from_bag<T, Listed>(kiosk, Listed { id: item_id });
  let Rentable {
    object,
    duration: _,
    start_date: _,
    price_per_day: _,
    kiosk_id: _,
  } = rentable;

  if (has_rule<T, LockRule>(transfer_policy)) {
    kiosk.lock(cap, transfer_policy, object);
  } else {
    kiosk.place(cap, object);
  }
}

public fun rent<T: key + store> (
  renter_kiosk: &mut Kiosk,
  borrower_kiosk: &mut Kiosk,
  rental_policy: &mut RentalPolicy<T>,
  item_id: ID,
  mut coin: Coin<SUI>,
  clock: &Clock,
  ctx: &mut TxContext
) {
  assert!(kiosk_extension::is_installed<Rentables>(borrower_kiosk), EExtensionNotInstalled);
  
  let mut rentable = take_from_bag<T, Listed>(renter_kiosk, Listed { id: item_id });
  
  let max_price_per_day = MAX_VALUE_U64 / rentable.duration;
  assert!(rentable.price_per_day <= max_price_per_day, ETotalPriceOverflow);
  let total_price = rentable.price_per_day * rentable.duration;

  let coin_value = coin.value();
  assert!(coin_value == total_price, ENotEnoughCoins);

  let mut fees_amount = coin_value as u128;
  fees_amount = fees_amount * (rental_policy.amount_bp as u128);
  fees_amount = fees_amount / (MAX_BASIS_POINTS as u128);

  let fees = coin.split(fees_amount as u64, ctx);

  coin::put(&mut rental_policy.balance, fees);

  transfer::public_transfer(coin, renter_kiosk.owner());
  rentable.start_date.fill(clock.timestamp_ms());

  place_in_bag<T, Rented>(borrower_kiosk, Rented { id: item_id }, rentable);
}


