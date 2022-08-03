(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** Errors that may arise while validating an anonymous operation. *)
module Anonymous : sig
  type denunciation_kind = Preendorsement | Endorsement | Block

  type error +=
    | Invalid_activation of {pkh : Ed25519.Public_key_hash.t}
    | Conflicting_activation of Ed25519.Public_key_hash.t * Operation_hash.t
    | Invalid_denunciation of denunciation_kind
    | Invalid_double_baking_evidence of {
        hash1 : Block_hash.t;
        level1 : Alpha_context.Raw_level.t;
        round1 : Alpha_context.Round.t;
        hash2 : Block_hash.t;
        level2 : Alpha_context.Raw_level.t;
        round2 : Alpha_context.Round.t;
      }
    | Inconsistent_denunciation of {
        kind : denunciation_kind;
        delegate1 : Signature.Public_key_hash.t;
        delegate2 : Signature.Public_key_hash.t;
      }
    | Already_denounced of {
        kind : denunciation_kind;
        delegate : Signature.Public_key_hash.t;
        level : Alpha_context.Level.t;
      }
    | Conflicting_denunciation of {
        kind : denunciation_kind;
        delegate : Signature.Public_key_hash.t;
        level : Alpha_context.Level.t;
        hash : Operation_hash.t;
      }
    | Too_early_denunciation of {
        kind : denunciation_kind;
        level : Alpha_context.Raw_level.t;
        current : Alpha_context.Raw_level.t;
      }
    | Outdated_denunciation of {
        kind : denunciation_kind;
        level : Alpha_context.Raw_level.t;
        last_cycle : Alpha_context.Cycle.t;
      }
    | Conflicting_nonce_revelation
end

(** Errors that may arise while validating a manager operation. *)
module Manager : sig
  type error +=
    | Manager_restriction of Signature.Public_key_hash.t * Operation_hash.t
    | Inconsistent_sources
    | Inconsistent_counters
    | Incorrect_reveal_position
    | Insufficient_gas_for_manager
    | Gas_quota_exceeded_init_deserialize
    | Tx_rollup_feature_disabled
    | Sc_rollup_feature_disabled
end