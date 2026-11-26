#!/bin/sh
# tests/card-run.sh FILE -- run one program of docs/card.md, for the bundle
# kit's card check.  X is the x under test; the lines INPUT reads are on
# standard input.
#
# FILE's lines are typed at a new machine, one after another, as at the
# prompt: X_BASIC_DIALECT's machine, the KIM's when it is unset.  What the
# machine prints is the output, less the blanks that end a line and the
# empty lines.  A line INPUT reads is shown after its question, as a
# terminal shows it.
d=$(mktemp -d) || exit 1
trap 'rm -rf "$d"' EXIT
case ${X_BASIC_DIALECT:-} in
gw | GW) dialect=gwbasic-dialect ;;
*) dialect=m6502-dialect ;;
esac
quote='s/[\\"]/\\&/g'
{
	cat <<-'E'
	(import x/type/list)
	(import x/type/dict)
	(import basic/m6502 m6502-dialect)
	(import basic/gwbasic gwbasic-dialect)
	(import basic/exec basic-machine basic-type)
	(import basic/term basic-term-out basic-term-zeros)
	(def %card-left (Dict make))
	(def %card-reply
	  (fn (_)
	    (let ((r (%card-left get (lit replies))))
	      (if (null? r) ()
	        (do (%card-left set! (lit replies) (rest r))
	            (basic-term-out (first r)) (basic-term-out "\n")
	            (first r))))))
	E
	printf '(%%card-left set! (lit replies) (list'
	sed -e "$quote" -e 's/.*/ "&"/' | tr -d '\n'
	printf '))\n'
	printf '(def %%card-machine (basic-machine %s basic-term-out basic-term-zeros %%card-reply (fn (_) ())))\n' "$dialect"
	sed -e "$quote" -e 's/.*/(basic-type %card-machine "&")/' "$1"
} > "$d/card.x"
"${X:-x}" -l basic -f "$d/card.x" < /dev/null | sed -e 's/ *$//' -e '/^$/d'
