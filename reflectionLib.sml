structure reflectionLib :> reflectionLib = struct

open preamble listSimps stringSimps listLib optionLib pairLib
open numSyntax pairSyntax stringSyntax listSyntax holSyntaxSyntax
open setSpecTheory holSyntaxTheory holSyntaxExtraTheory holSemanticsTheory holSemanticsExtraTheory
open holBoolTheory holConstrainedExtensionTheory
open reflectionTheory basicReflectionLib
open holSyntaxLib holSyntaxLibTheory
local open finite_mapSyntax in end

(* TODO: miscLib.prove_hyps_by is wrong: it needs to call PROVE_HYP multiple times *)

val ERR = mk_HOL_ERR"reflectionLib"

fun VALID_TAC_PROOF (goal,tac) = TAC_PROOF(goal, VALID tac)

val bool_to_inner_tm = ``bool_to_inner``
val fun_to_inner_tm = ``fun_to_inner``

fun to_inner_tm ty =
  mk_comb (
    mk_const ("to_inner0", (universe_ty --> universe_ty --> bool)
                       --> type_ty --> ty --> universe_ty),
    mk_var ("mem", universe_ty --> universe_ty --> bool)
  )

fun mk_to_inner tyin ty =
  let
    val newty = type_subst tyin ty
  in
    if ty = newty then
      case type_view ty of
        Tyapp(thy, "bool", [])        => bool_to_inner_tm
      | Tyapp(thy, "fun",  [ty1,ty2]) => mk_binop fun_to_inner_tm (mk_to_inner tyin ty1, mk_to_inner tyin ty2)
      | _                             => mk_monop (to_inner_tm ty) (type_to_deep ty)
    else
      mk_to_inner [] newty
  end

fun to_inner_prop vti (ty : hol_type) : term =
  ``wf_to_inner ^(mk_to_inner vti ty)``

fun mk_range vti (ty : hol_type) : term =
  ``range ^(mk_to_inner vti ty)``

datatype any_type_view =
  BoolType | FunType of hol_type * hol_type | BaseType of type_view

fun base_type_view (ty : hol_type) : type_view = case type_view ty of
    Tyapp(thy, "bool", [])        => raise ERR"base_type_view""called on bool"
  | Tyapp(thy, "fun",  [ty1,ty2]) => raise ERR"base_type_view""called on funtype"
  | view                          => view

fun any_type_view (ty : hol_type) : any_type_view = case type_view ty of
    Tyapp(thy, "bool", [])        => BoolType
  | Tyapp(thy, "fun",  [ty1,ty2]) => FunType(ty1,ty2)
  | view                          => BaseType view

fun base_types_of_type (ty : hol_type) : hol_type list = case any_type_view ty of
    BoolType         => []
  | BaseType v       => ty::(case v of Tyvar _ => []
                                     | Tyapp(_,_,args) =>
                                         flatten(map base_types_of_type args))
  | FunType(ty1,ty2) => base_types_of_type ty1 @ base_types_of_type ty2

fun tysig_prop tysig ty =
  let
    val (name,args) = dest_type ty
  in
     ``FLOOKUP ^tysig ^(string_to_inner name) =
         SOME ^(term_of_int (length args))``
  end

fun base_type_assums vti (ty : hol_type) : term list =
  to_inner_prop vti ty ::
  (case base_type_view ty of
     Tyapp(thy, name, args) => [tysig_prop tysig ty,
                                ``tyass ^(string_to_inner name)
                                    ^(mk_list(map (mk_range vti) args,universe_ty)) =
                                    ^(mk_range vti ty)``]
   | Tyvar name             => [``tyval ^(string_to_inner name) = ^(mk_range vti ty)``])

fun type_assums vti : hol_type -> term list =
  flatten o map (base_type_assums vti) o base_types_of_type

fun typesem_prop vti (ty : hol_type) : term =
  ``typesem tyass tyval ^(type_to_deep ty) = ^(mk_range vti ty)``

val good_context_is_set_theory =
  good_context_def  |> SPEC_ALL |> EQ_IMP_RULE |> fst |> UNDISCH |> CONJUNCT1

val good_context_is_std_type_assignment =
  good_context_def  |> SPEC_ALL |> EQ_IMP_RULE |> fst |> UNDISCH
  |> CONJUNCTS |> last |> REWRITE_RULE[is_std_interpretation_def]
  |> CONJUNCT1

val good_context = hd(hyp good_context_is_set_theory)
val is_valuation = Abs_thm |> hyp |> el 2

val tyass_fun_simp =
  tyass_fun_thm |> SIMP_RULE std_ss []

val [is_set_theory_mem, is_std_type_assignment] = hyp tyass_bool_thm

fun prim_typesem_cert vti ty =
  let
    val goal = (is_set_theory_mem::is_std_type_assignment::(type_assums vti ty), typesem_prop vti ty)
    (* set_goal goal *)
  in
    VALID_TAC_PROOF(goal,
      rpt(
        (CHANGED_TAC(REWRITE_TAC[typesem_def,listTheory.MAP,ETA_AX]))
        ORELSE
        (CHANGED_TAC(ASM_SIMP_TAC std_ss
          [tyass_bool_thm,
           tyass_fun_simp,
           wf_to_inner_bool_to_inner,
           wf_to_inner_fun_to_inner]))
        ORELSE match_mp_tac tyass_fun_thm))
  end

fun typesem_cert vti ty =
  PROVE_HYP good_context_is_std_type_assignment
    (PROVE_HYP good_context_is_set_theory (prim_typesem_cert vti ty))

fun types_of_term (tm : term) : hol_type list = case dest_term tm of
    VAR (name,ty)       => [ty]
  | CONST {Name,Thy,Ty} => [Ty]
  | LAMB (var,body)     => type_of var :: types_of_term body
  | COMB (tm1,tm2)      => types_of_term tm1 @ types_of_term tm2

val base_types_of_term : term -> hol_type list =
  mk_set o flatten o (map base_types_of_type) o types_of_term

fun dest_base_term (tm : term) : lambda = case dest_term tm of
    LAMB (var,body)     => raise ERR"dest_base_term""called on lambda"
  | COMB (tm1,tm2)      => raise ERR"dest_base_term""called on combination"
  | view                => view

val generic_type = type_of o prim_mk_const

fun complete_match_type Ty0 Ty =
  let
    val tyin0 = match_type Ty0 Ty
    val dom = map #redex tyin0
    fun f x = {redex = assert (not o C Lib.mem dom) x,
               residue = x}
  in
    mapfilter f (type_vars Ty0) @ tyin0
  end

fun type_instance c =
  let
    val {Name,Thy,Ty} = dest_thy_const c
    val Ty0 = generic_type {Name=Name,Thy=Thy}
  in
    complete_match_type Ty0 Ty
  end

fun cmp_to_P c x y = c (x,y) <> GREATER
fun tyvar_to_str (x : hol_type) = tyvar_to_deep (dest_vartype x)

local
  fun to_pair {redex,residue} = (tyvar_to_str redex, residue)
  val le = cmp_to_P (inv_img_cmp fst String.compare)
in
  val const_tyargs : term -> hol_type list =
    map snd o sort le o map to_pair o type_instance
end

local
  val s = HOLset.singleton Term.compare
  fun f (tm : term) = case dest_term tm of
      VAR (name,ty)       => s tm
    | CONST {Name,Thy,Ty} => s tm
    | LAMB (var,body)     => HOLset.difference(f body, s var)
    | COMB (tm1,tm2)      => HOLset.union(f tm1, f tm2)
in
  val set_base_terms_of_term = f
end

val base_terms_of_term = HOLset.listItems o set_base_terms_of_term

fun tmsig_prop tmsig c =
  let
    val {Thy,Name,Ty} =  dest_thy_const c
    val Ty0 = type_of(prim_mk_const{Name=Name,Thy=Thy})
  in
    ``FLOOKUP ^tmsig ^(string_to_inner Name) = SOME ^(type_to_deep Ty0)``
  end

fun base_term_assums vti (tm : term) : term list = case dest_base_term tm of
    VAR (name,ty)       => [``tmval (^(string_to_inner name), ^(type_to_deep ty)) =
                                ^(mk_to_inner vti ty) ^(inst vti tm)``]
  | CONST {Thy,Name,Ty} =>
    [tmsig_prop tmsig tm,
     ``tmass ^(string_to_inner Name)
             ^(mk_list (map (mk_range vti)
                          (const_tyargs tm),
                        universe_ty)) =
         ^(mk_to_inner vti Ty) ^(inst vti tm)``]

fun type_assums_of_term vti tm =
  HOLset.addList(
    Term.empty_tmset,
    flatten (map (base_type_assums vti) (base_types_of_term tm)))

fun term_assums vti (tm : term) : term list =
  HOLset.listItems(
    HOLset.addList(type_assums_of_term vti tm,
      flatten (map (base_term_assums vti) (base_terms_of_term tm))))

val instance_tm = Term.inst[alpha|->universe_ty]``instance``
fun mk_instance name ty =
  list_mk_comb(instance_tm,[tmsig,interpretation,name,ty,tyval])

fun instance_prop vti (tm : term) : term = case dest_term tm of
  CONST {Name,Thy,Ty} =>
    mk_eq(mk_instance (string_to_inner Name) (type_to_deep Ty),
          mk_comb(mk_to_inner vti Ty,inst vti tm))
| _ => raise ERR"instance_prop""called on non-constant"

local
  fun to_deep {redex,residue} =
    let
      val k = redex |> dest_vartype |> tyvar_to_deep
                    |> string_to_inner |> mk_Tyvar
      val v = type_to_deep residue
    in
      mk_pair(v,k)
    end
in
  fun tyin_to_deep tyin =
    mk_list (map to_deep tyin,mk_prod(type_ty,type_ty))
end


val good_context_tyass_bool =
  foldl (uncurry PROVE_HYP) tyass_bool_thm [good_context_is_set_theory,good_context_is_std_type_assignment]

val good_context_tyass_fun_simp =
  foldl (uncurry PROVE_HYP) tyass_fun_simp [good_context_is_set_theory,good_context_is_std_type_assignment]

local
  val instance_thm =
    instance_def |> SIMP_RULE std_ss [GSYM AND_IMP_INTRO]
  val ss = std_ss ++
    simpLib.std_conv_ss{
      name="string_EQ_CONV",
      pats=[``a:string = b``],
      conv=stringLib.string_EQ_CONV}
  val rws = [TYPE_SUBST_def,
             listTheory.MAP,
             holSyntaxLibTheory.REV_ASSOCD,
             mlstringTheory.implode_def,
             typesem_def,
             good_context_tyass_bool,
             good_context_tyass_fun_simp,
             MP wf_to_inner_bool_to_inner good_context_is_set_theory,
             MP wf_to_inner_fun_to_inner good_context_is_set_theory,
             type_11,mlstringTheory.mlstring_11]
in
  fun instance_cert vti (tm : term) : thm =
    let
      val goal = (good_context::(term_assums vti tm),instance_prop vti tm)
      val tyin = tyin_to_deep (type_instance tm)
      (* set_goal goal *)
    in
      VALID_TAC_PROOF(goal,
        first_assum(mp_tac o MATCH_MP instance_thm) >>
        disch_then(
          (CONV_TAC o LAND_CONV o RATOR_CONV o REWR_CONV) o
          SIMP_RULE ss rws o
          SPECL [interpretation,tyin]) >>
        CONV_TAC(LAND_CONV(BETA_CONV)) >>
        EVAL_STRING_SORT >>
        REV_FULL_SIMP_TAC ss rws)
    end
end

fun termsem_prop vti tm =
  mk_eq(mk_termsem (term_to_deep tm),
        mk_comb(mk_to_inner vti (type_of tm),inst vti tm))

(* TODO: assume good_context here, rather than using
good_context_is_set_theory wherever the return values of
wf_to_inner_mk_to_inner appear? *)
local
  val bool_th = wf_to_inner_bool_to_inner |> UNDISCH
  val fun_th = wf_to_inner_fun_to_inner |> UNDISCH
in
  fun wf_to_inner_mk_to_inner vti =
    let
      fun f ty =
        case any_type_view ty of
          BoolType => bool_th
        | FunType(x,y) =>
          let
            val th1 = f x
            val th2 = f y
          in
            MATCH_MP fun_th (CONJ th1 th2)
          end
        | BaseType _ => ASSUME (to_inner_prop vti ty)
     in f end
end

local
  val varth = type_ok_def |> CONJUNCT1 |> SIMP_RULE bool_ss []
  val appth = type_ok_def |> CONJUNCT2 |> SPEC_ALL |> EQ_IMP_RULE |> snd
              |> REWRITE_RULE[ETA_AX,GSYM AND_IMP_INTRO] |> GEN_ALL |> SPEC tysig
  val term_ok_clauses =
    holSyntaxExtraTheory.term_ok_clauses
    |> C MATCH_MP
        (good_context_def |> SPEC_ALL |> EQ_IMP_RULE |> fst
           |> UNDISCH |> CONJUNCT2 |> CONJUNCT1)
  val boolth =
    term_ok_clauses |> funpow 2 CONJUNCT2 |> CONJUNCT1 |> SIMP_RULE std_ss []
  val funth =
    term_ok_clauses |> funpow 3 CONJUNCT2 |> CONJUNCT1
    |> EQ_IMP_RULE |> snd |> SIMP_RULE std_ss []
in
  fun type_ok_type_to_deep ty = case any_type_view ty of
    BoolType => boolth
  (* val FunType(ty1,ty2) = it *)
  (* val ty = ty2 *)
  | FunType(ty1,ty2) =>
      MATCH_MP funth
        (CONJ (type_ok_type_to_deep ty1)
              (type_ok_type_to_deep ty2))
  | BaseType(Tyvar name) =>
      varth |> SPECL [string_to_inner (tyvar_to_deep name), tysig]
  (* val BaseType(Tyapp (thy,name,args)) = it *)
  | BaseType(Tyapp (thy,name,args)) =>
    let
      val ths = map type_ok_type_to_deep args
      val argsd = mk_list(map (rand o concl) ths, type_ty)
      val th = SPECL [string_to_inner name, argsd] appth
               |> CONV_RULE (LAND_CONV(
                    SIMP_CONV (bool_ss++listSimps.LIST_ss++numSimps.ARITH_ss)
                    [arithmeticTheory.ADD1]))
               |> UNDISCH
               |> CONV_RULE (LAND_CONV(
                    SIMP_CONV (bool_ss++listSimps.LIST_ss) []))
               |> C MP (if null ths then TRUTH else LIST_CONJ ths)
    in
      th
    end
end

local
  val get_rule =
    snd o EQ_IMP_RULE o SPEC_ALL o SIMP_RULE std_ss [] o SPEC signatur
  val varth = term_ok_def |> CONJUNCT1 |> get_rule |> Q.GEN`x`
    |> ADD_ASSUM good_context
  val constth =
    term_ok_def |> CONJUNCT2 |> CONJUNCT1 |> get_rule
    |> SIMP_RULE std_ss [GSYM LEFT_FORALL_IMP_THM]
    |> ONCE_REWRITE_RULE[CONJ_COMM]
    |> ONCE_REWRITE_RULE[GSYM CONJ_ASSOC]
    |> REWRITE_RULE[GSYM AND_IMP_INTRO]
    |> Q.GEN`name`
    |> ADD_ASSUM good_context
  val combth = term_ok_def |> funpow 2 CONJUNCT2 |> CONJUNCT1 |> get_rule
               |> SIMP_RULE std_ss [WELLTYPED_CLAUSES,GSYM AND_IMP_INTRO]
  val absth =
    term_ok_def |> funpow 3 CONJUNCT2 |> get_rule
      |> SIMP_RULE std_ss [PULL_EXISTS]
in
  fun term_ok_term_to_deep tm =
    case dest_term tm of
    (* val VAR (x,ty) = it *)
      VAR (x,ty) =>
        MATCH_MP varth (type_ok_type_to_deep ty)
        |> SPEC (string_to_inner x)
    | CONST {Name,Thy,Ty} =>
        let
          val th =
            constth
            |> C MATCH_MP (type_ok_type_to_deep Ty)
            |> SPEC (string_to_inner Name)
            |> SPEC (type_to_deep (generic_type {Name=Name,Thy=Thy}))
          val goal:goal = ([],th |> concl |> dest_imp |> fst)
          (* set_goal goal *)
          val th1 = VALID_TAC_PROOF(goal,
            exists_tac (tyin_to_deep (type_instance tm)) >>
            EVAL_TAC)
        in
          UNDISCH (MP th th1)
        end
    (* val COMB (f,x) = it *)
    | COMB (f,x) =>
        let
          val th1 = term_ok_term_to_deep f
          val th2 = term_ok_term_to_deep x
          val th =
            combth
            |> C MATCH_MP th1
            |> C MATCH_MP th2
            |> C MATCH_MP (MATCH_MP term_ok_welltyped th1)
            |> C MATCH_MP (MATCH_MP term_ok_welltyped th2)
          val th1 = th |> concl |> dest_imp |> fst
            |> ((QUANT_CONV((LAND_CONV EVAL) THENC
                            (RAND_CONV EVAL))) THENC
                (SIMP_CONV (std_ss++listSimps.LIST_ss) [type_11]))
            |> EQT_ELIM
        in
          MP th th1
        end
    | LAMB (x,b) =>
        let
          val th1 = term_ok_term_to_deep x
          val th2 = term_ok_term_to_deep b
        in
          MATCH_MP absth
            (LIST_CONJ
               [REFL(rand(concl th1)),
                type_ok_type_to_deep(type_of x),
                th2])
        end
end

fun termsem_cert_unint vti =
  let
    fun f tm =
      let
        val goal = (good_context::is_valuation::(term_assums vti tm),termsem_prop vti tm)
        (* set_goal goal *)
      in
        case dest_term tm of
          VAR _ => VALID_TAC_PROOF(goal,ASM_SIMP_TAC std_ss [termsem_def])
        | CONST _ => VALID_TAC_PROOF(goal,
            SIMP_TAC std_ss [termsem_def] >>
            ACCEPT_TAC(instance_cert vti tm))
        (* val COMB(t1,t2) = it *)
        (* val tm = t1 *)
        (* val tm = t2 *)
        | COMB(t1,t2) =>
          let
            val th1 = f t1
            val th2 = f t2
            val (dty,rty) = dom_rng (type_of t1)
            val th = MATCH_MP Comb_thm (CONJ th1 th2)
                     |> C MATCH_MP (wf_to_inner_mk_to_inner vti dty)
                     |> C MATCH_MP (wf_to_inner_mk_to_inner vti rty)
                     |> PROVE_HYP good_context_is_set_theory
          in
            VALID_TAC_PROOF(goal, ACCEPT_TAC th)
          end
        (* val LAMB(x,b) = it *)
        (* val tm = b *)
        | LAMB(x,b) =>
          let
            val th =
              MATCH_MP Abs_thm
                (CONJ (typesem_cert vti (type_of x))
                      (typesem_cert vti (type_of b)))
            val cb = f b
          in
            VALID_TAC_PROOF(goal,
              match_mp_tac th >>
              conj_tac >- (ACCEPT_TAC (term_ok_term_to_deep b)) >>
              conj_tac >- EVAL_TAC >>
              gen_tac >> strip_tac >>
              CONV_TAC(RAND_CONV(RAND_CONV(BETA_CONV))) >>
              match_mp_tac (MP_CANON (DISCH_ALL cb)) >>
              ASM_SIMP_TAC (std_ss++LIST_ss++STRING_ss)
                [combinTheory.APPLY_UPDATE_THM,
                 mlstringTheory.mlstring_11] >>
              rpt conj_tac >>
              TRY (
                match_mp_tac (MP_CANON (GSYM wf_to_inner_finv_right)) >>
                rpt conj_tac >>
                TRY(first_assum ACCEPT_TAC) >>
                imp_res_tac (DISCH_ALL good_context_is_set_theory) >>
                rpt (
                  TRY(first_assum ACCEPT_TAC) >>
                  TRY(MATCH_ACCEPT_TAC (UNDISCH wf_to_inner_bool_to_inner)) >>
                  match_mp_tac (UNDISCH wf_to_inner_fun_to_inner) >>
                  rpt conj_tac )) >>
              match_mp_tac is_valuation_extend >>
              (conj_tac >- first_assum ACCEPT_TAC) >>
              imp_res_tac (DISCH_ALL good_context_tyass_bool) >>
              ASM_SIMP_TAC (std_ss++LIST_ss)
                [typesem_def,
                 MP wf_to_inner_bool_to_inner good_context_is_set_theory,
                 MP wf_to_inner_fun_to_inner good_context_is_set_theory,
                 good_context_tyass_fun_simp])
          end
      end
  in f end

(*
  val tm = ``λx. K F``
  val tm = ``λx. K (λy. F) 3``
  val tm = ``let x = 5 in x + y``
  val tm = ``[x;y;[2]]``
  val tm = ``typesem tysig tyval Bool``
  val tm = mem
  val tm = good_context
  val tm = ``map (λf. (λ(x,y). x) = f) []``
  val tm = ``ARB``
  val tm =
     ``(λ(p :α -> β -> bool).
         ∃(x :α) (y :β). p = (λ(a :α) (b :β). (a = x) ∧ (b = y)))
            (r :α -> β -> bool) ⇔ (REP_prod (ABS_prod r) = r)``
  termsem_cert_unint tyin tm
  show_assums := true
*)

type update = {
  sound_update_thm  : thm, (* |- sound_update ctxt upd *)
  constrainable_thm : thm, (* |- constrainable_update upd *)
  updates_thm : thm, (* |- upd updates ctxt *)
  extends_init_thm : thm, (* |- ctxt extends init_ctxt *)
  tys : hol_type list,
  consts : term list,
  axs : thm list }

(* TODO: stolen from ml_translatorLib.sml *)

(* packers and unpackers for thms, terms and types *)

fun pack_type ty = REFL (mk_var("ty",ty));
fun unpack_type th = th |> concl |> dest_eq |> fst |> type_of;

fun pack_term tm = REFL tm;
fun unpack_term th = th |> concl |> dest_eq |> fst;

fun pack_thm th = PURE_ONCE_REWRITE_RULE [GSYM markerTheory.Abbrev_def] th |> DISCH_ALL;
fun unpack_thm th = th |> UNDISCH_ALL |> PURE_ONCE_REWRITE_RULE [markerTheory.Abbrev_def];

fun pack_list f xs = TRUTH :: map f xs |> LIST_CONJ |> PURE_ONCE_REWRITE_RULE [GSYM markerTheory.Abbrev_def];
fun unpack_list f th = th |> PURE_ONCE_REWRITE_RULE [markerTheory.Abbrev_def] |> CONJUNCTS |> tl |> map f;

(* -- *)

(* pack and unpack context *)
fun pack_update (upd:update) =
  pack_list I [pack_thm (#sound_update_thm upd),
               pack_thm (#constrainable_thm upd),
               pack_thm (#updates_thm upd),
               pack_thm (#extends_init_thm upd),
               pack_list pack_type (#tys upd),
               pack_list pack_term (#consts upd),
               pack_list pack_thm (#axs upd)]
fun unpack_update th =
  let
    val ls = unpack_list I th
  in
    {sound_update_thm  = unpack_thm (el 1 ls),
     constrainable_thm = unpack_thm (el 2 ls),
     updates_thm       = unpack_thm (el 3 ls),
     extends_init_thm  = unpack_thm (el 4 ls),
     tys    = unpack_list unpack_type (el 5 ls),
     consts = unpack_list unpack_term (el 6 ls),
     axs    = unpack_list unpack_thm  (el 7 ls)}
  end
val pack_ctxt = pack_list pack_update
val unpack_ctxt = unpack_list unpack_update

fun find_type_instances toconstrain fromupdate =
  mk_set (
  foldl
    (fn (ty1,acc) =>
      foldl (fn (ty2,acc) =>
                  case total (complete_match_type ty1) ty2 of NONE => acc
                    | SOME s => s::acc)
               acc
               toconstrain)
    []
    fromupdate
  )

(*
  val fromupdate = #consts upd
 *)
fun find_const_instances consts fromupdate =
  let
    val consts1 = filter (fn tm => exists (same_const tm) fromupdate) consts
  in
    mk_set(map type_instance consts1)
  end

fun tyvar_variant tvs tv =
  if List.exists (equal tv) tvs
  then
      mk_vartype((dest_vartype tv)^"_")
    |> tyvar_variant tvs
  else tv

local
  val distinct_tag_bool_range = prove(
    ``is_set_theory ^mem ⇒
      !x. wf_to_inner ((to_inner x):'a -> 'U) ⇒
      range ((to_inner x):'a -> 'U) ≠ range bool_to_inner``,
    rw[] >>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    qexists_tac`to_inner x ARB` >>
    qmatch_abbrev_tac`a ≠ b` >>
    qsuff_tac`~b`>-metis_tac[wf_to_inner_range_thm]>>
    simp[Abbr`a`,Abbr`b`,to_inner_def,range_bool_to_inner] >>
    simp[tag_def]) |> UNDISCH

  val distinct_tag_fun_range = prove(
    ``is_set_theory ^mem ⇒
      !x y z.
      wf_to_inner ((to_inner x):'a -> 'U) ⇒
      wf_to_inner y ⇒
      wf_to_inner z ⇒
      range ((to_inner x):'a -> 'U) ≠ range (fun_to_inner y z)``,
    rw[] >>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    qexists_tac`to_inner x ARB` >>
    qmatch_abbrev_tac`a ≠ b` >>
    qsuff_tac`~b`>-metis_tac[wf_to_inner_range_thm]>>
    simp[Abbr`a`,Abbr`b`,to_inner_def,range_fun_to_inner] >>
    simp[tag_def]) |> UNDISCH

  val distinct_tags = prove(
    ``is_set_theory ^mem ⇒
      !x y.
      wf_to_inner ((to_inner x):'a -> 'U) ⇒
      wf_to_inner ((to_inner y):'b -> 'U) ⇒
      x ≠ y ⇒
      range ((to_inner x):'a -> 'U) ≠
      range ((to_inner y):'b -> 'U)``,
    rw[] >>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    qexists_tac`to_inner x ARB` >>
    qmatch_abbrev_tac`a ≠ b` >>
    qsuff_tac`~b`>-metis_tac[wf_to_inner_range_thm]>>
    simp[Abbr`a`,Abbr`b`] >>
    spose_not_then strip_assume_tac >>
    imp_res_tac wf_to_inner_finv_right >>
    fs[to_inner_def] >>
    metis_tac[tag_def,pairTheory.PAIR_EQ]) |> UNDISCH

  val distinct_bool_fun = prove(
    ``is_set_theory ^mem ⇒
      !x y.
      wf_to_inner x ⇒
      wf_to_inner y ⇒
      range bool_to_inner ≠ range (fun_to_inner x y )``,
    rw[range_bool_to_inner,range_fun_to_inner] >>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    pop_assum kall_tac >>
    rw[mem_boolset] >>
    qexists_tac`True` >> rw[] >>
    spose_not_then strip_assume_tac >>
    imp_res_tac in_funspace_abstract >>
    fs[abstract_def,true_def] >>
    imp_res_tac is_extensional >>
    fs[Once extensional_def] >> rfs[mem_empty] >>
    pop_assum kall_tac >>
    imp_res_tac wf_to_inner_range_thm >>
    rfs[mem_sub,mem_product] >>
    last_x_assum(qspec_then`(x ARB,f (x ARB))`mp_tac) >>
    simp[pair_inj] >>
    metis_tac[is_extensional,extensional_def]) |> UNDISCH

  val unequal_suff = prove(
    ``is_set_theory ^mem ⇒
      (∀x y a. a <: x ∧ ¬(a <: y) ⇒ P x y ∧ P y x) ⇒
      (∀x y. x ≠ y ⇒ P x y)``,
    rw[] >>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    pop_assum kall_tac >>
    fs[EQ_IMP_THM] >>
    metis_tac[]) |> UNDISCH

  val distinct_fun_fun = prove(
    ``is_set_theory ^mem ⇒
      !d1 r1 d2 r2.
      wf_to_inner d1 ∧
      wf_to_inner r1 ∧
      wf_to_inner d2 ∧
      wf_to_inner r2 ⇒
      pair$, (range d1) (range r1) ≠ (range d2, range r2) ⇒
      range (fun_to_inner d1 r1) ≠ range (fun_to_inner d2 r2)``,
    rw[range_fun_to_inner] >>
    imp_res_tac wf_to_inner_range_thm >>
    rpt(qpat_x_assum`wf_to_inner X`kall_tac) >>
    rpt(first_x_assum(qspec_then`ARB`mp_tac)) >>
    pop_assum mp_tac >|[
      map_every qspec_tac
        [(`range r2`,`w`),(`range r1`,`z`),
         (`r2 ARB`,`we`),(`r1 ARB`,`ze`),
         (`d2 ARB`,`ye`),(`d1 ARB`,`xe`),
         (`range d2`,`y`),(`range d1`,`x`)],
      map_every qspec_tac
        [(`range d2`,`w`),(`range d1`,`z`),
         (`d2 ARB`,`we`),(`d1 ARB`,`ze`),
         (`r2 ARB`,`ye`),(`r1 ARB`,`xe`),
         (`range r2`,`y`),(`range r1`,`x`)]] >>
    simp[RIGHT_FORALL_IMP_THM] >>
    ho_match_mp_tac unequal_suff >>
    rpt gen_tac >> strip_tac >>
    (reverse conj_asm1_tac >- metis_tac[]) >>
    rpt strip_tac>>
    imp_res_tac is_extensional >>
    fs[extensional_def] >>
    pop_assum kall_tac >>
    pop_assum mp_tac >>
    simp[EQ_IMP_THM] >|[
      qexists_tac`Abstract y z (K ze)`,
      qexists_tac`Abstract z y (K a)`] >>
    disj1_tac >>
    (conj_tac >- (
       match_mp_tac (UNDISCH abstract_in_funspace) >> rw[] )) >>
    simp[funspace_def,relspace_def,mem_sub] >> disj1_tac >>
    simp[mem_power,abstract_def,mem_sub,mem_product,PULL_EXISTS,pair_inj] >>
    metis_tac[]) |> UNDISCH

  val ERR = mk_HOL_ERR"reflectionLib""ranges_distinct"
  val ERR_same = ERR"same_types"
in
  fun ranges_distinct vti ty1 ty2 =
    case (any_type_view ty1, any_type_view ty2) of
       (BoolType, BoolType) => raise ERR_same
    |  (BoolType, FunType (x,y)) =>
         distinct_bool_fun
         |> ISPECL [mk_to_inner vti x, mk_to_inner vti y]
         |> C MP (wf_to_inner_mk_to_inner vti x)
         |> C MP (wf_to_inner_mk_to_inner vti y)
    |  (FunType _, BoolType) => GSYM (ranges_distinct vti ty2 ty1)
    |  (BaseType _, FunType(x,y)) =>
         let
           val tvs = type_varsl [ty1,ty2]
           val b = tyvar_variant tvs beta
           val c = tyvar_variant tvs gamma
         in
           distinct_tag_fun_range
           |> INST_TYPE[alpha|->ty1,beta|->b,gamma|->c]
           |> ISPECL [type_to_deep ty1, mk_to_inner vti x, mk_to_inner vti y]
           |> UNDISCH
           |> C MP (wf_to_inner_mk_to_inner vti x)
           |> C MP (wf_to_inner_mk_to_inner vti y)
         end
    |  (FunType _, BaseType _) => GSYM (ranges_distinct vti ty2 ty1)
    (* val (FunType (x1,y1), FunType (x2,y2)) = it *)
    |  (FunType (x1,y1), FunType (x2,y2)) =>
         let
           val tys = [x1,y1,x2,y2]
           val ranges = map (mk_range vti) tys
           val th1 =
             pairTheory.PAIR_EQ
             |> EQ_IMP_RULE |> fst
             |> CONTRAPOS
             |> CONV_RULE(LAND_CONV(REWR_CONV(
                  CONJUNCT1 (SPEC_ALL DE_MORGAN_THM))))
             |> Q.GENL(rev[`x`,`y`,`a`,`b`])
             |> ISPECL ranges
           val th2 =
             if x1 = x2 then
               if y1 = y2 then raise ERR_same
               else
                 DISJ2
                 (th1|>concl|>dest_imp|>fst|>dest_disj|>fst)
                 (ranges_distinct vti y1 y2)
             else
               DISJ1
               (ranges_distinct vti x1 x2)
               (th1|>concl|>dest_imp|>fst|>dest_disj|>snd)
         in
           distinct_fun_fun
           |> ISPECL (map (mk_to_inner vti) tys)
           |> C MP (LIST_CONJ (map (wf_to_inner_mk_to_inner vti) tys))
           |> C MP (MP th1 th2)
         end
    |  (BaseType _, BoolType) =>
         distinct_tag_bool_range
         |> ISPEC (type_to_deep ty1)
         |> INST_TYPE[alpha|->ty1]
         |> UNDISCH
    |  (BoolType, BaseType _) => GSYM (ranges_distinct vti ty2 ty1)
    |  (BaseType _, BaseType _) =>
         if ty1 = ty2 then raise ERR_same
         else let
           val tys = map type_to_deep [ty1, ty2]
           (* TODO: purpose-built conversion rather than EVAL? *)
           val th = EVAL(mk_eq(el 1 tys, el 2 tys)) |> EQF_ELIM
         in
           distinct_tags
           |> ISPECL tys
           |> INST_TYPE[alpha|->ty1,beta|->ty2]
           |> funpow 2 UNDISCH
           |> C MP th
         end
end

local
  val [if_T_thm,if_F_thm] = SPEC_ALL COND_CLAUSES |> CONJUNCTS
  val TEST_CONV = RATOR_CONV o RATOR_CONV o RAND_CONV
  val lists_unequal_th =
    listTheory.LIST_EQ_REWRITE |> SPEC_ALL
    |> EQ_IMP_RULE |> fst |> CONTRAPOS
    |> SIMP_RULE (std_ss++boolSimps.DNF_ss) []
    |> CONJUNCT2 |> Q.GENL[`l2`,`l1`]
  val EVAL_LENGTH = computeLib.CBV_CONV (listSimps.list_compset())
  val EVAL_EL = EVAL_LENGTH
in
  fun cs_to_inner vti tys consts =
    let
      fun subst_to_cs s =
        let
          fun const_to_inner c =
            let
              val ic = inst s c
            in
              mk_comb(mk_to_inner vti (type_of ic), ic)
            end
          val inner_tys = map (mk_range vti o type_subst s) tys
          val inner_consts = map const_to_inner consts
        in
          mk_pair(mk_list(inner_tys,universe_ty),
                  mk_list(inner_consts,universe_ty))
        end
      fun subst_to_sorted_types (s:(hol_type,hol_type)subst) =
        let
          val by_name =
            cmp_to_P (inv_img_cmp (dest_vartype o #redex) String.compare)
          val sorted_subst = sort by_name s
        in
          map #residue sorted_subst
        end
      fun foldthis (s,(f,ths)) =
        let
          val instance_tys = subst_to_sorted_types s
          val instance = mk_list(map (mk_range vti) instance_tys,universe_ty)
          val result = optionSyntax.mk_some (subst_to_cs s)
          val new_map = combinSyntax.mk_update (instance, result)
          val new_f = mk_icomb(new_map, f)
          val th =
            combinTheory.APPLY_UPDATE_THM
            |> ISPECL [f,instance,result,instance]
            |> CONV_RULE(RAND_CONV(
                 TEST_CONV(REWR_CONV(EQT_INTRO(REFL instance)))
                 THENC REWR_CONV if_T_thm))
          (* val (instance_tys0,th0)::_ = ths *)
          fun update (instance_tys0,th0) =
            let
              val notinstance = th0 |> concl |> lhs |> rand
              val typairs = zip instance_tys instance_tys0
              val i = index (not o op=) typairs
              val rth = uncurry (ranges_distinct vti) (List.nth(typairs,i))
              val notinstanceth =
                lists_unequal_th
                |> ISPECL [instance,notinstance,numSyntax.term_of_int i]
                |> CONV_RULE(LAND_CONV(LAND_CONV EVAL_LENGTH THENC
                                       RAND_CONV(EVAL_EL THENC
                                                 REWR_CONV(EQT_INTRO rth))))
                |> C MP (CONJ TRUTH TRUTH)
              val uth0 =
                combinTheory.APPLY_UPDATE_THM
                |> ISPECL [f,instance,result,notinstance]
                |> CONV_RULE(RAND_CONV(
                     TEST_CONV(REWR_CONV(EQF_INTRO notinstanceth))
                     THENC REWR_CONV if_F_thm))
            in
              (instance_tys0,TRANS uth0 th0)
            end
          val updated_ths = map update ths
        in
          (new_f,((instance_tys,th)::updated_ths))
        end
    in
      foldl foldthis (``K NONE : 'U constraints``,
                      []:(hol_type list * thm) list)
    end
end

(*
  val tys = [mk_list_type alpha]
  val consts = [cons_tm]
  val substs = [[alpha|->numSyntax.num],[alpha|->bool]]
  val (s::_) = substs
  val (_::s::_) = substs
  val (csi, ths) = cs_to_inner tys consts substs
  val (ty1,th1) = hd ths
  val (ty2,th2) = hd (tl ths)
  rand(lhs (concl th1))
  rand(lhs (concl th2))
  aconv (rator (lhs (concl th2))) csi
  aconv (rator (lhs (concl th1))) csi
  val (f,ths) = it

  val tys = [mk_prod(alpha,beta),finite_mapSyntax.mk_fmap_ty(alpha,beta)]
  val consts = [comma_tm,finite_mapSyntax.fempty_t]
  val substs = [[alpha|->numSyntax.num,beta|->bool],
                [alpha|->bool,beta|->beta],
                [alpha|->bool,beta|->bool]]
  val (csi,ths) = cs_to_inner tys consts substs
  val [(ty1,th1),(ty2,th2),(ty3,th3)] = ths
  th2

  val true =
    rand(rator(rhs(concl(EVAL ``conexts_of_upd ^inner_upd``)))) =
    term_to_deep(concl(combinTheory.K_DEF))

  val substs =
    [[alpha|->bool,beta|->bool],
     [alpha|->``:'x``,beta|->``:'y``]]

  val int0 = ``hol_model select ind_to_inner``
*)

fun update_to_inner (upd:update) = #constrainable_thm upd |> concl |> rand

local
  val cons_lemma = last(CONJUNCTS listTheory.LIST_REL_def) |> EQ_IMP_RULE |> fst
  val betarule = CONV_RULE (RATOR_CONV BETA_CONV THENC BETA_CONV)
in
  fun split_LIST_REL th =
    let
      val (th1,th) = CONJ_PAIR(MATCH_MP cons_lemma th)
    in
      betarule th1::(split_LIST_REL th)
    end handle HOL_ERR _ => []
end

(*
  val substs = instances_to_constrain
 *)
fun make_cs_assums vti upd substs theory_ok_thm jtm =
  let
    val tys = #tys upd val consts = #consts upd
    val updates_thm = #updates_thm upd
    val (csi,tysths) = cs_to_inner vti tys consts substs
    val int = ``constrain_interpretation ^(update_to_inner upd) ^csi ^jtm``
    val tya = ``tyaof ^int``
    val tma = ``tmaof ^int``
    (* val (instances,th) = hd tysths *)
    fun mapthis (_,th) =
      let
        val lemma = MATCH_MP tmaof_constrain_interpretation_lemma th
        val alldistinct = MATCH_MP updates_upd_ALL_DISTINCT updates_thm |> CONJUNCT1
        val lem2 = MATCH_MP lemma alldistinct
        (* TODO: finer conversions than the EVALs below *)
        val lem3 = CONV_RULE(LAND_CONV EVAL) lem2 |> C MP TRUTH
        val lem4 = lem3 |> CONV_RULE(RATOR_CONV(RAND_CONV EVAL))
        val lem5 = lem4 |> Q.GEN`int0` |> SPEC jtm
        val tmths = split_LIST_REL lem5
        (* --- *)
        val lemma = MATCH_MP tyaof_constrain_interpretation_lemma th
        val alldistinct = MATCH_MP updates_upd_ALL_DISTINCT updates_thm |> CONJUNCT2
        val lem2 = MATCH_MP lemma alldistinct
        (* TODO: finer conversions than the EVALs below *)
        val lem3 = CONV_RULE(LAND_CONV EVAL) lem2 |> C MP TRUTH
        val lem4 = lem3 |> CONV_RULE(RATOR_CONV(RAND_CONV EVAL))
        val lem5 = lem4 |> Q.GEN`int0` |> SPEC jtm
        val tyths = split_LIST_REL lem5
      in
        tyths@tmths
      end
  in
    (int, flatten (map mapthis tysths), map snd tysths)
  end

fun get_int th = th |> concl |> rator |> rand

local
  val base_case = prove(``∀z. (IS_SOME (K NONE z) ⇔ MEM z [])``,rw[])
  val step_case = prove(``∀f z k v ls.
    (IS_SOME (f z) ⇔ MEM z ls) ⇒
      (IS_SOME ((k =+ SOME v) f z) ⇔ MEM z (k::ls))``,
    rw[combinTheory.APPLY_UPDATE_THM])
in
  fun updates_equal_some_cases z cs =
    INST_TYPE [beta|->optionSyntax.dest_option(type_of(rand cs))] (ISPEC z base_case) handle HOL_ERR _ =>
    let
      val ((k,sv),f) = combinSyntax.dest_update_comb cs
      val v = optionSyntax.dest_some sv
      val th = updates_equal_some_cases z f
      val ls = th |> concl |> rhs |> listSyntax.dest_mem |> snd
    in
      MP (ISPECL [f,z,k,v,ls] step_case) th
    end
end

val IS_SOME_cs_thm = prove(
  ``(∀vs tyvs tmvs. (cs vs = SOME (tyvs,tmvs)) ⇒ P vs tyvs tmvs) ⇔
    (∀vs. IS_SOME (cs vs) ⇒ P vs (FST (THE (cs vs))) (SND (THE (cs vs))))``,
  rw[IS_SOME_EXISTS,PULL_EXISTS,pairTheory.FORALL_PROD])

val inhabited_tm = ``inhabited``
val inhabited_eta = prove(``inhabited x ⇔ (λs. inhabited s) x``,rw[])
fun EVERY_range_inhabited vti tys =
  join_EVERY inhabited_tm (map (
    CONV_RULE(REWR_CONV(inhabited_eta))
      o MATCH_MP inhabited_range o (wf_to_inner_mk_to_inner vti)) tys)

(* val inner_upd = update_to_inner upd *)
fun prove_lengths_match_thm hyps cs cs_cases cs_rws inner_upd =
  let
    val gtm =
      constrain_interpretation_equal_on
      |> UNDISCH |> ISPECL [inner_upd,cs] |> SPEC_ALL
      |> concl |> dest_imp |> fst |> strip_conj |> el 2
    val listc = listLib.list_compset()
    val goal:goal = (hyps,gtm)
    (* set_goal goal *)
    val th = VALID_TAC_PROOF(goal,
      CONV_TAC(HO_REWR_CONV IS_SOME_cs_thm) >>
      CONV_TAC(QUANT_CONV(LAND_CONV(REWR_CONV cs_cases))) >>
      CONV_TAC(HO_REWR_CONV(GSYM listTheory.EVERY_MEM)) >>
      CONV_TAC(computeLib.CBV_CONV listc) >>
      REWRITE_TAC cs_rws >>
      EVAL_TAC)
  in
    th
  end

val length_thm_to_lengths_and_inhabited_thm = prove(
  ``∀cs.
    (∀vs tyvs tmvs.
      (cs vs = SOME (tyvs,tmvs)) ⇒
      (LENGTH tyvs = LENGTH (types_of_upd upd)) ∧
      (LENGTH tmvs = LENGTH (consts_of_upd upd))) ⇒
    (∀vs. IS_SOME (cs vs) ⇒
            EVERY inhabited vs ∧
            EVERY inhabited (FST (THE (cs vs)))) ⇒
    (∀vs tyvs tmvs.
      (cs vs = SOME (tyvs,tmvs)) ⇒
      EVERY (λs. inhabited s) tyvs ∧
      (LENGTH tyvs = LENGTH (types_of_upd upd)))``,
    rw[IS_SOME_EXISTS,PULL_EXISTS] >> res_tac >> fs[])

fun prove_inhabited_thm vti hyps instantiated_tys cs cs_cases cs_rws wf_to_inners =
  let
    val gtm =
      length_thm_to_lengths_and_inhabited_thm
      |> ISPEC cs |> concl |> dest_imp |> snd |> dest_imp |> fst
    val goal = (hyps,gtm)
    (* set_goal goal *)
    val c = listLib.list_compset()
    val () = optionLib.OPTION_rws c
    val () = pairLib.add_pair_compset c
    val eth = EVERY_range_inhabited vti instantiated_tys
    val eth1 = foldl (uncurry PROVE_HYP) eth wf_to_inners
    val vtys = cs_cases |> SPEC_ALL |> concl |> rand |> listSyntax.dest_mem |> snd
               |> listSyntax.dest_list |> fst |> map (fst o listSyntax.dest_list)
               |> flatten |> map (fst o dom_rng o type_of o rand)
               |> mk_set
    val vth = EVERY_range_inhabited vti vtys
    val vth1 = foldl (uncurry PROVE_HYP) vth wf_to_inners
    val th = VALID_TAC_PROOF(goal,
      CONV_TAC(QUANT_CONV(LAND_CONV(REWR_CONV cs_cases))) >>
      CONV_TAC(HO_REWR_CONV(GSYM listTheory.EVERY_MEM)) >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      REWRITE_TAC cs_rws >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      mp_tac eth1 >> mp_tac vth1 >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      PROVE_TAC[])
  in
    th
  end

val to_well_formed_constraints_thm = prove(
  ``∀upd cs δ.
    (∀vs tyvs tmvs.
      (cs vs = SOME (tyvs,tmvs)) ⇒
      (LENGTH tyvs = LENGTH (types_of_upd upd)) ∧
      (LENGTH tmvs = LENGTH (consts_of_upd upd))) ⇒
    (∀vs. IS_SOME (cs vs) ⇒
            EVERY inhabited vs ∧
            EVERY inhabited (FST (THE (cs vs)))) ⇒
      (∀vs. IS_SOME (cs vs) ⇒
            (LENGTH (tyvars_of_upd upd) = LENGTH vs) ∧
          ∀τ. is_type_valuation τ ∧ (MAP τ (tyvars_of_upd upd) = vs) ⇒
              LIST_REL
                (λv ty. v <: typesem (constrain_tyass cs upd δ) τ ty)
                (SND(THE (cs vs)))
                (MAP SND (consts_of_upd upd)))
     ⇒ well_formed_constraints upd cs δ``,
   rw[well_formed_constraints_def,IS_SOME_EXISTS,PULL_EXISTS,LET_THM] >>
   res_tac >> fs[])

val tyaof_constrain_interpretation = prove(
  ``∀upd cs i.
      tyaof (constrain_interpretation upd cs i) =
      constrain_tyass cs upd (tyaof i)``,
   rw[] >> PairCases_on`i` >> rw[constrain_interpretation_def])

val tmaof_constrain_interpretation = prove(
  ``∀upd cs i.
      tmaof (constrain_interpretation upd cs i) =
      constrain_tmass cs upd (tmaof i)``,
   rw[] >> PairCases_on`i` >> rw[constrain_interpretation_def])

fun prove_constrained_consts_in_type_thm
      vti hyps inner_upd cs cs_cases cs_rws jtm
      tyvars_of_upd_rw k_is_std_type_assignment all_assums new_sig =
  let
    val gtm =
      to_well_formed_constraints_thm
      |> ISPECL [inner_upd,cs,``tyaof ^jtm``] |> concl
      |> dest_imp |> snd
      |> dest_imp |> snd
      |> dest_imp |> fst
    val goal = (hyps,gtm)
    val c = listLib.list_compset()
    val () = optionLib.OPTION_rws c
    val () = pairLib.add_pair_compset c
    val () = computeLib.add_thms[listTheory.LIST_REL_def] c
    fun EVAL_vars tm =
      EVAL (assert (can (match_term``mlstring_sort X``)) tm)
    fun EVAL_consts_of_upd tm =
      EVAL (assert (can (match_term``consts_of_upd X``)) tm)
    (* set_goal goal *)
    val tyval_vars = filter (can (match_term``wf_to_inner (to_inner (Tyvar X))``)) (map concl all_assums)
    val tyval1 = foldl (fn (x,tyval) =>
        let
          val k = x |> funpow 3 rand
          val v = ``range (^(rand x))``
        in
            mk_comb(combinSyntax.mk_update(k,v),tyval)
        end) tyval tyval_vars
    val tyval1_thms = map (fn x =>
        let
          val k = x |> funpow 3 rand
          val v = ``range (^(rand x))``
        in
          prove(mk_eq(mk_comb(tyval1,k),v),rw[combinTheory.APPLY_UPDATE_THM])
        end) tyval_vars
    fun typesem_tac find_to_inner (g as (asl,w)) =
      let
        val th1 = prim_typesem_cert vti (fst(dom_rng(type_of(find_to_inner w))))
        val th2 = INST[tyass |-> rand(concl k_is_std_type_assignment ),
                       tyval |-> tyval1,
                       tysig |-> ``tysof ^new_sig``] th1
        val th3 = foldl (uncurry PROVE_HYP) th2 (k_is_std_type_assignment::(tyval1_thms@all_assums))
      in
        mp_tac th3 g
      end
    fun mk_tyin_tac (g as (asl,w)) =
      let
        val tasms = filter (can (match_term``τ (strlit x) = z``)) asl
        fun mapthis tm =
          let
            val (l,r) = dest_eq tm
           in
             mk_pair(type_to_deep(fst(dom_rng(type_of (rand r)))),
                     mk_Tyvar(rand l))
           end
        val tyin = listSyntax.mk_list(map mapthis tasms, pairSyntax.mk_prod(type_ty,type_ty))
        val args = w |> rand |> strip_comb |> snd
        val delta = el 1 args
        val tau = el 2 args
        val ty = el 3 args
        val tau' = ``λx. typesem ^delta ^tyval1 (TYPE_SUBST ^tyin (Tyvar x))``
      in
        mp_tac (ISPECL [delta,tau,ty,tau'] typesem_tyvars) g
      end
    fun wf_to_inner_mk_to_inner_tac (g as (asl,w)) =
      let
        val th = wf_to_inner_mk_to_inner vti (fst(dom_rng(type_of(rand w))))
        val th2 = foldl (uncurry PROVE_HYP) th all_assums
      in
        ACCEPT_TAC th2 g
      end
    val th = VALID_TAC_PROOF(goal,
      CONV_TAC(QUANT_CONV(LAND_CONV(REWR_CONV cs_cases))) >>
      CONV_TAC(HO_REWR_CONV(GSYM listTheory.EVERY_MEM)) >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      REWRITE_TAC cs_rws >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      REWRITE_TAC [tyvars_of_upd_rw] >>
      CONV_TAC(DEPTH_CONV EVAL_vars) >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      CONV_TAC(DEPTH_CONV EVAL_consts_of_upd) >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      rpt conj_tac >>
      gen_tac >>
      strip_tac >>
      rpt conj_tac >>
      mk_tyin_tac >>
      (impl_tac >- (
         gen_tac >>
         CONV_TAC(LAND_CONV EVAL) >>
         SIMP_TAC bool_ss [] >>
         CONV_TAC(RAND_CONV(LAND_CONV(RAND_CONV EVAL))) >>
         strip_tac >> BasicProvers.VAR_EQ_TAC >>
         CONV_TAC(LAND_CONV(RAND_CONV EVAL)) >>
         first_x_assum(CONV_TAC o RAND_CONV o REWR_CONV) >>
         typesem_tac (rand o rand) >>
         REWRITE_TAC[tyaof_constrain_interpretation])) >>
      disch_then(CHANGED_TAC o SUBST1_TAC o SYM) >>
      CONV_TAC(RAND_CONV(REWR_CONV(GSYM typesem_TYPE_SUBST))) >>
      CONV_TAC(RAND_CONV(RAND_CONV(EVAL))) >>
      typesem_tac (rator o rand o rator) >>
      REWRITE_TAC[tyaof_constrain_interpretation] >>
      disch_then(CHANGED_TAC o SUBST1_TAC) >>
      match_mp_tac wf_to_inner_range_thm >>
      wf_to_inner_mk_to_inner_tac)
  in
    th
  end

local
  val tysig_extend_thm = prove(
    ``(FLOOKUP (tysof (sigof ctxt)) nm = SOME arity) ⇒ upd updates ctxt ⇒
      (FLOOKUP (tysof (sigof (upd::ctxt))) nm = SOME arity)``,
    rw[finite_mapTheory.FLOOKUP_FUNION] >>
    BasicProvers.CASE_TAC >>
    imp_res_tac alistTheory.ALOOKUP_MEM  >>
    imp_res_tac updates_upd_DISJOINT >>
    fs[IN_DISJOINT,listTheory.MEM_MAP,pairTheory.EXISTS_PROD] >>
    metis_tac[])

  val tmsig_extend_thm = prove(
    ``(FLOOKUP (tmsof (sigof ctxt)) nm = SOME ty) ⇒ upd updates ctxt ⇒
      (FLOOKUP (tmsof (sigof (upd::ctxt))) nm = SOME ty)``,
    rw[finite_mapTheory.FLOOKUP_FUNION] >>
    BasicProvers.CASE_TAC >>
    imp_res_tac alistTheory.ALOOKUP_MEM  >>
    imp_res_tac updates_upd_DISJOINT >>
    fs[IN_DISJOINT,listTheory.MEM_MAP,pairTheory.EXISTS_PROD] >>
    metis_tac[])
in
  fun make_k_sig_assum uth ia =
    case total (MATCH_MP tysig_extend_thm) ia of
      SOME th =>
      MATCH_MP th uth | NONE =>
    let val th = (MATCH_MP tmsig_extend_thm) ia in
      MATCH_MP th uth
    end
end

local
  val tyass_extend_thm = prove(
    ``(tyaof i nm args = ty) ⇒
       equal_on sig i i' ⇒ nm ∈ FDOM (tysof sig) ⇒
      (tyaof i' nm args = ty)``,
    rw[equal_on_def] >> metis_tac[])

  val tmass_extend_thm = prove(
    ``(tmaof i nm args = m) ⇒
      equal_on sig i i' ⇒ nm ∈ FDOM (tmsof sig) ⇒
      (tmaof i' nm args = m)``,
    rw[equal_on_def] >> metis_tac[])
in
  fun make_k_int_assum eqth ia =
    case total (MATCH_MP tyass_extend_thm) ia of
      SOME th =>
          MP (CONV_RULE(LAND_CONV EVAL)(MATCH_MP th eqth)) TRUTH
    | NONE =>
    let val th = (MATCH_MP tmass_extend_thm) ia in
          MP (CONV_RULE(LAND_CONV EVAL)(MATCH_MP th eqth)) TRUTH
    end
end

fun make_wf_to_inner_th vti ax =
  let
    val th = MATCH_MP wf_to_inner_defined_type (GEN_ALL ax)
    val abs = rator(lhs(concl ax))
    val (b,a) = dom_rng(type_of abs)
    val th1 = SPECL [type_to_deep a, mk_to_inner vti b] th
    val th2 = MATCH_MP th1 (wf_to_inner_mk_to_inner vti b)
  in
    th2
  end

val of_sigof_rwt = prove(
  ``(tysof (sigof x) = tysof x) ∧
    (tmsof (sigof x) = tmsof x)``,
  rw[])

val unpair_sig = prove(``sig = (tysof sig, tmsof sig)``, rw[])
val unpair_int = prove(``int = (tyaof int, tmaof int)``, rw[])
val unpair_val = prove(``val = (tyvof val, tmvof val)``, rw[])
fun tosub x y = {redex = x, residue = y}
val is_valuation_sigof_lemma = prove(
  ``∀ctxt δ v.
      is_valuation (tysof ctxt) δ v ⇒ is_valuation (tysof (sigof ctxt)) δ v``,
  rw[])

fun prove_ax_satisfied vti hyps inner_upd old_ctxt cs cs_cases jtm
                       ktyass ktmass tyvars_of_upd_rw new_sig
                       good_context_k all_assums ax =
  let
    val inner_ax = term_to_deep (concl ax)
    val gtm =
      constrain_interpretation_satisfies |> UNDISCH
      |> SPECL [jtm,inner_upd,old_ctxt,cs]
      |> concl |> dest_imp |> fst
      |> strip_conj |> last |> rator |> rand
      |> C (curry mk_comb) inner_ax
    val c = reduceLib.num_compset()
    val () = computeLib.add_thms[listTheory.EVERY_DEF] c
    val cl = reduceLib.num_compset()
    val () = computeLib.add_thms[listTheory.MAP] cl
    val () = computeLib.add_datatype_info cl (valOf(TypeBase.fetch``:'a list``))
    val gck = good_context_k |> ONCE_REWRITE_RULE[unpair_sig, unpair_int]
    val sorted_tys =
      sort (cmp_to_P (inv_img_cmp tyvar_to_str String.compare))
        (type_vars_in_term (concl ax))
    fun termsem_tac (g as (asl,w)) =
      let
        val tys = w |> dest_imp |> fst |> rhs |> listSyntax.dest_list |> fst
                  |> map (fst o dom_rng o type_of o rand)
        val tyin = map2 tosub sorted_tys tys
        val iax = INST_TYPE tyin ax
        val th0 = termsem_cert_unint tyin (concl ax)
        val th1 = th0 |> CONV_RULE(RAND_CONV(RAND_CONV(REWR_CONV(EQT_INTRO iax))))
                      |> CONV_RULE(RAND_CONV(REWR_CONV bool_to_inner_true))
        val ktysig = ``tysof ^new_sig``
        val insts =  [tyass |-> ktyass,
                      tmass |-> ktmass,
                      tysig |-> ktysig,
                      tmsig |-> ``tmsof ^new_sig``]
        val th2 = INST insts th1
        val fvs = free_vars(concl ax)
        fun mapthis v0 =
          let
            val f = mk_to_inner tyin (type_of v0)
            val v = inst tyin v0
            val vd = term_to_deep v0
            val (n,ty) = dest_Var vd
            val lhsx = ``^tmval (^n,^ty)``
            val rs = ``finv ^f ^lhsx``
            val th6 = typesem_cert tyin (type_of v0) |> INST insts
            val th7 =
              is_valuation_def
              |> ISPECL [mem,ktysig,ktyass,mk_pair(tyval,tmval)]
              |> EQ_IMP_RULE |> fst
              |> REWRITE_RULE[of_sigof_rwt]
              |> UNDISCH
              |> CONJUNCT2
              |> REWRITE_RULE[is_term_valuation_def]
              |> ISPECL[n,ty]
              |> CONV_RULE(LAND_CONV EVAL)
              |> C MP TRUTH
              |> CONV_RULE(RAND_CONV(REWR_CONV th6))
            val th8 =
              wf_to_inner_finv_right
              |> ISPEC f
              |> C MP (wf_to_inner_mk_to_inner [] (fst(dom_rng(type_of f))))
              |> ISPEC lhsx
              |> C MP th7
              |> SYM
          in
            (v |-> rs, th8)
          end
        val (s,ths) = unzip (map mapthis fvs)
        val th3 = foldl (uncurry PROVE_HYP) (INST s th2) ths
        val valth = is_valuation_sigof_lemma
          |> ISPECL[new_sig |> funpow 4 rand,ktyass,mk_pair(tyval,tmval)]
          |> UNDISCH
        val wfs = map (wf_to_inner_mk_to_inner [] o #residue) tyin
        val th4 = foldl (uncurry PROVE_HYP) th3 (gck::valth::(wfs@all_assums))
      in
        (CONV_TAC(RATOR_CONV(computeLib.CBV_CONV cl)) >>
         (strip_tac ORELSE CONV_TAC BETA_CONV) >>
         mp_tac th4) g
      end
    val goal = (hyps,gtm)
    (* set_goal goal *)
    val th = VALID_TAC_PROOF(goal,
      CONV_TAC BETA_CONV >>
      CONV_TAC(QUANT_CONV(LAND_CONV(REWR_CONV cs_cases))) >>
      CONV_TAC(HO_REWR_CONV(GSYM listTheory.EVERY_MEM)) >>
      CONV_TAC(computeLib.CBV_CONV c) >>
      rpt conj_tac >>
      ntac 2 gen_tac >> strip_tac >>
      REWRITE_TAC[tyvars_of_upd_rw] >>
      CONV_TAC(LAND_CONV(LAND_CONV(RAND_CONV(EVAL)))) >>
      termsem_tac >>
      disch_then(SUBST1_TAC o SYM) >>
      REWRITE_TAC[of_sigof_rwt])
      (* val (asl,w) = top_goal() *)
  in
    th
  end

type interpretation_cert = {
  good_context_thm : thm,
  models_thm : thm,
  wf_to_inners : thm list,
  sig_assums : thm list,
  int_assums : thm list
}

(* TODO: MATCH_ACCEPT_TAC is broken? it fails when
  fun match_accept_tac th (g as (asl,w)) =
    ACCEPT_TAC (INST_TY_TERM (match_term (concl th) w) th) g
  doesn't, when the goal contains multiple occurrences of the same variable
*)

val bool_thms =
  [equality_thm,truth_thm,and_thm,implies_thm,forall_thm
  ,exists_thm,or_thm,falsity_thm,not_thm]

val vti:(hol_type,hol_type)subst = []

(* TODO: improve algorithm - maybe need to add more structure to the
         wf_to_inners when they are generated? *)
fun reduce_hyps i_wf_to_inners new_wf_to_inners0 =
  let
    val asms = filter (fn th => not(HOLset.member(hypset th,concl th))) i_wf_to_inners
    fun reduce thc [] = thc
      | reduce (th,c) (asm::asms) =
        if HOLset.member(hypset th,concl asm) andalso
           not(concl th = concl asm)
        then
          reduce (PROVE_HYP asm th,true) asms
        else reduce (th,c) asms
    fun loop thms =
      let
        val thmsc = map (fn th => reduce (th,false) (thms@asms)) thms
        val (thms,cs) = unzip thmsc
      in
        if exists I cs then loop thms else thms
      end
  in
    loop new_wf_to_inners0
  end

val base_hyps =
  [``wf_to_inner ((to_inner Ind):ind -> 'U)``,
   ``is_set_theory ^mem``]

fun mesg n =
  Feedback.HOL_MESG("build_interpretation: "^(Int.toString n))

fun build_interpretation length_ctxt vti wf_to_inner_hyps [] tys consts =
  let
    val _ = mesg length_ctxt
    val hypotheses =
      base_hyps @
      (mapfilter (fn ty => to_inner_prop vti (assert is_vartype ty)) tys)
    val tyassums = flatten (map (base_type_assums vti) tys)
         |> filter (not o can (assert (equal tyval) o fst o strip_comb o lhs))
    val tmassums = flatten (map (base_term_assums vti) consts)
      (* |> filter (not o can (assert (equal tmval) o fst o strip_comb o lhs)) *)
    val assums0 = tyassums @ tmassums
    val select_tys = filter (same_const boolSyntax.select) consts
      |> map (snd o dom_rng o type_of)
    fun foldthis (ty,th) =
      let
        val wf = wf_to_inner_mk_to_inner vti ty
        val th1 = MATCH_MP good_select_extend_base_select wf
        val th2 = MATCH_MP th1 th
      in th2 end
    val good_select =
      foldl foldthis
        (UNDISCH holAxiomsTheory.good_select_base_select)
        select_tys
    val select = rand(concl good_select)
    val int = ``hol_model ^select (to_inner Ind)``
    val inst_ind = Q.INST[`ind_to_inner`|->`to_inner Ind`]
    val gcth =
      MATCH_MP (inst_ind good_context_base_case)
      good_select
    val hmm = hol_model_models |> DISCH_ALL
      |> C MATCH_MP (ASSUME (el 1 hypotheses))
      |> C MATCH_MP good_select
      |> C MATCH_MP (ASSUME (el 2 hypotheses))
    val args = snd(strip_comb(concl gcth))
    val s = [tysig |-> ``tysof ^(el 2 args)``,
             tmsig |-> ``tmsof ^(el 2 args)``,
             tyass |-> ``tyaof ^(el 3 args)``,
             tmass |-> ``tmaof ^(el 3 args)``]
    val assums = map (subst s) assums0
    val th =
      MATCH_MP hol_model_def
        (LIST_CONJ [ASSUME (el 2 hypotheses),
                    good_select,
                    ASSUME (el 1 hypotheses)])
      |> CONJUNCT1
    val (wf_to_inner_tms,assums1) =
      partition (can(match_term``wf_to_inner x``)) assums
    val wf_to_inners = map
      (fn tm => VALID_TAC_PROOF((hypotheses,tm),first_assum ACCEPT_TAC))
      wf_to_inner_tms
    val (sig_tms,int_tms) =
      partition (can(match_term``FLOOKUP sig nm = SOME v``)) assums1
    val sig_assums = map
      (fn tm => VALID_TAC_PROOF((hypotheses,tm),EVAL_TAC))
      sig_tms
    (* rather than calculate these here, we make sure
       we only assume things that will be proved in parent calls.
       the parent calls pass them in as an argument to us.
    val wf_to_inner_hyps =
      foldl (fn (tm,s) => HOLset.addList(s,
          map (to_inner_prop vti) (base_types_of_term tm)))
        Term.empty_tmset consts
      |> HOLset.listItems
    *)
    val styvars = filter (not o equal universe_ty) (type_vars_in_term select)
    fun prepare_bool_thm th =
      let
        val tyvars = filter (not o equal universe_ty) (type_vars_in_term (concl th))
        val newtys = map (tyvar_variant styvars) tyvars
        val th1 = INST_TYPE (map2 (curry op |->) tyvars newtys) th
        val th2 = Q.INST[`select`|->`^select`] th1
        val th3 = PROVE_HYP good_select th2
      in
        th3
      end
    fun wf_match_accept_tac th (g as (asl,w)) =
      let
        val th1 = INST_TY_TERM (match_term (concl th) w) th
        val wfs = map (wf_to_inner_mk_to_inner vti o fst o dom_rng o type_of o rand)
                    (set_diff (hyp th1) hypotheses)
        val th2 = foldl (uncurry PROVE_HYP) th1 wfs
      in
        ACCEPT_TAC th2 g
      end
    fun ranges_distinct_tac (g as (asl,w)) =
      let
        val e = boolSyntax.dest_neg w
        val ty1 = fst(dom_rng(type_of(rand(lhs e))))
        val ty2 = fst(dom_rng(type_of(rand(rhs e))))
        val th = ranges_distinct vti ty1 ty2
      in
        ACCEPT_TAC th g
      end
    val select_thm = inst_ind tmaof_hol_model_select
    fun select_tac (g as (asl,w)) =
      let
        val wf = wf_to_inner_mk_to_inner vti (fst(dom_rng(type_of(rand(rand(rator(rand(lhs(w)))))))))
        val th1 = MATCH_MP select_thm wf
        val th2 = MATCH_MP th1 good_select
      in
        MATCH_MP_TAC th2 >>
        gen_tac >>
        REWRITE_TAC[combinTheory.APPLY_UPDATE_THM] >>
        rpt IF_CASES_TAC >>
        CONV_TAC(LAND_CONV(BETA_CONV)) >>
        TRY REFL_TAC >>
        MATCH_MP_TAC FALSITY >>
        pop_assum mp_tac >>
        simp_tac bool_ss [] >>
        ranges_distinct_tac
      end g
    val ind_tac = ACCEPT_TAC (last (CONJUNCTS hmm))
    val int_assums = map
      (fn tm =>
        VALID_TAC_PROOF((hypotheses@wf_to_inner_hyps,tm),
          FIRST (select_tac::ind_tac::(map (wf_match_accept_tac o prepare_bool_thm)
                                           (onto_thm::one_one_thm::bool_thms))))
      )
      int_tms
  in
    { good_context_thm = gcth,
      models_thm = th,
      wf_to_inners = wf_to_inners,
      sig_assums = sig_assums,
      int_assums = int_assums }
  end
| build_interpretation length_ctxt vti wf_to_inner_hyps (upd::ctxt) tys consts =
  let
    val instances_to_constrain =
      union (find_type_instances tys (#tys upd))
            (find_const_instances consts (#consts upd))
    val instantiated_tys =
      flatten (map (fn s => map (type_subst s) (#tys upd)) instances_to_constrain)
    val instantiated_consts =
      flatten (map (fn s => map (inst s) (#consts upd)) instances_to_constrain)
    val instantiated_axioms =
      flatten (map (fn s => map (INST_TYPE s) (#axs upd)) instances_to_constrain)
    val new_tys =
      mk_set(flatten (map (base_types_of_term o concl) instantiated_axioms))
    val new_consts =
      mk_set(flatten (map (filter is_const o base_terms_of_term o concl) instantiated_axioms))
    val {good_context_thm = good_context_i0,
         models_thm = i_models0,
         wf_to_inners = i_wf_to_inners,
         sig_assums = i_sig_assums,
         int_assums = i_int_assums }
      = build_interpretation (length_ctxt+1) vti
        (union wf_to_inner_hyps (map (to_inner_prop vti) instantiated_tys))
        ctxt
        (set_diff (union tys new_tys) instantiated_tys)
        (set_diff (union consts new_consts) instantiated_consts)
      (* [Note: It is *not* guaranteed that
          (instantiated_tys SUBSET tys) or the analog for consts;
          this is because we may have been *told* to constrain e.g.
          one of the constants of a certain instance of the update,
          but this means that we need to constrain *all* of the
          constants of that update] *)
    val _ = mesg length_ctxt
    (* val hyps = hyp i_models @ flatten (map hyp i_wf_to_inners) *)
    val hyps = base_hyps @ wf_to_inner_hyps
    val new_wf_to_inners0 = if null (#tys upd) then [] else
      mapfilter (make_wf_to_inner_th vti) instantiated_axioms
    val new_wf_to_inners = reduce_hyps i_wf_to_inners new_wf_to_inners0
    val wf_to_inners = new_wf_to_inners @ i_wf_to_inners
    val update_wf_to_inners1 = C (foldl (uncurry PROVE_HYP)) wf_to_inners
    val update_wf_to_inners = map update_wf_to_inners1
    val new_i_int_assums = update_wf_to_inners i_int_assums
    val i_models = update_wf_to_inners1 i_models0
    val good_context_i = update_wf_to_inners1 good_context_i0
    val jth = MATCH_MP update_interpretation_def (CONJ (#sound_update_thm upd) i_models)
    val (j_equal_on_i,j_models) = CONJ_PAIR jth
    val jtm = get_int j_models
    val good_context_j = MATCH_MP good_context_extend
      (LIST_CONJ [good_context_i, #updates_thm upd, #sound_update_thm upd, i_models])
    val new_sig = good_context_j |> concl |> strip_comb |> snd |> el 2
    val sig_ths =
        map (fn gtm => prove(gtm,EVAL_TAC))
          ((map (tmsig_prop ``tmsof ^new_sig``) instantiated_consts) @
           (map (tysig_prop ``tysof ^new_sig``) instantiated_tys))
    val theory_ok_thm = MATCH_MP (MATCH_MP extends_theory_ok (#extends_init_thm upd)) init_theory_ok
    val (ktm,cs_assums0,cs_rws0) = make_cs_assums vti upd instances_to_constrain theory_ok_thm jtm
    val cs_assums = update_wf_to_inners cs_assums0
    val cs_rws = update_wf_to_inners cs_rws0
    val cs = ktm |> rator |> rand
    val z = genvar(listSyntax.mk_list_type universe_ty)
    val cs_cases = GEN z (updates_equal_some_cases z cs)
    val inner_upd = update_to_inner upd
    val lengths_match = prove_lengths_match_thm hyps cs cs_cases cs_rws inner_upd
    val k_equal_on_j =
      MATCH_MP (UNDISCH constrain_interpretation_equal_on)
        (LIST_CONJ [#constrainable_thm upd,
                    lengths_match,
                    #updates_thm upd,
                    #extends_init_thm upd])
      |> SPEC jtm
    val k_equal_on_i = MATCH_MP equal_on_trans (CONJ j_equal_on_i k_equal_on_j)
    val [_,is_std_sig_thm,j_is_int,j_is_std] =
      good_context_j |> REWRITE_RULE[good_context_unpaired] |> CONJUNCTS
    val jistya = j_is_int |> REWRITE_RULE[is_interpretation_def] |> CONJUNCT1
    val jistma = j_is_int |> REWRITE_RULE[is_interpretation_def] |> CONJUNCT2
    val inhabited_thm = prove_inhabited_thm vti hyps instantiated_tys cs cs_cases cs_rws wf_to_inners
    val k_sig_assums = map (make_k_sig_assum (#updates_thm upd)) i_sig_assums
    val k_int_assums = map (make_k_int_assum k_equal_on_i) new_i_int_assums
    val sig_assums = sig_ths@k_sig_assums
    val int_assums = cs_assums@k_int_assums
    val old_sig_is_std = good_context_i |> REWRITE_RULE[good_context_unpaired] |> CONJUNCT2 |> CONJUNCT1
    val k_is_std = MATCH_MP is_std_interpretation_equal_on
                     (LIST_CONJ [j_is_std,k_equal_on_j,old_sig_is_std])
    val tyvars_of_upd_rw =
      MATCH_MP tyvars_of_TypeDefn
        (CONJ (#updates_thm upd) old_sig_is_std)
      handle HOL_ERR _ =>
        MATCH_MP tyvars_of_ConstSpec
          (CONJ
            (MATCH_MP ConstSpec_updates_welltyped (#updates_thm upd))
            (#constrainable_thm upd))
    val k_is_std_type_assignment =
      k_is_std |> REWRITE_RULE[is_std_interpretation_def] |> CONJUNCT1
    val j_is_std_type_assignment =
      j_is_std |> REWRITE_RULE[is_std_interpretation_def] |> CONJUNCT1
    (* TODO: use these in a more fine-grained way *)
    val all_assums = wf_to_inners@sig_assums@int_assums
    val constrained_consts_in_type_thm =
      prove_constrained_consts_in_type_thm vti hyps inner_upd cs cs_cases cs_rws jtm
        tyvars_of_upd_rw k_is_std_type_assignment all_assums new_sig
    val well_formed_constraints_thm =
      MATCH_MP
        (MATCH_MP
           (MATCH_MP to_well_formed_constraints_thm lengths_match)
           inhabited_thm)
        constrained_consts_in_type_thm
    val istmath =
      MATCH_MP (UNDISCH constrain_tmass_is_term_assignment)
        (LIST_CONJ [jistma,
                    j_is_std_type_assignment,
                    k_is_std_type_assignment |> REWRITE_RULE[tyaof_constrain_interpretation],
                    #constrainable_thm upd,
                    well_formed_constraints_thm,
                    #updates_thm upd,
                    #extends_init_thm upd])
    val istyath =
      let
        val th2 =
          MATCH_MP
            (MATCH_MP (ISPEC cs length_thm_to_lengths_and_inhabited_thm) lengths_match)
            inhabited_thm
      in
        MATCH_MP constrain_tyass_is_type_assignment
                 (CONJ jistya th2)
      end
    val istyath1 = REWRITE_RULE[GSYM tyaof_constrain_interpretation]istyath
    val istmath1 = REWRITE_RULE[GSYM tmaof_constrain_interpretation,
                                GSYM tyaof_constrain_interpretation]istmath
    val k_is_int =
      EQ_MP
        (CONV_RULE(LAND_CONV(REWRITE_CONV[of_sigof_rwt]))
           (SYM(SPECL[mem,new_sig,ktm]is_interpretation_def)))
        (CONJ istyath1 istmath1)
    val good_context_k =
      EQ_MP
        (SYM(SPECL[mem,new_sig,ktm] (Q.GENL[`i`,`sig`,`mem`]good_context_unpaired)))
        (LIST_CONJ
          [good_context_j |> REWRITE_RULE[good_context_unpaired] |> CONJUNCTS |> el 1,
           good_context_j |> REWRITE_RULE[good_context_unpaired] |> CONJUNCTS |> el 2,
           k_is_int,
           k_is_std])
    val axexts_empty = prove(``axexts_of_upd ^inner_upd = []``,EVAL_TAC)
    val old_ctxt = #updates_thm upd |> concl |> rand
    val ktyass = istyath1 |> concl |> rand
    val ktmass = istmath1 |> concl |> rand
    val axs_satisfied =
      map (prove_ax_satisfied vti hyps inner_upd old_ctxt cs cs_cases jtm
                              ktyass ktmass tyvars_of_upd_rw new_sig
                              good_context_k all_assums)
          (#axs upd)
    val EVERY_axs =
      let
        val pr =
          constrain_interpretation_satisfies
          |> UNDISCH
          |> ISPECL[jtm,inner_upd,old_ctxt,cs]
          |> concl |> dest_imp |> fst |> strip_conj |> last
          |> rator |> rand
        val eth = join_EVERY pr axs_satisfied
        val axs_of_upd_rwt =
          prove(``^(rand(concl eth)) = axioms_of_upd ^inner_upd``,EVAL_TAC)
      in
        eth |> CONV_RULE(RAND_CONV(REWR_CONV axs_of_upd_rwt))
      end
    val valid_constraints_thm =
      LIST_CONJ [
        #constrainable_thm upd,
        #updates_thm upd,
        theory_ok_thm,
        axexts_empty,
        j_models,
        lengths_match |> CONV_RULE(HO_REWR_CONV IS_SOME_cs_thm),
        EVERY_axs]
      |> MATCH_MP (UNDISCH constrain_interpretation_satisfies)
    val k_models =
      LIST_CONJ
        [#constrainable_thm upd,
         #updates_thm upd,
         #extends_init_thm upd,
         j_models,
         well_formed_constraints_thm,
         valid_constraints_thm]
      |> MATCH_MP (UNDISCH add_constraints_thm)
  in
    { good_context_thm = good_context_k,
      models_thm = k_models,
      wf_to_inners = wf_to_inners,
      sig_assums = sig_assums,
      int_assums = int_assums
    }
  end

val build_interpretation = build_interpretation 0 []

fun build_ConstDef extends_init_thm def =
  let
    val ctxt = extends_init_thm |> concl |> rator |> rand
    val (c,d) = dest_eq(concl def)
    val {Name,Thy,Ty} = dest_thy_const c
    val tm = term_to_deep d
    val name = string_to_inner Name
    val theory_ok =
      MATCH_MP (
        MATCH_MP extends_theory_ok extends_init_thm)
        init_theory_ok
    val is_std_sig = MATCH_MP theory_ok_sig theory_ok
      |> REWRITE_RULE[of_sigof_rwt]
    val (EVAL_type_ok,EVAL_term_ok) = holSyntaxLib.EVAL_type_ok_term_ok EVAL is_std_sig
    val conditions =
      prove(ConstDef_updates |> SPECL[name,tm,ctxt] |> concl |> dest_imp |> fst,
        conj_tac >- ACCEPT_TAC theory_ok >>
        conj_tac >- (
          CONV_TAC EVAL_term_ok >>
          rw[holSyntaxLibTheory.tyvar_inst_exists] >>
          rw[tyvar_inst_exists2,tyvar_inst_exists2_diff]) >>
        conj_tac >- EVAL_TAC >>
        conj_tac >- ( EVAL_TAC >> rw[] >> PROVE_TAC[] ) >>
        EVAL_TAC >> rw[])
    val inner_upd = ``ConstDef ^name ^tm``
    val updates_thm = MATCH_MP ConstDef_updates conditions
    val sound_update_thm =
      holExtensionTheory.new_definition_correct
      |> UNDISCH |> C MATCH_MP conditions
    val constrainable_thm = prove(``constrainable_update ^inner_upd``,
      ho_match_mp_tac (GEN_ALL ConstSpec_constrainable) >>
      exists_tac ctxt >> conj_tac >- ACCEPT_TAC updates_thm >>
      EVAL_TAC >> rw[])
    val upd:update =
      { sound_update_thm  = sound_update_thm
      , constrainable_thm = constrainable_thm
      , updates_thm       = updates_thm
      , extends_init_thm  = extends_init_thm
      , consts            = [c]
      , tys               = []
      , axs               = [def]
      }
  val new_extends_init_thm =
    MATCH_MP updates_extends_trans (CONJ updates_thm extends_init_thm)
  in
    (upd, new_extends_init_thm)
  end

val termsem_cert_unint = termsem_cert_unint []

val inhabited_range_lemma = prove(
  ``∀a:mlstring inx. wf_to_inner inx ⇒ ((λs. inhabited s) o SND) (a,range inx)``,
  rw[inhabited_range])
val inhabited_SND = inhabited_range_lemma
  |> SPEC_ALL |> UNDISCH |> concl |> rator

fun termsem_cert ctxt tm =
  let
    val _ = assert HOLset.isEmpty (FVL [tm] empty_tmset)
    val tys = base_types_of_term tm
    val consts = base_terms_of_term tm
    val tyvars = type_vars_in_term tm
    val { good_context_thm,
          models_thm,
          wf_to_inners,
          sig_assums,
          int_assums } =
        build_interpretation (map (to_inner_prop []) tyvars) ctxt tys consts
    val th1 = termsem_cert_unint tm
    val args = good_context_thm |> concl |> strip_comb |> snd
    val s = [tysig |-> ``tysof ^(el 2 args)``,
             tmsig |-> ``tmsof ^(el 2 args)``,
             tyass |-> ``tyaof ^(el 3 args)``,
             tmass |-> ``tmaof ^(el 3 args)``]
    val th2 = INST s th1
    val gc = good_context_thm |> ONCE_REWRITE_RULE[unpair_sig, unpair_int]
    val th3 = foldl (uncurry PROVE_HYP) th2 (gc::sig_assums@int_assums)
    val th4 = foldl (uncurry PROVE_HYP) th3 wf_to_inners
    val tyval_asms = filter is_eq (hyp th4)
    val tyval_constraints = map (fn tm => mk_pair(rand(lhs tm),rhs tm)) tyval_asms
    val ls = mk_list(tyval_constraints,
                     mk_prod(mlstringSyntax.mlstring_ty,universe_ty))
    fun mapthis tm =
      let val (a,rinx) = dest_pair tm in
        UNDISCH(ISPECL [a,rand rinx] inhabited_range_lemma)
      end
    val inhabited_thms = map mapthis tyval_constraints
    val tyval_thm =
      SPEC ls is_type_valuation_update_list
      |> C MATCH_MP is_type_valuation_base
      |> C MATCH_MP (join_EVERY inhabited_SND inhabited_thms)
    val valth =
      a_valuation_def
      |> SPEC_ALL |> UNDISCH
      |> C MATCH_MP
        (MATCH_MP good_context_is_type_assignment gc
         |> ONCE_REWRITE_RULE[])
      |> C MATCH_MP tyval_thm
    val v = valth |> CONJUNCT1 |> concl |> rand
    val sub = [tyval |-> ``tyvof ^v``,tmval |-> ``tmvof ^v``]
    val th5 = th4 |> INST sub
                  |> PROVE_HYP (valth |> CONJUNCT1 |> PURE_ONCE_REWRITE_RULE[unpair_val])
    fun mapthis tm =
      tm |> subst sub
         |> (LAND_CONV(RATOR_CONV(REWR_CONV(CONJUNCT2 valth)) THENC
                       REWRITE_CONV[UPDATE_LIST_THM,combinTheory.APPLY_UPDATE_THM])
             THENC SIMP_CONV (std_ss++listSimps.LIST_ss++stringSimps.STRING_ss) [mlstringTheory.mlstring_11])
         |> EQT_ELIM
    val th6 = foldl (uncurry PROVE_HYP) th5 (map mapthis tyval_asms)
  in
    LIST_CONJ [models_thm,valth,th6]
  end

val of_sigof_thy =
  LIST_CONJ
  [``tysof (sigof (thy:thy)) = tysof thy`` |> EVAL |> EQT_ELIM,
   ``tmsof (sigof (thy:thy)) = tmsof thy`` |> EVAL |> EQT_ELIM]

val of_thyof =
  LIST_CONJ
  [``tysof (thyof ctxt) = tysof ctxt`` |> EVAL |> EQT_ELIM,
   ``tmsof (thyof ctxt) = tmsof ctxt`` |> EVAL |> EQT_ELIM]

fun prop_to_loeb_hyp0 res =
  let
    val [models_thm,v1,v2,sem_thm] = CONJUNCTS res
    val inner_tm = sem_thm |> concl |> lhs |> rand
  in
     provable_imp_eq_true |> SPEC_ALL |> UNDISCH
     |> PURE_REWRITE_RULE[of_sigof_thy]
     |> C MATCH_MP models_thm
     |> PURE_REWRITE_RULE[of_thyof]
     |> C MATCH_MP (PURE_REWRITE_RULE[of_sigof_rwt]v1)
     |> SPEC inner_tm
     |> PURE_REWRITE_RULE[PURE_REWRITE_RULE[of_sigof_rwt,pairTheory.PAIR]sem_thm]
     |> PURE_REWRITE_RULE[bool_to_inner_def,UNDISCH setSpecTheory.boolean_eq_true]
  end

fun prop_to_loeb_hyp ctxt tm = prop_to_loeb_hyp0 (termsem_cert ctxt tm)

val wf_to_inners = ref (Redblackmap.mkDict Type.compare : (hol_type, thm) Redblackmap.dict)

val TD_tm = prim_mk_const{Thy="bool",Name="TYPE_DEFINITION"}
val TD1_tm = TD_tm |> type_of |> dom_rng |> #1 |> genvar |> (fn v => mk_comb(TD_tm,v))

fun get_TYPE_DEFINITION {Thy,Tyop,Args} =
  let
    val n = List.length Args
    val args = List.tabulate(n,(fn _ => gen_tyvar()))
    val ty0 = mk_thy_type{Thy=Thy,Tyop=Tyop,Args=args}
    val abs = genvar(ty0 --> (gen_tyvar()))
    val (_,(th0,_))::_ = DB.match [] (mk_icomb(TD1_tm,abs))
    val args_from_thm =
      th0 |> concl |> boolSyntax.dest_exists |> #1
      |> type_of |> dom_rng |> #1 |> dest_type |> #2
  in
    INST_TYPE (map2 (curry (op |->)) args_from_thm Args) th0
  end

local
  val fun_th = wf_to_inner_fun_to_inner |> UNDISCH
in
fun prove_wf_to_inner ty =
  Redblackmap.find (!wf_to_inners, ty)
  handle Redblackmap.NotFound =>
  let val th =
    case any_type_view ty of
      BoolType => UNDISCH_ALL wf_to_inner_bool_to_inner
    | FunType(x,y) =>
      let
        val th1 = prove_wf_to_inner x
        val th2 = prove_wf_to_inner y
      in
        MATCH_MP fun_th (CONJ th1 th2)
      end
    | BaseType (Tyapp("min","ind",[])) => ASSUME (to_inner_prop [] ``:ind``)
    | BaseType (Tyvar _) => ASSUME (to_inner_prop [] ty)
    | BaseType (Tyapp(thy,tyop,args)) =>
      let
        val _ = (print tyop; print " ")
        val TD = get_TYPE_DEFINITION{Thy=thy,Tyop=tyop,Args=args}
        val th = MATCH_MP wf_to_inner_TYPE_DEFINITION TD
        val repth =
          TD |> concl |> boolSyntax.dest_exists |> #1
          |> type_of |> dom_rng |> #2
          |> prove_wf_to_inner
      in
        MATCH_MP th repth
        |> SPEC(type_to_deep ty)
      end
  in th before wf_to_inners := Redblackmap.insert (!wf_to_inners,ty,th) end
end

val ranges_distincts = ref (Redblackmap.mkDict (Lib.pair_compare(Type.compare,Type.compare))
                                : (hol_type * hol_type, thm) Redblackmap.dict)

fun prove_ranges_distinct ty1 ty2 =
  Redblackmap.find (!ranges_distincts, (ty1,ty2))
  handle Redblackmap.NotFound =>
  let val th = ranges_distinct [] ty1 ty2
             |> PROVE_HYP (prove_wf_to_inner ty1)
             |> PROVE_HYP (prove_wf_to_inner ty2)
  in th before ranges_distincts := Redblackmap.insert (!ranges_distincts,(ty1,ty2),th) end

fun prove_distinct_tys ctxt tys =
  EVAL``ALL_DISTINCT (MAP FST (type_list (NewTypes_ctxt ^tys ++ ^ctxt)))``
  |> EQT_ELIM

fun prove_distinct_tms ctxt tms =
  EVAL``ALL_DISTINCT (MAP FST (const_list (NewConsts_ctxt ^tms ++ ^ctxt)))``
  |> EQT_ELIM

local
  val P1 = ``(EVERY (inhabited o SND) o SND o SND) : mlstring # num # ('U list # 'U) list -> bool``
  val P2 = P1 |> rator |> rand |> rand
in
  fun prove_inhabited_tys tys =
    let
      val (tysl,_) = listSyntax.dest_list tys
      (*
      val tyel = tysl |> el 1
      val (cs,_) = tyel |> pairSyntax.strip_pair |> last |> listSyntax.dest_list
      val csel = cs |> el 1
      *)
      fun prove_P2 csel =
        let
          val wf_to_inner_thm =
            prove_wf_to_inner(csel |> rand |> rand |> type_of |> dom_rng |> #1)
          val inhab = MATCH_MP inhabited_range wf_to_inner_thm
        in
          mk_comb(P2,csel)
          |> (REWR_CONV o_THM THENC BETA_CONV
              THENC QUANT_CONV (RAND_CONV (REWR_CONV SND)))
          |> SYM |> C EQ_MP inhab
        end
      fun prove_P1 tyel =
        let
          val (cs,_) = tyel |> pairSyntax.strip_pair |> last |> listSyntax.dest_list
          val csths = map prove_P2 cs
          val EVERY_cs = join_EVERY P2 csths
        in
          mk_comb(P1,tyel)
          |> (REWR_CONV o_THM THENC
              RAND_CONV (REWR_CONV o_THM) THENC
              RAND_CONV (RAND_CONV (REWR_CONV SND)) THENC
              RAND_CONV (REWR_CONV SND))
          |> SYM |> C EQ_MP EVERY_cs
        end
    in
      join_EVERY P1 (map prove_P1 tysl)
    end
end

fun prove_types_ok base_is_std_sig distinct_tys tys tms =
  let
    val is_std_sig = MATCH_MP NewTypes_ctxt_extends distinct_tys
                     |> MATCH_MP is_std_sig_extends
                     |> C MATCH_MP base_is_std_sig
    val (EVAL_type_ok,_) = EVAL_type_ok_term_ok EVAL is_std_sig
    val (tmsl,tmsy) = listSyntax.dest_list tms
    val ax_ctxt = is_std_sig |> concl |> funpow 5 rand
    val P = typedTerm`(type_ok (tysof ^ax_ctxt) o FST o SND)`(tmsy-->bool)
    (* val tmel = el 1 tmsl *)
    fun prove_P tmel =
      mk_comb(P,tmel)
      |> (REWR_CONV o_THM THENC
          RAND_CONV (REWR_CONV o_THM) THENC
          RAND_CONV (RAND_CONV (REWR_CONV SND)) THENC
          RAND_CONV (REWR_CONV FST) THENC
          RATOR_CONV (RAND_CONV (REWR_CONV (SYM (CONJUNCT1 of_sigof_rwt))))
          THENC EVAL_type_ok)
      |> EQT_ELIM
  in
    join_EVERY P (map prove_P tmsl)
  end

(* TODO:
  if this can be made more general (so that it can return F as well as T) then
  it should move to listLib
*)
local
  val (ALL_DISTINCT_NIL,ALL_DISTINCT_CONS) = CONJ_PAIR ALL_DISTINCT
  val AND_CLAUSES_TX = AND_CLAUSES |> SPEC_ALL |> CONJUNCT1
  val NOT_CLAUSES_F = NOT_CLAUSES |> CONJUNCTS |> last
in
  fun ALL_DISTINCT_CONV distinct_conv =
    let
      fun conv tm = tm |>
        ((REWR_CONV ALL_DISTINCT_NIL) ORELSEC
         (REWR_CONV ALL_DISTINCT_CONS
          THENC (FORK_CONV
                  (RAND_CONV (IS_EL_CONV distinct_conv)
                   THENC (REWR_CONV NOT_CLAUSES_F),
                  conv))
          THENC (REWR_CONV AND_CLAUSES_TX)))
    in conv end
end

fun ranges_distinct_conv equ =
  let
    val (l,r) = dest_eq equ
    val th = prove_ranges_distinct
              (l |> rand |> type_of |> dom_rng |> #1)
              (r |> rand |> type_of |> dom_rng |> #1)
  in
    EQF_INTRO th
  end

fun prove_disjoint tys =
  let
    val (tysl,tysy) = listSyntax.dest_list tys
    val P = typedTerm`((ALL_DISTINCT o MAP FST) o SND o SND)`(tysy --> bool)
    (* val tyel = el 2 tysl *)
    fun prove_P tyel =
      mk_comb(P,tyel)
      |> (REWR_CONV o_THM
          THENC (RAND_CONV (REWR_CONV o_THM)
                 THENC (RAND_CONV (RAND_CONV (REWR_CONV SND)))
                 THENC (RAND_CONV (REWR_CONV SND))
                 THENC (REWR_CONV o_THM)
                 THENC (RAND_CONV (MAP_CONV (REWR_CONV FST))))
          THENC (ALL_DISTINCT_CONV (list_EQ_CONV ranges_distinct_conv)))
      |> ADD_ASSUM is_set_theory_mem (* in case it's not there already, don't want join_EVERY to rename mem *)
      |> EQT_ELIM
  in
    join_EVERY P (map prove_P tysl)
  end

local
  val IMP_CLAUSES_TX = IMP_CLAUSES |> SPEC_ALL |> CONJUNCTS |> el 1 |> GEN_ALL
in
  fun prove_intypes ax_tyass tyass_asms tmtys tys tms =
    let
      val (tmsl,tmsy) = listSyntax.dest_list tms
      val P1 = typedTerm`λ(name,ty,cs). EVERY (intype ^ax_tyass ty) cs`(tmsy --> bool)
      (* val tmel = el 3 tmsl *)
      (* val tmty = el 3 tmtys *)
      (* val csel = el 1 csl *)
      fun prove_P2 P2 tmty csel =
        let
          val th2 = mk_comb(P2,csel) |> PAIRED_BETA_CONV
          val ty = th2 |> concl |> rhs |> rator |> rand |> rator |> type_of |> dom_rng |> #1
          val th3 =
            prim_typesem_cert (complete_match_type tmty ty) tmty
            |> Q.INST[`tyass`|->`^ax_tyass`]
            |> itlist PROVE_HYP tyass_asms
          val tyval = th2 |> concl |> rhs |> rand |> rator |> rand
          (* maybe want to use this plus other stuff instead of the EVAL below
          val tyval_rwt =
            (RAND_CONV (RAND_CONV (LAND_CONV EVAL) THENC computeLib.CBV_CONV lc)
             THENC computeLib.CBV_CONV lcupd) tyval
          *)
          val th4 =
            th3
            |> itlist DISCH (filter (fn tm => is_eq tm andalso is_var(#1(strip_comb(lhs tm)))) (hyp th3))
            |> Q.INST[`tyval`|->`^tyval`]
            |> CONV_RULE(REPEATC((fn tm => if is_imp tm then ALL_CONV tm else NO_CONV tm) THENC
                                  LAND_CONV EVAL THENC REWR_CONV IMP_CLAUSES_TX))
          val th5 =
            th2
            |> CONV_RULE(RAND_CONV(RAND_CONV (REWR_CONV th4)))
            |> CONV_RULE(RAND_CONV(PURE_REWRITE_CONV[MATCH_MP wf_to_inner_range_thm (prove_wf_to_inner ty)]))
        in th5 |> EQT_ELIM end
      fun prove_P1 tmel tmty =
        let
          val th1 = mk_comb(P1,tmel) |> PAIRED_BETA_CONV
          val (_,[P2,cs]) = th1 |> concl |> rhs |> strip_comb
          val (csl,_) = listSyntax.dest_list cs
          val EVERY_cs = join_EVERY P2 (map (prove_P2 P2 tmty) csl)
        in
          th1 |> SYM |> C EQ_MP EVERY_cs
        end
    in
      join_EVERY P1 (map2 prove_P1 tmsl tmtys)
    end
end

val conj_elim = PROVE[]``a /\ b /\ a <=> a /\ b``

fun prove_props_ok base_is_std_sig distinct_tys distinct_tms types_ok ths =
  let
    val tys_is_std_sig
      = MATCH_MP NewTypes_ctxt_extends distinct_tys
        |> MATCH_MP is_std_sig_extends
        |> C MATCH_MP base_is_std_sig
    val is_std_sig
      = MATCH_MP NewConsts_ctxt_extends (CONJ distinct_tms types_ok)
        |> MATCH_MP is_std_sig_extends
        |> C MATCH_MP tys_is_std_sig
    val (EVAL_type_ok,EVAL_term_ok) = holSyntaxLib.EVAL_type_ok_term_ok EVAL is_std_sig
    val P = Term`λp. term_ok ^(rand (concl is_std_sig)) p ∧ (typeof p = Bool)`
    (* val p = el 1 ths *)
    fun prove_P p =
      let
        val target = mk_comb(P,p)
        val th0 = target |> BETA_CONV
        val (t1,t2) = th0 |> concl |> rand |> dest_conj
        val th1 =
          EVAL_term_ok t1
          |> CONV_RULE(RAND_CONV(
               SIMP_CONV(srw_ss())
                 [holSyntaxLibTheory.tyvar_inst_exists,
                  tyvar_inst_exists2,
                  tyvar_inst_exists2_diff,
                  conj_elim]))
          |> EQT_ELIM
        val th2 = CONJ th1 (EVAL_typeof t2 |> EQT_ELIM)
      in
        EQ_MP (SYM th0) th2
      end
  in
    join_EVERY P (map prove_P ths)
  end

val tysof_tm = ``tysof:sig->tysig``
val tmsof_tm = ``tmsof:sig->tmsig``
val tyaof_tm = ``tyaof``
val tmaof_tm = ``tmaof``
fun mk_tysof_sig tm = mk_icomb(tysof_tm,tm)
fun mk_tmsof_sig tm = mk_icomb(tmsof_tm,tm)
fun mk_tyaof tm = mk_icomb(tyaof_tm,tm)
fun mk_tmaof tm = mk_icomb(tmaof_tm,tm)
(*
val tysof_tm = ``tysof:update list->tysig``
val tmsof_tm = ``tmsof:update list->tmsig``
fun mk_tysof tm = mk_icomb(tysof_tm,tm) |> beta_conv
fun mk_tmsof tm = mk_icomb(tmsof_tm,tm) |> beta_conv
*)

fun prove_props_true gcth sig_assums int_assums wf_to_inners outer_ths =
  let
    val args = snd(strip_comb(concl gcth))
    val ax_sig = el 2 args
    val ax_int = el 3 args
    val ax_tysig = mk_tysof_sig ax_sig
    val ax_tmsig = mk_tmsof_sig ax_sig

    val gcth1 = gcth
                |> CONV_RULE (RAND_CONV(REWR_CONV(GSYM PAIR)))
                |> CONV_RULE (RATOR_CONV(RAND_CONV(REWR_CONV(GSYM PAIR))))

    val P = Term`λp. ∀v. is_valuation ^ax_tysig ^(mk_tyaof ax_int) v ⇒
                         (termsem ^ax_tmsig ^ax_int v p = True)`
    (* val th = el 1 outer_ths *)
    fun prove_P th =
      let
        val outer_p = th |> concl
        val p = outer_p |> term_to_deep
        val th1 = mk_comb(P,p) |> BETA_CONV
        val (v,t) = th1 |> concl |> rand |> dest_forall
        val cert = termsem_cert_unint outer_p |> DISCH_ALL
                   |> PURE_REWRITE_RULE[AND_IMP_INTRO]
                   |> CONV_RULE(LAND_CONV(move_conj_left(can(match_term good_context))))
                   |> PURE_REWRITE_RULE[GSYM AND_IMP_INTRO]
        val th2 = MATCH_MP cert gcth1
                  |> INST[tyval |-> ``tyvof ^v``,
                          tmval |-> ``tmvof ^v``]
                  |> CONV_RULE(DEPTH_CONV(REWR_CONV PAIR))
                  |> UNDISCH_ALL
                  |> C (foldl (uncurry PROVE_HYP)) (wf_to_inners@sig_assums@int_assums)
                  |> CONV_RULE(RAND_CONV(RAND_CONV(REWR_CONV(EQT_INTRO th))))
                  |> CONV_RULE(RAND_CONV(REWR_CONV bool_to_inner_true))
                  |> DISCH (#1(dest_imp t))
                  |> GEN v
      in
        EQ_MP (SYM th1) th2
      end
  in
    join_EVERY P (map prove_P outer_ths)
  end

(*
example:

val inner_num = mk_range [] ``:num``
val inner_bool = mk_range [] ``:bool``
val inner_alpha = mk_range [] ``:'a``

val tys = ``[(strlit"num",0n,[([],^inner_num)]);
             (strlit"list",1,
                [([^inner_num],^(mk_range[]``:num list``));
                 ([^inner_bool],^(mk_range[]``:bool list``));
                 ([^inner_alpha],^(mk_range[]``:'a list``))
                 ])]``;

val [name0,ty0] = strip_comb(term_to_deep``0n``) |> #2
val [namenil,tynil] = strip_comb(term_to_deep``[]``) |> #2
val tms = ``[(^name0,^ty0,[([],^(mk_comb(mk_to_inner[]``:num``,``0n``)))]);
             (^namenil,^tynil,[([^inner_bool],^(mk_comb(mk_to_inner[]``:bool list``,``[]:bool list``)));
                               ([^inner_num],^(mk_comb(mk_to_inner[]``:num list``,``[]:num list``)));
                               ([^inner_alpha],^(mk_comb(mk_to_inner[]``:'a list``,``[]:'a list``)))
                               ])]``
val tmtys = map type_of [``0n``,``[]``]

val distinct_tys = prove_distinct_tys tys
val distinct_tms = prove_distinct_tms tms
val inhabited_tys = prove_inhabited_tys tys
val types_ok = prove_types_ok distinct_tys tys tms
val disjoint_tys = prove_disjoint tys
val disjoint_tms = prove_disjoint tms
val tyass = ``ax_tyass select ^tys``
val tyass_asms_values =
  ax_tyass_values
  |> ADD_ASSUM is_set_theory_mem
  |> C MATCH_MP (CONJ distinct_tys disjoint_tys)
  |> SIMP_RULE (bool_ss++pairSimps.PAIR_ss) [EVERY_DEF]
  |> CONJUNCTS
val ax_int_std =
  is_std_interpretation_ax_int
  |> REWRITE_RULE[GSYM AND_IMP_INTRO]
  |> funpow 3 UNDISCH
  |> C MATCH_MP distinct_tys
  |> C MATCH_MP distinct_tms
val ax_tyass_std =
  ax_int_std
  |> PURE_REWRITE_RULE[is_std_interpretation_def]
  |> CONJUNCT1
  |> PURE_REWRITE_RULE[ax_int_def,FST]
val tyass_asms = ax_tyass_std::tyass_asms_values
(* tyass_asms |> el 2 |> concl |> lhs |> rator |> rator |> equal tyass *)
val intypes = prove_intypes tyass tyass_asms tmtys tys tms

val ax_int_intro =
  ax_int_def
  |> CONV_RULE(STRIP_QUANT_CONV(LAND_CONV(REWR_CONV(GSYM PAIR)) THENC REWR_CONV PAIR_EQ))

val tmass_values =
  ax_tmass_values
  |> ADD_ASSUM is_set_theory_mem
  |> C MATCH_MP (CONJ distinct_tms disjoint_tms)
  |> Q.GEN`δ` |> SPEC tyass
  |> PURE_REWRITE_RULE[ax_int_intro |> SPEC_ALL |> CONJUNCT2 |> SYM]
  |> SIMP_RULE (bool_ss++pairSimps.PAIR_ss) [EVERY_DEF]
  |> CONJUNCTS

val tyass_values =
  tyass_asms_values
  |> map(PURE_REWRITE_RULE[
    ax_int_intro
    |> Q.SPECL[`mem`,`select`]
    |> ISPECL [tys,tms]
    |> CONJUNCT1
    |> SYM])

val gc_thm =
  good_context_ax
  |> PURE_REWRITE_RULE[GSYM AND_IMP_INTRO]
  |> funpow 3 UNDISCH
  |> C MATCH_MP distinct_tys
  |> C MATCH_MP distinct_tms
  |> C MATCH_MP inhabited_tys
  |> C MATCH_MP types_ok
  |> C MATCH_MP intypes

*)

(*

val outer_tys = [``:bool``,``:num list``]
val outer_tms = [``0n``,``[]:bool list``]
val outer_ths = [EVAL``LENGTH ([]:num list)``]

fun base_from_good_select good_select =
  let
    val base_ok_thm = theory_ok_hol_ctxt
    val select = rand (concl good_select)
    val base_models_thm =
      (CONJUNCT1 hol_model_models
       |> DISCH_ALL
       |> C MATCH_MP(prove_wf_to_inner``:ind``)
       |> C MATCH_MP good_select
       |> UNDISCH)
  in
    (base_ok_thm,base_models_thm)
  end

val ty = el 1 all_outer_tys
val tm = el 1 all_outer_tms

*)

val ax_tyass_tm = mk_comb(prim_mk_const{Name="ax_tyass0",Thy="reflection"},mem);

val sigof_thyof = ``sigof (thyof x) = sigof x`` |> EVAL |> EQT_ELIM

val wf_to_inner_tm = ``wf_to_inner``
fun is_wf_to_inner tm = is_comb tm andalso can (match_term wf_to_inner_tm) (rator tm)

val init_ctxt_consts = [``$=``]
val init_ctxt_tys = [bool,alpha-->beta]
val bool_ctxt_consts = [``$~``,``F``,``$\/``,``$?``,``$!``,``$==>``,``$/\``,``T``]
val select_ctxt_consts = [``$@``]
val infinity_ctxt_consts = [``ONE_ONE``,``ONTO``]
val hol_ctxt_consts = infinity_ctxt_consts @ select_ctxt_consts @ bool_ctxt_consts @ init_ctxt_consts
val hol_ctxt_tys = ind::init_ctxt_tys

val init_update:update = {
  sound_update_thm = TRUTH,
  constrainable_thm = TRUTH,
  updates_thm = TRUTH,
  extends_init_thm = TRUTH,
  tys = hol_ctxt_tys,
  consts = hol_ctxt_consts,
  axs = [] }

fun term_in_update tm (upd:update) = List.exists (same_const tm) (#consts upd)
local
  fun type_name ty = let val {Thy,Tyop,...} = dest_thy_type ty in (Thy,Tyop) end
in
  fun type_in_update ty (upd:update) = List.exists (fn ty' => type_name ty = type_name ty') (#tys upd)
end
fun term_in_ctxt upds tm = List.exists (term_in_update tm) (init_update::upds)
fun type_in_ctxt upds ty = List.exists (type_in_update ty) (init_update::upds)


(*

val base_ok_thm = theory_ok_hol_ctxt
val outer_ctxt:update list = []
val outer_tys = [``:bool list``,``:ind``]
val outer_tms = [``MAP:(bool -> ind) -> bool list -> ind list``,``T``]
val outer_ths = [EVAL``MAP (K (ARB:ind)) [F;F]``,SELECT_AX |> INST_TYPE[alpha|->ind]]

*)

local
  (* ``:num list`` |-> (("list",1),``([^(mk_range [] ``:num``)],^(mk_range[]``:num list``))`` *)
  fun mk_tyel ty =
    let
      val (name,args) = dest_type ty
    in
      ((name, length args),
       (map (mk_range []) args, mk_range[] ty))
    end

  fun insert_el (k,v) =
    let fun f acc [] = (k,[v])::acc
          | f acc ((k',vs)::t) =
            if k = k' then
              (k,v::vs)::acc@t
            else
              f ((k',vs)::acc) t
    in f [] end

  fun mk_tmel tm =
    let
      val {Name=name,Thy=Thy,Ty=ity} = dest_thy_const tm
      val ty = generic_type {Name=name,Thy=Thy}
      val args = const_tyargs tm
    in
      ((name,ty),
       (map (mk_range[]) args,
        mk_comb(mk_to_inner[] ity,tm)))
    end

  val constraint_ty = mk_prod(mk_list_type universe_ty,universe_ty)

  fun fix_constraint (x,y) = mk_pair(mk_list(x,universe_ty),y)

  fun fix_ty ((name,arity),vs) =
    mk_pair(string_to_inner name,
            mk_pair(numSyntax.term_of_int arity,
                    listSyntax.mk_list(map fix_constraint vs, constraint_ty)))

  fun fix_tm ((name,ty),vs) =
    mk_pair(string_to_inner name,
            mk_pair(type_to_deep ty,
                    listSyntax.mk_list(map fix_constraint vs, constraint_ty)))

  val ax_int_intro =
    ax_int_def
    |> CONV_RULE(STRIP_QUANT_CONV(LAND_CONV(REWR_CONV(GSYM PAIR)) THENC REWR_CONV PAIR_EQ))

in
  fun build_axiomatic_interpretation base_ok_thm outer_ctxt outer_tys outer_tms outer_ths =
    let

      val all_outer_tms =
        union (Lib.U (map base_terms_of_term outer_tms))
        (Lib.U (map (base_terms_of_term o concl) outer_ths))
      val all_outer_tys =
        union (Lib.U (map base_types_of_type outer_tys))
              (Lib.U (map base_types_of_term all_outer_tms))

      val wf_to_inners = map prove_wf_to_inner all_outer_tys

      val (base_outer_tms,ax_outer_tms) =
        partition (term_in_ctxt outer_ctxt) all_outer_tms
      val (base_outer_tys,ax_outer_tys) =
        partition (type_in_ctxt outer_ctxt) all_outer_tys

      val { good_context_thm = base_good_context_thm,
            models_thm = base_models_thm0,
            wf_to_inners = base_wf_to_inners,
            sig_assums = base_sig_assums,
            int_assums = base_int_assums } =
          build_interpretation (map concl wf_to_inners) outer_ctxt base_outer_tys base_outer_tms
      val base_models_thm = base_models_thm0 |> itlist PROVE_HYP wf_to_inners

      val tys0 = foldl (uncurry insert_el) [] (map mk_tyel ax_outer_tys)
      val tys = mk_list(map fix_ty tys0,
                  mk_prod(mlstringSyntax.mlstring_ty,
                          mk_prod(numSyntax.num,mk_list_type(constraint_ty))))
      val tms0 = foldl (uncurry insert_el) [] (map mk_tmel ax_outer_tms)
      val tms = mk_list(map fix_tm tms0,
                  mk_prod(mlstringSyntax.mlstring_ty,
                          mk_prod(type_ty,mk_list_type(constraint_ty))))
      val ths = map (term_to_deep o concl) outer_ths

      val base_is_std_sig =
        MATCH_MP theory_ok_sig base_ok_thm
        |> CONV_RULE(RAND_CONV(REWR_CONV sigof_thyof))
      val ctxt = base_ok_thm |> concl |> funpow 5 rand
      val base_int = base_models_thm |> concl |> rator |> rand
      val base_tyass = mk_tyaof base_int
      val base_tmass = mk_tmaof base_int
      val [base_is_int, base_is_std_int, base_satisfies] =
        base_models_thm
        |> PURE_REWRITE_RULE[models_def,sigof_thyof]
        |> CONJUNCTS
      val distinct_tys = prove_distinct_tys ctxt tys
      val distinct_tms = prove_distinct_tms ctxt tms
      val inhabited_tys = prove_inhabited_tys tys
      val types_ok = prove_types_ok base_is_std_sig distinct_tys tys tms
      val disjoint_tys = prove_disjoint tys
      val disjoint_tms = prove_disjoint tms

      val ax_tyass = mk_icomb(mk_icomb(ax_tyass_tm,base_tyass),tys)
      val tyass_asms_values =
        if null ax_outer_tys then [] else
        ax_tyass_values
        |> ADD_ASSUM is_set_theory_mem
        |> C MATCH_MP (CONJ distinct_tys disjoint_tys)
        |> SIMP_RULE (bool_ss++pairSimps.PAIR_ss) [EVERY_DEF]
        |> Q.GEN`δ` |> SPEC base_tyass
        |> CONJUNCTS
      val ax_int_std =
        is_std_interpretation_ax_int
        |> REWRITE_RULE[GSYM AND_IMP_INTRO]
        |> UNDISCH
        |> C MATCH_MP base_is_std_sig
        |> C MATCH_MP base_is_std_int
        |> C MATCH_MP distinct_tys
        |> C MATCH_MP distinct_tms
      val ax_tyass_std =
        ax_int_std
        |> PURE_REWRITE_RULE[is_std_interpretation_def]
        |> CONJUNCT1
        |> PURE_REWRITE_RULE[ax_int_def,FST]
      val tyass_asms = ax_tyass_std::(tyass_asms_values@wf_to_inners)
      val tmtys = map (#2 o #1) tms0
      val intypes = prove_intypes ax_tyass tyass_asms tmtys tys tms
                    |> PROVE_HYP (prove_wf_to_inner bool) (* TODO: investigate why... *)

      val props_ok = prove_props_ok base_is_std_sig distinct_tys distinct_tms types_ok ths

      val gcth =
        good_context_ax
        |> PURE_REWRITE_RULE[GSYM AND_IMP_INTRO]
        |> UNDISCH
        |> C MATCH_MP base_ok_thm
        |> C MATCH_MP base_is_int
        |> C MATCH_MP base_is_std_int
        |> C MATCH_MP distinct_tys
        |> C MATCH_MP distinct_tms
        |> C MATCH_MP inhabited_tys
        |> C MATCH_MP types_ok
        |> C MATCH_MP intypes
        |> C MATCH_MP props_ok

      val tyass_values =
        tyass_asms_values
        |> map(PURE_REWRITE_RULE[
          ax_int_intro
          |> SPECL[mem,base_int]
          |> ISPECL [tys,tms]
          |> CONJUNCT1
          |> SYM])
      val tmass_values =
        if null ax_outer_tms then [] else
        ax_tmass_values
        |> ADD_ASSUM is_set_theory_mem
        |> C MATCH_MP (CONJ distinct_tms disjoint_tms)
        |> Q.GEN`i` |> SPEC (mk_pair(ax_tyass,base_tmass))
        |> PURE_REWRITE_RULE[ax_int_intro |> SPEC_ALL |> CONJUNCT2 |> SYM]
        |> SIMP_RULE (bool_ss++pairSimps.PAIR_ss) [EVERY_DEF]
        |> CONJUNCTS

      val vti = []
      val tyassums = flatten (map (base_type_assums vti) all_outer_tys)
           |> filter (not o can (assert (equal tyval) o fst o strip_comb o lhs))
      val tmassums = flatten (map (base_term_assums vti) all_outer_tms)
      val assums0 = tyassums @ tmassums
      val args = snd(strip_comb(concl gcth))
      val ax_sig = el 2 args
      val ax_int = el 3 args
      val s = [tysig |-> mk_tysof_sig ax_sig,
               tmsig |-> mk_tmsof_sig ax_sig,
               tyass |-> mk_tyaof ax_int,
               tmass |-> mk_tmaof ax_int]
      val assums = map (subst s) assums0

      val (wf_to_inner_tms,assums1) = partition is_wf_to_inner assums
      val _ = assert (set_eq wf_to_inner_tms) (map concl wf_to_inners)

      val (sig_tms,int_tms) =
        partition (fn tm =>
          is_eq tm andalso
          finite_mapSyntax.is_flookup (lhs tm))
        assums1

      val ax_extends_thm =
        ax_ctxt_extends_ctxt
        |> C MATCH_MP (LIST_CONJ [distinct_tys,distinct_tms,types_ok,props_ok])

      val tysof_extends = MATCH_MP FLOOKUP_tysof_extends ax_extends_thm
      val tmsof_extends = MATCH_MP FLOOKUP_tmsof_extends ax_extends_thm
      val extended_base_sig_assums =
        List.map (fn th => MATCH_MP tysof_extends th handle HOL_ERR _ => MATCH_MP tmsof_extends th)
        base_sig_assums

      val (tyaof_extends_thm,tmaof_extends_thm) =
        ax_int_equal_on
        |> ADD_ASSUM is_set_theory_mem
        |> C MATCH_MP distinct_tys
        |> C MATCH_MP distinct_tms
        |> CONV_RULE(REWR_CONV(equal_on_def |> SIMP_RULE std_ss [FDOM_FLOOKUP,PULL_EXISTS]))
        |> CONJ_PAIR

      val int_extends_thms =
        List.map (fn th =>
                    SYM(MATCH_MP tyaof_extends_thm th handle HOL_ERR _ =>
                        MATCH_MP tmaof_extends_thm th))
                 base_sig_assums

      val extended_base_int_assums =
        List.map (fn th =>
           Lib.tryfind (fn rth =>
             CONV_RULE(LAND_CONV(RATOR_CONV(REWR_CONV rth)))th)
           int_extends_thms)
        (List.map (itlist PROVE_HYP wf_to_inners) base_int_assums)

      val sig_assums = map
        (fn tm => VALID_TAC_PROOF(([],tm),FIRST (map ACCEPT_TAC extended_base_sig_assums) ORELSE EVAL_TAC))
        sig_tms

      val int_assums = map
        (fn tm => VALID_TAC_PROOF((base_hyps,tm),
          FIRST (map ACCEPT_TAC (extended_base_int_assums@tmass_values@tyass_values))))
        int_tms

      val gcth1 =
        gcth |>
        itlist PROVE_HYP
          (mapfilter
            (CONV_RULE(LAND_CONV(RATOR_CONV(RATOR_CONV(REWR_CONV(CONJUNCT1(SPEC_ALL ax_int_intro)))))))
            extended_base_int_assums)

      val props_true = prove_props_true gcth1 sig_assums int_assums wf_to_inners outer_ths

      val models_thm =
        ax_int_models
        |> ADD_ASSUM is_set_theory_mem
        |> C MATCH_MP base_ok_thm
        |> C MATCH_MP distinct_tys
        |> C MATCH_MP distinct_tms
        |> C MATCH_MP gcth1
        |> C MATCH_MP base_models_thm
        |> C MATCH_MP props_true

    in
      {
        good_context_thm = CONJ ax_extends_thm gcth1,
        models_thm = models_thm,
        int_assums = int_assums,
        sig_assums = sig_assums,
        wf_to_inners = wf_to_inners
      }
    end
  end

  val base_term_assums = base_term_assums []
  val base_type_assums = base_type_assums []
end
