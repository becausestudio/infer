(*
 * Copyright (c) 2016 - present Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *)

open! Utils

module F = Format

module TestInterpreter = AnalyzerTester.Make
    (ProcCfg.Backward (ProcCfg.Exceptional))
    (Scheduler.ReversePostorder)
    (Liveness.Domain)
    (Liveness.TransferFunctions)

let tests =
  let open OUnit2 in
  let open AnalyzerTester.StructuredSil in
  let assert_empty = invariant "{  }" in
  let fun_ptr_typ = Sil.Tptr (Tfun false, Pk_pointer) in
  let closure_exp captured_pvars =
    let mk_captured_var str = (Sil.Var (ident_of_str str), pvar_of_str str, dummy_typ) in
    let captured_vars = IList.map mk_captured_var captured_pvars in
    let closure = { Sil.name=dummy_procname; captured_vars; } in
    Sil.Const (Cclosure closure) in
  let unknown_cond =
    (* don't want to use AnalyzerTest.unknown_exp because we'll treat it as a live var! *)
    Sil.exp_zero in
  let test_list = [
    "basic_live",
    [
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "basic_live_then_dead",
    [
      assert_empty;
      var_assign_int "b" 1;
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "iterative_live",
    [
      invariant "{ &b, &d, &f }";
      var_assign_var "e" "f";
      invariant "{ &b, &d }";
      var_assign_var "c" "d";
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "live_kill_live",
    [
      invariant "{ &b }";
      var_assign_var "c" "b";
      assert_empty;
      var_assign_int "b" 1;
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "basic_live_letderef",
    [
      invariant "{ y$0 }";
      id_assign_id "x" "y"
    ];
    "basic_live_then_kill_letderef",
    [
      invariant "{ z$0 }";
      id_assign_id "y" "z";
      invariant "{ y$0 }";
      id_assign_id "x" "y"
    ];
    "if_exp_live",
    [
      assert_empty;
      var_assign_int "x" 1;
      invariant "{ &x }";
      If (var_of_str "x", [], []);
    ];
    "while_exp_live",
    [
      assert_empty;
      var_assign_int "x" 1;
      invariant "{ &x }";
      While (var_of_str "x", []);
    ];
    "call_params_live",
    [
      invariant "{ &a, &b, &c }";
      call_unknown_no_ret ["a"; "b"; "c";]
    ];
    "dead_after_call_with_retval",
    [
      assert_empty;
      call_unknown ["y"] [];
      invariant "{ y$0 }";
      id_assign_id "x" "y";
    ];
    "closure_captured_live",
    [
      invariant "{ b$0, c$0 }";
      var_assign_exp ~rhs_typ:fun_ptr_typ "a" (closure_exp ["b"; "c"])
    ];
    "if_conservative_live1",
    [
      invariant "{ &b }";
      If (unknown_cond,
          [var_assign_var "a" "b"],
          []
         )
    ];
    "if_conservative_live2",
    [
      invariant "{ &b, &d }";
      If (unknown_cond,
          [var_assign_var "a" "b"],
          [var_assign_var "c" "d"]
         )
    ];
    "if_conservative_kill",
    [
      invariant "{ &b }";
      If (unknown_cond,
          [var_assign_int "b" 1],
          []
         );
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "if_conservative_kill_live",
    [
      invariant "{ &b, &d }";
      If (unknown_cond,
          [var_assign_int "b" 1],
          [var_assign_var "c" "d"]
         );
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "if_precise1",
    [
      assert_empty;
      If (unknown_cond,
          [var_assign_int "b" 1;
           invariant "{ &b }";
           var_assign_var "a" "b"],
          [var_assign_int "d" 1;
           invariant "{ &d }";
           var_assign_var "c" "d"]
         )
    ];
    "if_precise2",
    [
      assert_empty;
      If (unknown_cond,
          [var_assign_int "b" 2],
          [var_assign_int "b" 1]
         );
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "loop_as_if1",
    [
      invariant "{ &b }";
      While (unknown_cond,
             [var_assign_var "a" "b"]
            )
    ];
    "loop_as_if2",
    [
      invariant "{ &b }";
      While (unknown_cond,
             [var_assign_int "b" 1]
            );
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
    "loop_before_after",
    [
      invariant "{ &b, &d }";
      While (unknown_cond,
             [var_assign_var "b" "d"]
            );
      invariant "{ &b }";
      var_assign_var "a" "b"
    ];
  ] |> TestInterpreter.create_tests in
  "liveness_test_suite">:::test_list
