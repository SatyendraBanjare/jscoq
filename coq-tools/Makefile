.PHONY: clean all

# CAMLDEBUG=-g
CAMLDEBUG=
CAMLWARN=-w @A
BYTEFLAGS=-rectypes -safe-string $(CAMLDEBUG) $(CAMLWARN) -package yojson,ppx_deriving_yojson -I ../coq-js/ 

# Our OCAML rules, we could refine the includes
%.cmi: %.mli
	ocamlfind ocamlc -c $(BYTEFLAGS) $<

%.cmo: %.ml
	ocamlfind ocamlc -c $(BYTEFLAGS) $<

all: mklibfs mklibjson

COQ_LIB:=../coq-js/jslib.cmo

########################################################################
# Tools
mklibfs.cmo: $(COQ_LIB) dftlibs.cmo

mklibfs: mklibfs.cmo
	ocamlfind ocamlc -linkpkg $(BYTEFLAGS) $(COQ_LIB) dftlibs.cmo mklibfs.cmo -o mklibfs

mklibjson.cmo: $(COQ_LIB) dftlibs.cmo

mklibjson: mklibjson.cmo
	ocamlfind ocamlc -linkpkg $(BYTEFLAGS) $(COQ_LIB) dftlibs.cmo mklibjson.cmo -o mklibjson

clean:
	rm -f *.cmi *.cmo *.ml.d *.mli.d mklibfs mklibjson
