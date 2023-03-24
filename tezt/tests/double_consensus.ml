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

(* Testing
   -------
   Component:    Accuser
   Invocation:   dune exec tezt/tests/main.exe -- --file double_consensus.ml
   Subject:      Detect double (pre)endorsement through the accuser.
*)

let double_endorsement_waiter accuser =
  Accuser.wait_for accuser "double_endorsement_denounced.v0" (fun _ -> Some ())

let double_preendorsement_waiter accuser =
  Accuser.wait_for accuser "double_preendorsement_denounced.v0" (fun _ ->
      Some ())

let double_consensus_already_denounced_waiter accuser oph =
  Accuser.wait_for accuser "double_consensus_already_denounced.v0" (fun json ->
      if String.equal (JSON.as_string json) oph then Some () else None)

let get_double_consensus_denounciation_hash consensus_name client =
  let* mempool =
    RPC.Client.call client @@ RPC.get_chain_mempool_pending_operations ()
  in
  let ops = JSON.(mempool |-> "applied" |> as_list) in
  let op =
    List.find_map
      (fun op ->
        let kind =
          JSON.(op |-> "contents" |> as_list |> List.hd |-> "kind" |> as_string)
        in
        if String.equal kind (sf "double_%s_evidence" consensus_name) then
          Some JSON.(op |-> "hash" |> as_string)
        else None)
      ops
  in
  match op with
  | None -> failwith "Denunciation not found in the mempool"
  | Some op -> return op

let double_endorsement_init
    (consensus_for :
      ?endpoint:Client.endpoint ->
      ?protocol:Protocol.t ->
      ?key:string list ->
      ?force:bool ->
      Client.t ->
      unit Lwt.t) consensus_name protocol () =
  let* node, client = Client.init_with_protocol ~protocol `Client () in
  let* accuser = Accuser.init ~event_level:`Debug ~protocol node in
  let* () = repeat 5 (fun () -> Client.bake_for client) in
  Log.info "Recover available slots for %s." Constant.bootstrap1.alias ;
  let* slots =
    RPC.Client.call client
    @@ RPC.get_chain_block_helper_validators
         ~delegate:Constant.bootstrap1.public_key_hash
         ()
  in
  let slots =
    List.map
      JSON.as_int
      JSON.(List.hd JSON.(slots |> as_list) |-> "slots" |> as_list)
  in
  Log.info "Inject valid %s." consensus_name ;
  let waiter = Node.wait_for_request ~request:`Inject node in
  let* () =
    consensus_for ~protocol ~force:true ~key:[Constant.bootstrap1.alias] client
  in
  let* () = waiter in
  Log.info "Get mempool and recover consensus information." ;
  let* mempool =
    RPC.Client.call client @@ RPC.get_chain_mempool_pending_operations ()
  in
  let op = List.hd JSON.(mempool |-> "applied" |> as_list) in
  let branch = JSON.(op |-> "branch" |> as_string) in
  let content = JSON.(op |-> "contents" |> as_list |> List.hd) in
  let level = JSON.(content |-> "level" |> as_int) in
  let round = JSON.(content |-> "round" |> as_int) in
  let block_payload_hash =
    JSON.(content |-> "block_payload_hash" |> as_string)
  in
  return ((client, accuser), (branch, level, round, slots, block_payload_hash))

let double_consensus_wrong_slot
    (consensus_for, mk_consensus, consensus_waiter, consensus_name) protocol =
  let* (client, accuser), (branch, level, round, slots, block_payload_hash) =
    double_endorsement_init consensus_for consensus_name protocol ()
  in
  Log.info "Inject an invalid %s and wait for denounciation" consensus_name ;
  let op =
    mk_consensus ~slot:(List.nth slots 1) ~level ~round ~block_payload_hash
  in
  let waiter = consensus_waiter accuser in
  let* _ =
    Operation.Consensus.inject ~branch ~signer:Constant.bootstrap1 op client
  in
  let* () = waiter in
  Log.info
    "Inject another invalid %s and wait for already_denounced event"
    consensus_name ;
  let op =
    mk_consensus ~slot:(List.nth slots 2) ~level ~round ~block_payload_hash
  in
  let* oph = get_double_consensus_denounciation_hash consensus_name client in
  let waiter_already_denounced =
    double_consensus_already_denounced_waiter accuser oph
  in
  let* _ =
    Operation.Consensus.inject ~branch ~signer:Constant.bootstrap1 op client
  in
  let* () = waiter_already_denounced in
  unit

let endorse_utils =
  ( Client.endorse_for,
    Operation.Consensus.endorsement,
    double_endorsement_waiter,
    "endorsement" )

let preendorse_utils =
  ( Client.preendorse_for,
    Operation.Consensus.preendorsement,
    double_preendorsement_waiter,
    "preendorsement" )

let double_endorsement_wrong_slot =
  Protocol.register_test
    ~__FILE__
    ~title:"double endorsement using wrong slot"
    ~supports:Protocol.(From_protocol (number Nairobi))
    ~tags:["double"; "endorsement"; "accuser"; "slot"; "node"]
  @@ fun protocol -> double_consensus_wrong_slot endorse_utils protocol

let double_preendorsement_wrong_slot =
  Protocol.register_test
    ~__FILE__
    ~title:"double preendorsement using wrong slot"
    ~supports:Protocol.(From_protocol (number Nairobi))
    ~tags:["double"; "preendorsement"; "accuser"; "slot"; "node"]
  @@ fun protocol -> double_consensus_wrong_slot preendorse_utils protocol

let double_consensus_wrong_block_payload_hash
    (consensus_for, mk_consensus, consensus_waiter, consensus_name) protocol =
  let* (client, accuser), (branch, level, round, slots, _block_payload_hash) =
    double_endorsement_init consensus_for consensus_name protocol ()
  in
  let* header =
    RPC.Client.call client @@ RPC.get_chain_block_header ~block:"head~2" ()
  in
  let block_payload_hash = JSON.(header |-> "payload_hash" |> as_string) in
  Log.info "Inject an invalid %s and wait for denounciation" consensus_name ;
  let op =
    mk_consensus ~slot:(List.nth slots 0) ~level ~round ~block_payload_hash
  in
  let waiter = consensus_waiter accuser in
  let* _ =
    Operation.Consensus.inject
      ~force:true
      ~branch
      ~signer:Constant.bootstrap1
      op
      client
  in
  let* () = waiter in
  Log.info
    "Inject another invalid %s and wait for already_denounced event"
    consensus_name ;
  let* header =
    RPC.Client.call client @@ RPC.get_chain_block_header ~block:"head~3" ()
  in
  let block_payload_hash = JSON.(header |-> "payload_hash" |> as_string) in
  let op =
    mk_consensus ~slot:(List.nth slots 2) ~level ~round ~block_payload_hash
  in
  let* oph = get_double_consensus_denounciation_hash consensus_name client in
  let waiter_already_denounced =
    double_consensus_already_denounced_waiter accuser oph
  in
  let* _ =
    Operation.Consensus.inject
      ~force:true
      ~branch
      ~signer:Constant.bootstrap1
      op
      client
  in
  let* () = waiter_already_denounced in
  unit

let double_endorsement_wrong_block_payload_hash =
  Protocol.register_test
    ~__FILE__
    ~title:"double endorsement using wrong block_payload_hash"
    ~supports:Protocol.(From_protocol (number Nairobi))
    ~tags:["double"; "endorsement"; "accuser"; "block_payload_hash"; "node"]
  @@ fun protocol ->
  double_consensus_wrong_block_payload_hash endorse_utils protocol

let double_preendorsement_wrong_block_payload_hash =
  Protocol.register_test
    ~__FILE__
    ~title:"double preendorsement using wrong block_payload_hash"
    ~supports:Protocol.(From_protocol (number Nairobi))
    ~tags:["double"; "preendorsement"; "accuser"; "block_payload_hash"; "node"]
  @@ fun protocol ->
  double_consensus_wrong_block_payload_hash preendorse_utils protocol

let register ~protocols =
  double_endorsement_wrong_slot protocols ;
  double_preendorsement_wrong_slot protocols ;
  double_endorsement_wrong_block_payload_hash protocols ;
  double_preendorsement_wrong_block_payload_hash protocols
