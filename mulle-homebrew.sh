#! /usr/bin/env bash
#
#   Copyright (c) 2017 Nat! - Mulle kybernetiK
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are met:
#
#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
#   Neither the name of Mulle kybernetiK nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#   POSSIBILITY OF SUCH DAMAGE.
#


get_class_from_name()
{
   local name="$1"

   local formula

   ## formula is dervied from name, which is rbfile w/o extension

   formula="$(tr '-' ' ' <<< "${name}")"

   (

      local i
      local tmp
      local result

      IFS=" "
      for i in $formula
      do
         if [ ! -z "$i" ]
         then
            tmp="$(tr '[A-Z]' '[a-z]' <<< "${i}")"
            tmp="$(tr '[a-z]' '[A-Z]' <<< "${tmp:0:1}")${tmp:1}"
            result="${result}${tmp}"
         fi
      done
      echo "${result}"
   )
}


generate_brew_formula_header()
{
   local project="$1"
   local name="$2"
   local version="$3"
   local homepage="$4"
   local desc="$5"
   local archiveurl="$6"

   [ -z "${version}" ]    && internal_fail "empty version"
   [ -z "${archiveurl}" ] && internal_fail "empty archiveurl"

   local tmparchive

   tmparchive="/tmp/${project}-${version}-archive"

   if [ -z "${USE_CACHE}" -a -f "${tmparchive}" ]
   then
      exekutor rm "${tmparchive}" || fail "could not delete old \"${tmparchive}\""
   fi

   if [ ! -f "${tmparchive}" ]
   then
      log_verbose "Downloading \"${archiveurl}\" to \"${tmparchive}\"..."

      exekutor curl -L -o "${tmparchive}" "${archiveurl}"
      if [ -z "${MULLE_FLAG_EXEKUTOR_DRY_RUN}" ]
      then
         if [ $? -ne 0 -o ! -f "${tmparchive}"  ]
         then
            fail "Download failed"
         fi
      fi
   else
      echo "Using cached file \"${tmparchive}\" instead of downloading again" >&2
   fi

   #
   # anything less than 2 KB is wrong
   #
   size="`exekutor du -k "${tmparchive}" | exekutor awk '{ print $ 1}'`"
   if [ -z "${MULLE_FLAG_EXEKUTOR_DRY_RUN}" ]
   then
      if [ "$size" -lt "${ARCHIVE_MINSIZE:-2}" ]
      then
         echo "Archive truncated or missing" >&2
         cat "${tmparchive}" >&2
         rm "${tmparchive}"
         exit 1
      fi
   fi

   local hash

   hash="`exekutor shasum -p -a 256 "${tmparchive}" | exekutor awk '{ print $1 }'`"
   log_verbose "Calculated shasum256 \"${hash}\" for \"${tmparchive}\"."

   local formula

   formula="`get_class_from_name "${name}"`"

   ##
   ##

   local lines

   lines="`cat <<EOF
class ${formula} < Formula
${INDENTATION}desc "${desc}"
${INDENTATION}homepage "${homepage}"
${INDENTATION}url "${archiveurl}"
${INDENTATION}sha256 "${hash}"
EOF
`"

   line="version \"${version}\""
   if fgrep -s "${version}" <<< "${archiveurl}" > /dev/null
   then
      line="# ${line}"
   fi

   lines="${lines}
${INDENTATION}${line}"
   exekutor echo "${lines}"
}


_print_dependencies()
{
   local dependencies="$1"
   local epilog="$2"

   local lines
   local line

   IFS="
"
   for dependency in ${dependencies}
   do
      IFS="${DEFAULT_IFS}"
      dependency="`eval echo "${dependency}"`"

      line="${INDENTATION}depends_on \"${dependency}\"${epilog}"

      # initial LF is liked
      lines="${lines}
${line}"
   done
   IFS="${DEFAULT_IFS}"

   if [ ! -z "${lines}" ]
   then
      exekutor echo "${lines}"
   fi
}


generate_brew_formula_dependencies()
{
   local dependencies="$1"
   local builddependencies="$2"

   if [ ! -z "${dependencies}" ]
   then
      _print_dependencies "${dependencies}"
   fi

   if [ ! -z "${builddependencies}" ]
   then
      _print_dependencies "${builddependencies}" " => :build"
   fi
}


generate_brew_formula_xcodebuild()
{
   local project="$1"; shift
   local name="$1" ; shift
   local version="$1" ; shift
   local configuration="${1:-Release}" ; [ $# -ne 0 ] && shift

   local aux_args
   local option

   for option in "$@"
   do
      aux_args="\"${option}\", ${aux_args}"
   done

   local lines

   lines="`cat <<EOF

${INDENTATION}def install
${INDENTATION}${INDENTATION}system "xcodebuild", "-configuration", "${configuration}", \
"DSTROOT=#{prefix}",${aux_args} "install"
${INDENTATION}end
EOF
`"
   exekutor echo "${lines}"
}


generate_brew_formula_mulle_build()
{
   local project="$1"; shift
   local name="$1" ; shift
   local version="$1" ; shift

   local aux_args
   local option

   for option in "$@"
   do
      aux_args=" ,${aux_args}\"${option}\""
   done

   local lines

   lines="`cat <<EOF

${INDENTATION}def install
${INDENTATION}${INDENTATION}system "mulle-install", "-vvv", "--prefix", prefix, "--homebrew"${aux_args}
${INDENTATION}end
EOF
`"
   exekutor echo "${lines}"
}


generate_brew_formula_mulle_test()
{
   local project="$1"; shift
   local name="$1" ; shift
   local version="$1" ; shift

   local aux_args
   local option

   for option in "$@"
   do
      aux_args=" ,${aux_args}\"${option}\""
   done

   local lines

   lines="`cat <<EOF

${INDENTATION}test do
${INDENTATION}${INDENTATION}if File.directory? 'tests'
${INDENTATION}${INDENTATION}${INDENTATION}system "mulle-test", "-vvv", "--fast-test"
${INDENTATION}${INDENTATION}end
${INDENTATION}end
EOF
`"
   exekutor echo "${lines}"
}


generate_brew_formula_footer()
{
   local name="$1"

   local lines

   lines="`cat <<EOF
end
# FORMULA ${name}.rb
EOF
`"
   exekutor echo "${lines}"
}


_generate_brew_formula()
{
   local project="$1"
   local name="$2"
   local version="$3"
   local dependencies="$4"
   local builddependencies="$5"
   local homepage="$6"
   local desc="$7"
   local archiveurl="$8"

   generate_brew_formula_header "${project}" "${name}" "${version}" \
                                "${homepage}" "${desc}" "${archiveurl}"  &&
   generate_brew_formula_dependencies "${dependencies}" "${builddependencies}" &&
   generate_brew_formula_build "${project}" "${name}" "${version}" "${dependencies}" &&
   generate_brew_formula_footer "${name}"
}


formula_push()
{
   local rbfile="$1" ; shift
   local version="$1" ; shift
   local name="$1" ; shift
   local homebrewtap="$1" ; shift

   HOMEBREW_TAP_BRANCH="${HOMEBREW_TAP_BRANCH:-master}"
   HOMEBREW_TAP_REMOTE="${HOMEBREW_TAP_REMOTE:-origin}"

   log_info "Push brew fomula \"${rbfile}\" to \"${HOMEBREW_TAP_REMOTE}\""
   (
      exekutor cd "${homebrewtap}" &&
      exekutor git add "${rbfile}" &&
      exekutor git commit -m "${version} release of ${name}" "${rbfile}" &&
      exekutor git push "${HOMEBREW_TAP_REMOTE}" "${HOMEBREW_TAP_BRANCH}"
   )  || exit 1
}


#
# the caller won't know how many options have been consumed
#
homebrew_parse_options()
{
   OPTION_NO_FORMULA="NO"

   while [ $# -ne 0 ]
   do
      case "$1" in
         -v|--verbose)
            GITFLAGS="`concat "${GITFLAGS}" "-v"`"
            MULLE_FLAG_LOG_VERBOSE="YES"
         ;;

         -vv)
            GITFLAGS="`concat "${GITFLAGS}" "-v"`"
            MULLE_FLAG_LOG_FLUFF="YES"
            MULLE_FLAG_LOG_VERBOSE="YES"
            MULLE_FLAG_LOG_EXEKUTOR="YES"
         ;;

         -vvv)
            GITFLAGS="`concat "${GITFLAGS}" "-v"`"
            MULLE_TEST_TRACE_LOOKUP="YES"
            MULLE_FLAG_LOG_FLUFF="YES"
            MULLE_FLAG_LOG_VERBOSE="YES"
            MULLE_FLAG_LOG_EXEKUTOR="YES"
         ;;

         -f)
            MULLE_TEST_IGNORE_FAILURE="YES"
         ;;

         -n|--dry-run)
            MULLE_FLAG_EXEKUTOR_DRY_RUN="YES"
         ;;

         -s|--silent)
            MULLE_FLAG_LOG_TERSE="YES"
         ;;

         -t|--trace)
            set -x
         ;;

         -te|--trace-execution)
            MULLE_FLAG_LOG_EXEKUTOR="YES"
         ;;

         # single arg long (kinda lame)
         -cache)
            USE_CACHE="YES"
         ;;

         -echo)
            OPTION_ECHO="YES"
         ;;

         -no-formula)
            OPTION_NO_FORMULA="YES"
         ;;

         -no-push|-no-tap-push)
            OPTION_NO_TAP_PUSH="YES"
         ;;

         # arg long

         --bootstrap-tap)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            BOOTSTRAP_TAP="$1"
         ;;

         --branch)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            BRANCH="$1"
         ;;

         --dependency-tap)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            DEPENDENCY_TAP="$1"
         ;;

         --github)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            GITHUB="$1"
         ;;

         --homepage-url)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            HOMEPAGE_URL="$1"
         ;;

         --origin)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            ORIGIN="$1"
         ;;

         --publisher)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            PUBLISHER="$1"
         ;;

         --publisher-tap)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            PUBLISHER_TAP="$1"
         ;;

         --tag)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            TAG="$1"
         ;;

         --tag-prefix)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            TAG_PREFIX="$1"
         ;;

         --taps-location)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""
            shift
            TAPS_LOCATION="$1"
         ;;

            # allow user to specify own parameters for his
            # generate_formula scripts w/o having to modify this file
         --*)
            [ $# -eq 1 ] && fail "missing parameter for \"$1\""

            varname="`sed 's/^..//' <<< "$1"`"
            varname="`tr '-' '_' <<< "${varname}"`"
            varname="`tr '[a-z]' '[A-Z]' <<< "${varname}"`"
            if ! egrep -q -s '^[A-Z_][A-Z0-9_]*$' <<< "${varname}" > /dev/null
            then
               fail "invalid variable specification \"${varname}\", created by \"$1\""
            fi

            shift
            eval "${varname}='$1'"
            log_info "User variable ${varname} set to \"$1\""
         ;;

         -*)
            log_error "unknown option \"$1\""
            exit 1
         ;;
      esac

      shift
   done
}


homebrew_is_compatible_version()
{
   local installed="$1"
   local script="$2"

   local s_major
   local s_minor
   local i_major
   local i_minor

   s_major="`echo "${script}"    | head -1 | cut -d. -f1`"
   s_minor="`echo "${script}"    | head -1 | cut -d. -f2`"
   i_major="`echo "${installed}" | head -1 | cut -d. -f1`"
   i_minor="`echo "${installed}" | head -1 | cut -d. -f2`"

   if [ "${i_major}" = "" -o "${i_minor}" = "" -o \
        "${s_major}" = "" -o "${s_minor}" = "" ]
   then
      return 2
   fi

   if [ "${i_major}" != "${s_major}" ]
   then
      return 1
   fi

   if [ "${i_minor}" -lt "${s_minor}" ]
   then
      return 1
   fi

   return 0
}


homebrew_main()
{
   local project="$1" ; shift
   local name="$1"; shift
   local version="$1"; shift
   local dependencies="$1"; shift
   local builddependencies="$1"; shift
   local homepage="$1"; shift
   local desc="$1"; shift
   local archiveurl="$1"; shift
   local homebrewtap="$1"; shift
   local rbfile="$1"; shift

   local formula
# DESC must not be empty
   [ -z "${desc}" ]  && fail "DESC is empty"

   [ "${OPTION_NO_FORMULA}" = "YES" ] && return

   [ -z "${project}" ]     && internal_fail "missing project"
   [ -z "${name}" ]        && internal_fail "missing name"
   [ -z "${version}" ]     && internal_fail "missing version"
   [ -z "${homepage}" ]    && internal_fail "missing homepage"
   [ -z "${archiveurl}" ]  && internal_fail "missing archiveurl"
   [ -z "${homebrewtap}" ] && internal_fail "missing homebrewtap"
   [ -z "${rbfile}" ]      && internal_fail "missing rbfile"


   [ ! -d "${homebrewtap}" ] && fail "Failed to locate tap directory \"${homebrewtap}\" from \"$PWD\""

   log_info "Generate brew fomula \"${homebrewtap}/${rbfile}\""

   log_fluff "project           = ${C_RESET}${project}"
   log_fluff "name              = ${C_RESET}${name}"
   log_fluff "version           = ${C_RESET}${version}"
   log_fluff "homepage          = ${C_RESET}${homepage}"
   log_fluff "desc              = ${C_RESET}${desc}"
   log_fluff "archiveurl        = ${C_RESET}${archiveurl}"
   log_fluff "dependencies      = ${C_RESET}${dependencies}"
   log_fluff "builddependencies = ${C_RESET}${builddependencies}"

   formula="`generate_brew_formula "${project}" \
                                   "${name}" \
                                   "${version}" \
                                   "${dependencies}" \
                                   "${builddependencies}" \
                                   "${homepage}" \
                                   "${desc}" \
                                   "${archiveurl}"`" || exit 1

   if [ "${OPTION_ECHO}" ]
   then
      echo "${formula}"
      return
   fi

   redirect_exekutor "${homebrewtap}/${rbfile}" echo "${formula}"

   if [ "${OPTION_NO_TAP_PUSH}" != "YES" ]
   then
      formula_push "${rbfile}" "${version}" "${name}" "${homebrewtap}"
   fi
}


homebrew_initialize()
{
   local directory

   if [ -z "${MULLE_EXECUTABLE_PID}" ]
   then
      MULLE_EXECUTABLE_PID=$$

      if [ -z "${DEFAULT_IFS}" ]
      then
         DEFAULT_IFS="${IFS}"
      fi

      INDENTATION="  "  # ruby fascism

      directory="`mulle-bootstrap library-path 2> /dev/null`"
      [ ! -d "${directory}" ] && echo "Failed to locate mulle-bootstrap library. https://github.com/mulle-nat/mulle-bootstrap" >&2 && exit 1
      PATH="${directory}:$PATH"

      [ -z "${MULLE_BOOTSTRAP_LOGGING_SH}" ]   && . mulle-bootstrap-logging.sh
      [ -z "${MULLE_BOOTSTRAP_FUNCTIONS_SH}" ] && . mulle-bootstrap-functions.sh
      [ -z "${MULLE_BOOTSTRAP_ARRAY_SH}" ]     && . mulle-bootstrap-array.sh
  fi
}

homebrew_initialize

:
