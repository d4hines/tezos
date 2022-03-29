(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs, <contact@nomadic-labs.com>               *)
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
open Script_typed_ir

(** {2 [Script_ir_translator] benchmarks} *)

module Config = struct
  type config = {
    generator_config : Michelson_generation.generator_config;
    michelson_terms_file : string option;
  }

  let default_config =
    {
      generator_config = Michelson_generation.default_generator_config;
      michelson_terms_file = None;
    }

  let config_encoding =
    let open Data_encoding in
    conv
      (fun {generator_config; michelson_terms_file} ->
        (generator_config, michelson_terms_file))
      (fun (generator_config, michelson_terms_file) ->
        {generator_config; michelson_terms_file})
      (obj2
         (req "generator_config" Michelson_generation.generator_config_encoding)
         (opt "michelson_terms_file" string))
end

module Default_boilerplate = struct
  type workload = Translator_workload.t

  let workload_encoding = Translator_workload.encoding

  let workload_to_vector = Translator_workload.workload_to_sparse_vec

  let tags = [Tags.translator]

  let make_models t_kind code_or_data =
    [
      ( "gas_translator_model",
        Translator_model.gas_based_model t_kind code_or_data );
      ( "size_translator_model",
        Translator_model.size_based_model t_kind code_or_data );
    ]
end

(* ----------------------------------------------------------------------- *)
(* Error handling *)

type phase = Workload_production | In_protocol | Global

type error_kind =
  | Global_error of {
      benchmark_name : string;
      workload : Tezos_base.TzPervasives.tztrace;
    }
  | Bad_data of {
      benchmark_name : string;
      micheline : Alpha_context.Script.expr;
      expected_type : Alpha_context.Script.expr;
      phase : phase;
    }
  | Bad_code of {
      benchmark_name : string;
      micheline : Alpha_context.Script.expr;
      expected_stack_type : Alpha_context.Script.expr list;
      phase : phase;
    }

let pp_phase fmtr (phase : phase) =
  match phase with
  | Workload_production -> Format.fprintf fmtr "workload production"
  | In_protocol -> Format.fprintf fmtr "in protocol"
  | Global -> Format.fprintf fmtr "global"

let report_michelson_errors fmtr errs =
  Michelson_v1_error_reporter.report_errors
    ~details:true
    ~show_source:true
    fmtr
    errs

let make_printable node =
  Micheline_printer.printable Michelson_v1_primitives.string_of_prim node

let pp_error_kind fmtr (error_kind : error_kind) =
  match error_kind with
  | Global_error {benchmark_name; workload} ->
      Format.open_vbox 1 ;
      Format.fprintf fmtr "Global error:@," ;
      Format.fprintf fmtr "benchmark = %s@," benchmark_name ;
      Format.fprintf fmtr "workload:@," ;
      report_michelson_errors fmtr workload ;
      Format.close_box ()
  | Bad_data {benchmark_name; micheline; expected_type; phase} ->
      Format.open_vbox 1 ;
      Format.fprintf fmtr "Bad data:@," ;
      Format.fprintf fmtr "benchmark = %s@," benchmark_name ;
      Format.fprintf
        fmtr
        "expression = @[<v 1>%a@]@,"
        Micheline_printer.print_expr
        (make_printable micheline) ;
      Format.fprintf
        fmtr
        "expected type = @[<v 1>%a@]@,"
        Micheline_printer.print_expr
        (make_printable expected_type) ;
      Format.fprintf fmtr "phase = %a@," pp_phase phase ;
      Format.close_box ()
  | Bad_code {benchmark_name; micheline; expected_stack_type; phase} ->
      Format.open_vbox 1 ;
      Format.fprintf fmtr "Bad code:@," ;
      Format.fprintf fmtr "benchmark = %s@," benchmark_name ;
      Format.fprintf
        fmtr
        "expression = @[<v 1>%a@]@,"
        Micheline_printer.print_expr
        (make_printable micheline) ;
      Format.fprintf
        fmtr
        "expected stack = @[<v 1>%a@]@,"
        (Format.pp_print_list
           ~pp_sep:(fun fmtr () -> Format.fprintf fmtr "::")
           (fun fmtr node ->
             let printable = make_printable node in
             Format.fprintf fmtr "%a" Micheline_printer.print_expr printable))
        expected_stack_type ;
      Format.fprintf fmtr "phase = %a@," pp_phase phase ;
      Format.close_box ()

exception Translator_benchmark_error of error_kind

let () =
  Printexc.register_printer (function
      | Translator_benchmark_error err ->
          Some (Format.asprintf "%a" pp_error_kind err)
      | _ -> None)

let global_error benchmark_name workload =
  raise (Translator_benchmark_error (Global_error {benchmark_name; workload}))

let bad_data benchmark_name micheline expected_type phase =
  raise
    (Translator_benchmark_error
       (Bad_data {benchmark_name; micheline; expected_type; phase}))

let bad_code benchmark_name micheline expected_stack_type phase =
  raise
    (Translator_benchmark_error
       (Bad_code {benchmark_name; micheline; expected_stack_type; phase}))

(* ----------------------------------------------------------------------- *)
(* Typechecking data (Micheline data -> typed data) *)

module Typechecking_data : Benchmark.S = struct
  include Config
  include Default_boilerplate

  let models = make_models Translator_workload.Parsing Translator_workload.Data

  let name = "TYPECHECKING_DATA"

  let info = "Benchmarking typechecking of data"

  let typechecking_data_benchmark rng_state (node : Protocol.Script_repr.expr)
      (michelson_type : Script_repr.expr) =
    Lwt_main.run
      ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
        let ex_ty = Type_helpers.michelson_type_to_ex_ty michelson_type ctxt in
        let workload =
          match
            Translator_workload.data_typechecker_workload
              ctxt
              Translator_workload.Parsing
              (Micheline.root node)
              ex_ty
          with
          | None -> bad_data name node michelson_type Workload_production
          | Some workload -> workload
        in
        match ex_ty with
        | Script_ir_translator.Ex_ty ty ->
            let closure () =
              match
                Lwt_main.run
                  (Script_ir_translator.parse_data
                     ctxt
                     ~legacy:false
                     ~allow_forged:false
                     ty
                     (Micheline.root node))
              with
              | Error _ | (exception _) ->
                  bad_data name node michelson_type In_protocol
              | Ok _ -> ()
            in
            return (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let make_bench rng_state cfg () =
    let Michelson_mcmc_samplers.{term; typ} =
      Michelson_generation.make_data_sampler rng_state cfg.generator_config
    in
    typechecking_data_benchmark rng_state term typ

  let create_benchmarks ~rng_state ~bench_num config =
    match config.michelson_terms_file with
    | Some file ->
        Format.eprintf "Loading terms from %s@." file ;
        let terms = Michelson_mcmc_samplers.load ~filename:file in
        List.filter_map
          (function
            | Michelson_mcmc_samplers.Data {term; typ} ->
                Some (fun () -> typechecking_data_benchmark rng_state term typ)
            | _ -> None)
          terms
    | None ->
        Format.eprintf "No michelson_terms_file given, generating on-the-fly@." ;
        List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Typechecking_data)

module Unparsing_data : Benchmark.S = struct
  include Config
  include Default_boilerplate

  let models =
    make_models Translator_workload.Unparsing Translator_workload.Data

  let name = "UNPARSING_DATA"

  let info = "Benchmarking unparsing of data"

  let unparsing_data_benchmark rng_state (node : Protocol.Script_repr.expr)
      (michelson_type : Protocol.Script_repr.expr) =
    Lwt_main.run
      ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
        let ex_ty = Type_helpers.michelson_type_to_ex_ty michelson_type ctxt in
        let workload =
          match
            Translator_workload.data_typechecker_workload
              ctxt
              Translator_workload.Unparsing
              (Micheline.root node)
              ex_ty
          with
          | None -> bad_data name node michelson_type Workload_production
          | Some workload -> workload
        in
        match ex_ty with
        | Script_ir_translator.Ex_ty ty ->
            Script_ir_translator.parse_data
              ctxt
              ~legacy:false
              ~allow_forged:false
              ty
              (Micheline.root node)
            >|= Environment.wrap_tzresult
            >>=? fun (typed, ctxt) ->
            let closure () =
              match
                Lwt_main.run
                  (Script_ir_translator.unparse_data
                     ctxt
                     Script_ir_translator.Optimized
                     ty
                     typed)
              with
              | Error _ | (exception _) ->
                  bad_data name node michelson_type In_protocol
              | Ok _ -> ()
            in
            return (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let make_bench rng_state cfg () =
    let Michelson_mcmc_samplers.{term; typ} =
      Michelson_generation.make_data_sampler rng_state cfg.generator_config
    in
    unparsing_data_benchmark rng_state term typ

  let create_benchmarks ~rng_state ~bench_num config =
    match config.michelson_terms_file with
    | Some file ->
        Format.eprintf "Loading terms from %s@." file ;
        let terms = Michelson_mcmc_samplers.load ~filename:file in
        List.filter_map
          (function
            | Michelson_mcmc_samplers.Data {term; typ} ->
                Some (fun () -> unparsing_data_benchmark rng_state term typ)
            | _ -> None)
          terms
    | None ->
        Format.eprintf "No michelson_terms_file given, generating on-the-fly@." ;
        List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Unparsing_data)

module Typechecking_code : Benchmark.S = struct
  include Config
  include Default_boilerplate

  let models = make_models Translator_workload.Parsing Translator_workload.Code

  let name = "TYPECHECKING_CODE"

  let info = "Benchmarking typechecking of code"

  let typechecking_code_benchmark rng_state (node : Protocol.Script_repr.expr)
      (stack : Script_repr.expr list) =
    Lwt_main.run
      ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
        let ex_stack_ty =
          Type_helpers.michelson_type_list_to_ex_stack_ty stack ctxt
        in
        let workload =
          match
            Translator_workload.code_typechecker_workload
              ctxt
              Translator_workload.Parsing
              (Micheline.root node)
              ex_stack_ty
          with
          | None -> bad_code name node stack Workload_production
          | Some workload -> workload
        in
        let (Script_ir_translator.Ex_stack_ty bef) = ex_stack_ty in
        let closure () =
          let result =
            Lwt_main.run
              (Script_ir_translator.parse_instr
                 Script_ir_translator.Lambda
                 ctxt
                 ~legacy:false
                 (Micheline.root node)
                 bef)
          in
          match Environment.wrap_tzresult result with
          | Error trace ->
              Format.eprintf "%a@." Error_monad.pp_print_trace trace ;
              bad_code name node stack In_protocol
          | Ok _ -> ()
        in
        return (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let make_bench rng_state (cfg : Config.config) () =
    let open Michelson_generation in
    let Michelson_mcmc_samplers.{term; bef; aft = _} =
      make_code_sampler rng_state cfg.generator_config
    in
    typechecking_code_benchmark rng_state term bef

  let create_benchmarks ~rng_state ~bench_num config =
    match config.michelson_terms_file with
    | Some file ->
        Format.eprintf "Loading terms from %s@." file ;
        let terms = Michelson_mcmc_samplers.load ~filename:file in
        List.filter_map
          (function
            | Michelson_mcmc_samplers.Code {term; bef; aft = _} ->
                Some (fun () -> typechecking_code_benchmark rng_state term bef)
            | _ -> None)
          terms
    | None ->
        Format.eprintf "No michelson_terms_file given, generating on-the-fly@." ;
        List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Typechecking_code)

module Unparsing_code : Benchmark.S = struct
  include Config
  include Default_boilerplate

  let models =
    make_models Translator_workload.Unparsing Translator_workload.Code

  let name = "UNPARSING_CODE"

  let info = "Benchmarking unparsing of code"

  let unparsing_code_benchmark rng_state (node : Protocol.Script_repr.expr)
      (stack : Script_repr.expr list) =
    Lwt_main.run
      ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
        let ex_stack_ty =
          Type_helpers.michelson_type_list_to_ex_stack_ty stack ctxt
        in
        let workload =
          match
            Translator_workload.code_typechecker_workload
              ctxt
              Translator_workload.Unparsing
              (Micheline.root node)
              ex_stack_ty
          with
          | None -> bad_code name node stack Workload_production
          | Some workload -> workload
        in
        let (Script_ir_translator.Ex_stack_ty bef) = ex_stack_ty in
        (* We parse the code just to check it is well-typed. *)
        Script_ir_translator.parse_instr
          Script_ir_translator.Lambda
          ctxt
          ~legacy:false
          (Micheline.root node)
          bef
        >|= Environment.wrap_tzresult
        >>=? fun (_typed, ctxt) ->
        let closure () =
          let result =
            Lwt_main.run
              (Script_ir_translator.unparse_code
                 ctxt
                 Optimized
                 (Micheline.root node))
          in
          match Environment.wrap_tzresult result with
          | Error trace ->
              Format.eprintf "%a@." Error_monad.pp_print_trace trace ;
              bad_code name node stack In_protocol
          | Ok _ -> ()
        in
        return (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let make_bench rng_state (cfg : Config.config) () =
    let open Michelson_generation in
    let Michelson_mcmc_samplers.{term; bef; aft = _} =
      make_code_sampler rng_state cfg.generator_config
    in
    unparsing_code_benchmark rng_state term bef

  let create_benchmarks ~rng_state ~bench_num config =
    match config.michelson_terms_file with
    | Some file ->
        Format.eprintf "Loading terms from %s@." file ;
        let terms = Michelson_mcmc_samplers.load ~filename:file in
        List.filter_map
          (function
            | Michelson_mcmc_samplers.Code {term; bef; aft = _} ->
                Some (fun () -> unparsing_code_benchmark rng_state term bef)
            | _ -> None)
          terms
    | None -> List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Unparsing_code)

let rec check_printable_ascii v i =
  if Compare.Int.(i < 0) then true
  else
    match v.[i] with
    | '\n' | '\x20' .. '\x7E' -> check_printable_ascii v (i - 1)
    | _ -> false

let check_printable_benchmark =
  let open Tezos_shell_benchmarks.Encoding_benchmarks_helpers in
  linear_shared
    ~name:"CHECK_PRINTABLE"
    ~generator:(fun rng_state ->
      let open Base_samplers in
      let string =
        readable_ascii_string rng_state ~size:{min = 1; max = 1024}
      in
      (string, {Shared_linear.bytes = String.length string}))
    ~make_bench:(fun generator () ->
      let (generated, workload) = generator () in
      let closure () =
        ignore (check_printable_ascii generated (String.length generated - 1))
      in
      Generator.Plain {workload; closure})

let () = Registration_helpers.register check_printable_benchmark

module Merge_types : Benchmark.S = struct
  type config = {max_size : int}

  let config_encoding =
    let open Data_encoding in
    conv
      (fun {max_size} -> max_size)
      (fun max_size -> {max_size})
      (obj1 (req "max_size" int31))

  let default_config = {max_size = 64}

  type workload = Merge_types_workload of {nodes : int; consumed : Size.t}

  let workload_encoding =
    let open Data_encoding in
    conv
      (function Merge_types_workload {nodes; consumed} -> (nodes, consumed))
      (fun (nodes, consumed) -> Merge_types_workload {nodes; consumed})
      (obj2 (req "nodes" int31) (req "consumed" int31))

  let workload_to_vector = function
    | Merge_types_workload {nodes; consumed} ->
        Sparse_vec.String.of_list
          [("nodes", float_of_int nodes); ("consumed", float_of_int consumed)]

  let name = "MERGE_TYPES"

  let info = "Benchmarking merging of types"

  let tags = [Tags.translator]

  let intercept_var = Free_variable.of_string (Format.asprintf "%s_const" name)

  let coeff_var = Free_variable.of_string (Format.asprintf "%s_coeff" name)

  let size_model =
    Model.make
      ~conv:(function Merge_types_workload {nodes; _} -> (nodes, ()))
      ~model:
        (Model.affine_split_const
           ~intercept1:Builtin_benchmarks.timer_variable
           ~intercept2:intercept_var
           ~coeff:coeff_var)

  let codegen_model =
    Model.make
      ~conv:(function Merge_types_workload {nodes; _} -> (nodes, ()))
      ~model:(Model.affine ~intercept:intercept_var ~coeff:coeff_var)

  let () =
    Registration_helpers.register_for_codegen
      name
      (Model.For_codegen codegen_model)

  let models =
    [("size_translator_model", size_model); ("codegen", codegen_model)]

  let merge_type_benchmark rng_state nodes (ty : Script_ir_translator.ex_ty) =
    Lwt_main.run
      ( Execution_context.make ~rng_state >>=? fun (ctxt, _) ->
        let ctxt = Gas_helpers.set_limit ctxt in
        match ty with
        | Ex_ty ty ->
            let dummy_loc = 0 in
            Lwt.return (Script_ir_translator.ty_eq ctxt dummy_loc ty ty)
            >|= Environment.wrap_tzresult
            >>=? fun (_, ctxt') ->
            let consumed =
              Alpha_context.Gas.consumed ~since:ctxt ~until:ctxt'
            in
            let workload =
              Merge_types_workload
                {nodes; consumed = Z.to_int (Gas_helpers.fp_to_z consumed)}
            in
            let closure () = ignore (Script_ir_translator.ty_eq ctxt 0 ty ty) in
            return (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let make_bench rng_state (cfg : config) () =
    let nodes =
      Base_samplers.(
        sample_in_interval ~range:{min = 1; max = cfg.max_size} rng_state)
    in
    let ty =
      Michelson_generation.Samplers.Random_type.m_type ~size:nodes rng_state
    in
    merge_type_benchmark rng_state nodes ty

  let create_benchmarks ~rng_state ~bench_num config =
    List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Merge_types)

(* A dummy type generator, sampling linear terms of a given size. *)
let rec dummy_type_generator depth =
  let open Script_ir_translator in
  if depth = 0 then Ex_ty (unit_t ~annot:None)
  else
    match dummy_type_generator (depth - 1) with
    | Ex_ty something -> Ex_ty (Michelson_types.list something)

(* Generate combs; the size of a comb of depth d should be
   d * 2 + 1. *)
let rec dummy_comparable_type_generator depth =
  let open Script_ir_translator in
  let open Script_typed_ir in
  if depth = 0 then Ex_comparable_ty (unit_key ~annot:None)
  else
    match dummy_comparable_type_generator (depth - 1) with
    | Ex_comparable_ty r ->
        let l = unit_key ~annot:None in
        Ex_comparable_ty
          (match pair_key (-1) (l, None) (r, None) ~annot:None with
          | Error _ -> assert false
          | Ok t -> t)

module Parse_type_shared = struct
  type config = {max_size : int}

  let default_config = {max_size = Constants_repr.michelson_maximum_type_size}

  let config_encoding =
    let open Data_encoding in
    conv
      (fun {max_size} -> max_size)
      (fun max_size -> {max_size})
      (obj1 (req "max_size" int31))

  type workload = Type_workload of {nodes : int; consumed : Size.t}

  let workload_encoding =
    let open Data_encoding in
    conv
      (function Type_workload {nodes; consumed} -> (nodes, consumed))
      (fun (nodes, consumed) -> Type_workload {nodes; consumed})
      (obj2 (req "nodes" int31) (req "consumed" int31))

  let workload_to_vector = function
    | Type_workload {nodes; consumed} ->
        Sparse_vec.String.of_list
          [("nodes", float_of_int nodes); ("consumed", float_of_int consumed)]

  let tags = [Tags.translator]
end

let parse_ty ctxt node =
  Script_ir_translator.parse_ty
    ctxt
    ~legacy:true
    ~allow_lazy_storage:true
    ~allow_operation:true
    ~allow_contract:true
    ~allow_ticket:true
    node

let unparse_ty ctxt ty = Script_ir_translator.unparse_ty ctxt ty

module Parse_type_benchmark : Benchmark.S = struct
  include Parse_type_shared

  let name = "PARSE_TYPE"

  let info = "Benchmarking parse_ty"

  let make_bench rng_state config () =
    ( Lwt_main.run (Execution_context.make ~rng_state) >>? fun (ctxt, _) ->
      let ctxt = Gas_helpers.set_limit ctxt in
      let depth = Random.State.int rng_state config.max_size in
      let ty = dummy_type_generator depth in
      match ty with
      | Ex_ty ty ->
          Environment.wrap_tzresult @@ unparse_ty ctxt ty
          >>? fun (unparsed, _) ->
          Environment.wrap_tzresult @@ parse_ty ctxt unparsed
          >>? fun (_, ctxt') ->
          let consumed =
            Z.to_int
              (Gas_helpers.fp_to_z
                 (Alpha_context.Gas.consumed ~since:ctxt ~until:ctxt'))
          in
          let workload = Type_workload {nodes = depth; consumed} in
          let closure () = ignore (parse_ty ctxt unparsed) in
          ok (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let size_model =
    Model.make
      ~conv:(function Type_workload {nodes; consumed = _} -> (nodes, ()))
      ~model:
        (Model.affine
           ~intercept:
             (Free_variable.of_string (Format.asprintf "%s_const" name))
           ~coeff:(Free_variable.of_string (Format.asprintf "%s_coeff" name)))

  let models = [("size_translator_model", size_model)]

  let create_benchmarks ~rng_state ~bench_num config =
    List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Parse_type_benchmark)

module Unparse_type_benchmark : Benchmark.S = struct
  include Parse_type_shared

  let name = "UNPARSE_TYPE"

  let info = "Benchmarking unparse_ty"

  let make_bench rng_state config () =
    ( Lwt_main.run (Execution_context.make ~rng_state) >>? fun (ctxt, _) ->
      let ctxt = Gas_helpers.set_limit ctxt in
      let depth = Random.State.int rng_state config.max_size in
      let ty = dummy_type_generator depth in
      match ty with
      | Ex_ty ty ->
          Environment.wrap_tzresult @@ unparse_ty ctxt ty >>? fun (_, ctxt') ->
          let consumed =
            Z.to_int
              (Gas_helpers.fp_to_z
                 (Alpha_context.Gas.consumed ~since:ctxt ~until:ctxt'))
          in
          let workload = Type_workload {nodes = depth; consumed} in
          let closure () = ignore (unparse_ty ctxt ty) in
          ok (Generator.Plain {workload; closure}) )
    |> function
    | Ok closure -> closure
    | Error errs -> global_error name errs

  let size_model =
    Model.make
      ~conv:(function Type_workload {nodes; consumed = _} -> (nodes, ()))
      ~model:
        (Model.affine
           ~intercept:
             (Free_variable.of_string (Format.asprintf "%s_const" name))
           ~coeff:(Free_variable.of_string (Format.asprintf "%s_coeff" name)))

  let models = [("size_translator_model", size_model)]

  let create_benchmarks ~rng_state ~bench_num config =
    List.repeat bench_num (make_bench rng_state config)
end

let () = Registration_helpers.register (module Unparse_type_benchmark)
