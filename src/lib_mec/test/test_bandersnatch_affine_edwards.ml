(*****************************************************************************)
(*                                                                           *)
(* Copyright (c) 2021 Danny Willems <be.danny.willems@gmail.com>             *)
(* Copyright (c) 2023 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

(** Testing
    -------
    Component:    lib_mec
    Invocation:   dune exec src/lib_mec/test/main.exe \
                  -- --file test_bandersnatch_affine_edwards.ml
    Subject:      Test lib mec
*)

module ValueGeneration =
  Mec.Curve.Utils.PBT.MakeValueGeneration (Mec.Curve.Bandersnatch.AffineEdwards)
module Equality =
  Mec.Curve.Utils.PBT.MakeEquality (Mec.Curve.Bandersnatch.AffineEdwards)
module Properties =
  Mec.Curve.Utils.PBT.MakeECProperties (Mec.Curve.Bandersnatch.AffineEdwards)
module EdwardsCurveProperties =
  Mec.Curve.Utils.PBT.MakeEdwardsCurveProperties
    (Mec.Curve.Bandersnatch.AffineEdwards)

let () =
  let open Alcotest in
  run
    ~__FILE__
    "Bandersnatch Edwards form, affine coordinates"
    [
      ValueGeneration.get_tests ();
      Properties.get_tests ();
      EdwardsCurveProperties.get_tests ();
      Equality.get_tests ();
    ]
