open Utils
open Ast

module Env:sig

  type t

  val empty: t

  val value: t -> Ast.id -> Nast.id
  val try_value: t -> Ast.id -> Nast.id option
  val field: t -> Ast.id -> Nast.id
  val type_: t -> Ast.id -> Nast.id
  val try_type: t -> Ast.id -> Nast.id option
  val tvar: t -> Ast.id -> Nast.id
  val cstr: t -> Ast.id -> Nast.id

  val new_value: t -> Ast.id -> t * Nast.id
  val new_field: t -> Ast.id -> t * Nast.id
  val new_type: t -> Ast.id -> t * Nast.id
  val new_tvar: t -> Ast.id -> t * Nast.id
  val new_cstr: t -> Ast.id -> t * Nast.id

  val add_type: t -> Ast.id -> Nast.id -> t
  val add_value: t -> Ast.id -> Nast.id -> t

  val alias: t -> Ast.id -> Ast.id -> t

  val check_signature: Ast.decl list -> t -> unit

end = struct

  type t = {
      values: Ident.t SMap.t ;
      fields: Ident.t SMap.t ;
      types: Ident.t SMap.t ;
      tvars: Ident.t SMap.t ;
      cstrs: Ident.t SMap.t ;
    }

  let prim_types = [
    "int8" ; "int16" ; "int32" ; "int64" ;
    "bool" ; "float" ; "double" ]

  let types = 
    List.fold_left (fun acc x -> 
      let id = Ident.make (Pos.none, x) in
      SMap.add x id acc) 
      SMap.empty
      prim_types

  let empty = {
    values = SMap.empty ;
    fields = SMap.empty ;
    types = types ;
    tvars = SMap.empty ;
    cstrs = SMap.empty ;
  }

  let value t (p, x) =
    try p, SMap.find x t.values
    with Not_found -> Error.unbound_name p x

  let try_value t (p, x) = 
    try Some (p, SMap.find x t.values)
    with Not_found -> None

  let field t (p, x) =
    try p, SMap.find x t.fields
    with Not_found -> Error.unbound_name p x

  let type_ t (p, x) =
    try p, SMap.find x t.types
    with Not_found -> Error.unbound_name p x

  let try_type t (p, x) = 
    try Some (p, SMap.find x t.types)
    with Not_found -> None

  let tvar t (p, x) =
    try p, SMap.find x t.tvars
    with Not_found -> Error.unbound_name p x

  let cstr t (p, x) =
    try p, SMap.find x t.cstrs
    with Not_found -> Error.unbound_name p x

  let new_id t env ((p, x) as pos_x) = 
    let id = Ident.make pos_x in
    if SMap.mem x env
    then Error.multiple_def p x ;
    let env = SMap.add x id env in
    t, env, (p, id)

  let new_value t x = 
    let env = t.values in
    let t, env, id = new_id t env x in
    { t with values = env }, id
      
  let new_field t x = 
    let env = t.fields in
    let t, env, id = new_id t env x in
    { t with fields = env }, id

  let new_type t x = 
    let env = t.types in
    let t, env, id = new_id t env x in
    { t with types = env }, id

  let new_tvar t x = 
    let env = t.tvars in
    let t, env, id = new_id t env x in
    { t with tvars = env }, id

  let new_cstr t x = 
    let env = t.cstrs in
    let t, env, id = new_id t env x in
    { t with cstrs = env }, id

  let add_type t (_, x) (_, id) =
    { t with types = SMap.add x id t.types }

  let add_value t (_, x) (_, id) = 
    { t with values = SMap.add x id t.values }

  let alias t x y = 
    let id = value t y in
    add_value t x id

  let check_value t = function
    | Dval ((p,v),_) when not (SMap.mem v t.values) -> 
	Error.undefined_sig p v
    | _ -> ()

  let check_signature l t = 
    List.iter (check_value t) l
end

module Genv: sig

  type t

  val make: Ast.program -> t
  val module_id: t -> Ast.id -> Nast.id
  val sig_: t -> Nast.id -> Env.t
  val alias: t -> Ast.id -> Ast.id -> t

end = struct
    
  type t = { 
      sigs: Env.t IMap.t ;
      module_ids: Ident.t SMap.t ;
    }

  let empty = {
    sigs = IMap.empty ;
    module_ids = SMap.empty ;
  }

  let sig_ t (_, id) = 
    IMap.find id t.sigs

  let module_id t (p, x) =
    try p, SMap.find x t.module_ids
    with Not_found -> Error.unbound_name p x

  let new_module t ((_, x) as pos_x) = 
    let id = Ident.make pos_x in
    let t = { t with module_ids = SMap.add x id t.module_ids } in
    t, id

  let alias t id1 id2 =
    let id2 = module_id t id2 in
    let _, id1 = new_module t id1 in
    let sig_ = sig_ t id2 in
    { t with sigs = IMap.add id1 sig_ t.sigs }

  let rec make mdl = 
    List.fold_left module_decl empty mdl

  and module_decl genv md =
    let env = List.fold_left decl Env.empty md.md_decls in
    let t, md_id = new_module genv md.md_id in
    { t with sigs = IMap.add md_id env t.sigs }

  and decl env = function
    | Dtype tdef_l -> List.fold_left tdef env tdef_l
    | Dval (id, _) -> fst (Env.new_value env id)

  and tdef env ((id, _), (_, ty)) = 
    let env, _ = Env.new_type env id in
    match ty with
    | Talgebric vtl -> List.fold_left variant env vtl 
    | Trecord fdl -> List.fold_left field env fdl
    | _ -> env

  and variant env (id, _) = fst (Env.new_cstr env id)
  and field env (id, _) = fst (Env.new_field env id)

end

let rec program mdl = 
  let genv = Genv.make mdl in
  List.map (module_ genv) mdl 

and module_ genv md = 
  let md_id = Genv.module_id genv md.md_id in
  let sig_ = Genv.sig_ genv md_id in
  let _, decls = lfold (decl genv sig_) Env.empty md.md_decls in
  let acc = genv, Env.empty, [] in
  let _, env, defs = List.fold_left (def sig_) acc md.md_defs in
  Env.check_signature md.md_decls env ;
  let defs = List.rev defs in
  { Nast.md_id = md_id ;
    Nast.md_decls = decls ;
    Nast.md_defs = defs ;
  }

and decl genv sig_ env = function
  | Dtype tdl -> 
      let env = List.fold_left (bind_type sig_) env tdl in
      env, Nast.Dtype (List.map (type_def genv sig_ env) tdl)

  | Dval (id, ty) -> 
      let id = Env.value sig_ id in
      env, Nast.Dval (id, type_expr genv sig_ env ty)

and bind_type sig_ env ((x, _), _) = 
  let id = Env.type_ sig_ x in
  Env.add_type env x id

and type_def genv sig_ env ((id, tvarl), ty) = 
  let id = Env.type_ env id in
  let env, tvarl = lfold Env.new_tvar env tvarl in
  ((id, tvarl), type_expr genv sig_ env ty)

and type_expr genv sig_ env (p, ty) = p, type_expr_ genv sig_ env ty
and type_expr_ genv sig_ env x = 
  let k = type_expr genv sig_ env in
  match x with
  | Tvar x -> Nast.Tvar (Env.tvar env x)
  | Tid x -> Nast.Tid (Env.type_ env x)
  | Tapply (ty, tyl) -> Nast.Tapply (k ty, List.map k tyl)
  | Ttuple tyl -> Nast.Ttuple (List.map k tyl)
  | Tpath (id1, id2) -> 
      let md_id = Genv.module_id genv id1 in
      let sig_ = Genv.sig_ genv md_id in
      let id2 = Env.type_ sig_ id2 in
      Nast.Tpath (md_id, id2)
  | Tfun (ty1, ty2) -> Nast.Tfun (k ty1, k ty2)
  | Talgebric l -> Nast.Talgebric (List.map (tvariant genv sig_ env) l)
  | Trecord l -> Nast.Trecord (List.map (tfield genv sig_ env) l)
  | Tabbrev ty -> Nast.Tabbrev (k ty)

and tvariant genv sig_ env (id, ty) = 
  let ty = match ty with 
  | None -> None
  | Some ty -> Some (type_expr genv sig_ env ty) in
  Env.cstr sig_ id, ty

and tfield genv sig_ env (id, ty) = 
  Env.field sig_ id, type_expr genv sig_ env ty  
  
and def sig_ (genv, env, acc) = function
  | Dmodule (id1, id2) -> Genv.alias genv id1 id2, env, acc
  | Dlet (id,pl,e) -> 
      let env, pl = lfold (pat genv sig_) env pl in
      let e = expr genv sig_ env e in
      let env = bind_val sig_ env id in
      let id = Env.value env id in
      genv, env, Nast.Dlet (id, pl, e) :: acc

  | Dletrec dl  -> 
      let env = List.fold_left (bind_let sig_) env dl in
      let dl = List.map (dlet genv sig_ env) dl in
      genv, env, Nast.Dletrec dl :: acc

  | Dalias (id1, id2) -> genv, Env.alias env id1 id2, acc

and bind_let sig_ env (x, _, _) = bind_val sig_ env x
and bind_val sig_ env x = 
  match Env.try_value sig_ x with
  | None -> fst (Env.new_value env x)
  | Some id -> Env.add_value env x id

and dlet genv sig_ env (id, pl, e) = 
  let id = Env.value env id in
  let env, pl = lfold (pat genv sig_) env pl in
  let e = expr genv sig_ env e in
  (id, pl, e)

and pat genv sig_ env (pos, p) = 
  let env, p = pat_ genv sig_ env p in
  env, (pos, p)

and pat_ genv sig_ env = function
  | Punit -> env, Nast.Punit
  | Pany -> env, Nast.Pany
  | Pid x -> 
      let env, x = Env.new_value env x in
      env, Nast.Pid x
  | Pchar x -> env, Nast.Pchar x
  | Pint x -> env, Nast.Pint x
  | Pbool b -> env, Nast.Pbool b
  | Pfloat f -> env, Nast.Pfloat f
  | Pstring s -> env, Nast.Pstring s
  | Pcstr id -> env, Nast.Pcstr (Env.cstr sig_ id)
  | Pvariant (id, p) -> 
      let env, p = pat genv sig_ env p in
      env, Nast.Pvariant (Env.cstr sig_ id, p)

  | Precord fl -> 
      let env, fl = lfold (pat_field genv sig_) env fl in
      env, Nast.Precord fl

  | Pbar (p1, p2) -> 
      let env, p1 = pat genv sig_ env p1 in
      let env, p2 = pat genv sig_ env p2 in
      env, Nast.Pbar (p1, p2)

  | Ptuple pl -> 
      let env, pl = lfold (pat genv sig_) env pl in
      env, Nast.Ptuple pl

and pat_field genv sig_ env (p, pf) = 
  let env, pf = pat_field_ genv sig_ env pf in
  env, (p, pf)

and pat_field_ genv sig_ env = function
  | PFany -> env, Nast.PFany
  | PFid _ -> assert false
  | PField (id, p) -> 
      let env, p = pat genv sig_ env p in
      env, Nast.PField (Env.field sig_ id, p)

and expr genv sig_ env (p, e) = p, expr_ genv sig_ env e
and expr_ genv sig_ env e = 
  let k = expr genv sig_ env in
  match e with
  | Eunit -> Nast.Eunit
  | Ebool x -> Nast.Ebool x
  | Eint x -> Nast.Eint x
  | Efloat x -> Nast.Efloat x
  | Echar x -> Nast.Echar x
  | Estring x -> Nast.Estring x
  | Eid x -> Nast.Eid (Env.value env x)
  | Eeq (e1, e2) -> Nast.Eeq (k e1, k e2)
  | Elt (e1, e2) -> Nast.Elt (k e1, k e2)
  | Elte (e1, e2) -> Nast.Elte (k e1, k e2)
  | Egt (e1, e2) -> Nast.Egt (k e1, k e2)
  | Egte (e1, e2) -> Nast.Egte (k e1, k e2)
  | Eplus (e1, e2) -> Nast.Eplus (k e1, k e2)
  | Eminus (e1, e2) -> Nast.Eminus (k e1, k e2)
  | Estar (e1, e2) -> Nast.Estar (k e1, k e2)
  | Eseq (e1, e2) -> Nast.Eseq (k e1, k e2)
  | Euminus e -> Nast.Euminus (k e)
  | Etuple el -> Nast.Etuple (List.map k el)
  | Ecstr x -> Nast.Ecstr (Env.cstr sig_ x)
  | Ederef (e1, e2) -> Nast.Ederef (k e1, k e2)
  | Epath ((_, Ecstr md_id), v) -> 
      let md_id = Genv.module_id genv md_id in
      let v = Env.value (Genv.sig_ genv md_id) v in
      Nast.Eextern (md_id, v)
  | Epath (e, v) -> Nast.Efield (k e, Env.field sig_ v)
  | Ematch (e, pel) -> 
      let pel = List.map (pat_expr genv sig_ env) pel in
      Nast.Ematch (k e, pel) 

  | Elet (p, e1, e2) -> 
      let env, p = pat genv sig_ env p in
      let e2 = expr genv sig_ env e2 in
      Nast.Elet (p, k e1, e2)

  | Eif (e1, e2, e3) -> Nast.Eif (k e1, k e2, k e3) 
  | Efun (pl, e) -> 
      let env, pl = lfold (pat genv sig_) env pl in
      let e = expr genv sig_ env e in
      Nast.Efun (pl, e)

  | Eapply (e, el) -> Nast.Eapply (k e, List.map k el) 
  | Erecord fdl -> Nast.Erecord (List.map (field genv sig_ env) fdl)

and field genv sig_ env (id, e) = 
  Env.field env id, expr genv sig_ env e

and pat_expr genv sig_ env (p, e) = 
  let env, p = pat genv sig_ env p in
  p, expr genv sig_ env e
