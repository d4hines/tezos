(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021-2022 Nomadic Labs, <contact@nomadic-labs.com>          *)
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

type dac = {
  addresses : Tezos_crypto.Aggregate_signature.public_key_hash list;
  threshold : int;
  reveal_data_dir : string;
}

type t = {data_dir : string; rpc_addr : string; rpc_port : int; dac : dac}

let default_data_dir = Filename.concat (Sys.getenv "HOME") ".tezos-dac-node"

let data_dir_path config subpath = Filename.concat config.data_dir subpath

let relative_filename data_dir = Filename.concat data_dir "config.json"

let filename config = relative_filename config.data_dir

let default_rpc_addr = "127.0.0.1"

let default_rpc_port = 10832

let default_dac_threshold = 0

let default_dac_addresses = []

let default_reveal_data_dir =
  Filename.concat
    (Filename.concat (Sys.getenv "HOME") ".tezos-smart-rollup-node")
    "wasm_2_0_0"

let default_dac =
  {
    addresses = default_dac_addresses;
    threshold = default_dac_threshold;
    reveal_data_dir = default_reveal_data_dir;
  }

let dac_encoding : dac Data_encoding.t =
  let open Data_encoding in
  conv
    (fun {addresses; threshold; reveal_data_dir} ->
      (addresses, threshold, reveal_data_dir))
    (fun (addresses, threshold, reveal_data_dir) ->
      {addresses; threshold; reveal_data_dir})
    (obj3
       (req
          "addresses"
          (list Tezos_crypto.Aggregate_signature.Public_key_hash.encoding))
       (req "threshold" uint8)
       (req "reveal-data-dir" string))

let encoding : t Data_encoding.t =
  let open Data_encoding in
  conv
    (fun {data_dir; rpc_addr; rpc_port; dac} ->
      (data_dir, rpc_addr, rpc_port, dac))
    (fun (data_dir, rpc_addr, rpc_port, dac) ->
      {data_dir; rpc_addr; rpc_port; dac})
    (obj4
       (dft
          "data-dir"
          ~description:"Location of the data dir"
          string
          default_data_dir)
       (dft "rpc-addr" ~description:"RPC address" string default_rpc_addr)
       (dft "rpc-port" ~description:"RPC port" uint16 default_rpc_port)
       (dft
          "dac"
          ~description:"Data Availability Committee"
          dac_encoding
          default_dac))

type error += DAC_node_unable_to_write_configuration_file of string

let () =
  register_error_kind
    ~id:"dac.node.unable_to_write_configuration_file"
    ~title:"Unable to write configuration file"
    ~description:"Unable to write configuration file"
    ~pp:(fun ppf file ->
      Format.fprintf ppf "Unable to write the configuration file %s" file)
    `Permanent
    Data_encoding.(obj1 (req "file" string))
    (function
      | DAC_node_unable_to_write_configuration_file path -> Some path
      | _ -> None)
    (fun path -> DAC_node_unable_to_write_configuration_file path)

let save config =
  let open Lwt_syntax in
  let file = filename config in
  protect @@ fun () ->
  let* v =
    let* () = Lwt_utils_unix.create_dir config.data_dir in
    Lwt_utils_unix.with_atomic_open_out file @@ fun chan ->
    let json = Data_encoding.Json.construct encoding config in
    let content = Data_encoding.Json.to_string json in
    Lwt_utils_unix.write_string chan content
  in
  Lwt.return
    (Result.map_error
       (fun _ -> [DAC_node_unable_to_write_configuration_file file])
       v)

let load ~data_dir =
  let open Lwt_result_syntax in
  let+ json =
    let*! json = Lwt_utils_unix.Json.read_file (relative_filename data_dir) in
    match json with
    | Ok json -> return json
    | Error (Exn _ :: _ as e) ->
        let*! () = Event.(emit data_dir_not_found data_dir) in
        fail e
    | Error e -> fail e
  in
  let config = Data_encoding.Json.destruct encoding json in
  {config with data_dir}