#! /usr/bin/env bash
#    _       _  o         
#  __)) ___  )) _  ___  __
# ((_( ((_( (( (( ((_( _))
#
# Copyright (C) 2022, Stéphane MEYER.
#
# Dalias is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>
#
# DALIAS
# C : 2021/04/19
# M : 2023/03/12
# D : Dynamic aliases.

# TODO: Add optional description for dynamic aliases,
#       --desc

declare __version="0.2.1"

declare ALIASDIR="$HOME/.config/dalias/aliases"
declare BINDIR="$HOME/.local/bin"

_help() {
cat << HELP
dalias: version ${__version}.
Dynamic aliases.

Commands:
  dalias                                   - reads from standard input.
  dalias do <name> '<command> [arguments]' - create/replace.
  dalias ed <name>                         - edit.
  dalias cp <name> <newname>               - copy.
  dalias mv <name> <newname>               - rename.
  dalias rm <name>                         - delete.
  dalias dp <file>                         - dump existing aliases in a file.
  dalias ls [name|glob]                    - print aliases list.
  dalias fix                               - search and fix missing links.
  dalias help                              - show this help and exit.
  dalias version                           - show program version and exit.

HELP
}

_msg() {
  # error/message display.

  local _type msg

  case $1 in
    E) _type="error: "; msg="$2" ;;   # error
    W) _type="warning: "; msg="$2" ;; # warning
    M) msg="$2"                       # message
  esac

  case $1 in
    E | W ) >&2 echo "${_type}${msg}" ;;
        M ) echo "$msg"
  esac
}

confirm() {
  # ask user for confirmation.

  local prompt
  prompt="${1:-"sure?"}"

  printf "%s [y/N]: " "$prompt"
  read -r
  [[ ${REPLY,,} == "y" ]] && return 0
  return 1
}

do_alias() {
  # create/modify given dynamic alias
  
  local name cmd
  name=$1; shift
  cmd=("$@")

  [[ ! $name || ! ${cmd[*]} ]] && {
    _msg E "missing parameters."
    return 1
  }

  # does alias already exist?
  local _alias
  _alias="$(which "$name" 2> /dev/null)" && {
    if [[ $(readlink -f "$_alias") =~ \.da$ ]]; then
      [[ $NOCONFIRM ]] && {
        _msg M "skipped: $name already exists."
        return 0
      }
      _msg W "a dynamic alias named '${name}' already exists."
      confirm "overwrite?" || return 1
      local FORCE=1
    else
      _msg E "'${name}' found in ${_alias}."
      return 1
    fi
  }

  [[ -d $ALIASDIR ]] ||
    mkdir -p "$ALIASDIR"

  local da
  da="$ALIASDIR/${name}.da"

  local script

read -d "" -r script <<- DALIAS
#! /usr/bin/env sh
${cmd[@]}
DALIAS

  echo -e "$script" > "$da"
  chmod 700 "$da"

  [[ $FORCE ]] && rm "${BINDIR}/${name}"
  ln -s "$da" "${BINDIR}/${name}" &&
    _msg M "${name}: dynamic alias created."
}

ed_alias() {
  local name
  name="$1"

  [[ $name ]] || {
    _msg E "dynamic alias name missing."
    return 1
  }

  local da
  da="${ALIASDIR}/${name}.da"

  if [[ -a $da ]]; then
    [[ $EDITOR ]] || {
      _msg E "EDITOR environment variable not set."
      return 1
    }
    "${EDITOR}" "$da"
  else
    _msg E "${name}: no such dynamic alias."
    return 1
  fi
}

op_alias() {
  local cmd from to msg
  cmd=$1; shift
  from="$1"
  to="$2"

  [[ ! $from || ! $to ]] && {
    _msg E "missing parameters."
    return 1
  }

  which "$to" &> /dev/null && {
    _msg E "${to} is an existing command/alias."
    return 1
  }

  local alias_src link_src
  alias_src="${ALIASDIR}/${from}.da"
  link_src="${BINDIR}/${from}"

  if [[ -a $alias_src ]] && [[ -L $link_src ]]; then
    local alias_dst link_dst
    alias_dst="${ALIASDIR}/${to}.da"
    link_dst="${BINDIR}/${to}"

    "$cmd" "$alias_src" "$alias_dst" 2> /dev/null || {
      [[ $cmd  == "cp" ]] && msg="copy"
      [[ $cmd  == "mv" ]] && msg="rename"
      _msg E "${from} -> ${to}: could not ${msg}."
      return 1
    }

    [[ $cmd == "mv" ]] && rm "$link_src"
    ln -s "$alias_dst" "$link_dst" && {
      [[ $cmd  == "cp" ]] && msg="copied"
      [[ $cmd  == "mv" ]] && msg="renamed"
      _msg M "${from} -> ${to}: dynamic alias ${msg}."
    }
  else
    _msg E "no such dynamic alias: ${from}."
    return 1
  fi
}

rm_alias() {
  [[ $1 ]] && {
    local name dst link
    name="$1"
    dst="${ALIASDIR}/${name}.da"
    link="${BINDIR}/${name}"

    [[ -a $dst ]] || {
      _msg E "${name}: no such alias."
      return 1
    }
    [[ $NOCONFIRM ]] || {
      confirm "warning: delete '${name}' dynamic alias?" || return 1
    }

    rm "$link" 2> /dev/null
    rm "$dst" 2> /dev/null || {
      _msg E "${name}: could not delete dynamic alias"
      return 1
    }
    _msg M "${name}: dynamic alias deleted."
    return 0
  }
  _msg E "dynamic alias name missing."
}

ls_alias() {
  local _alias name cmd

  [[ $1 == "-d" ]] && { shift; local DUMP=1; }
  
  [[ $1 ]] && _alias="$1" || _alias="*"

  compgen -G "${ALIASDIR}/${_alias}.da" &> /dev/null || {
    >&2 echo "no result."
    return 1
  }
  
  for f in "${ALIASDIR}"/${_alias}.da; do
    name="$(basename "${f%*.da}")"
    while read -r; do
      [[ $REPLY =~ ^#.+$ ]] && continue
      cmd="$REPLY"
    done < "$f"
    if [[ $DUMP ]]; then
      printf "do %s %s\n" "$name" "$cmd"
    else
      printf "%s=%s\n" "$name" "$cmd"
    fi
  done
}

dp_alias() {
  # dump existing dynamic aliases into a file.

  [[ $1 ]] || {
    _msg E "filename missing."
    return 1
  }

  [[ -a "$1" ]] && {
    _msg W "$1 already exists,"
    confirm "overwrite?" || return 1
  }

  ls_alias -d > "$1"

  _msg M "done."
}

fix_aliases() {
  # search and fix missing alias links.
  local f name count=0
  for f in ${ALIASDIR}/*.da; do
    name="$(basename $f)"
    name="${name//.da}"
    which "${BINDIR}/${name}" &> /dev/null || {
      ln -s "$f" "${BINDIR}/${name}" && {
        _msg M "${name}: missing [fixed]"
        ((count++))
    }
  }
  done
  ((count)) &&
    _msg M "fixed $((count)) links."
  ((count)) ||
    _msg M "nothing to do."
}

if (( $# > 0 )); then
  case $1 in
    do     ) shift; do_alias "$@" ;;
    ed     ) shift; ed_alias "$@" ;;
    cp     ) shift; op_alias "cp" "$@" ;;
    mv     ) shift; op_alias "mv" "$@" ;;
    rm     ) shift; rm_alias "$@" ;;
    dp     ) shift; dp_alias "$@" ;;
    ls     ) shift; ls_alias "$@" ;;
    fix    ) shift; fix_aliases   ;;
    help   ) _help ;;
    version) _msg M "dalias version ${__version}." ;;
    *      ) _msg E "invalid command: $1"; exit 1
  esac
else
  NOCONFIRM=1
  LINE=0
  while IFS= read -r; do
    ((++LINE))

    # ignore comments, dp, ed, ls and help commands...
    [[ $REPLY =~ ^#.*$ ]] && continue
    [[ $REPLY =~ ^cp.*$ ]] && continue
    [[ $REPLY =~ ^mv.*$ ]] && continue
    [[ $REPLY =~ ^ed.*$ ]] && continue
    [[ $REPLY =~ ^dp.*$ ]] && continue
    [[ $REPLY =~ ^ls.*$ ]] && continue
    [[ $REPLY =~ ^help.*$ ]] && continue
    [[ $REPLY =~ ^fix.*$ ]] && continue

    mapfile -t arglist <<< "${REPLY// /$'\n'}"
    set -- "${arglist[@]}"
    echo -n "${1}: "
    case $1 in
      do) shift; do_alias "$@" || { _msg E "on line ${LINE}."; } ;;
      rm) shift; rm_alias "$@" || { _msg E "on line ${LINE}."; } ;;
      * ) _msg E "invalid command: ${1} (line ${LINE})."; exit 1
    esac
  done
fi
