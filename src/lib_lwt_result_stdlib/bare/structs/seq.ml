(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Monad
include Stdlib.Seq

let init ~when_negative_length n f =
  if n < 0 then Error when_negative_length else Ok (init n f)

let take ~when_negative_length n s =
  if n < 0 then Error when_negative_length else Ok (take n s)

let drop ~when_negative_length n s =
  if n < 0 then Error when_negative_length else Ok (drop n s)

module E = Seqes.Standard.Make2 (Result)
module S = Seqes.Standard.Make1 (Lwt)
module ES = Seqes.Standard.Make2 (Lwt_result)

let iter_ep f seq =
  let rec iter_ep f seq (acc : (unit, 'error) result Lwt.t list) =
    match seq () with
    | Nil -> Lwt_result_syntax.join acc
    | Cons (item, seq) -> iter_ep f seq (Lwt.apply f item :: acc)
  in
  iter_ep f seq []

let iter_p f seq =
  let rec iter_p f seq acc =
    match seq () with
    | Nil -> Lwt_syntax.join acc
    | Cons (item, seq) -> iter_p f seq (Lwt.apply f item :: acc)
  in
  iter_p f seq []

let iteri_ep f seq =
  let rec iteri_ep f i seq (acc : (unit, 'error) result Lwt.t list) =
    match seq () with
    | Nil -> Lwt_result_syntax.join acc
    | Cons (item, seq) -> iteri_ep f (i + 1) seq (lwt_apply2 f i item :: acc)
  in
  iteri_ep f 0 seq []

let iteri_p f seq =
  let rec iteri_p f i seq acc =
    match seq () with
    | Nil -> Lwt_syntax.join acc
    | Cons (item, seq) -> iteri_p f (i + 1) seq (lwt_apply2 f i item :: acc)
  in
  iteri_p f 0 seq []

let iter2_ep f seqa seqb =
  let rec iter2_ep f seqa seqb (acc : (unit, 'error) result Lwt.t list) =
    let a = seqa () in
    let b = seqb () in
    match (a, b) with
    | Nil, Nil | Nil, Cons _ | Cons _, Nil -> Lwt_result_syntax.join acc
    | Cons (itema, seqa), Cons (itemb, seqb) ->
        iter2_ep f seqa seqb (lwt_apply2 f itema itemb :: acc)
  in
  iter2_ep f seqa seqb []

let iter2_p f seqa seqb =
  let rec iter2_p f seqa seqb acc =
    let a = seqa () in
    let b = seqb () in
    match (a, b) with
    | Nil, Nil | Nil, Cons _ | Cons _, Nil -> Lwt_syntax.join acc
    | Cons (itema, seqa), Cons (itemb, seqb) ->
        iter2_p f seqa seqb (lwt_apply2 f itema itemb :: acc)
  in
  iter2_p f seqa seqb []
