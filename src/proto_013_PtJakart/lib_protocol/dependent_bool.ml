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

type no = private DNo

type yes = private DYes

type _ dbool = No : no dbool | Yes : yes dbool

type ('a, 'b, 'r) dand =
  | NoNo : (no, no, no) dand
  | NoYes : (no, yes, no) dand
  | YesNo : (yes, no, no) dand
  | YesYes : (yes, yes, yes) dand

type ('a, 'b) ex_dand = Ex_dand : ('a, 'b, _) dand -> ('a, 'b) ex_dand
[@@unboxed]

let dand : type a b. a dbool -> b dbool -> (a, b) ex_dand =
 fun a b ->
  match (a, b) with
  | (No, No) -> Ex_dand NoNo
  | (No, Yes) -> Ex_dand NoYes
  | (Yes, No) -> Ex_dand YesNo
  | (Yes, Yes) -> Ex_dand YesYes

let dbool_of_dand : type a b r. (a, b, r) dand -> r dbool = function
  | NoNo -> No
  | NoYes -> No
  | YesNo -> No
  | YesYes -> Yes

type (_, _) eq = Eq : ('a, 'a) eq

let merge_dand :
    type a b c1 c2. (a, b, c1) dand -> (a, b, c2) dand -> (c1, c2) eq =
 fun w1 w2 ->
  match (w1, w2) with
  | (NoNo, NoNo) -> Eq
  | (NoYes, NoYes) -> Eq
  | (YesNo, YesNo) -> Eq
  | (YesYes, YesYes) -> Eq
