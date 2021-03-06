structure lcaLib :> lcaLib = struct
open HolKernel boolLib bossLib
     reflectionTheory lcaProofTheory
     basicReflectionLib reflectionLib

val _ = Globals.max_print_depth := 10

fun mk_asm1_concl phi l n =
  ``(Comb (Comb ^phi ^(term_to_deep l)) (quote ^n))``

fun LCA_l_UNIV l = term_to_deep ``LCA ^l (UNIV:'U set)``

val unpair_sig = prove(``sig = (tysof sig, tmsof sig)``, SRW_TAC[][])
val unpair_int = prove(``int = (tyaof int, tmaof int)``, SRW_TAC[][])
val tmsof_thyof = SIMP_CONV std_ss [] ``tmsof(thyof x)``
val tysof_thyof = SIMP_CONV std_ss [] ``tysof(thyof x)``
val tmsof_sigof = SIMP_CONV std_ss [] ``tmsof(sigof x)``
val tysof_sigof = SIMP_CONV std_ss [] ``tysof(sigof x)``
val vpair = SIMP_CONV std_ss []``(tyvof v,tmvof v)``
val ipair = SIMP_CONV std_ss []``(tyaof v,tmaof v)``

(*

open relationTheory holSyntaxTheory holSyntaxLibTheory holSyntaxExtraTheory holSyntaxLib lcaCtxtTheory reflectionTheory

val lca_ctxt = unpack_ctxt lca_ctxt_thm
val ctxt = rhs(concl lca_ctxt_def)
val base_extends_lca_thm = ``^ctxt extends lca_ctxt``
  |> SIMP_CONV std_ss [extends_def,RTC_REFL,GSYM lca_ctxt_def]
  |> EQT_ELIM

val outer_ctxt = lca_ctxt

val l = ``l:num``
val n = ``n:num``

val phi = ``λl n. LENGTH [l:num] > n``

val typeof_phi =
  ``typeof ^(term_to_deep phi)`` |> EVAL_typeof

val outer_ths = [INST_TYPE[alpha|->numSyntax.num]listTheory.LENGTH]

*)

(* ...

val (EVAL_type_ok0,EVAL_term_ok0) =
  EVAL_type_ok_term_ok
    EVAL (MATCH_MP theory_ok_sig theory_ok_lca |> SIMP_RULE std_ss[])
val th = prove(``tysof lca_ctxt = tysof(sigof lca_ctxt)``,rw[])
val EVAL_type_ok =
  (RATOR_CONV(RAND_CONV(REWR_CONV th))) THENC EVAL_type_ok0
val EVAL_term_ok =
  EVAL_term_ok0 THENC
  SIMP_CONV (srw_ss()) [
    tyvar_inst_exists,
    tyvar_inst_exists2,
    tyvar_inst_exists2_diff]

val term_ok_phi =
  ``term_ok (sigof ^ctxt) ^(term_to_deep phi)``
  |> ((REWRITE_CONV[GSYM lca_ctxt_def]) THENC EVAL_term_ok)
  |> EQT_ELIM

*)


fun build_ax_master_theorem outer_ctxt outer_ths base_extends_lca_thm term_ok_phi typeof_phi phi l n =
  let
    val outer_tys = union [``:num``] (base_types_of_term phi)
    val outer_tms = union [``0:num``,``SUC``] (base_terms_of_term phi)
    val tyvars = type_vars_in_term phi
    val vti:(hol_type,hol_type)Lib.subst = []
    val wf_to_inner_hyps = map (to_inner_prop vti) tyvars
    val base_ok_thm = MATCH_MP holSyntaxExtraTheory.extends_theory_ok base_extends_lca_thm
                      |> C MATCH_MP theory_ok_lca
    val {
      good_context_thm = extends_and_good_context_thm,
      models_thm = models_thm,
      wf_to_inners = wf_to_inners,
      sig_assums = sig_assums,
      int_assums = int_assums } =
        build_axiomatic_interpretation base_ok_thm outer_ctxt outer_tys outer_tms outer_ths
    val (extends_thm,good_context_thm) = CONJ_PAIR extends_and_good_context_thm
    val extends_lca_thm = MATCH_MP holSyntaxExtraTheory.extends_trans (CONJ extends_thm base_extends_lca_thm)
    val inner_ctxt = extends_lca_thm |> concl |> rator |> rand
    val thy = ``thyof ^inner_ctxt``
    val tma = mk_asm1_concl (term_to_deep phi) l n
    val tm = ``Implies ^(LCA_l_UNIV l) ^tma``
    val assumption1 = ASSUME ``(^thy,[]) |- ^tm``
    val iphi = models_thm |> concl |> rator |> rand
    val th3 =
      ASSUME ``termsem (tmsof ^thy) ^iphi v ^(LCA_l_UNIV l) = True``
      |> DISCH_ALL
      |> PURE_REWRITE_RULE[tmsof_thyof]
      |> UNDISCH
    val th4 =
      holSoundnessTheory.proves_sound |> UNDISCH
      |> C MATCH_MP assumption1
      |> MATCH_MP entails_imp_eq_true
      |> C MATCH_MP models_thm
      |> PURE_REWRITE_RULE[tmsof_thyof,tysof_thyof]
      |> UNDISCH
    val th5 =
      termsem_implies_specialised
      |> UNDISCH
      |> C MATCH_MP extends_lca_thm
      |> C MATCH_MP models_thm
      |> UNDISCH
      |> C MATCH_MP th3
      |> C MATCH_MP th4
      |> C MATCH_MP term_ok_phi
      |> C MATCH_MP typeof_phi
    val th6a = termsem_cert_unint ``^phi ^l``
    val args = good_context_thm |> concl |> strip_comb |> snd
    val s = [tysig |-> ``tysof ^(el 2 args)``,
             tmsig |-> ``tmsof ^(el 2 args)``,
             tyass |-> ``tyaof ^(el 3 args)``,
             tmass |-> ``tmaof ^(el 3 args)``]
    val th6b = INST s th6a
    val gc = good_context_thm |> ONCE_REWRITE_RULE[unpair_sig,unpair_int]
    val th6c = foldl (uncurry PROVE_HYP) th6b (gc::sig_assums@int_assums)
    val th6d = foldl (uncurry PROVE_HYP) th6c wf_to_inners
    val th6 = Q.INST[`tmval`|->`tmvof v`,`tyval`|->`tyvof v`] th6d
      |> DISCH_ALL
      |> PURE_REWRITE_RULE[tmsof_sigof,tysof_sigof,vpair,ipair]
      |> UNDISCH_ALL
    val th7 =
      termsem_comb_quote
      |> UNDISCH
      |> C MATCH_MP extends_lca_thm
      |> UNDISCH
      |> C MATCH_MP th6
      |> UNDISCH
      |> UNDISCH
      |> C MATCH_MP th5
    fun add_name th =
      th
      |> Q.GEN`name`
      |> Q.SPEC`strlit^(stringSyntax.fromMLstring(fst(dest_var l)))`
    val ith1 =
      intermediate_thm
      |> add_name
      |> Q.GEN`l` |> SPEC l
      |> CONV_RULE(LAND_CONV EVAL) |> C MP TRUTH
      |> UNDISCH
      |> Q.GEN`gi`
      |> Q.SPEC`λ^mem. ^iphi`
      |> CONV_RULE(DEPTH_CONV BETA_CONV)
    val (xv1,xtm1) = ith1 |> concl |> dest_exists
    val ith2 = ASSUME xtm1
    val ist = CONJUNCT1 ith2
    val (wfi,ith3) = CONJ_PAIR (CONJUNCT2 (CONJUNCT2 ith2))
    val izero = first (fn th => rand(rator(lhs(concl th))) = ``strlit"0"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val isuc = first (fn th => rand(rator(lhs(concl th))) = ``strlit"SUC"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
                |> CONV_RULE(RAND_CONV(REWR_CONV fun_to_inner_def))
    val iind = first (fn th => rand(rator(lhs(concl th))) = ``strlit"ind"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val inum = first (fn th => rand(rator(lhs(concl th))) = ``strlit"num"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val wfn = hd wf_to_inners
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val m0th = models_thm
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val mth = MP models_lca_extend ist
              |> C MATCH_MP extends_lca_thm
              |> C MATCH_MP m0th
    val ith4 = MP ith3 (LIST_CONJ [wfn,mth,iind,inum,izero,isuc])
    val (xv2,xtm2) = ith4 |> concl |> dest_exists
    val ith5 = ASSUME xtm2
    val veth =
      valuation_extend
      |> C MATCH_MP ist
      |> C MATCH_MP extends_lca_thm
      |> C MATCH_MP m0th
      |> C MATCH_MP ith5
      |> C MATCH_MP (add_name term_ok_LCA_l_UNIV)
      |> C MATCH_MP (add_name VFREE_IN_LCA_l_UNIV)
    val (xv3,xtm3) = veth |> concl |> dest_exists
    val ith6 = ASSUME xtm3
    val isv = CONJUNCT1 ith6
    val (vl,sem) = CONJ_PAIR (CONJUNCT2 ith6)
    val th8 = th7 |> Q.INST[`i`|->`^iphi`]
      |> PROVE_HYP ist
      |> PROVE_HYP wfi
      |> PROVE_HYP wfn
      |> PROVE_HYP izero
      |> PROVE_HYP isuc
      |> INST[xv2|->xv3]
      |> PROVE_HYP vl
      |> PROVE_HYP isv
      |> PROVE_HYP sem
    val th9 = CHOOSE (xv3,veth) th8
           |> CHOOSE (xv2,ith4)
           |> CHOOSE (xv1,ith1)
  in
    th9
    |> DISCH ``LCA (SUC ^l) (UNIV:'U set)``
    |> GEN l
    |> DISCH_ALL
    |> GEN n
  end

fun build_master_theorem ctxt extends_lca_thm term_ok_phi typeof_phi phi l n =
  let
    val tys = union [``:num``] (base_types_of_term phi)
    val consts = union [``0:num``,``SUC``] (base_terms_of_term phi)
    val tyvars = type_vars_in_term phi
    val vti:(hol_type,hol_type)Lib.subst = []
    val wf_to_inner_hyps = map (to_inner_prop vti) tyvars
    val {
      good_context_thm = good_context_thm,
      models_thm = models_thm,
      wf_to_inners = wf_to_inners,
      sig_assums = sig_assums,
      int_assums = int_assums } =
        build_interpretation (* vti *) wf_to_inner_hyps ctxt tys consts
    val inner_ctxt = extends_lca_thm |> concl |> rator |> rand
    val thy = ``thyof ^inner_ctxt``
    val tma = mk_asm1_concl (term_to_deep phi) l n
    val tm = ``Implies ^(LCA_l_UNIV l) ^tma``
    val assumption1 = ASSUME ``(^thy,[]) |- ^tm``
    val iphi = models_thm |> concl |> rator |> rand
    val th3 =
      ASSUME ``termsem (tmsof ^thy) ^iphi v ^(LCA_l_UNIV l) = True``
      |> DISCH_ALL
      |> PURE_REWRITE_RULE[tmsof_thyof]
      |> UNDISCH
    val th4 =
      holSoundnessTheory.proves_sound |> UNDISCH
      |> C MATCH_MP assumption1
      |> MATCH_MP entails_imp_eq_true
      |> C MATCH_MP models_thm
      |> PURE_REWRITE_RULE[tmsof_thyof,tysof_thyof]
      |> UNDISCH
    val th5 =
      termsem_implies_specialised
      |> UNDISCH
      |> C MATCH_MP extends_lca_thm
      |> C MATCH_MP models_thm
      |> UNDISCH
      |> C MATCH_MP th3
      |> C MATCH_MP th4
      |> C MATCH_MP term_ok_phi
      |> C MATCH_MP typeof_phi
    val th6a = termsem_cert_unint ``^phi ^l``
    val args = good_context_thm |> concl |> strip_comb |> snd
    val s = [tysig |-> ``tysof ^(el 2 args)``,
             tmsig |-> ``tmsof ^(el 2 args)``,
             tyass |-> ``tyaof ^(el 3 args)``,
             tmass |-> ``tmaof ^(el 3 args)``]
    val th6b = INST s th6a
    val gc = good_context_thm |> ONCE_REWRITE_RULE[unpair_sig,unpair_int]
    val th6c = foldl (uncurry PROVE_HYP) th6b (gc::sig_assums@int_assums)
    val th6d = foldl (uncurry PROVE_HYP) th6c wf_to_inners
    val th6 = Q.INST[`tmval`|->`tmvof v`,`tyval`|->`tyvof v`] th6d
      |> DISCH_ALL
      |> PURE_REWRITE_RULE[tmsof_sigof,tysof_sigof,vpair,ipair]
      |> UNDISCH_ALL
    val th7 =
      termsem_comb_quote
      |> UNDISCH
      |> C MATCH_MP extends_lca_thm
      |> UNDISCH
      |> C MATCH_MP th6
      |> UNDISCH
      |> UNDISCH
      |> C MATCH_MP th5
    fun add_name th =
      th
      |> Q.GEN`name`
      |> Q.SPEC`strlit^(stringSyntax.fromMLstring(fst(dest_var l)))`
    val ith1 =
      intermediate_thm
      |> add_name
      |> Q.GEN`l` |> SPEC l
      |> CONV_RULE(LAND_CONV EVAL) |> C MP TRUTH
      |> UNDISCH
      |> Q.GEN`gi`
      |> Q.SPEC`λ^mem. ^iphi`
      |> CONV_RULE(DEPTH_CONV BETA_CONV)
    val (xv1,xtm1) = ith1 |> concl |> dest_exists
    val ith2 = ASSUME xtm1
    val ist = CONJUNCT1 ith2
    val (wfi,ith3) = CONJ_PAIR (CONJUNCT2 (CONJUNCT2 ith2))
    val izero = first (fn th => rand(rator(lhs(concl th))) = ``strlit"0"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val isuc = first (fn th => rand(rator(lhs(concl th))) = ``strlit"SUC"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
                |> CONV_RULE(RAND_CONV(REWR_CONV fun_to_inner_def))
    val iind = first (fn th => rand(rator(lhs(concl th))) = ``strlit"ind"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val inum = first (fn th => rand(rator(lhs(concl th))) = ``strlit"num"``) int_assums
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val wfn = hd wf_to_inners
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val m0th = models_thm
                |> PROVE_HYP ist |> PROVE_HYP wfi
    val mth = MP models_lca_extend ist
              |> C MATCH_MP extends_lca_thm
              |> C MATCH_MP m0th
    val ith4 = MP ith3 (LIST_CONJ [wfn,mth,iind,inum,izero,isuc])
    val (xv2,xtm2) = ith4 |> concl |> dest_exists
    val ith5 = ASSUME xtm2
    val veth =
      valuation_extend
      |> C MATCH_MP ist
      |> C MATCH_MP extends_lca_thm
      |> C MATCH_MP m0th
      |> C MATCH_MP ith5
      |> C MATCH_MP (add_name term_ok_LCA_l_UNIV)
      |> C MATCH_MP (add_name VFREE_IN_LCA_l_UNIV)
    val (xv3,xtm3) = veth |> concl |> dest_exists
    val ith6 = ASSUME xtm3
    val isv = CONJUNCT1 ith6
    val (vl,sem) = CONJ_PAIR (CONJUNCT2 ith6)
    val th8 = th7 |> Q.INST[`i`|->`^iphi`]
      |> PROVE_HYP ist
      |> PROVE_HYP wfi
      |> PROVE_HYP wfn
      |> PROVE_HYP izero
      |> PROVE_HYP isuc
      |> INST[xv2|->xv3]
      |> PROVE_HYP vl
      |> PROVE_HYP isv
      |> PROVE_HYP sem
    val th9 = CHOOSE (xv3,veth) th8
           |> CHOOSE (xv2,ith4)
           |> CHOOSE (xv1,ith1)
  in
    th9
    |> DISCH ``LCA (SUC ^l) (UNIV:'U set)``
    |> GEN l
    |> DISCH_ALL
    |> GEN n
  end

end

(*
master theorem...

``∀n. (^thy,[]) |- [LCA l UNIV ⇒ ^^phi l ^(quote n)] ⇒
    ∀l. LCA (SUC l) UNIV ⇒ ^phi l n``

where thy extends (thyof LCA_ctxt)

to prove master theorem:
1. assume Provable(LCA l ==> phi l)
2. assume LCA (SUC l)
3. get termsem (LCA l) = True from 2 and intermediate
4. get termsem (LCA l ==> phi l) = True from 1 and soundness
5. combine 3 and 4 to get termsem (phi l) = True
6. termsem_cert (phi l) to get termsem (phi l) = True <=> phi l
7. combine 5 and 6
*)
