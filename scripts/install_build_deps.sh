#! /bin/sh

set -e

script_dir="$(cd "$(dirname "$0")" && echo "$(pwd -P)/")"
src_dir="$(dirname "$script_dir")"

#shellcheck source=scripts/version.sh
. "$script_dir"/version.sh

# make sure that this variable is declared
ocaml_version=${ocaml_version:?}
opam_repository=${opam_repository:?}

create_opam_switch() {
    [ -n "$1" ] || { echo "create_opam_switch expects a non-empty argument"; return 1; }
    opam switch create "$1" --repositories=tezos "ocaml-base-compiler.$ocaml_version"
}

if [ "$1" = "--dev" ]; then
    dev=yes
else
    dev=
fi

# $OPAMSWITCH variable makes the following commands fail if the switch referred
# to by it does not exist. Since we're going to create it later, for now let's
# pretend it's not set.
opamswitch="$OPAMSWITCH"
unset OPAMSWITCH

opam repository set-url tezos --dont-select "$opam_repository" || \
    opam repository add tezos --dont-select "$opam_repository" > /dev/null 2>&1

opam update --repositories --development

OPAMSWITCH="$opamswitch"

# If $OPAMSWITCH is set to a non-existent switch, such a switch should be created.
if [ -n "$OPAMSWITCH" ]; then
    if ! opam env --set-switch > /dev/null; then
        echo "Creating local switch $OPAMSWITCH..."
        create_opam_switch "$OPAMSWITCH"
    else
        echo "$OPAMSWITCH already exists. Installing dependencies."
    fi
    eval "$(opam env --switch="$OPAMSWITCH" --set-switch)"
else
    if [ ! -d "$src_dir/_opam" ] ; then
        create_opam_switch "$src_dir"
    fi

    if [ ! -d "$src_dir/_opam" ] ; then
        echo "Failed to create the opam switch"
        exit 1
    fi
fi

eval "$(opam env --shell=sh)"

# Check if the default opam repo was set in this switch
default_switch=
if opam remote -s | grep -q default ; then
  default_switch=yes
fi

# remove the default repo so install tezos dependencies
opam repository remove default > /dev/null 2>&1

if [ "$(ocaml -vnum)" != "$ocaml_version" ]; then
    # If not removed, automatically installed dependencies would be
    # (tried to be) rebuilt in their old version with the new compiler
    # while they will probably be updated (and at least reinstalled)
    # by the next steps of the script
    opam remove -a --yes
    opam install --yes --unlock-base "ocaml-base-compiler.$ocaml_version"
fi

# Must be done before install_build_deps.raw.sh because install_build_deps.raw.sh installs
# opam packages that depend on Rust.
"$script_dir"/install_build_deps.rust.sh

# Opam < 2.1 requires opam-depext as a plugin, later versions include it
# natively:
case $(opam --version) in
    2.0.* )
        opam install --yes opam-depext ;;
esac

"$script_dir"/install_build_deps.raw.sh "$1"

# add back the default repo if asked to or it was present in the first
# place.  we add the rank here even if it wasn't there just to be on
# the safe side
if [ -n "$default_switch" ] || [ -n "$dev" ]; then
    opam remote add default --rank=-1 > /dev/null 2>&1 || true
fi

# install dev dependencies if asked
if [ -n "$dev" ]; then
    # Note: ocaml-lsp-server.1.6.0 dependencies are not constrained
    # enough (for [ppx_yojson_conv_lib] in particular), so we add a
    # minimal bound to ensure it won’t be picked by opam.
    opam install --yes merlin odoc utop ocp-indent "ocaml-lsp-server>=1.6.1" js_of_ocaml-compiler --criteria="-changed,-removed"
fi

"$script_dir"/install_sapling_parameters.sh
