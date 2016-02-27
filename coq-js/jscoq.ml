(* Coq JavaScript API. Based in the coq source code and js_of_ocaml.
 *
 * By Emilio J. Gallego Arias, Mines ParisTech, Paris.
 * LICENSE: GPLv3+
 *
 * We provide a message-based asynchronous API for communication with
 * Coq. Our object listens to the following messages:
 *
 * And emits:
 *
 * - CoqLogEvent(level, msg): Log [msg] of priority [level].
 *
 *)

open Js
open Dom

(* Packages to load *)
class type initInfo = object
  method init_pkgs_ : js_string t js_array t readonly_prop
  method all_pkgs_  : js_string t js_array t readonly_prop
  method base_path_ : js_string t            readonly_prop
end

class type jsCoq = object

  (* When the libraries are loaded and JsCoq is ready, onInit is called *)
  method init        : ('self t, initInfo t -> Stateid.t) meth_callback writeonly_prop
  method onInit      : ('self t, unit)                    event_listener prop

  (* When a new package is known we push the information to the GUI *)
  method onNewPkgInfo : ('self t, Jslibmng.bundleInfo t ) event_listener prop

  method version     : ('self t, js_string t)           meth_callback writeonly_prop
  method goals       : ('self t, js_string t)           meth_callback writeonly_prop

  method goal_sexp_  : ('self t, js_string t)           meth_callback writeonly_prop
  method goal_json_  : ('self t, 'a t)                  meth_callback writeonly_prop

  method add         : ('self t, Stateid.t -> int -> js_string t -> Stateid.t) meth_callback writeonly_prop
  method edit        : ('self t, Stateid.t -> unit)     meth_callback writeonly_prop
  method commit      : ('self t, Stateid.t -> unit)     meth_callback writeonly_prop

  method query       : ('self t, Stateid.t -> js_string t -> unit) meth_callback writeonly_prop

  (* Options. XXX must improve thanks to json serialization *)
  method set_printing_width_ : ('self t, int -> unit) meth_callback writeonly_prop

  (* Package management *)
  method add_pkg_    : ('self t, js_string t -> unit) meth_callback writeonly_prop

  (* When package loading starts/progresses/completes  *)
  method onPkgLoadStart : ('self t, Jslibmng.progressInfo t) event_listener prop
  method onPkgProgress  : ('self t, Jslibmng.progressInfo t) event_listener prop
  method onPkgLoad      : ('self t, Jslibmng.progressInfo t) event_listener prop

  (* Request to log from Coq *)
  method onLog       : ('self t, js_string t)           event_listener prop

  (* Error from Coq *)
  method onError     : ('self t, Stateid.t)             event_listener writeonly_prop

  (* We don't want to use event_listener due to limitations of invoke_handler... *)
  (* method onLog       : ('self t, js_string t -> unit)      meth_callback opt writeonly_prop *)

end

let setup_pseudo_fs () =
  Sys_js.register_autoload' ~path:"/" (fun (_,s) -> Jslibmng.coq_vo_req s)

(* type feedback = { *)
(*   id : edit_or_state_id;        (\* The document part concerned *\) *)
(*   contents : feedback_content;  (\* The payload *\) *)
(*   route : route_id;             (\* Extra routing info *\) *)
(* } *)

let string_of_feedback fb : string =
  let open Feedback in
  match fb with
  (* STM mandatory data (must be displayed) *)
    | Processed       -> "Processed."
    | Incomplete      -> "Incomplete."
    | Complete        -> "Complete."
    | ErrorMsg(_l, s) -> "ErrorMsg: " ^ s

  (* STM optional data *)
    | ProcessingIn s       -> "ProcessingIn: " ^ s
    | InProgress d         -> "InProgress: " ^ (string_of_int d)
    | WorkerStatus(w1, w2) -> "WorkerStatus: " ^ w1 ^ ", " ^ w2

  (* Generally useful metadata *)
    | Goals(_loc, g) -> "goals: " ^ g
    | AddedAxiom -> "AddedAxiom."
    | GlobRef (_loc, s1, s2, s3, s4) -> "GlobRef: " ^ s1 ^ ", " ^ s2 ^ ", " ^ s3 ^ ", " ^ s4
    | GlobDef (_loc, s1, s2, s3) -> "GlobDef: " ^ s1 ^ ", " ^ s2 ^ ", " ^ s3
    | FileDependency (os, s) -> "FileDep: " ^ (Option.default "" os) ^ ", " ^ s
    | FileLoaded (s1, s2)    -> "FileLoaded: " ^ s1 ^ " " ^ s2

    (* Extra metadata *)
    | Custom(_loc, msg, _xml) -> "Custom: " ^ msg
    (* Old generic messages *)
    | Message m -> "Msg: " ^ m.message_content
    (* Richer printing needed in trunk. *)
    (* | Message m -> "Msg: " ^ (Xml_printer.to_string m.message_content) *)

let string_of_eosid esid =
  let open Feedback in
  match esid with
  | Edit  eid -> "eid: " ^ string_of_int eid
  | State sid -> "sid: " ^ (Stateid.to_string sid)

let internal_log (this : jsCoq t) (str : js_string t) =
  let _    = invoke_handler this##onLog this str  in
  ()

let jscoq_feedback_handler this (fb : Feedback.feedback) =
  let open Feedback in
  let fb_s = Printf.sprintf "feedback for [%s]: %s\n%!"
                            (string_of_eosid fb.id)
                            (string_of_feedback fb.contents)  in

  internal_log this (string fb_s)

let setup_printers (this : jsCoq t) =
  try
    (* How to create a channel *)
    (* let _sharp_chan = open_out "/dev/null0" in *)
    (* let _sharp_ppf = Format.formatter_of_out_channel _sharp_chan in *)
    (* Sys_js.set_channel_flusher stdout (add_text js_stdout Info); *)
    (* Sys_js.set_channel_flusher stderr (add_text js_stderr Info) *)
    Sys_js.set_channel_flusher stdout
           (fun s -> internal_log this (string @@ "stdout: " ^ s));
    Sys_js.set_channel_flusher stderr
           (fun s -> internal_log this (string @@ "stderr: " ^ s))
  with Not_found -> ()

let jscoq_init (this : jsCoq t) (init_info : initInfo t) =
  setup_pseudo_fs ();
  setup_printers this;
  let sid = Icoq.init { Icoq.ml_load    = Jslibmng.coq_cma_req;
                        Icoq.fb_handler = (jscoq_feedback_handler this);
                      } in

  let init_callback () = ignore (invoke_handler this##onInit this ()) in
  let open Jslibmng in
  let pkg_callbacks = {
    pkg_info     = (fun pi -> ignore (invoke_handler this##onNewPkgInfo   this pi));
    pkg_start    = (fun pi -> ignore (invoke_handler this##onPkgLoadStart this pi));
    pkg_progress = (fun pi -> ignore (invoke_handler this##onPkgProgress  this pi));
    pkg_load     = (fun pi -> ignore (invoke_handler this##onPkgLoad      this pi));
  } in
  Jslibmng.init init_callback pkg_callbacks init_info##base_path_ init_info##all_pkgs_ init_info##init_pkgs_;
  sid

let jscoq_version _this =
  let coqv, coqd, ccd, ccv = Icoq.version                     in
  let header1 = Printf.sprintf
      " JsCoq alpha, Coq %s (%s),\n   compiled on %s\n Ocaml %s"
      coqv coqd ccd ccv                                       in
  let header2 = Printf.sprintf
      " Js_of_ocaml version %s\n" Sys_js.js_of_ocaml_version  in
  string @@ header1 ^ header2

(* let jscoq_add this (cmd : js_string t) : Stateid.t = *)
let jscoq_add _this sid eid cmd  =
  (* Printf.eprintf "adding command %s\n%!" (to_string cmd); *)
  (* Catch parsing errors. *)
  try
    Icoq.add_to_doc sid eid (to_string cmd)
  with
  (* Hackkk *)
  | _ -> Obj.magic 0

let jscoq_edit _this sid : unit = Icoq.edit_doc sid

let jscoq_commit this sid =
  let ee () = let _ = invoke_handler this##onError this sid in () in
  try
    (* XXX: Careful with the difference between Stm.observe and Stm.finish XXX *)
    Icoq.commit_doc sid
  with
    | Errors.UserError(_msg, _pp) ->
       (* console.log *)
       ee ()
    | Errors.AlreadyDeclared _pp ->
       ee ()
    | _ ->
       ee ()

let jscoq_query _this sid cmd : unit =
  Icoq.query sid (to_string cmd)

let jscoq_add_pkg _this pkg : unit =
  Jslibmng.load_pkg (to_string pkg)

let jscoq_json_of_proof () =
  let json = Jssexp.yojson_of_proof () in
  Js._JSON##parse(string (Yojson.Safe.to_string json))

(* see: https://github.com/ocsigen/js_of_ocaml/issues/248 *)
let jsCoq : jsCoq t =
  let open Js.Unsafe in
  global##jsCoq <- obj [||];
  global##jsCoq

let _ =
  jsCoq##init     <- Js.wrap_meth_callback jscoq_init;
  jsCoq##version  <- Js.wrap_meth_callback jscoq_version;
  jsCoq##add      <- Js.wrap_meth_callback jscoq_add;
  jsCoq##edit     <- Js.wrap_meth_callback jscoq_edit;
  jsCoq##commit   <- Js.wrap_meth_callback jscoq_commit;
  jsCoq##query    <- Js.wrap_meth_callback jscoq_query;
  jsCoq##goals    <- Js.wrap_meth_callback (fun _this -> string @@ Icoq.string_of_goals ());

  jsCoq##set_printing_width_ <- begin
    let open Icoq.Options in
    Js.wrap_meth_callback (fun _this -> set_int_option pw)
  end;

  jsCoq##goal_sexp_ <- Js.wrap_meth_callback (fun _this -> string @@ Jssexp.sexp_of_proof ());

  jsCoq##goal_json_ <- Js.wrap_meth_callback (fun _this -> jscoq_json_of_proof ());

  jsCoq##add_pkg_       <- Js.wrap_meth_callback jscoq_add_pkg;

  (* Empty handlers *)
  jsCoq##onInit         <- no_handler;
  jsCoq##onNewPkgInfo   <- no_handler;
  jsCoq##onPkgLoadStart <- no_handler;
  jsCoq##onPkgLoad      <- no_handler;
  jsCoq##onPkgProgress  <- no_handler;
  jsCoq##onLog          <- no_handler;
  jsCoq##onError        <- no_handler;
  ()

(*
class type coqLogMsg = object
  inherit [jsCoq] event

  method msg : js_string t readonly_prop
end

and addCodeEvent = object
  inherit [jsCoq] event

  method code : js_string t readonly_prop
  method eid  : int         readonly_prop
end

and assignStateEvent = object
  inherit [jsCoq] event

  method eid  : int   readonly_prop
  method sid  : int   readonly_prop
end

and coqErrorEvent = object
  inherit [jsCoq] event

  method eid  : int         readonly_prop
  method msg  : js_string t readonly_prop

end

and jsCoq = object

  method onLog       : ('self t, coqLogEvent      t) event_listener writeonly_prop
  method addCode     : ('self t, addCodeEvent     t) event_listener writeonly_prop
  method assignState : ('self t, assignStateEvent t) event_listener writeonly_prop
  method coqError    : ('self t, coqErrorEvent    t) event_listener writeonly_prop

  inherit eventTarget
end

let addCodeHandler = handler (fun e ->
                              Js._true)

let jsCoq_methods (j : #jsCoq t) : unit =
  (* addEventListener *)
  let _ = addEventListener j addCodeEvent addCodeHandler false in
  ()
  (* (#eventTarget t as 'a) -> 'b Event.typ -> *)
  (* ('a, 'b) event_listener -> bool t -> event_listener_id *)
  (* j##addCode <- addCodeHandler *)
*)
