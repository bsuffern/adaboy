// Fusion+ Escrow Contract (Aiken)
// Single‑hash hash‑time‑locked escrow without partial fills
use aiken/builtin.{sha2_256}
use aiken/interval.{contains}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId, from_asset_list, merge}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use cocktail.{
  address_pub_key, all_key_signed, get_all_value_to, inputs_at, key_signed,
  one_of_keys_signed, outputs_at, value_geq, value_length,
}

pub type MValue =
  Pairs<PolicyId, Pairs<AssetName, Int>>

// ─────────────────────────────────────────────────────────────────────────────
// Datum & Redeemer
// ─────────────────────────────────────────────────────────────────────────────
// • `hash`     – sha‑256 hash of a secret pre‑image (32‑byte max)
// • `timelock` – absolute POSIX time after which either party can cancel

pub type EscrowDatum {
  Initiation {
    initiator: Address,
    initiator_assets: MValue,
    hash: ByteArray,
    timelock: Int,
  }
  ActiveEscrow {
    initiator: Address,
    initiator_assets: MValue,
    recipient: Address,
    recipient_assets: MValue,
    hash: ByteArray,
    timelock: Int,
  }
}

pub type EscrowRedeemer {
  RecipientDeposit { recipient: Address, recipient_assets: MValue }
  CancelTrade
  CompleteTrade { preimage: ByteArray }
}

// ─────────────────────────────────────────────────────────────────────────────
// Validator
// ─────────────────────────────────────────────────────────────────────────────
validator escrow {
  spend(
    _datum: Option<EscrowDatum>,
    redeemer: EscrowRedeemer,
    input: OutputReference,
    tx: Transaction,
  ) {
    let Transaction { inputs, outputs, extra_signatories, validity_range, .. } =
      tx
    expect Some(own_input) = find_input(inputs, input)
    let own_address = own_input.output.address

    when redeemer is {
      // ───────────────────────────────────────────── RecipientDeposit ────────
      RecipientDeposit { recipient, recipient_assets } -> {
        expect ([input], [output]) =
          (inputs_at(inputs, own_address), outputs_at(outputs, own_address))

        expect InlineDatum(raw_input_datum) = input.output.datum
        expect InlineDatum(raw_output_datum) = output.datum
        expect Initiation { initiator, initiator_assets, hash, timelock }: EscrowDatum =
          raw_input_datum

        expect output_datum: EscrowDatum = raw_output_datum

        let is_datum_updated =
          output_datum == ActiveEscrow {
            initiator,
            initiator_assets,
            recipient,
            recipient_assets,
            hash,
            timelock,
          }

        let is_value_deposited =
          value_geq(
            output.value,
            input.output.value
              |> merge(recipient_assets |> from_asset_list()),
          )

        // ADA + 4(recipient) + 4(initiator)
        let is_output_value_clean = value_length(output.value) <= 9
        is_datum_updated && is_value_deposited && is_output_value_clean
      }

      // ─────────────────────────────────────────────────── CancelTrade ────────
      CancelTrade -> {
        expect ([input], []) =
          (inputs_at(inputs, own_address), outputs_at(outputs, own_address))

        expect InlineDatum(raw_input_datum) = input.output.datum
        expect input_datum: EscrowDatum = raw_input_datum

        when input_datum is {
          Initiation { initiator, .. } -> {
            // Only initiator may abort before recipient deposit.
            expect Some(pub_key) = address_pub_key(initiator)
            key_signed(extra_signatories, pub_key)
          }

          ActiveEscrow {
            initiator,
            recipient,
            initiator_assets,
            recipient_assets,
            hash: _,
            timelock,
          } -> {
            let initiator_received = get_all_value_to(outputs, initiator)
            let recipient_received = get_all_value_to(outputs, recipient)

            let is_assets_returned =
              value_geq(
                initiator_received,
                initiator_assets |> from_asset_list(),
              ) && value_geq(
                recipient_received,
                recipient_assets |> from_asset_list(),
              )

            // Either party may cancel after timelock expires.
            let is_after_deadline = contains(validity_range, timelock)

            expect Some(initiator_pk) = address_pub_key(initiator)
            expect Some(recipient_pk) = address_pub_key(recipient)
            let is_any_party_signed =
              one_of_keys_signed(
                extra_signatories,
                [initiator_pk, recipient_pk],
              )

            is_after_deadline && is_any_party_signed && is_assets_returned
          }
        }
      }

      // ─────────────────────────────────────────── CompleteTrade ─────────────
      CompleteTrade { preimage } -> {
        expect ([input], []) =
          (inputs_at(inputs, own_address), outputs_at(outputs, own_address))

        expect InlineDatum(raw_input_datum) = input.output.datum
        expect ActiveEscrow {
          initiator,
          recipient,
          initiator_assets,
          recipient_assets,
          hash,
          timelock: _,
        }: EscrowDatum = raw_input_datum

        let initiator_received = get_all_value_to(outputs, initiator)
        let recipient_received = get_all_value_to(outputs, recipient)

        let is_value_swapped =
          value_geq(initiator_received, recipient_assets |> from_asset_list()) && value_geq(
            recipient_received,
            initiator_assets |> from_asset_list(),
          )

        // Verify secret matches expected hash
        let is_hash_match = sha2_256(preimage) == hash

        expect Some(initiator_pk) = address_pub_key(initiator)
        expect Some(recipient_pk) = address_pub_key(recipient)
        let is_both_signed =
          all_key_signed(extra_signatories, [initiator_pk, recipient_pk])

        is_both_signed && is_hash_match && is_value_swapped
      }
    }
  }

  else(_) {
    fail
  }
}
