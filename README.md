# README

car: A collection of aliases for common tasks on OCaml projects using ocamlbuild.
(cons was taken!)

Provides shortcuts for common tasks involving OCaml projects, e.g.:
- installing a project as a library
- writing the same list of dependencies to .merlin, _tags, and META
- running _test.ml files

# Installing

You can install using OPAM:

    opam pin add .

This will ensure you have all the required dependencies.

Alternatively you can just copy or link `car` to somewhere on your `$PATH`.

# Usage

You're expected to have a directory structure like this:

    project/
      car
      car.toml
      src/
        main.ml
        some_module.ml
        some_module_test.ml
        ...

To create an initial `car.toml` file you can run `./car init`.
You can also install `car` to somewhere on `$PATH` and do `car` instead of
`./car`, although then you won't be able to make customizations per-project.

## Help text

This is the standard helptext which should give a brief description of the functions of `car`.

    Usage car [rule]*
    A collection of aliases for common tasks on OCaml projects using ocamlbuild.
    
    init    Create an initial _car file.
    gen     Generate a META file and dependency lists in .merlin, and _tags.
    reqs    Print a list of the required packages listed in the config.
    clean   Delete binaries created by other commands.
    byte    Build main.d.byte from src/main.ml.
    opt     Build main.native from main.ml.
    top     Build a toplevel.
    topgen  Splice support code for a toplevel in .ocamlinit and _top.ml.
    doc     Build project documentation.
    lib     Install project modules as an ocamlfind package.
    unlib   Delete the ocamlfind package created by lib.
    test    Run test files.
    run     Run main or a specified file.
    
    If you don't supply a rule, all rules will run but: gen, reqs, clean, topgen, lib, unlib, run.

# Building a toplevel

If you want to build a toplevel using `car top`, running `car topgen` will
splice support code in the following files (paths relative to the root of the
project): 

In `.ocamlinit`:

    #thread
    #directory "src/_build"

In `src/project_top.ml` (replace `project` with the name of your project):

    let () = UTop_main.main ()

`project_top.ml` file is ignored when building your project as a library.

After running `car topgen`, you can run `car top` to build your own custom
toplevel using UTop (car will add the UTop package to the build flags, so you don't need it in your `requires` directive).
You can run it with `./project.top` (where `project` is your project's name).
