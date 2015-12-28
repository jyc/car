# README

mk: a fanny pack for OCaml projects.
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
