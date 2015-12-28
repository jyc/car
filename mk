#!/usr/bin/env utop
#require "unix"

(* mk: a fanny pack for OCaml projects.
   Disorganized and unstlyish, but handy.

   Provides shortcuts for common tasks involving OCaml projects, e.g.:
   - installing a project as a library
   - writing the same list of dependencies to .merlin, _tags, and META
   - running _test.ml files

   It's intended that you copy this script to your project's directory and
   modify it however you see fit. It's called mk because it's easy to type
   "./mk" with one hand.

   You're expected to have a directory structure like this:

       project/
         mk
         src/
           main.ml
           some_module.ml
           some_module_test.ml
           ...

   Licensed under the BSD 2-Clause License.
   Copyright 2015 Jonathan Y. Chan <jyc@fastmail.fm>
   https://github.com/jonathanyc/mk *)

let src_dir = "src"
let top_name = "my_project_top"
let project = "my_project"
let package = "my-project"

let dependencies =
  ["pcre"; "lwt"; "lwt.unix"; "yojson"]

open Unix
open Printf
(* Make sure we are using Pervasive's stderr, etc. *)
open Pervasives

(** If [log_commands] is true, we print out the commands we are exiting through
    [run] and [run_status] before executing them.
    It can be toggled directly or around a block of code using [with_log_commands]. *)
let log_commands = ref true

(** [with_log_commands x f] sets [log_commands] to [x] before calling [f ()].
    After that call returns it sets [log_commands] to what it was previously. *)
let with_log_commands x f =
  let prev = !log_commands in
  log_commands := x ;
  f () ;
  log_commands := prev

(** [run cmd] runs the command [cmd] using [system] (i.e. it is interpreted
    using /bin/sh). If [log_commands] is true, the command is output before it
    is run. If the command returns a non-zero exit code or is killed by / exits
    due to a signal, we print an error is printed to stderr and [exit 1]. *)
let run cmd =
  if !log_commands then
    print_endline cmd 
  else () ;
  match system cmd with
  | WEXITED 0 -> ()
  | WEXITED x ->
    fprintf stderr "\nCommand failed: '%s' exited with code %d.\n" cmd x ;
    exit 1
  | _ ->
    fprintf stderr "\nCommand failed: '%s' exited abnormally.\n" cmd ;
    exit 1

(** [run_status cmd] is ike [run cmd] except it returns the exit code of the
    command. Unlike [run cmd] it only prints an error and exits when the
    process is terminated unusually -- non-zero exit codes are simply returned. *)
let run_status cmd =
  if !log_commands then
    print_endline cmd
  else () ;
  match system cmd with
  | WEXITED code -> code
  | _ ->
    fprintf stderr "\nCommand failed: '%s' exited abnormally.\n" cmd ;
    exit 1

(** [has_package name] returns true if the package [name] is known to
    ocamlfind. *)
let has_package name =
  run_status (sprintf "ocamlfind query %s" name) = 0

(** [ocb ?quiet cmd] runs the ocamlfind command [cmd]. If [quiet] is true the
    -quiet flag is given to ocamlbuild, which causes normal output to be
    suppressed (only errors are output). The main point is that it includes the
    -use-ocamlfind flag which we need for pretty much everything. *)
let ocb ?(quiet=false) cmd =
  if quiet then
    run ("ocamlbuild -quiet -use-ocamlfind " ^ cmd) 
  else
    run ("ocamlbuild -use-ocamlfind " ^ cmd) 

(** [mcase s] returns the string [s] with its first character uppercased (i.e.
    how OCaml gets module names from file names. *)
let mcase s =
  sprintf "%c%s"
    (Char.uppercase s.[0])
    (String.sub s 1 (String.length s - 1))

(** [check_prefix a b] returns true if [a] is a prefix of [b]. *)
let check_prefix a b =
  String.length a <= String.length b &&
  String.sub b 0 (String.length a) = a

(** [install path] moves the file at [path] to the parent directory,
    overwriting any file already there.
    It's used because we run ocamlbuild in the source directory, like it wants.
    But we store the sources in src/ and want the build outputs to go to its
    parent directory, the root of the repository. *)
let install path =
  run ("rm -rf ../" ^ path) ;
  run (sprintf "mv %s ../%s" path path)

(** [modules ()] returns a list of the OCaml modules in the current directory.
    It does this by finding all the .ml files and calling [mcase] on the
    filenames. *)
let modules () =
  Sys.readdir "."
  |> Array.to_list
  |> List.filter (fun s -> Filename.check_suffix s ".ml")
  |> List.map Filename.chop_extension
  |> List.map mcase

(** [write_module_list ?excludes dest] writes a list of the modules in the
    current directory, separated by newlines, to [dest]. We use it to create
    the .mllib, .odocl, and .mltop files that ocamlbuild wants, including all
    of the modules in the project. Modules named in [excludes] are excluded,
    as well as any modules suffixed _test. *)
let write_module_list ?(excludes=[]) ~dest =
  let mods = modules () in
  let out = Buffer.create 128 in
  let och = open_out dest in
  List.iter
    (fun m -> 
       if List.mem m excludes || Filename.check_suffix m "_test" then ()
       else Buffer.add_string out (m ^ "\n"))
    mods ;
  output_string och (Buffer.contents out) ;
  close_out och

(** [with_module_list ?excludes dest f] calls [write_module_list ?excludes
    ~dest], then [f ()], then removes the created module list afterwards. So
    you don't have to remember to. *)
let with_module_list ?excludes ~dest f =
  write_module_list ?excludes ~dest ;
  f () ;
  run (sprintf "rm '%s'" dest)

(** [splice_file path tag s] splices the autogenerated text [s] into the file
    at [path]. If no file exists then a new one is created containing [s]. If
    one already exist that doesn't contain a splice section tagged [tag] then
    [s] is spliced at the end of the file. Otherwise the existing splice
    section is replaced with [s]. A splice section looks like:
    
        #begin mk TAG
        S
        #end

    We use it to autogenerate portions of files like META and .merlin, which
    the user may want to edit (so we don't want to just overwrite the whole
    thing.) *)
let splice_file path tag s =
  let start_line = sprintf "# begin mk %s" tag in
  let end_line = "# end" in

  let out = Buffer.create 128 in
  let spliced = ref false in
  let splice () = 
    assert (not !spliced) ;
    Buffer.add_string out (sprintf "%s\n%s\n%s\n" start_line s end_line) ;
    spliced := true ;
  in

  if not (Sys.file_exists path) then begin
    splice ()
  end else begin
    let inch = open_in path in
    let splicing = ref true in

    while !splicing do
      match input_line inch with
      | line when line = start_line && not !spliced ->
        splice () ;
        (* Keep reading until we get to the [end_line]. *)
        let skipping = ref true in
        while !skipping do 
          match input_line inch with
          | s when s = end_line -> skipping := false
          | _ -> ()
          | exception End_of_file -> skipping := false
        done
      | line -> 
        Buffer.add_string out line ;
        Buffer.add_char out '\n'
      | exception End_of_file ->
        if not !spliced then begin
          Buffer.add_char out '\n' ;
          splice () 
        end ;
        splicing := false
    done ;

    close_in inch ;
  end ;

  let ouch = open_out path in
  output_string ouch (Buffer.contents out) ;
  close_out ouch

(* A list of file extensions of artifacts to install with ocamlfind. *)
let desired_artifacts =
  [".cmi"; ".cmt"; ".ml"; ".mli"; ".cma"; ".cmxa"; ".a" ]

type rule_group =
  | Destroy
  | Build
  | Install
  | Generate
  | Test

(** [rules] is a alist of (name, group, procedure) tuples. Each specifies a
    subcommand for mk. For example, ./mk splice will call the procedure whose
    name is "splice". The [group] currently only affects [rule_all], which
    doesn't run "destructive" rules like clean and unlib (otherwise it'd delete
    the files it just created!) *)
let rules =
  [(* splice autogenerates:
      - requires and archive directives in META
      - PKG directives in .merlin
      - package flags in _tags
      ... based on the dependencies listed in [dependencies].
      It's pointlessly tedious to have to edit three files every time you add a
      new dependency. *)
   ("splice",
    Generate,
    (fun () ->
       let merlin = String.concat "\n" (List.map (fun s -> sprintf "PKG %s" s) dependencies) in
       let tags = "true: " ^ String.concat ", " (List.map (fun s -> sprintf "package(%s)" s) dependencies) in
       let meta =
         sprintf
           "requires = \"%s\"\n\
            archive(byte) = \"%s.cma\"\n\
            archive(native) = \"%s.cmxa\""
           (String.concat " " dependencies) project project
       in
       splice_file "META" "META" meta (* wow such meta *) ;
       splice_file "_tags" "_tags" tags (* very tags *) ;
       splice_file ".merlin" ".merlin" merlin));

   (* clean deletes the binaries created by other commands. It doesn't delete
      the spliced files, beacuse it makes sense to commit those and because you
      might have your own changes. *)
   ("clean",
    Destroy,
    (fun () ->
       ocb "-clean" ;
       chdir ".." ;
       run (sprintf "rm -f main.native main.d.byte %s.top %s.docdir" top_name project) ;
       chdir src_dir));

   (* byte builds main.d.byte using ocamlbuild from a src/main.ml file. *)
   ("byte",
    Build,
    (fun () ->
       ocb "main.d.byte" ;
       install "main.d.byte"));

   (* opt builds main.native using ocamlbuild from a src/main.ml file. *)
   ("opt",
    Build,
    (fun () ->
       ocb "main.native" ;
       install "main.native"));

   (* top builds a custom toplevel top_name.top containing all the modules in
      the project except for Main and *_test.
      You should add a file called <project>_top.ml containing the following line:

          let () = UTop_main.main ()

      ... to have your top be based on UTop (this requires utop to be in the
      dependencies). You should also create a file called .ocamlinit in the
      root of the project (if that's where you're going to be running the top)
      with the contents:
   
          #thread
          #directory "src/_build"
   
      ... to set up the top properly. *)
   ("top",
    Build,
    (fun () ->
       with_module_list ~excludes:["Main"] ~dest:(sprintf "%s.mltop" top_name)
         (fun () ->
            ocb (sprintf "%s.top" top_name) ;
            install (sprintf "%s.top" top_name)))) ;

   (* doc runs ocamldoc on all of the modules in your project except for *_test
      modules. The generated documentation is located at <project>.docdir. *)
   ("doc",
    Build,
    (fun () ->
       with_module_list ~dest:(sprintf "%s.odocl" project)
         (fun () ->
            ocb (sprintf "%s.docdir/index.html" project) ;
            install (sprintf "%s.docdir" project))));

   (* lib installs all of the modules in your project except for Main and
      *_test modules as an ocamlfind package named [package]. *)
   ("lib",
    Install,
    (fun () ->
       (* Remove this package if it's already installed. *)
       if has_package package then
         run (sprintf "ocamlfind remove %s" package)
       else () ;

       with_module_list ~excludes:["Main"] ~dest:(sprintf "%s.mllib" project)
         (fun () ->
            (* Bytecode. *)
            ocb (sprintf "%s.cma" project) ;
            (* Native code. *)
            ocb (sprintf "%s.cmxa" project) ;

            let artifacts = 
              Sys.readdir "_build"
              |> Array.to_list
              |> List.map (fun s -> "_build/" ^ s) 
              |> List.filter (fun s -> not (Sys.is_directory s))
              |> List.filter (fun s -> List.exists (fun f -> Filename.check_suffix s f) desired_artifacts)
              |> String.concat " "
            in

            run (sprintf "ocamlfind install %s META %s >/dev/null 2>&1" package artifacts))));

   (* unlib removes the package created by lib named [package]. *)
   ("unlib",
    Destroy,
    (fun () ->
       run (sprintf "ocamlfind remove %s" package)));

   (* test finds all the files named *_test.ml, builds them to bytecode with
      debugging flags, then runs them with backtraces enabled. *)
   ("test",
    Test,
    (fun () ->
       let test_files =
         Sys.readdir "."
         |> Array.to_list
         |> List.filter (fun s -> Filename.check_suffix s "_test.ml")
       in
       with_log_commands false
         (fun () ->
            List.iter
              (fun test ->
                 let out = "./" ^ Filename.chop_extension test ^ ".d.byte" in
                 printf "Testing: %s\n%!" test ;
                 ocb ~quiet:true out ;
                 run ({|OCAMLRUNPARAM="b" |} ^ out) ;
                 run ("rm " ^ out))
              test_files)))]

(** [rule name] runs the rule named [name] if it exists. If no such rule
    exists, we print an error is printed then [exit 1]. *)
let rule name =
  let rec rule' = function
    | [] -> raise Not_found
    | (name', _, proc) :: rs ->
      if name' = name then proc else rule' rs
  in
  match rule' rules with
  | proc ->
    printf "Rule: %s\n%!" name ;
    proc ()
  | exception Not_found ->
    printf "No such rule: %s\n" name ;
    exit 1

(** [rule_all ()] executes every rule except for "clean" and "unlib". *)
let rule_all () =
  List.iter
    (fun (name, group, _) ->
       if group = Destroy then ()
       else begin
         rule name ;
         print_endline ""
       end)
    rules

(* Here we go! *)
let () = 
  chdir src_dir ;
  if Array.length Sys.argv = 1 then
    rule_all ()
  else
    rule Sys.argv.(1)

(* vim: set filetype=ocaml : *)
