open Types
open Display

exception MainError of string

let show_control_sequence_type : bool ref = ref false
let show_function_type         : bool ref = ref false

(* string -> bool *)
let is_document_file str =
  if String.length str < 5 then false else
    (compare ".mcrd" (String.sub str ((String.length str) - 5) 5)) == 0

(* string -> bool *)
let is_header_file str =
  if String.length str < 6 then false else
    (compare ".mcrdh" (String.sub str ((String.length str) - 6) 6)) == 0

(* string -> bool *)
let is_standalone_file str =
  if String.length str < 6 then false else
    (compare ".mcrds" (String.sub str ((String.length str) - 6) 6)) == 0


(* Variantenv.t -> Typeenv.t -> environment -> string -> (Variantenv.t * Typeenv.t * environment) *)
let make_environment_from_header_file varntenv tyenv env file_name_in =
  begin
    print_string (" ---- ---- ---- ----\n") ;
    print_string ("  reading '" ^ file_name_in ^ "' ...\n") ;
    let file_in = open_in file_name_in in
      begin
        Lexer.reset_to_numexpr () ;
        let utast = Parser.main Lexer.cut_token (Lexing.from_channel file_in) in
        let (ty, newvarntenv, newtyenv, ast) = Typechecker.main varntenv tyenv utast in
          begin
            print_string ("  type check: " ^ (string_of_type_struct ty) ^ "\n") ;
            let evaled = Evaluator.interpret env ast in
              match evaled with
              | EvaluatedEnvironment(newenv) ->
                  begin
                    ( if !show_control_sequence_type then
                        if !show_function_type then
                          print_string (Typeenv.string_of_type_environment newtyenv "Environment")
                        else
                          print_string (Typeenv.string_of_control_sequence_type newtyenv)
                      else () ) ;
                    (newvarntenv, newtyenv, newenv)
                  end
              | _ -> raise (MainError("'" ^ file_name_in ^ "' is not a header file"))
          end
      end
  end


(* Typeenv.t -> environment -> string -> string -> unit *)
let read_standalone_file varntenv tyenv env file_name_in file_name_out =
  begin
    print_string (" ---- ---- ---- ----\n") ;
    print_string ("  reading '" ^ file_name_in ^ "' ...\n") ;
    let file_in = open_in file_name_in in
      begin
        Lexer.reset_to_numexpr () ;
        let utast = Parser.main Lexer.cut_token (Lexing.from_channel file_in) in
        let (ty, _, _, ast) = Typechecker.main varntenv tyenv utast in
          begin
            print_string ("  type check: " ^ (string_of_type_struct ty) ^ "\n") ;
            match ty with
            | StringType(_) ->
                let evaled = Evaluator.interpret env ast in
                let content_out = Out.main evaled in
                  begin
                    Files.file_out_of_string file_name_out content_out ;
                    print_string (" ---- ---- ---- ----\n") ;
                    print_string ("  output written on '" ^ file_name_out ^ "'.\n")
                  end
            | _  -> raise (TypeCheckError("the output of '" ^ file_name_in ^ "' is not string"))
          end
      end
  end


(* Typeenv.t -> environment -> string -> string -> unit *)
let read_document_file varntenv tyenv env file_name_in file_name_out =
  begin
    print_string (" ---- ---- ---- ----\n") ;
    print_string ("  reading '" ^ file_name_in ^ "' ...\n") ;
    let file_in = open_in file_name_in in
      begin
        Lexer.reset_to_strexpr () ;
        let utast = Parser.main Lexer.cut_token (Lexing.from_channel file_in) in
        let (ty, _, _, ast) = Typechecker.main varntenv tyenv utast in
          begin
            print_string ("  type check: " ^ (string_of_type_struct ty) ^ "\n") ;
            match ty with
            | StringType(_) ->
                let evaled = Evaluator.interpret env ast in
                let content_out = Out.main evaled in
                if (String.length content_out) == 0 then
                  begin
                    print_string " ---- ---- ---- ----\n" ;
                    print_string "  no output.\n"
                  end
                else
                  begin
                    Files.file_out_of_string file_name_out content_out ;
                    print_string " ---- ---- ---- ----\n" ;
                    print_string ("  output written on '" ^ file_name_out ^ "'.\n")
                  end
            | _ -> raise (TypeCheckError("the output of '" ^ file_name_in ^ "' is not string"))
          end
      end
  end


(* Variantenv.t -> Typeenv.t -> environment -> string list -> string -> unit *)
let rec main varntenv tyenv env file_name_in_list file_name_out =
  try
    match file_name_in_list with
    | [] ->
        begin
          print_string " ---- ---- ---- ----\n" ;
        	print_string "  no output.\n"
        end
    | file_name_in :: tail when is_document_file file_name_in ->
          read_document_file varntenv tyenv env file_name_in file_name_out

    | file_name_in :: tail when is_header_file file_name_in ->
          let (newvarntenv, newtyenv, newenv) = make_environment_from_header_file varntenv tyenv env file_name_in in
            main newvarntenv newtyenv newenv tail file_name_out

    | file_name_in :: tail when is_standalone_file file_name_in ->
          read_standalone_file varntenv tyenv env file_name_in file_name_out

    | file_name_in :: _ -> raise (MainError("'" ^ file_name_in ^ "' has illegal filename extension"))
  with
  | Lexer.LexError(s)             -> print_string ("! [ERROR AT LEXER] " ^ s ^ ".\n")
  | Parsing.Parse_error           -> print_string ("! [ERROR AT PARSER] something is wrong.\n")
  | ParseErrorDetail(s)           -> print_string ("! [ERROR AT PARSER] " ^ s ^ "\n")
  | TypeCheckError(s)             -> print_string ("! [ERROR AT TYPECHECKER] " ^ s ^ ".\n")
  | Evaluator.EvalError(s)        -> print_string ("! [ERROR AT EVAL] " ^ s ^ ".\n")
  | Out.IllegalOut(s)             -> print_string ("! [ERROR AT OUT] " ^ s ^ ".\n")
  | MainError(s)                  -> print_string ("! [ERROR AT MAIN] " ^ s ^ ".\n")
  | Sys_error(s)                  -> print_string ("! [ERROR AT MAIN] System error - " ^ s ^ "\n")


(* int -> (string list) -> string -> unit *)
let rec see_argv num file_name_in_list file_name_out =
    if num == Array.length Sys.argv then
      begin
        print_string ("  [output] " ^ file_name_out ^ "\n\n") ;
        Typechecker.initialize () ;
        let varntenv = Primitives.make_variant_environment () in
        let tyenv = Primitives.make_type_environment () in
        let env = Primitives.make_environment () in
          main varntenv tyenv env file_name_in_list file_name_out
      end
    else
      match Sys.argv.(num) with
      | "-v" ->
          print_string (
              "  Macrodown version 1.00g\n"
            ^ "    ____   ____       ________     _____   ______\n"
            ^ "    \\   \\  \\   \\     /   _____|   /   __| /      \\\n"
            ^ "     \\   \\  \\   \\   /   /        /   /   /   /\\   \\\n"
            ^ "     /    \\  \\   \\  \\   \\       /   /   /   /  \\   \\\n"
            ^ "    /      \\  \\   \\  \\   \\     /   /   /   /    \\   \\\n"
            ^ "   /   /\\   \\  \\   \\  \\   \\   /   /   /   /      \\   \\\n"
            ^ "  /   /  \\   \\  \\   \\  \\___\\ /___/   /   /        \\   \\\n"
            ^ " /   /    \\   \\  \\   \\              /   /_________/   /\n"
            ^ "/___/      \\___\\  \\___\\            /_________________/\n"
          )
      | "-o" ->
          begin
            try see_argv (num + 2) file_name_in_list (Sys.argv.(num + 1)) with
            | Invalid_argument(s) -> print_string "! missing file name after '-o' option\n"
          end
      | "-t" ->
          begin
            show_control_sequence_type := true ;
            see_argv (num + 1) file_name_in_list file_name_out
          end
      | "-f" ->
          begin
            show_control_sequence_type := true ;
            show_function_type         := true ;
            see_argv (num + 1) file_name_in_list file_name_out
          end
      | _    ->
          begin
            print_string ("  [input] " ^ Sys.argv.(num) ^ "\n") ;
            see_argv (num + 1) (file_name_in_list @ [Sys.argv.(num)]) file_name_out
          end


let _ = see_argv 1 [] "mcrd.out"
