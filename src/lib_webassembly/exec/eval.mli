open Values
open Instance

exception Link of Source.region * string

exception Trap of Source.region * string

exception Crash of Source.region * string

exception Exhaustion of Source.region * string

type ('a, 'b, 'acc) fold_right2_kont = {
  acc : 'acc;
  lv : 'a Vector.t;
  rv : 'b Vector.t;
  offset : int32;
}

type init_kont =
  | IK_Start  (** Very first tick of the [init] function *)
  | IK_Add_import of (extern, Ast.import, module_inst) fold_right2_kont
  | IK_Remaining of module_inst
  | IK_Stop of module_inst
      (** Witness that there is no more tick to execute to complete
          the [init] process. *)

(** Small-step execution of the [init] process. See {!init}.

    @raise Invalid_argument if called with [IK_Stop]. There is no
    transition from the terminal state. *)
val init_step :
  module_reg:module_reg ->
  self:module_key ->
  Host_funcs.registry ->
  Ast.module_ ->
  extern list ->
  init_kont ->
  init_kont Lwt.t

val init :
  module_reg:module_reg ->
  self:module_key ->
  Host_funcs.registry ->
  Ast.module_ ->
  extern list ->
  module_inst Lwt.t (* raises Link, Trap *)

val invoke :
  module_reg:module_reg ->
  caller:module_key ->
  ?input:Input_buffer.t ->
  Host_funcs.registry ->
  func_inst ->
  value list ->
  value list Lwt.t (* raises Trap *)

type frame = {inst : module_key; locals : value ref list}

type code = value list * admin_instr list

and admin_instr = admin_instr' Source.phrase

and admin_instr' =
  | From_block of Ast.block_label * int32
  | Plain of Ast.instr'
  | Refer of ref_
  | Invoke of func_inst
  | Trapping of string
  | Returning of value list
  | Breaking of int32 * value list
  | Label of int32 * Ast.instr list * code
  | Frame of int32 * frame * code

type config = {
  frame : frame;
  input : input_inst;
  code : code;
  host_funcs : Host_funcs.registry;
  budget : int; (* to model stack overflow *)
}

val step : module_reg -> config -> config Lwt.t

val config :
  ?input:input_inst ->
  Host_funcs.registry ->
  module_key ->
  value list ->
  admin_instr list ->
  config
