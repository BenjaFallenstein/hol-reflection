open HolKernel boolLib bossLib lcsymtacs listTheory combinTheory
open holSyntaxLibTheory holSyntaxTheory holSyntaxExtraTheory
open holConsistencyTheory
open holExtensionTheory holConstrainedExtensionTheory
open reflectionTheory reflectionLib

val _ = new_theory"reflectionDemo"
val () = Globals.max_print_depth := 13

(* TODO: this is from boolSyntaxTheory. export? *)
val tyvar_inst_exists = prove(
  ``∃i. ty = REV_ASSOCD (Tyvar a) i b``,
  qexists_tac`[(ty,Tyvar a)]` >>
  rw[REV_ASSOCD])

(* example 1: defining products on top of hol_ctxt *)
val ctxt = ``hol_ctxt``
val prod_pred_tm = ``λp. ∃x y. p = λa b. (a=x) ∧ (b=y)``
val prod_pred_inner = term_to_deep prod_pred_tm
val prod_inner_upd = ``TypeDefn (strlit"prod") ^prod_pred_inner (strlit"ABS_prod") (strlit"REP_prod")``
val prod_updates_thm = prove(
  ``^prod_inner_upd updates ^ctxt``,
  match_mp_tac (updates_rules |> CONJUNCTS |> el 5) >>
  exists_tac(term_to_deep``λa b. (a=x) ∧ (b=y)``) >>
  conj_tac >- ( cheat ) >>
  conj_tac >- ( EVAL_TAC >> rw[] >> metis_tac[] ) >>
  EVAL_TAC)
val prod_sound_update_thm = prove(
  ``is_set_theory ^mem ⇒
    sound_update ^ctxt ^prod_inner_upd``,
  strip_tac >>
  ho_match_mp_tac (UNDISCH new_type_definition_correct) >>
  (prod_updates_thm |> SIMP_RULE (srw_ss()) [updates_cases] |> strip_assume_tac) >>
  simp[] >> PROVE_TAC[]) |> UNDISCH
val prod_constrainable_thm = prove(
  ``constrainable_update ^prod_inner_upd``,
  REWRITE_TAC[constrainable_update_def] >>
  qexists_tac`set(tvars(HD(axioms_of_upd ^prod_inner_upd)))` >>
  conj_tac >- (EVAL_TAC >> rw[]) >>
  conj_tac >- EVAL_TAC >>
  conj_tac >- EVAL_TAC >>
  conj_tac >- ( EVAL_TAC >> rw[] ) >>
  REWRITE_TAC[mlstring_sort_SET_TO_LIST_set_tvars] >>
  EVAL_TAC >> rw[] >> fs[] >> rw[] >>
  rpt(fs[subtype_Tyvar,subtype_Tyapp] >> rw[]))
val prod_upd:update = {
  sound_update_thm  = prod_sound_update_thm,
  constrainable_thm = prod_constrainable_thm,
  updates_thm = prod_updates_thm,
  extends_init_thm = hol_extends_init,
  tys = [``:('a,'b)prod``],
  consts = [``ABS_prod``,``REP_prod``],
  axs = map SPEC_ALL (CONJUNCTS pairTheory.ABS_REP_prod) }
val tys = [``:'c#bool``]
val substs = [[alpha|->bool,beta|->alpha],[alpha|->gamma,beta|->(bool-->bool)]]
val consts =  map (C inst ``ABS_prod``) substs
val ctxt:update list = []
val res = build_interpretation (prod_upd::ctxt) tys consts
val example1 = save_thm("example1",#models_thm res)

(* example 2: defining K on top of hol_ctxt *)
val ctxt = ``hol_ctxt``
val tm = term_to_deep(rhs(concl K_DEF))
val inner_upd = ``ConstDef (strlit"K") ^tm``
val updates_thm = prove(
  ``^inner_upd updates hol_ctxt``,
  ho_match_mp_tac ConstDef_updates >>
  conj_tac >- (
    rw[hol_ctxt_def,fhol_ctxt_def,hol_theory_ok] ) >>
  conj_tac >- ( EVAL_TAC >> rw[] >> EVAL_TAC ) >>
  conj_tac >- EVAL_TAC >>
  conj_tac >- ( EVAL_TAC >> rw[] >> PROVE_TAC[] ) >>
  EVAL_TAC >> rw[])
val sound_update_thm = prove(
  ``is_set_theory ^mem ⇒
    sound_update ^ctxt ^inner_upd``,
  strip_tac >>
  ho_match_mp_tac (UNDISCH new_specification_correct) >>
  conj_asm1_tac >- (
    rw[hol_ctxt_def,fhol_ctxt_def,hol_theory_ok] ) >>
  conj_tac >- (
    simp_tac (srw_ss()) [] >>
    match_mp_tac (el 2 (CONJUNCTS proves_rules)) >>
    conj_tac >- rw[] >>
    conj_tac >- (
      simp_tac std_ss [EQUATION_HAS_TYPE_BOOL] >>
      simp_tac (srw_ss())[] ) >>
    imp_res_tac theory_ok_sig >>
    simp[term_ok_equation] >>
    simp[term_ok_def,type_ok_def] >>
    EVAL_TAC ) >>
  (updates_thm |> SIMP_RULE (srw_ss()) [updates_cases] |> strip_assume_tac) >>
  simp_tac (srw_ss())[] >>
  rpt conj_tac >>
  first_assum ACCEPT_TAC) |> UNDISCH
val constrainable_thm = prove(
  ``constrainable_update ^inner_upd``,
  rw[constrainable_update_def] >> rw[] >>
  rw[conexts_of_upd_def] >>
  rw[listTheory.EVERY_MAP] >>
  unabbrev_all_tac >> rw[] >>
  TRY(pop_assum mp_tac) >>
  EVAL_TAC)
val upd:update = {
  sound_update_thm  = sound_update_thm,
  constrainable_thm = constrainable_thm,
  updates_thm = updates_thm,
  extends_init_thm = hol_extends_init,
  tys = [],
  consts = [``K``],
  axs = [combinTheory.K_DEF] }
val substs = [[alpha|->bool,beta|->alpha],[alpha|->gamma,beta|->(bool-->bool)]]
val consts =  map (C inst ``K``) substs
val tys:hol_type list = []
val ctxt:update list = []
val res = build_interpretation (upd::ctxt) tys consts
val example2 = save_thm("example2",#models_thm res)

(* example 3: defining COMMA after products *)
val prod_ctxt = ``^(update_to_inner prod_upd)::hol_ctxt``
val comma_def = prove(
  ``$, = λx y. ABS_prod ^(prod_pred_tm |> dest_abs |> snd |> strip_exists |> snd |> rhs)``,
  rw[FUN_EQ_THM,pairTheory.COMMA_DEF])
val tm = term_to_deep(rhs(concl comma_def))
val inner_upd = ``ConstDef (strlit",") ^tm``

val extends_init_thm =
  MATCH_MP updates_extends_trans
        (CONJ (#updates_thm prod_upd) (#extends_init_thm prod_upd))

val prod_theory_ok = prove(
  ``theory_ok (thyof ^prod_ctxt)``,
    match_mp_tac(MATCH_MP extends_theory_ok extends_init_thm) >>
    rw[init_theory_ok] )

val term_ok_tm = prove(
  ``term_ok (sigof ^prod_ctxt) ^tm``,
  map_every (assume_tac o SIMP_RULE std_ss [] o GEN_ALL)
    (CONJUNCTS (MATCH_MP holBoolSyntaxTheory.term_ok_clauses (MATCH_MP theory_ok_sig prod_theory_ok))) >>
  ASM_SIMP_TAC std_ss [WELLTYPED_CLAUSES] >>
  rpt conj_tac >>
  TRY (EVAL_TAC >> rw[] >> NO_TAC) >>
  TRY (rw[] >> NO_TAC) >>
  simp[term_ok_def,type_ok_def] >>
  EVAL_TAC >> rw[tyvar_inst_exists])

val updates_thm = prove(
  ``^inner_upd updates ^prod_ctxt``,
  ho_match_mp_tac ConstDef_updates >>
  conj_asm1_tac >- ACCEPT_TAC prod_theory_ok >>
  conj_tac >- ACCEPT_TAC term_ok_tm >>
  conj_tac >- EVAL_TAC >>
  conj_tac >- ( EVAL_TAC >> rw[] >> PROVE_TAC[] ) >>
  EVAL_TAC >> rw[])

val sound_update_thm = prove(
  ``is_set_theory ^mem ⇒
    sound_update ^prod_ctxt ^inner_upd``,
  strip_tac >>
  ho_match_mp_tac (UNDISCH new_specification_correct) >>
  conj_asm1_tac >- ACCEPT_TAC prod_theory_ok >>
  conj_tac >- (
    CONV_TAC(RATOR_CONV(RAND_CONV(RAND_CONV(SIMP_CONV(std_ss++listSimps.LIST_ss)[])))) >>
    match_mp_tac (el 2 (CONJUNCTS proves_rules)) >>
    conj_tac >- (first_assum ACCEPT_TAC) >>
    conj_tac >- (
      simp_tac std_ss [EQUATION_HAS_TYPE_BOOL] >>
      simp_tac (srw_ss())[] ) >>
    imp_res_tac theory_ok_sig >>
    ASM_SIMP_TAC std_ss [term_ok_equation] >>
    conj_tac >- (
      simp[term_ok_def,type_ok_def] >>
      EVAL_TAC ) >>
    conj_tac >- (ACCEPT_TAC term_ok_tm) >>
    EVAL_TAC ) >>
  (updates_thm |> SIMP_RULE bool_ss [updates_cases,update_distinct,update_11] |> strip_assume_tac) >>
  rpt conj_tac >>
  first_assum ACCEPT_TAC) |> UNDISCH

val constrainable_thm = prove(
  ``constrainable_update ^inner_upd``,
  rw[constrainable_update_def] >> rw[] >>
  rw[conexts_of_upd_def] >>
  rw[listTheory.EVERY_MAP] >>
  unabbrev_all_tac >> rw[] >>
  TRY(pop_assum mp_tac) >>
  EVAL_TAC)

val comma_upd:update = {
  sound_update_thm = sound_update_thm,
  constrainable_thm = constrainable_thm,
  updates_thm = updates_thm,
  extends_init_thm = extends_init_thm,
  consts = [lhs(concl(comma_def))],
  tys = [],
  axs = [comma_def]}

val substs = [[alpha|->bool,beta|->alpha],[alpha|->gamma,beta|->(bool-->bool)]]
val consts =  map (C inst ``pair$,``) substs
val tys:hol_type list = []
val ctxt:update list = []
val res = build_interpretation (comma_upd::prod_upd::ctxt) tys consts
val example3 = save_thm("example3",#models_thm res)

(* example 4: defining FST and SND

val proj_th =
  TAC_PROOF(([``fst = @fst. ∃snd. ∀x:'a#'b. (fst x, snd x) = x``,
              ``snd = @snd. ∃fst. ∀x:'a#'b. (fst x, snd x) = x``],
            ``∀x:'a#'b. (fst x, snd x) = x``),
  rw[] >>
  SELECT_ELIM_TAC >>
  rw[pairTheory.FORALL_PROD,pairTheory.EXISTS_PROD] >- (
    map_every qexists_tac[`FST`,`SND`] >> rw[] ) >>
  SELECT_ELIM_TAC >>
  rw[pairTheory.FORALL_PROD,pairTheory.EXISTS_PROD] >- (
    map_every qexists_tac[`SND`,`FST`] >> rw[] ) >>
  Cases_on`x`>>rw[])
*)

val _ = export_theory()
