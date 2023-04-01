module CommonStubs = struct
  type ctxt

  type scalar

  external allocate_g1_affine : unit -> Bls12_381.G1.affine
    = "allocate_p1_affine_stubs"

  external allocate_g2_affine : unit -> Bls12_381.G2.affine
    = "allocate_p2_affine_stubs"

  external uncompress_g1 : Bls12_381.G1.affine -> Bytes.t -> int
    = "caml_blst_p1_uncompress_stubs"

  external uncompress_g2 : Bls12_381.G2.affine -> Bytes.t -> int
    = "caml_blst_p2_uncompress_stubs"

  external allocate_scalar : unit -> scalar = "allocate_scalar_stubs"

  external scalar_of_fr : scalar -> Bls12_381.Fr.t -> int
    = "caml_blst_scalar_from_fr_stubs"

  external scalar_to_bytes_le : Bytes.t -> scalar -> int
    = "caml_blst_scalar_to_bytes_stubs"

  external keygen :
    scalar ->
    Bytes.t ->
    Unsigned.Size_t.t ->
    Bytes.t ->
    Unsigned.Size_t.t ->
    unit = "caml_bls12_381_signature_blst_signature_keygen_stubs"

  external pairing_init : bool -> Bytes.t -> Unsigned.Size_t.t -> ctxt
    = "caml_bls12_381_signature_blst_pairing_init_stubs"

  external pairing_commit : ctxt -> int
    = "caml_bls12_381_signature_blst_pairing_commit_stubs"

  external pairing_finalverify : ctxt -> bool
    = "caml_bls12_381_signature_blst_pairing_finalverify_stubs"
end

let check_unicity_lst list =
  let hashtbl = Hashtbl.create (List.length list) in
  List.for_all
    (fun x ->
      let res = not (Hashtbl.mem hashtbl x) in
      Hashtbl.add hashtbl x 0 ;
      res)
    list

let with_aggregation_ctxt ciphersuite f =
  let ciphersuite_length = Bytes.length ciphersuite in
  let ctxt =
    CommonStubs.pairing_init
      true
      ciphersuite
      (Unsigned.Size_t.of_int ciphersuite_length)
  in
  f ctxt

type sk = CommonStubs.scalar

let sk_size_in_bytes = Bls12_381.Fr.size_in_bytes

let sk_of_bytes_exn bytes =
  let buffer = CommonStubs.allocate_scalar () in
  let exn =
    Invalid_argument
      "Input should be maximum 32 bytes, encoded the secret key in little \
       endian and must be smaller than the order of Bls12_381.Fr"
  in
  if Bytes.length bytes > 32 then raise exn
  else
    try
      let sk = Bls12_381.Fr.of_bytes_exn bytes in
      ignore @@ CommonStubs.scalar_of_fr buffer sk ;
      buffer
    with Bls12_381.Fr.Not_in_field _ -> raise exn

let sk_of_bytes_opt bytes =
  try Some (sk_of_bytes_exn bytes) with Invalid_argument _ -> None

let sk_to_bytes sk =
  let bytes = Bytes.make 32 '\000' in
  ignore @@ CommonStubs.scalar_to_bytes_le bytes sk ;
  bytes

let generate_sk ?(key_info = Bytes.empty) ikm =
  let buffer_scalar = CommonStubs.allocate_scalar () in
  let key_info_length = Bytes.length key_info in
  let ikm_length = Bytes.length ikm in

  (* https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-bls-signature-04
     Section 2.3 - KeyGen

     For security, IKM MUST be infeasible to guess, e.g., generated by a trusted
     source of randomness. IKM MUST be at least 32 bytes long, but it MAY be
     longer.

     Also, blst_keygen returns a vector of zero (commit
     095a8c53787d6c91b725152ebfbbf33acf05a931) if ikm is less than 32 bytes *)
  if ikm_length < 32 then
    raise
      (Invalid_argument
         "generate_sk: ikm argument must be at least 32 bytes long")
  else
    CommonStubs.keygen
      buffer_scalar
      ikm
      (Unsigned.Size_t.of_int ikm_length)
      key_info
      (Unsigned.Size_t.of_int key_info_length) ;
  buffer_scalar

module MinPk = struct
  module Stubs = struct
    external sk_to_pk : Bls12_381.G1.t -> CommonStubs.scalar -> int
      = "caml_bls12_381_signature_blst_sk_to_pk_in_g1_stubs"

    external sign :
      Bls12_381.G2.t -> Bls12_381.G2.t -> CommonStubs.scalar -> int
      = "caml_bls12_381_signature_blst_sign_pk_in_g1_stubs"

    external pairing_chk_n_mul_n_aggr_pk_in_g1 :
      CommonStubs.ctxt ->
      Bls12_381.G1.affine ->
      bool ->
      Bls12_381.G2.affine option ->
      bool ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      int
      = "caml_bls12_381_signature_blst_pairing_chk_n_mul_n_aggr_pk_in_g1_stubs_bytecode" "caml_bls12_381_signature_blst_pairing_chk_n_mul_n_aggr_pk_in_g1_stubs"
  end

  type pk = Bytes.t

  let pk_size_in_bytes = Bls12_381.G1.size_in_bytes / 2

  let unsafe_pk_of_bytes pk_bytes = Bytes.copy pk_bytes

  let pk_of_bytes_exn pk_bytes =
    let pk_opt = Bls12_381.G1.of_compressed_bytes_opt pk_bytes in
    match pk_opt with
    | None ->
        raise
          (Invalid_argument
             (Printf.sprintf
                "%s is not a valid public key"
                Hex.(show (`Hex (Bytes.to_string pk_bytes)))))
    | Some _ -> Bytes.copy pk_bytes

  let pk_of_bytes_opt pk_bytes =
    let pk_opt = Bls12_381.G1.of_compressed_bytes_opt pk_bytes in
    match pk_opt with None -> None | Some _ -> Some (Bytes.copy pk_bytes)

  let pk_to_bytes pk_bytes = Bytes.copy pk_bytes

  let derive_pk sk =
    let buffer_g1 = Bls12_381.G1.(copy zero) in
    ignore @@ Stubs.sk_to_pk buffer_g1 sk ;
    Bls12_381.G1.to_compressed_bytes buffer_g1

  type signature = Bytes.t

  let signature_size_in_bytes = Bls12_381.G2.size_in_bytes / 2

  let unsafe_signature_of_bytes bytes = Bytes.copy bytes

  let signature_of_bytes_exn bytes =
    let opt = Bls12_381.G2.of_compressed_bytes_opt bytes in
    match opt with
    | None ->
        raise
          (Invalid_argument
             (Printf.sprintf
                "%s is not a valid signature"
                Hex.(show (`Hex (Bytes.to_string bytes)))))
    | Some _ -> Bytes.copy bytes

  let signature_of_bytes_opt bytes =
    let opt = Bls12_381.G2.of_compressed_bytes_opt bytes in
    match opt with None -> None | Some _ -> Some (Bytes.copy bytes)

  let signature_to_bytes bytes = Bytes.copy bytes

  let core_sign sk message ciphersuite =
    let hash = Bls12_381.G2.hash_to_curve message ciphersuite in
    let buffer = Bls12_381.G2.(copy zero) in
    ignore @@ Stubs.sign buffer hash sk ;
    Bls12_381.G2.to_compressed_bytes buffer

  let core_verify pk msg signature_bytes ciphersuite =
    with_aggregation_ctxt ciphersuite (fun ctxt ->
        let msg_length = Bytes.length msg in
        let unsafe_signature_affine = CommonStubs.allocate_g2_affine () in
        let res_signature =
          CommonStubs.uncompress_g2 unsafe_signature_affine signature_bytes
        in
        let unsafe_pk_affine = CommonStubs.allocate_g1_affine () in
        let res_pk = CommonStubs.uncompress_g1 unsafe_pk_affine pk in
        if res_signature = 0 && res_pk = 0 then
          let res =
            Stubs.pairing_chk_n_mul_n_aggr_pk_in_g1
              ctxt
              unsafe_pk_affine
              (* the pk argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. IMPORTANT: a test
                 called test_sign_and_verify_with_a_pk_not_in_the_subgroup does
                 exist. We can check the verification is performed correctly
                 because this call returns 3, neaning the point is not in the
                 subgroup. However, even when not verifying the point is in the
                 subgroup, the verification will fail. *)
              true
              (Some unsafe_signature_affine)
              (* the signature argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. *)
              true
              (* scalar *)
              Bytes.empty
              Unsigned.Size_t.zero
              (* msg *)
              msg
              (Unsigned.Size_t.of_int msg_length)
              (* aug *)
              Bytes.empty
              Unsigned.Size_t.zero
          in
          if res = 0 then (
            ignore @@ CommonStubs.pairing_commit ctxt ;
            CommonStubs.pairing_finalverify ctxt)
          else false
        else false)

  let aggregate_signature_opt signatures =
    let rec aux signatures acc =
      match signatures with
      | [] -> Some acc
      | signature :: signatures -> (
          let signature = Bls12_381.G2.of_compressed_bytes_opt signature in
          match signature with
          | None -> None
          | Some signature ->
              let acc = Bls12_381.G2.(add signature acc) in
              aux signatures acc)
    in
    let res = aux signatures Bls12_381.G2.zero in
    Option.map Bls12_381.G2.to_compressed_bytes res

  let core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite =
    let rec aux aggregated_signature pks_with_msgs ctxt =
      match pks_with_msgs with
      | (unsafe_pk_affine, msg) :: rest ->
          let msg_length = Bytes.length msg in
          (* sign the message *)
          let res =
            Stubs.pairing_chk_n_mul_n_aggr_pk_in_g1
              ctxt
              unsafe_pk_affine
              (* the signature argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. *)
              true
              aggregated_signature
              (* IMPORTANT: does not check signature is a point on the curve and
                 in the subgroup, it is verified by of_compressed_bytes_opt
                 below. *)
              false
              (* scalar *)
              Bytes.empty
              Unsigned.Size_t.zero
              (* msg *)
              msg
              (Unsigned.Size_t.of_int msg_length)
              (* aug *)
              Bytes.empty
              Unsigned.Size_t.zero
          in
          if res = 0 then
            (* signature: must be null except the first one *)
            aux None rest ctxt
          else false
      | [] -> true
    in
    (* IMPORTANT: the verification the aggregated signature is in the subgroup
       is performed here. *)
    let aggregated_signature_opt =
      Bls12_381.G2.of_compressed_bytes_opt aggregated_signature
    in
    (* Converts the pk received as bytes in points on the curve. There are no
       checks about points belonging to the subgroup. It is verified when
       calling the auxiliary function. *)
    let pks = List.map fst pks_with_msgs in
    let are_pks_on_curve = ref true in
    let unsafe_pks_affine =
      List.map
        (fun pk_bytes ->
          let pk_affine = CommonStubs.allocate_g1_affine () in
          let res = CommonStubs.uncompress_g1 pk_affine pk_bytes in
          are_pks_on_curve := res = 0 && !are_pks_on_curve ;
          pk_affine)
        pks
    in
    let pks_with_msgs =
      List.map2
        (fun pk_affine (_, msg) -> (pk_affine, msg))
        unsafe_pks_affine
        pks_with_msgs
    in
    if !are_pks_on_curve then
      match aggregated_signature_opt with
      | None -> false
      | Some aggregated_signature ->
          with_aggregation_ctxt ciphersuite (fun ctxt ->
              let signature_affine =
                Bls12_381.G2.affine_of_jacobian aggregated_signature
              in
              let res = aux (Some signature_affine) pks_with_msgs ctxt in
              if res then (
                ignore @@ CommonStubs.pairing_commit ctxt ;
                CommonStubs.pairing_finalverify ctxt)
              else false)
    else false

  module Basic = struct
    let ciphersuite =
      Bytes.of_string "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_"

    let sign sk message = core_sign sk message ciphersuite

    let verify pk msg signature = core_verify pk msg signature ciphersuite

    let aggregate_verify pks_with_msgs aggregated_signature =
      let msgs = List.map snd pks_with_msgs in
      if check_unicity_lst msgs then
        core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite
      else raise (Invalid_argument "Messages must be distinct")
  end

  module Aug = struct
    let ciphersuite =
      Bytes.of_string "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_AUG_"

    let sign sk msg =
      let pk = derive_pk sk in
      (* Important note: we concatenate with the compressed representation of
         the point! *)
      let msg = Bytes.concat Bytes.empty [pk; msg] in
      core_sign sk msg ciphersuite

    let verify pk msg signature =
      (* Important note: we concatenate with the compressed representation of
         the point! *)
      let msg = Bytes.concat Bytes.empty [pk; msg] in
      core_verify pk msg signature ciphersuite

    let aggregate_verify pks_with_msgs aggregated_signature =
      let pks_with_msgs =
        List.map
          (fun (pk, msg) -> (pk, Bytes.concat Bytes.empty [pk; msg]))
          pks_with_msgs
      in
      core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite
  end

  module Pop = struct
    type proof = Bytes.t

    let sign sk message =
      let ciphersuite =
        Bytes.of_string "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_sign sk message ciphersuite

    let verify pk msg signature =
      let ciphersuite =
        Bytes.of_string "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_verify pk msg signature ciphersuite

    let pop_prove sk =
      let ciphersuite =
        Bytes.of_string "BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
      in
      let pk = derive_pk sk in
      core_sign sk pk ciphersuite

    let pop_verify pk signature =
      let ciphersuite =
        Bytes.of_string "BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_verify pk pk signature ciphersuite

    let aggregate_verify pks_with_pops msg aggregated_signature =
      let pks_bytes = List.map fst pks_with_pops in
      let pks_opts = List.map Bls12_381.G1.of_compressed_bytes_opt pks_bytes in
      let pks_are_ok = List.for_all Option.is_some pks_opts in
      if not pks_are_ok then false
      else
        let pks = List.map Option.get pks_opts in
        let aggregated_pk =
          List.fold_left Bls12_381.G1.add Bls12_381.G1.zero pks
        in
        let aggregated_pk = Bls12_381.G1.to_compressed_bytes aggregated_pk in
        let signature_check = verify aggregated_pk msg aggregated_signature in
        let pop_checks =
          List.for_all
            (fun (pk, signature) -> pop_verify pk signature)
            pks_with_pops
        in
        pop_checks && signature_check
  end
end

module MinSig = struct
  module Stubs = struct
    external sk_to_pk : Bls12_381.G2.t -> CommonStubs.scalar -> int
      = "caml_bls12_381_signature_blst_sk_to_pk_in_g2_stubs"

    external sign :
      Bls12_381.G1.t -> Bls12_381.G1.t -> CommonStubs.scalar -> int
      = "caml_bls12_381_signature_blst_sign_pk_in_g2_stubs"

    external pairing_chk_n_mul_n_aggr_pk_in_g2 :
      CommonStubs.ctxt ->
      Bls12_381.G2.affine ->
      bool ->
      Bls12_381.G1.affine option ->
      bool ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      Bytes.t ->
      Unsigned.Size_t.t ->
      int
      = "caml_bls12_381_signature_blst_pairing_chk_n_mul_n_aggr_pk_in_g2_stubs_bytecode" "caml_bls12_381_signature_blst_pairing_chk_n_mul_n_aggr_pk_in_g2_stubs"
  end

  type pk = Bytes.t

  let pk_size_in_bytes = Bls12_381.G2.size_in_bytes / 2

  let unsafe_pk_of_bytes pk_bytes = Bytes.copy pk_bytes

  let pk_of_bytes_exn pk_bytes =
    let pk_opt = Bls12_381.G2.of_compressed_bytes_opt pk_bytes in
    match pk_opt with
    | None ->
        raise
          (Invalid_argument
             (Printf.sprintf
                "%s is not a valid public key"
                Hex.(show (`Hex (Bytes.to_string pk_bytes)))))
    | Some _ -> Bytes.copy pk_bytes

  let pk_of_bytes_opt pk_bytes =
    let pk_opt = Bls12_381.G2.of_compressed_bytes_opt pk_bytes in
    match pk_opt with None -> None | Some _ -> Some (Bytes.copy pk_bytes)

  let pk_to_bytes pk_bytes = Bytes.copy pk_bytes

  let derive_pk sk =
    let buffer = Bls12_381.G2.(copy one) in
    ignore @@ Stubs.sk_to_pk buffer sk ;
    Bls12_381.G2.to_compressed_bytes buffer

  type signature = Bytes.t

  let signature_size_in_bytes = Bls12_381.G1.size_in_bytes / 2

  let unsafe_signature_of_bytes bytes = Bytes.copy bytes

  let signature_of_bytes_exn bytes =
    let opt = Bls12_381.G1.of_compressed_bytes_opt bytes in
    match opt with
    | None ->
        raise
          (Invalid_argument
             (Printf.sprintf
                "%s is not a valid signature"
                Hex.(show (`Hex (Bytes.to_string bytes)))))
    | Some _ -> Bytes.copy bytes

  let signature_of_bytes_opt bytes =
    let opt = Bls12_381.G1.of_compressed_bytes_opt bytes in
    match opt with None -> None | Some _ -> Some (Bytes.copy bytes)

  let signature_to_bytes bytes = Bytes.copy bytes

  let core_sign sk message ciphersuite =
    let hash = Bls12_381.G1.hash_to_curve message ciphersuite in
    let buffer = Bls12_381.G1.(copy one) in
    ignore @@ Stubs.sign buffer hash sk ;
    Bls12_381.G1.to_compressed_bytes buffer

  let core_verify pk msg signature_bytes ciphersuite =
    with_aggregation_ctxt ciphersuite (fun ctxt ->
        let msg_length = Bytes.length msg in
        let unsafe_signature_affine = CommonStubs.allocate_g1_affine () in
        let res_signature =
          CommonStubs.uncompress_g1 unsafe_signature_affine signature_bytes
        in
        let unsafe_pk_affine = CommonStubs.allocate_g2_affine () in
        let res_pk = CommonStubs.uncompress_g2 unsafe_pk_affine pk in
        if res_signature = 0 && res_pk = 0 then
          let res =
            Stubs.pairing_chk_n_mul_n_aggr_pk_in_g2
              ctxt
              unsafe_pk_affine
              (* the pk argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. IMPORTANT: a test
                 called test_sign_and_verify_with_a_pk_not_in_the_subgroup does
                 exist. We can check the verification is performed correctly
                 because this call returns 3, neaning the point is not in the
                 subgroup. However, even when not verifying the point is in the
                 subgroup, the verification will fail. *)
              true
              (Some unsafe_signature_affine)
              (* the signature argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. *)
              true
              (* scalar *)
              Bytes.empty
              Unsigned.Size_t.zero
              (* msg *)
              msg
              (Unsigned.Size_t.of_int msg_length)
              (* aug *)
              Bytes.empty
              Unsigned.Size_t.zero
          in
          if res = 0 then (
            ignore @@ CommonStubs.pairing_commit ctxt ;
            CommonStubs.pairing_finalverify ctxt)
          else false
        else false)

  let aggregate_signature_opt signatures =
    let rec aux signatures acc =
      match signatures with
      | [] -> Some acc
      | signature :: signatures -> (
          let signature = Bls12_381.G1.of_compressed_bytes_opt signature in
          match signature with
          | None -> None
          | Some signature ->
              let acc = Bls12_381.G1.(add signature acc) in
              aux signatures acc)
    in
    let res = aux signatures Bls12_381.G1.zero in
    Option.map Bls12_381.G1.to_compressed_bytes res

  let core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite =
    let rec aux aggregated_signature pks_with_msgs ctxt =
      match pks_with_msgs with
      | (unsafe_pk_affine, msg) :: rest ->
          let msg_length = Bytes.length msg in
          (* sign the message *)
          let res =
            Stubs.pairing_chk_n_mul_n_aggr_pk_in_g2
              ctxt
              unsafe_pk_affine
              (* the signature argument might not be in the subgroup even if the
                 decompression went successfull. `true` means the function must
                 verify the point is in the prime subgroup. *)
              true
              aggregated_signature
              (* IMPORTANT: does not check signature is a point on the curve and
                 in the subgroup, it is verified by of_compressed_bytes_opt
                 below. *)
              false
              (* scalar *)
              Bytes.empty
              Unsigned.Size_t.zero
              (* msg *)
              msg
              (Unsigned.Size_t.of_int msg_length)
              (* aug *)
              Bytes.empty
              Unsigned.Size_t.zero
          in
          if res = 0 then
            (* signature: must be null except the first one *)
            aux None rest ctxt
          else false
      | [] -> true
    in
    (* IMPORTANT: the verification the aggregated signature is in the subgroup
       is performed here. *)
    let aggregated_signature_opt =
      Bls12_381.G1.of_compressed_bytes_opt aggregated_signature
    in
    (* Converts the pk received as bytes in points on the curve. There are no
       checks about points belonging to the subgroup. It is verified when
       calling the auxiliary function. *)
    let pks = List.map fst pks_with_msgs in
    let are_pks_on_curve = ref true in
    let unsafe_pks_affine =
      List.map
        (fun pk_bytes ->
          let pk_affine = CommonStubs.allocate_g2_affine () in
          let res = CommonStubs.uncompress_g2 pk_affine pk_bytes in
          are_pks_on_curve := res = 0 && !are_pks_on_curve ;
          pk_affine)
        pks
    in
    let pks_with_msgs =
      List.map2
        (fun pk_affine (_, msg) -> (pk_affine, msg))
        unsafe_pks_affine
        pks_with_msgs
    in
    if !are_pks_on_curve then
      match aggregated_signature_opt with
      | None -> false
      | Some aggregated_signature ->
          with_aggregation_ctxt ciphersuite (fun ctxt ->
              let signature_affine =
                Bls12_381.G1.affine_of_jacobian aggregated_signature
              in
              let res = aux (Some signature_affine) pks_with_msgs ctxt in
              if res then (
                ignore @@ CommonStubs.pairing_commit ctxt ;
                CommonStubs.pairing_finalverify ctxt)
              else false)
    else false

  module Basic = struct
    let ciphersuite =
      Bytes.of_string "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"

    let sign sk message = core_sign sk message ciphersuite

    let verify pk msg signature = core_verify pk msg signature ciphersuite

    let aggregate_verify pks_with_msgs aggregated_signature =
      let msgs = List.map snd pks_with_msgs in
      if check_unicity_lst msgs then
        core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite
      else raise (Invalid_argument "Messages must be distinct")
  end

  module Aug = struct
    let ciphersuite =
      Bytes.of_string "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_AUG_"

    let sign sk msg =
      let pk = derive_pk sk in
      (* Important note: we concatenate with the compressed representation of
         the point! *)
      let msg = Bytes.concat Bytes.empty [pk; msg] in
      core_sign sk msg ciphersuite

    let verify pk msg signature =
      (* Important note: we concatenate with the compressed representation of
         the point! *)
      let msg = Bytes.concat Bytes.empty [pk; msg] in
      core_verify pk msg signature ciphersuite

    let aggregate_verify pks_with_msgs aggregated_signature =
      let pks_with_msgs =
        List.map
          (fun (pk, msg) -> (pk, Bytes.concat Bytes.empty [pk; msg]))
          pks_with_msgs
      in
      core_aggregate_verify pks_with_msgs aggregated_signature ciphersuite
  end

  module Pop = struct
    type proof = Bytes.t

    let sign sk message =
      let ciphersuite =
        Bytes.of_string "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_sign sk message ciphersuite

    let verify pk msg signature =
      let ciphersuite =
        Bytes.of_string "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_verify pk msg signature ciphersuite

    let pop_prove sk =
      let ciphersuite =
        Bytes.of_string "BLS_POP_BLS12381G1_XMD:SHA-256_SSWU_RO_POP_"
      in
      let pk = derive_pk sk in
      core_sign sk pk ciphersuite

    let pop_verify pk signature =
      let ciphersuite =
        Bytes.of_string "BLS_POP_BLS12381G1_XMD:SHA-256_SSWU_RO_POP_"
      in
      core_verify pk pk signature ciphersuite

    let aggregate_verify pks_with_pops msg aggregated_signature =
      let pks_bytes = List.map fst pks_with_pops in
      let pks_opts = List.map Bls12_381.G2.of_compressed_bytes_opt pks_bytes in
      let pks_are_ok = List.for_all Option.is_some pks_opts in
      if not pks_are_ok then false
      else
        let pks = List.map Option.get pks_opts in
        let aggregated_pk =
          List.fold_left Bls12_381.G2.add Bls12_381.G2.zero pks
        in
        let aggregated_pk = Bls12_381.G2.to_compressed_bytes aggregated_pk in
        let signature_check = verify aggregated_pk msg aggregated_signature in
        let pop_checks =
          List.for_all
            (fun (pk, signature) -> pop_verify pk signature)
            pks_with_pops
        in
        pop_checks && signature_check
  end
end
