#!/bin/bash
#
# rm-make-pdf
# John Simpson <jms1@jms1.net> 2023-08-13
# Giorgos Keramidas <gkeramidas@gmail.com> 2025-09-07
#
# 2025-04-19 gkeramidas - enable ligatures, typographically 'prettier'
#   characters, and auto-hyphenation.
#
# 2025-06-12 gkeramidas - switch to 'Source (Sans|Serif|Code) Pro'
#   fonts, which look nice and readable, but not as heavy-weight as
#   Bookerly or Literata.
#
# 2025-04-19 gkeramidas - bump base font size to 20, and scale page by
#   2x in every devicepixel dimension, to allow 'smoother' font size
#   changes, because with actual 1x1 pixel size, 11pt looks too
#   small, 12pt is too large, and ebook-convert unfortunately
#   doesn't like float args for base font size.
#
# 2025-03-07 gkeramidas - add support for dynamically scaling all sizes
#   of --font-size-mapping, based on -s argument, so that 'x-small'
#   and similar CSS font-size options DTRT, when the base font size
#   changes from 12pt.
#
# John Simpson <jms1@jms1.net> 2023-08-13
#
# Use Calibre's "ebook-convert" to convert an input file to a PDF, using
# settings that I think look good on a reMarkable Paper Pro tablet.
#
# Requirements:
# - OS: macOS or Linux. This *might* also work on windows, if you install
#   whatever "Linux-ish" things you need to run it on.
# - Calibre.
#   https://calibre-ebook.com/
# - reMarkable tablet, or some other device or program to view the resulting
#   PDF file with.
#   https://remarkable.com/
#
# 2023-08-15 jms1 - fixed handling of title/author values containing spaces
#
# 2023-09-10 jms1 - show usage message if no input filename
#

# Copyright (C) 2025 Giorgos Keramidas
# Copyright (C) 2023 John Simpson
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the “Software”),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

#
# checkyesno var
#       Test $1 variable, and warn if not set to YES or NO.
#       Return 0 if it's "yes" (et al), nonzero otherwise.
#
checkyesno()
{
    eval _value=\$${1}
    case $_value in

    #   "yes", "true", "on", or "1"
    [Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
        return 0
        ;;

    #   "no", "false", "off", or "0"
    [Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0)
        return 1
        ;;

    *)
        warn "\$${1} is not set properly - see rc.conf(5)."
        return 1
        ;;

    esac
}


#
# err exitval message
#
# Display message to stderr and log to the syslog, and exit with exitval.
#
err()
{
    exitval=$1
    shift

    echo 1>&2 "$0: ERROR: $*"
    exit $exitval
}

#
# locate_ebook_convert
#
# Locate the binary of 'book-convert', by checking a number of paths which
# make sense on macOS, Linux, BSD, etc.
#

function locate_ebook_convert {
    EBC_LOCATIONS=()
    EBC_LOCATIONS+=('/Applications/calibre.app/Contents/MacOS/ebook-convert')
    EBC_LOCATIONS+=('/opt/calibre/ebook-convert')
    EBC_LOCATIONS+=('/usr/local/bin/ebook-convert')
    EBC_LOCATIONS+=('/usr/bin/ebook-convert')

    for _exe in "${EBC_LOCATIONS[@]}"; do
        if [ -x "${_exe}" ]; then
            echo "${_exe}"
            return 0
        fi
    done
}

#
# usage
#       Print a basic usage message, and explain how to run this script, how
#       to print detailed help, and exit. This is the minimal usage message we
#       print when the script is run without any arguments.
#
#       Optionally append a custom error message to the help summary.
#

function usage {
    local _message="$*"
    local _script="$(basename "$0")"
    
    cat <<EOF
${_script} [options] INFILE [OUTFILE]

Use Calibre's 'ebook-convert' to convert an input file to a PDF, using
settings that I think look good on a reMarkable Paper Pro tablet.

(Use '${_script} -h' for a detailed list of all options.)
EOF
    if [ -n "${_message}" ]; then
        err 72 "${_message}"            # EX_USAGE (72)
    fi
    exit 0
}

#
# help
#       Print a detailed help message, with all CLI options, their acceptable
#       arguments, default values, etc.  This is what -h option triggers.
#
function help {
    local _script="$(basename "$0")"

    cat <<EOF
${_script} [options] INFILE [OUTFILE]

Use Calibre's 'ebook-convert' to convert an input file to a PDF, using
settings that I think look good on a reMarkable Paper Pro tablet.

-a AUTHOR   Specify the author in the metadata of the output PDF.

-j JUSTIFY  Change justification of lines of text in the PDF.
            Can be set to one of: 'original', 'left', or 'justify'.
            Default: 'justify'

-m NUM      Specify the minimum line-height as a percentage of the default
            line height. To achieve "double spaced" text, try setting this
            to 240. Default: 160

-p          For input documents which have "H1" section headers (e.g.
            HTML, Markdown, etc.) start a new page for each H1 section.

-s SIZE     Specify the document's base font size. Default: 20

-t TITLE    Specify the title in the metadata of the output PDF.

-x          Enable tracing of the bash commands run by the script.
            Default: off.

Note:

  * If the input file has metadata, the '-t' and '-a' options will
    override the values from the input file.

  * If OUTFILE is specified, it must end with '.pdf'.

EOF
    exit 0
}

#
# Process the command line
#
if [ $# -eq 0 ]; then
    usage
fi

SET_X=false
TITLE=''
AUTHOR=''
SIZE='20'
SPACE=160
JUSTIFY='justify'
H1_NO_SPLIT=true

while getopts 'a:hj:m:ps:t:x' OPT
do
    case $OPT in
        h)
            help
            ;;
        x)
            SET_X=true
            ;;
        t)
            TITLE="$OPTARG"
            ;;
        a)
            AUTHOR="$OPTARG"
            ;;
        s)
            SIZE="$OPTARG"
            ;;
        m)
            SPACE="$OPTARG"
            ;;
        j)
            JUSTIFY="$OPTARG"
            ;;
        p)
            H1_NO_SPLIT=false
            ;;
        \?)
            echo ''
            usage
            ;;
    esac
done
shift $((OPTIND-1))

#
# Get the input and output filenames.
#

INFILE="${1:-}"
if [[ -z "$INFILE" ]]
then
    usage
fi

OUTFILE="${2:-.pdf}"
if [[ ! "$OUTFILE" =~ \.pdf$ ]]
then
    usage "output filename must end with '.pdf'"
fi


#
# Build a string containing options which may or may not need to be included
# in the final 'ebook-convert' command line.
#
#
# Array of options
OPTA=()

if [[ -n "$TITLE" ]]
then
    OPTA+=( '--title' )
    OPTA+=( "$TITLE" )
fi

if [[ -n "$AUTHOR" ]]
then
    OPTA+=( '--authors' )
    OPTA+=( "$AUTHOR" )
fi

if checkyesno H1_NO_SPLIT ; then
    OPTA+=( '--page-breaks-before' '/' )
    OPTA+=( '--chapter' '/' )
fi

#
# Compute a font-size mapping list.  This is computed by figuring out the
# ratio of the currently specified $SIZE to '20' pt (default size), and then
# scaling all other sizes of the default font-size mapping by the same ratio,
# but also rounding any fractional sizes to 2 decimal places with bc(1).
#

_ratio="$( echo "r($SIZE / 20, 2)" | bc -l )"
echo "Font scaling ratio: $_ratio"
_font_map=""
for _map in '8.40' '11.60' '15.00' '20.00' '22.50' '28.40' '33.50' '36.80' '40.00' ; do
    _scaled="$( echo "r( ${_map} * ${_ratio}, 2)" | bc -l )"
    _font_map="${_font_map} ${_scaled}"
done
_font_map_option="$(
    echo "${_font_map}"                     | \
    expand                      | \
    sed -e 's/^ *//' -e 's/ *$//' -e 's/  */, /g'
)"

# Find the 'ebook-convert' executable.  This is the last point where we
# can defer this, since we have to run it very soon.
EBOOK_CONVERT=$( locate_ebook_convert )
if [ -z "${EBOOK_CONVERT}" ]; then
    err 69 "Could not locate 'ebook-convert' binary."
fi

#
# Run the actual ebook conversion process.
#
# 'ebook-convert' command line option reference:
# https://manual.calibre-ebook.com/generated/en/ebook-convert.html
#

if checkyesno SET_X ; then
    set -x
fi

"$EBOOK_CONVERT" "$INFILE" "$OUTFILE"                                    \
    --input-profile                 default                              \
    --output-profile                kindle_scribe                        \
                                                                         \
    --base-font-size                $SIZE                                \
    --font-size-mapping             "${_font_map_option}"                \
    --embed-all-fonts                                                    \
    --subset-embedded-fonts                                              \
                                                                         \
    "${OPTA[@]}"                                                         \
    --custom-size                   3240x4320                            \
    --unit                          devicepixel                          \
    --preserve-cover-aspect-ratio                                        \
                                                                         \
    --pdf-sans-family               'Source Sans Pro'                    \
    --pdf-serif-family              'Source Serif Pro'                   \
    --pdf-mono-family               'Source Code Pro'                    \
    --pdf-standard-font             serif                                \
    --pdf-mono-font-size            $SIZE                                \
    --pdf-page-margin-left          96                                   \
    --pdf-page-margin-right         96                                   \
    --pdf-page-margin-top           110                                  \
    --pdf-page-margin-bottom        80                                   \
                                                                         \
    --minimum-line-height           $SPACE                               \
    --change-justification          $JUSTIFY                             \
    --smarten-punctuation                                                \
    --pdf-hyphenate                                                      \
    ;
