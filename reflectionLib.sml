structure reflectionLib = struct
local
  open HolKernel boolLib bossLib lcsymtacs listSimps stringSimps listLib optionLib pairLib
  open miscLib miscTheory combinTheory pred_setTheory numSyntax pairSyntax stringSyntax listSyntax holSyntaxSyntax
  open setSpecTheory holSyntaxTheory holSyntaxExtraTheory holSemanticsTheory holSemanticsExtraTheory
  open holBoolTheory holConstrainedExtensionTheory
  open reflectionTheory basicReflectionLib

  val ERR = mk_HOL_ERR"reflectionLib"

  fun VALID_TAC_PROOF (goal,tac) = TAC_PROOF(goal, VALID tac)

  val bool_to_inner_tm = ``bool_to_inner``
  val fun_to_inner_tm = ``fun_to_inner``

  val universe_ty = ``:'U``
  val type_ty = ``:type``
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
    flatten o (map base_types_of_type) o types_of_term

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

  fun base_terms_of_term (tm : term) : term list = case dest_term tm of
      VAR (name,ty)       => [tm]
    | CONST {Name,Thy,Ty} => [tm]
    | LAMB (var,body)     => filter (not o equal var) (base_terms_of_term body)
    | COMB (tm1,tm2)      => base_terms_of_term tm1 @ base_terms_of_term tm2

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

  fun term_assums vti (tm : term) : term list =
    HOLset.listItems(
      HOLset.addList(
        HOLset.addList(
          Term.empty_tmset,
          flatten (map (base_type_assums vti) (base_types_of_term tm))),
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
      holBoolSyntaxTheory.term_ok_clauses
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

  fun termsem_cert vti =
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
                  (fn (g as (asl,w)) =>
                    ACCEPT_TAC(wf_to_inner_mk_to_inner []
                      (fst(dom_rng(type_of(rand w))))) g)) >>
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
    termsem_cert tyin tm
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
      rpt(qpat_assum`wf_to_inner X`kall_tac) >>
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
      |  (FunType (x,y), BoolType) =>
           distinct_bool_fun
           |> ISPECL [mk_to_inner vti x, mk_to_inner vti y]
           |> C MP (wf_to_inner_mk_to_inner vti x)
           |> C MP (wf_to_inner_mk_to_inner vti y)
           |> GSYM
      |  (BaseType _, FunType(x,y)) =>
           distinct_tag_fun_range
           |> ISPECL [type_to_deep ty1, mk_to_inner vti x, mk_to_inner vti y]
           |> INST_TYPE[alpha|->ty1]
           |> UNDISCH
           |> C MP (wf_to_inner_mk_to_inner vti x)
           |> C MP (wf_to_inner_mk_to_inner vti y)
      |  (FunType (x,y), BaseType _) =>
           distinct_tag_fun_range
           |> ISPECL [type_to_deep ty2, mk_to_inner vti x, mk_to_inner vti y]
           |> INST_TYPE[alpha|->ty2]
           |> UNDISCH
           |> C MP (wf_to_inner_mk_to_inner vti x)
           |> C MP (wf_to_inner_mk_to_inner vti y)
           |> GSYM
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
      |  (BoolType, BaseType _) =>
           distinct_tag_bool_range
           |> ISPEC (type_to_deep ty2)
           |> INST_TYPE[alpha|->ty2]
           |> UNDISCH
           |> GSYM
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
            (* val (tys0,th0)::_ = ths *)
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

    val ctxt = ``hol_ctxt``
    val tm = term_to_deep(rhs(concl K_DEF))
    val inner_upd = ``ConstDef (strlit"K") ^tm``
    val sound_update_thm = prove(
      ``is_set_theory ^mem ⇒
        sound_update ^ctxt ^inner_upd``,
      strip_tac >>
      ho_match_mp_tac (UNDISCH holExtensionTheory.new_specification_correct) >>
      conj_asm1_tac >- rw[hol_theory_ok,holConsistencyTheory.hol_ctxt_def,
                     holConsistencyTheory.fhol_ctxt_def] >>
      conj_tac >- (
        simp[] >>
        match_mp_tac (el 2 (CONJUNCTS proves_rules)) >>
        conj_tac >- rw[] >>
        conj_tac >- cheat >>
        cheat ) >>
      cheat) |> UNDISCH
    val constrainable_thm = prove(
      ``constrainable_update ^inner_upd``,
      rw[constrainable_update_def] >> rw[] >>
      rw[conexts_of_upd_def] >>
      rw[listTheory.EVERY_MAP] >>
      cheat )
    val updates_thm = prove(
      ``^inner_upd updates hol_ctxt``,
      ho_match_mp_tac ConstDef_updates >>
      cheat)
    val upd:update = {
        sound_update_thm  = sound_update_thm,
        constrainable_thm = constrainable_thm,
        updates_thm = updates_thm,
        extends_init_thm = hol_extends_init,
        tys = [],
        consts = [``K``],
        axs = [combinTheory.K_DEF] }

    val true =
      rand(rator(rhs(concl(EVAL ``conexts_of_upd ^inner_upd``)))) =
      term_to_deep(concl(combinTheory.K_DEF))

    val substs =
      [[alpha|->bool,beta|->bool],
       [alpha|->``:'x``,beta|->``:'y``]]
    (* for build interpretation: *)
    val ctxt:update list = []
    val tys:hol_type list = []
    val consts = map (C inst combinSyntax.K_tm) substs
    (* -- *)

    val int0 = ``hol_model select ind_to_inner``

    val ctxt = ``^inner_upd::hol_ctxt``
    val pred_tm = ``λp. ∃x y. p = λa b. (a=x) ∧ (b=y)``
    val pred_inner = term_to_deep pred_tm
    val inner_upd = ``TypeDefn (strlit"prod") ^pred_inner (strlit"ABS_prod") (strlit"REP_prod")``
    val sound_update_thm = prove(
      ``is_set_theory ^mem ⇒
        sound_update ^ctxt ^inner_upd``,
      strip_tac >>
      ho_match_mp_tac (UNDISCH holExtensionTheory.new_type_definition_correct) >>
      cheat) |> UNDISCH
    val constrainable_thm = prove(
      ``constrainable_update ^inner_upd``,
      REWRITE_TAC[constrainable_update_def] >>
      cheat )
    val updates_thm2 = prove(
      ``^inner_upd updates ^ctxt``,
      cheat)
    val extends_init_thm2 =
      MATCH_MP updates_extends_trans (CONJ updates_thm hol_extends_init)
    val upd:update = {
        sound_update_thm  = sound_update_thm,
        constrainable_thm = constrainable_thm,
        updates_thm = updates_thm2,
        extends_init_thm = extends_init_thm2,
        tys = [``:('a,'b)prod``],
        consts = [``ABS_prod``,``REP_prod``],
        (* TODO: axs may need tweaking to match the inner *)
        axs = CONJUNCTS pairTheory.ABS_REP_prod }

    val ctxt = ``hol_ctxt``
    val pred_tm = ``λp. ∃x y. p = λa b. (a=x) ∧ (b=y)``
    val pred_inner = term_to_deep pred_tm
    val inner_upd = ``TypeDefn (strlit"prod") ^pred_inner (strlit"ABS_prod") (strlit"REP_prod")``
    val sound_update_thm = prove(
      ``is_set_theory ^mem ⇒
        sound_update ^ctxt ^inner_upd``,
      strip_tac >>
      ho_match_mp_tac (UNDISCH holExtensionTheory.new_type_definition_correct) >>
      cheat) |> UNDISCH
    val constrainable_thm = prove(
      ``constrainable_update ^inner_upd``,
      REWRITE_TAC[constrainable_update_def] >>
      cheat )
    val updates_thm2 = prove(
      ``^inner_upd updates ^ctxt``,
      cheat)
    val extends_init_thm2 = hol_extends_init
    val upd:update = {
        sound_update_thm  = sound_update_thm,
        constrainable_thm = constrainable_thm,
        updates_thm = updates_thm2,
        extends_init_thm = extends_init_thm2,
        tys = [``:('a,'b)prod``],
        consts = [``ABS_prod``,``REP_prod``],
        axs = map SPEC_ALL (CONJUNCTS pairTheory.ABS_REP_prod) }

     val substs = [[alpha|->bool,beta|->alpha],[alpha|->gamma,beta|->(bool-->bool)]]
     val consts =  map (C inst ``ABS_prod``) substs
     val tys = [``:'c#bool``]
     val ctxt:update list = []
     val vti:(hol_type,hol_type)subst = []
     val () = Globals.max_print_depth := 13
  *)

  fun upd_to_inner (upd:update) = #constrainable_thm upd |> concl |> rand

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
    val int0 = jtm
   *)
  fun make_cs_assums vti upd substs theory_ok_thm int0 =
    let
      val tys = #tys upd val consts = #consts upd
      val updates_thm = #updates_thm upd
      val (csi,tysths) = cs_to_inner vti tys consts substs
      val int = ``constrain_interpretation ^(upd_to_inner upd) ^csi ^int0``
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
          val lem5 = lem4 |> Q.GEN`int0` |> SPEC int0
          val tmths = split_LIST_REL lem5
          (* --- *)
          val lemma = MATCH_MP tyaof_constrain_interpretation_lemma th
          val alldistinct = MATCH_MP updates_upd_ALL_DISTINCT updates_thm |> CONJUNCT2
          val lem2 = MATCH_MP lemma alldistinct
          (* TODO: finer conversions than the EVALs below *)
          val lem3 = CONV_RULE(LAND_CONV EVAL) lem2 |> C MP TRUTH
          val lem4 = lem3 |> CONV_RULE(RATOR_CONV(RAND_CONV EVAL))
          val lem5 = lem4 |> Q.GEN`int0` |> SPEC int0
          val tyths = split_LIST_REL lem5
        in
          tyths@tmths
        end
    in
      (int, flatten (map mapthis tysths), map snd tysths)
    end

  fun get_int th = th |> concl |> rator |> rand

  (*
    val tys =
        (set_diff (union tys new_tys) instantiated_tys)
    val consts =
        (set_diff (union consts new_consts) instantiated_consts)
    val mth = hol_model_def |> SPEC mem |> SPEC_ALL |>
              REWRITE_RULE[GSYM AND_IMP_INTRO] |>
              funpow 3 UNDISCH |> CONJUNCT1
    val ith = CONJ mth (prove(assums,cheat))

    in hol_ctxt:
    NewAxiom × 3
    NewConst × 1 (select)
    NewType × 1 (ind)
    ConstDef × 10
      (true, false, implies, and, or, not, forall, exists, one_one, onto)

    val consts = [T,inst[alpha|->numSyntax.num]``$!``]
    val tys:hol_type list = []
  *)

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

  fun join_EVERY P =
    let
      val nilth = listTheory.EVERY_DEF |> CONJUNCT1 |> ISPEC P |> EQT_ELIM
      val consth = listTheory.EVERY_DEF |> CONJUNCT2 |> ISPEC P |> SPEC_ALL |> EQ_IMP_RULE |> snd
                   |> REWRITE_RULE[GSYM AND_IMP_INTRO]
      fun f [] = nilth
        | f (t::ts) = MATCH_MP (MATCH_MP consth t) (f ts)
    in
      f
    end
  val inhabited_tm = ``inhabited``
  val inhabited_eta = prove(``inhabited x ⇔ (λs. inhabited s) x``,rw[])
  fun EVERY_range_inhabited vti tys =
    join_EVERY inhabited_tm (map (
      CONV_RULE(REWR_CONV(inhabited_eta))
        o MATCH_MP inhabited_range o (wf_to_inner_mk_to_inner vti)) tys)

  (* val inner_upd = upd_to_inner upd *)
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
        (discharge_hyps >- (
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

  (*
  val IN_FDOM_implies_type_ok = store_thm("IN_FDOM_implies_type_ok",
    ``name ∈ FDOM tysig ⇒ ∃args. type_ok tysig (Tyapp name args)``,
    rw[type_ok_def,finite_mapTheory.FLOOKUP_DEF] >>
    qexists_tac`GENLIST (K (Tyvar ARB)) (tysig ' name)` >>
    rw[listTheory.EVERY_MEM,listTheory.MEM_GENLIST] >>
    rw[type_ok_def])
  *)

  (* TODO: miscLib.prove_hyps_by is wrong: it needs to call PROVE_HYP multiple times *)

  local
    val tysig_extend_thm = prove(
      ``(FLOOKUP (tysof (sigof ctxt)) name = SOME arity) ⇒ upd updates ctxt ⇒
        (FLOOKUP (tysof (sigof (upd::ctxt))) name = SOME arity)``,
      rw[finite_mapTheory.FLOOKUP_FUNION] >>
      BasicProvers.CASE_TAC >>
      imp_res_tac alistTheory.ALOOKUP_MEM  >>
      imp_res_tac updates_upd_DISJOINT >>
      fs[IN_DISJOINT,listTheory.MEM_MAP,pairTheory.EXISTS_PROD] >>
      metis_tac[])

    val tmsig_extend_thm = prove(
      ``(FLOOKUP (tmsof (sigof ctxt)) name = SOME ty) ⇒ upd updates ctxt ⇒
        (FLOOKUP (tmsof (sigof (upd::ctxt))) name = SOME ty)``,
      rw[finite_mapTheory.FLOOKUP_FUNION] >>
      BasicProvers.CASE_TAC >>
      imp_res_tac alistTheory.ALOOKUP_MEM  >>
      imp_res_tac updates_upd_DISJOINT >>
      fs[IN_DISJOINT,listTheory.MEM_MAP,pairTheory.EXISTS_PROD] >>
      metis_tac[])

    val tyass_extend_thm = prove(
      ``(tyaof i name args = ty) ⇒
         equal_on sig i i' ⇒ name ∈ FDOM (tysof sig) ⇒
        (tyaof i' name args = ty)``,
      rw[equal_on_def] >> metis_tac[])

    val tmass_extend_thm = prove(
      ``(tmaof i name args = m) ⇒
        equal_on sig i i' ⇒ name ∈ FDOM (tmsof sig) ⇒
        (tmaof i' name args = m)``,
      rw[equal_on_def] >> metis_tac[])
  in
    fun make_k_assum uth eqth istyath ia =
      case total (MATCH_MP tysig_extend_thm) ia of
        SOME th => MATCH_MP th uth
      | NONE =>
      case total (MATCH_MP tmsig_extend_thm) ia of
        SOME th => MATCH_MP th uth
      | NONE =>
      case total (MATCH_MP tyass_extend_thm) ia of
        SOME th =>
            MP (CONV_RULE(LAND_CONV EVAL)(MATCH_MP th eqth)) TRUTH
      | NONE =>
      case total (MATCH_MP tmass_extend_thm) ia of
        SOME th =>
            MP (CONV_RULE(LAND_CONV EVAL)(MATCH_MP th eqth)) TRUTH
      | NONE => assert (can (match_term``wf_to_inner X`` o concl)) ia
  end

  val wf_to_inner_can_be_tagged = store_thm("wf_to_inner_can_be_tagged",
    ``is_set_theory ^mem ⇒
      ∀f t. wf_to_inner f ⇒ wf_to_inner (tag t o f)``,
    rw[] >>
    imp_res_tac tag_def >>
    fs[wf_to_inner_def] >>
    ntac 2 (pop_assum kall_tac) >>
    first_x_assum(qspecl_then[`x`,`t`]strip_assume_tac) >>
    qexists_tac`u` >>
    match_mp_tac BIJ_COMPOSE >>
    first_assum(match_exists_tac o concl) >> simp[] >>
    fs[ext_def] >>
    fs[GSYM IMAGE_SURJ] >>
    simp[BIJ_DEF,INJ_DEF] >>
    fs[SURJ_DEF] >>
    metis_tac[])

  val wf_to_inner_defined_type = save_thm("wf_to_inner_defined_type",
    prove(
    ``is_set_theory ^mem ⇒
      ∀abs rep.
      (∀a:α. abs ((rep a):β) = a) ⇒
      ∀tya tyb_to_inner.
      wf_to_inner (tyb_to_inner:β -> 'U) ⇒
      wf_to_inner ((to_inner tya):α -> 'U)``,
    rw[] >>
    pop_assum(fn th =>
      assume_tac th >>
      strip_assume_tac (SIMP_RULE std_ss [wf_to_inner_def] th)) >>
    pop_assum(strip_assume_tac o SIMP_RULE std_ss [BIJ_IFF_INV]) >>
    simp[to_inner_def] >>
    SELECT_ELIM_TAC >>
    conj_tac >- (
      qexists_tac`tyb_to_inner o rep` >>
      simp[wf_to_inner_def] >>
      qexists_tac`x suchthat (λb. g b = rep (abs (g b)))` >>
      simp[BIJ_IFF_INV] >> fs[] >>
      simp[mem_sub] >>
      qexists_tac`abs o g` >>
      simp[] >>
      metis_tac[] ) >>
    match_mp_tac wf_to_inner_can_be_tagged >>
    rw[]) |> UNDISCH)

  (*
    val assums = i_wf_to_inners
    val ax = el 3 instantiated_axioms
  *)

  fun make_wf_to_inner_th vti assums ax =
    let
      val th = MATCH_MP wf_to_inner_defined_type (GEN_ALL ax)
      val abs = rator(lhs(concl ax))
      val (b,a) = dom_rng(type_of abs)
      val th1 = SPECL [type_to_deep a, mk_to_inner vti b] th
      val th2 = MATCH_MP th1 (wf_to_inner_mk_to_inner vti b)
    in
      foldl (uncurry PROVE_HYP) th2 assums
    end

  val of_sigof_rwt = prove(
    ``(tysof (sigof x) = tysof x) ∧
      (tmsof (sigof x) = tmsof x)``,
    rw[])

  val unpair_sig = prove(``sig = (tysof sig, tmsof sig)``, rw[])
  val unpair_int = prove(``int = (tyaof int, tmaof int)``, rw[])
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
          val th0 = termsem_cert tyin (concl ax)
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
          (*
          val valth = is_valuation_def |> ISPECL[mem,ktysig,ktyass,mk_pair(tyval,tmval)]
                      |> EQ_IMP_RULE |> fst
                      |> REWRITE_RULE[of_sigof_rwt]
                      |> UNDISCH |> CONJUNCT2
                      |> CONV_RULE(RAND_CONV(SIMP_CONV std_ss []))
                      |> CONV_RULE(RATOR_CONV(RAND_CONV(SIMP_CONV std_ss [])))
          *)
          val wfs = map (wf_to_inner_mk_to_inner [] o #residue) tyin
          val th4 = foldl (uncurry PROVE_HYP) th3 (gck::valth::(wfs@all_assums))
          (* val th4 = DISCH_ALL th4 *)
          (* val th4 = DISCH(valOf(List.find(can(match_term``is_valuation X Y Z``))(hyp th4)))th4 *)
        in
          (CONV_TAC(RATOR_CONV(computeLib.CBV_CONV cl)) >> strip_tac >>
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

  fun build_interpretation vti [] tys consts =
    let
      val gsbs = (UNDISCH holAxiomsTheory.good_select_base_select)
      val hypotheses =
        [``wf_to_inner (ind_to_inner:ind -> 'U)``,
         ``is_set_theory ^mem``] @
        (mapfilter (fn ty => to_inner_prop vti (assert is_vartype ty)) tys)
      val tyassums = flatten (map (base_type_assums vti) tys)
           |> filter (not o can (assert (equal tyval) o fst o strip_comb o lhs))
      val tmassums = flatten (map (base_term_assums vti) consts)
        (* |> filter (not o can (assert (equal tmval) o fst o strip_comb o lhs)) *)
      val assums0 = list_mk_conj (tyassums @ tmassums)
      (* TODO: need to choose select according to constraints *)
      val int = ``hol_model base_select ind_to_inner``
      val gcth =
        MATCH_MP good_context_base_case gsbs
      val args = snd(strip_comb(concl gcth))
      val s = [tysig |-> ``tysof ^(el 2 args)``,
               tmsig |-> ``tmsof ^(el 2 args)``,
               tyass |-> ``tyaof ^(el 3 args)``,
               tmass |-> ``tmaof ^(el 3 args)``]
      val assums = subst s assums0
      val th =
        MATCH_MP hol_model_def
          (LIST_CONJ [ASSUME (el 2 hypotheses),
                      gsbs,
                      ASSUME (el 1 hypotheses)])
        |> CONJUNCT1
      val assumsth = VALID_TAC_PROOF((hypotheses,assums),cheat)
    in
      LIST_CONJ [gcth,th,assumsth]
    end
  | build_interpretation vti (upd::ctxt) tys consts =
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
      val ith = build_interpretation vti ctxt
        (set_diff (union tys new_tys) instantiated_tys)
        (set_diff (union consts new_consts) instantiated_consts)
        (* [Note: It is *not* guaranteed that
            (instantiated_tys SUBSET tys) or the analog for consts;
            this is because we may have been *told* to constrain e.g.
            one of the constants of a certain instance of the update,
            but this means that we need to constrain *all* of the
            constants of that update]
         *)
      val hyps = hyp ith
      val good_context_i = CONJUNCT1 ith
      val i_models = CONJUNCT1 (CONJUNCT2 ith)
      val itm = get_int i_models
      val i_assums = CONJUNCT2(CONJUNCT2 ith)
      val i_wf_to_inners = filter(can(match_term``wf_to_inner X``) o concl)(CONJUNCTS i_assums)
      val new_wf_to_inners = if null (#tys upd) then [] else
        mapfilter (make_wf_to_inner_th vti i_wf_to_inners) instantiated_axioms
      val wf_to_inners = i_wf_to_inners @ new_wf_to_inners
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
      val (ktm,cs_assums,cs_rws) = make_cs_assums vti upd instances_to_constrain theory_ok_thm jtm
      val cs = ktm |> rator |> rand
      val z = genvar(listSyntax.mk_list_type universe_ty)
      val cs_cases = GEN z (updates_equal_some_cases z cs)
      val inner_upd = upd_to_inner upd
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
      val k_assums = map
        (make_k_assum (#updates_thm upd) k_equal_on_i istyath)
        (CONJUNCTS i_assums)
      val old_sig_is_std = good_context_i |> REWRITE_RULE[good_context_unpaired] |> CONJUNCT2 |> CONJUNCT1
      val k_is_std = MATCH_MP is_std_interpretation_equal_on
                       (LIST_CONJ [j_is_std,k_equal_on_j,old_sig_is_std])
      val tyvars_of_upd_rw =
        MATCH_MP tyvars_of_TypeDefn
          (CONJ (#updates_thm upd) old_sig_is_std)
        handle HOL_ERR _ => (* TODO *) tyvars_of_ConstSpec
      val k_is_std_type_assignment =
        k_is_std |> REWRITE_RULE[is_std_interpretation_def] |> CONJUNCT1
      val j_is_std_type_assignment =
        j_is_std |> REWRITE_RULE[is_std_interpretation_def] |> CONJUNCT1
      val all_assums = new_wf_to_inners@sig_ths@cs_assums@k_assums
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
      LIST_CONJ (good_context_k::k_models::all_assums)
    end
  (* build_interpretation vti (upd::ctxt) tys consts *)

(*******************
  val MID_EXISTS_AND_THM = prove(
    ``(?x. P x /\ Q /\ R x) <=> (Q /\ ?x. P x /\ R x)``,
    metis_tac[])
  val eval = SIMP_CONV (std_ss++LIST_ss)
    [typeof_def,codomain_def,typesem_def,
     term_ok_def,WELLTYPED_CLAUSES,
     type_ok_def,type_11]
   THENC SIMP_CONV std_ss [GSYM CONJ_ASSOC,MID_EXISTS_AND_THM]

  val tyass_eq_sym = PROVE[](``∀x y z. (^tyass x y = z) ⇒ (z = ^tyass x y)``)
  val tyval_eq_sym = PROVE[](``∀x z. (^tyval x = z) ⇒ (z = ^tyval x)``)
in

  val get_simpths = mapfilter (QCHANGED_CONV eval) o hyp
  fun simp_asms th = foldl (uncurry (C simplify_assum)) th (get_simpths th)
  val replace_asms =
    repeat (C replace_assum good_context_instance_equality) o
    repeat (C replace_assum good_context_wf_to_inner_bool_to_inner) o
    repeat (C replace_assum good_context_wf_to_inner_fun_to_inner) o
    repeat (C replace_assum good_context_tyass_bool) o
    repeat (C replace_assum good_context_tyass_fun) o
    repeat (C replace_assum good_context_lookup_bool) o
    repeat (C replace_assum good_context_lookup_fun) o
    repeat (C replace_assum tyass_eq_sym) o
    repeat (C replace_assum tyval_eq_sym) o
    repeat (C replace_assum TRUTH)
  fun changed f th =
      assert (not o curry HOLset.equal (hypset th) o hypset)
             (f th)
  val full_simp_asms = repeat (changed (simp_asms o replace_asms))

  val bool_to_inner_tm = ``bool_to_inner``
  val fun_to_inner_tm = ``fun_to_inner``

  val universe_ty = ``:'U``
  val bool_ty = ``:bool``
  val type_ty = ``:type``
  fun to_inner_tm ty = 
    mk_comb (
      mk_const ("to_inner0", (universe_ty --> universe_ty --> bool_ty)
                         --> type_ty --> ty --> universe_ty),
      mk_var ("mem", universe_ty --> universe_ty --> bool_ty)
    )

  fun mk_to_inner (ty : hol_type) = case type_view ty of
      Tyapp(thy, "bool", [])        => bool_to_inner_tm
    | Tyapp(thy, "fun",  [ty1,ty2]) => mk_binop fun_to_inner_tm (mk_to_inner ty1, mk_to_inner ty2)
    | _                             => mk_monop (to_inner_tm ty) (type_to_deep ty)

  (* Take a HOL type {ty} and return a theorem of the form
   * [^good_context, wf_is_inner in_ty1, ..., wf_is_inner in_tyn] |- wf_is_inner ^(mk_to_inner ty),
   * where ty1,...,tyn are types in ty other than
   * bool and function types.
   *)
  fun mk_wf_is_inner_thm ty = case type_view ty of
      Tyapp ("min","bool",[]) => good_context_wf_to_inner_bool_to_inner
    | Tyapp ("min","fun",[ty1,ty2]) =>
         good_context_wf_to_inner_fun_to_inner
         |> ISPECL [mk_to_inner ty1, mk_to_inner ty2]
         |> C MP (CONJ (mk_wf_is_inner_thm ty1)
                             (mk_wf_is_inner_thm ty2))
    | _ => ASSUME ``wf_to_inner ^(mk_to_inner ty)``

  fun type_to_cert ty = case type_view ty of
      Tyapp ("min","bool",[]) => bool_cert_thm
    | Tyapp ("min","fun",[ty1,ty2]) =>
         fun_cert_thm
         |> C MATCH_MP (type_to_cert ty1)
         |> C MATCH_MP (type_to_cert ty2)
    | Tyapp (_,con,args) =>
         tycon_cert_thm (* TODO: get rid of the MAP somehow *)
         |> INST_TYPE [``:'a`` |-> ty]
	 |> INST [``con:string`` |-> string_to_inner con,
		  ``args:type list`` |-> mk_list (map type_to_deep args, ``:type``)]
    | Tyvar v =>
         tyvar_cert_thm
         |> INST_TYPE [``:'a`` |-> ty]
         |> INST [``v:string`` |-> string_to_inner v]

  fun var_to_cert v =
    let
      val v_deep = term_to_deep (assert is_var v)
      val (x_deep,ty_deep) = dest_Var v_deep
      val l = mk_comb(mk_to_inner (type_of v),v)
      val a = mk_eq(mk_comb(tmval,mk_pair(x_deep,ty_deep)),l)
    in
      MATCH_MP Var_thm (ASSUME a) |> SPEC mem
    end

  val instance_tm = Term.inst[alpha|->U]``instance``
  fun mk_instance name ty =
    list_mk_comb(instance_tm,[tmsig,interpretation,name,ty,tyval])

  fun const_to_cert c =
    let
      val c_deep = term_to_deep (assert is_const c)
      val (name_deep,ty_deep) = dest_Const c_deep
      val l = mk_comb(mk_to_inner (type_of c),c)
      val a = mk_eq(mk_instance name_deep ty_deep,l)
      val th = MATCH_MP Const_thm (ASSUME a) |> SPEC mem
    in
      full_simp_asms th
    end

  fun term_to_cert tm =
    case dest_term tm of
      VAR _ => var_to_cert tm
    | CONST _ => const_to_cert tm
    | COMB(t1,t2) =>
      let
        val c1 = term_to_cert t1
        val c2 = term_to_cert t2
        val (dty,rty) = dom_rng (type_of t1)
      in
        MATCH_MP (Comb_thm) (CONJ c1 c2)
        |> C MATCH_MP (mk_wf_is_inner_thm dty)
        |> C MATCH_MP (mk_wf_is_inner_thm rty)
        |> full_simp_asms
      end
    | LAMB(x,b) =>
      let
        val (xd,tyd) = dest_Var(term_to_deep x)
        val bd = term_to_deep b
        val cx = var_to_cert x
        val cb = term_to_cert b
        val ina = cx |> concl |> lhs |> rator
        val inb = cb |> concl |> lhs |> rator
        val th = Abs_thm |> ISPECL[ina,inb,tm,xd,tyd,bd] |> funpow 2 UNDISCH
        val thd = mk_wf_is_inner_thm (type_of x)
        val thr = mk_wf_is_inner_thm (type_of b)
        val th = MATCH_MP th thd
        val th = MATCH_MP th thr
        val hyps = set_diff (mk_set(hyp cb @ hyp th)) (hyp cx)
        val goal = (hyps, th |> concl |> dest_imp |> fst)
        val th1 = VALID_TAC_PROOF(goal,
          gen_tac >> strip_tac >>
          CONV_TAC(LAND_CONV(RAND_CONV(BETA_CONV))) >>
          match_mp_tac (MP_CANON (DISCH_ALL cb)) >>
          ASM_SIMP_TAC (std_ss++LIST_ss++STRING_ss)
            [combinTheory.APPLY_UPDATE_THM] >>
          TRY (
            conj_tac >- (
              match_mp_tac good_context_extend_tmval >>
              PROVE_TAC[])) >>
          TRY (
            match_mp_tac good_context_extend_tmval >>
            PROVE_TAC[]) >>
          match_mp_tac EQ_SYM >>
          match_mp_tac (MP_CANON wf_to_inner_finv_right) >>
          PROVE_TAC[good_context_wf_to_inner_bool_to_inner,
                    good_context_wf_to_inner_fun_to_inner])
        val th2 = MP th th1
      in
        th2 |> UNDISCH |> full_simp_asms
      end

  fun find_equation_thms p acc =
    let
      val (l,r) = dest_eq p
      val acc = find_equation_thms l acc
      val acc = find_equation_thms r acc
      val a = equation_def
            |> SPECL[term_to_deep l, term_to_deep r]
            |> SYM
            |> SIMP_RULE (srw_ss())[]
    in
      a::acc
    end handle HOL_ERR _ => acc

  fun prop_to_loeb_hyp p =
    let
      val cert = term_to_cert p
      val equation_intro_rule = PURE_REWRITE_RULE (find_equation_thms p [])
      val th2 = AP_TERM``finv bool_to_inner`` cert
      val th3 =
        wf_to_inner_finv_left
        |> Q.ISPEC`bool_to_inner`
        |> C MATCH_MP good_context_wf_to_inner_bool_to_inner
        |> (fn th => CONV_RULE (LAND_CONV (REWR_CONV th)) th2)
        |> EQ_IMP_RULE |> snd
      val th4 = MATCH_MP finv_bool_to_inner_True th3
      val inst_sig = Q.INST[`tmsig`|->`tmsof(sigof(thyof ctxt))`,
                            `tysig`|->`tysof(sigof(thyof ctxt))`]
      val th5 = th4 |> inst_sig
      val th = Q.SPEC`thyof ctxt` provable_imp_eq_true
             |> SPECL [interpretation,valuation]
             |> funpow 3 UNDISCH
             |> SPEC (th5 |> concl |> rator |> rand |> lhs |> rand)
      val th6 = MATCH_MP mp_lemma (CONJ th5 th)
              |> equation_intro_rule
              |> C simplify_assum (inst_sig (SPEC_ALL good_context_def))
    in
      simp_asms th6
    end

  (*
  local
    val tyval_asms = filter (can (match_term ``^tyval x = range y``)) o hyp
    val mk_wf_to_inner = mk_monop``wf_to_inner``
    val is_set_theory_mem = ``is_set_theory ^mem``
    val is_type_valuation_tm = ``is_type_valuation``
    val update_list_tm = ``$=++``
    val base_tyval_tm = ``base_tyval``
  in
    fun mk_tyval th =
      let
        val asms = tyval_asms th
        fun mk_kv eq =
          let
            val (l,r) = dest_eq eq
          in
            mk_pair(rand l,r)
          end
        val pairs = map mk_kv asms
        val pairs = mk_list(pairs,mk_prod(string_ty,U))
        val tyval = list_mk_icomb(update_list_tm,[base_tyval_tm,pairs])
        val wf_to_inners = map (mk_wf_to_inner o rand o rand) asms
        val goal = (is_set_theory_mem::wf_to_inners,mk_comb(is_type_valuation_tm,tyval))
        val th = VALID_TAC_PROOF(goal,
          match_mp_tac is_type_valuation_update_list >>
          conj_tac >- ACCEPT_TAC base_tyval_def >>
          SIMP_TAC (std_ss ++ LIST_ss) [] >>
          rpt conj_tac >>
          match_mp_tac inhabited_range >>
          first_assum ACCEPT_TAC)
      in
        SIMP_RULE std_ss [UPDATE_LIST_THM] th
      end
  end
  *)

  val tmval_asms = filter (can (match_term ``^tmval x = y``)) o hyp

  local
    val empty_tyset = HOLset.empty Type.compare
    val sing_tyset = HOLset.singleton Type.compare
  in
    fun select_types tm =
      case dest_term tm of
        VAR _ => empty_tyset
      | CONST{Name="@",Thy="min",Ty} => sing_tyset (snd(dom_rng Ty))
      | CONST _ => empty_tyset
      | COMB(t1,t2) =>
        HOLset.union (select_types t1,select_types t2)
      | LAMB(_,b) => select_types b
  end

  fun IINST1 var tm th =
    INST_TY_TERM (match_term var tm) th
*******************)
end end
