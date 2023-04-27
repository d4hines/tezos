(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Protocol
open Alpha_context
open Client_proto_rollups

let group =
  {
    Tezos_clic.name = "smart rollup";
    title = "Commands for managing the record of known smart rollup";
  }

let commands () =
  let open Tezos_clic in
  [
    command
      ~group
      ~desc:"Add a smart rollup to the wallet."
      (args1 (SoruAlias.force_switch ()))
      (prefixes ["remember"; "smart"; "rollup"]
      @@ SoruAlias.fresh_alias_param @@ SoruAlias.source_param @@ stop)
      (fun force name hash cctxt ->
        let open Lwt_result_syntax in
        let* name = SoruAlias.of_fresh cctxt force name in
        SoruAlias.add ~force cctxt name hash);
    command
      ~group
      ~desc:"Remove a smart rollup from the wallet."
      no_options
      (prefixes ["forget"; "smart"; "rollup"] @@ SoruAlias.alias_param @@ stop)
      (fun () (name, _) cctxt -> SoruAlias.del cctxt name);
    command
      ~group
      ~desc:"Lists all known smart rollup in the wallet."
      no_options
      (fixed ["list"; "known"; "smart"; "rollups"])
      (fun () (cctxt : Protocol_client_context.full) ->
        let open Lwt_result_syntax in
        let* smart_rollups = SoruAlias.load cctxt in
        let*! () =
          List.iter_s
            (fun (alias, rollup) ->
              cctxt#message "%s: %a" alias Sc_rollup.Address.pp rollup)
            smart_rollups
        in
        return_unit);
    command
      ~group
      ~desc:"Forget the entire wallet of known smart rollups."
      (args1 (SoruAlias.force_switch ()))
      (fixed ["forget"; "all"; "smart"; "rollups"])
      (fun force cctxt ->
        let open Lwt_result_syntax in
        let* () =
          fail_unless
            force
            (error_of_fmt "this can only be used with option --force")
        in
        SoruAlias.set cctxt []);
    command
      ~group
      ~desc:"Display a smart rollup from the wallet."
      no_options
      (prefixes ["show"; "known"; "smart"; "rollup"]
      @@ SoruAlias.alias_param @@ stop)
      (fun () (_, rollup) (cctxt : Protocol_client_context.full) ->
        let open Lwt_result_syntax in
        let*! () = cctxt#message "%a\n%!" Sc_rollup.Address.pp rollup in
        return_unit);
  ]
