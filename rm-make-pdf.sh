#!/bin/bash
#
# rm-make-pdf
# John Simpson <jms1@jms1.net> 2023-08-13
# Giorgos Keramidas <gkeramidas@gmail.com> 2025-09-07
#
# 2025-04-19 gkeramidas - enable ligatures, typographically 'prettier'
#	characters, and auto-hyphenation.
#
# 2025-06-12 gkeramidas - switch to 'Source (Sans|Serif|Code) Pro'
#	fonts, which look nice and readable, but not as heavy-weight as
#	Bookerly or Literata.
#
# 2025-04-19 gkeramidas - bump base font size to 20, and scale page by
#	2x in every devicepixel dimension, to allow 'smoother' font size
#	changes, because with actual 1x1 pixel size, 11pt looks too
#	small, 12pt is too large, and ebook-convert unfortunately
#	doesn't like float args for base font size.
#
# 2025-03-07 gkeramidas - add support for dynamically scaling all sizes
#	of --font-size-mapping, based on -s argument, so that 'x-small'
#	and similar CSS font-size options DTRT, when the base font size
#	changes from 12pt.
#
# John Simpson <jms1@jms1.net> 2023-08-13
#
# Use Calibre's "ebook-convert" to convert an input file to a PDF, using
# settings that I think look good on a reMarkable 2 tablet.
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
###############################################################################
#
# The MIT License (MIT)
#
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
###############################################################################

########################################
# Possible locations for the 'ebook-convert' executable. The first of these
# which exists will be used.

EBC_MAYBE="
/Applications/calibre.app/Contents/MacOS/ebook-convert
/opt/calibre/ebook-convert
/usr/local/bin/ebook-convert
/usr/bin/ebook-convert
"

###############################################################################
#
# usage

function usage {
    MSG="${1:-}"

    cat <<EOF
$0 [options] INFILE [OUTFILE]

Use Calibre's 'ebook-convert' to convert an input file to a PDF, using
settings that I think look good on a reMarkable 2 tablet.

-a ___  Specify the author in the PDF's metadata.

-j ___  Change justification to 'left', or 'justify'. Default: 'justify'.

-m ___  Specify the minimum line-height percentage (default: 160).
        To achieve "double spaced" text, set to 240.

-p      For input documents which have "H1" section headers (HTML, Markdown,
        etc.) start a new page for each H1 section.

-s ___  Specify the document's base font size. Default is 13.

-t ___  Specify the title in the PDF's metadata.

-x      Enable tracing of the bash commands run by the script.
        Default: off.

If the input file has metadata, the '-t' and '-a' options will override the
values from the input file.

If OUTFILE is specified, it must end with '.pdf'.

EOF

    if [[ -n "$MSG" ]]
    then
        echo "$MSG"
        exit 1
    fi

    exit 0
}

###############################################################################
###############################################################################
###############################################################################
#
# Process the command line

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
        h)  usage
            ;;
        x)  SET_X=true
            ;;
        t)  TITLE="$OPTARG"
            ;;
        a)  AUTHOR="$OPTARG"
            ;;
        s)  SIZE="$OPTARG"
            ;;
        m)  SPACE="$OPTARG"
            ;;
        j)  JUSTIFY="$OPTARG"
            ;;
        p)  H1_NO_SPLIT=false
            ;;
        *)  usage "ERROR: unknown option '-$OPTARG'"
            ;;
    esac
done
shift $((OPTIND-1))

########################################
# Get the input filename

INFILE="${1:-}"
if [[ -z "$INFILE" ]]
then
    usage
fi

OUTFILE="${2:-.pdf}"
if [[ ! "$OUTFILE" =~ \.pdf$ ]]
then
    usage "ERROR: output filename must end with '.pdf'"
fi

########################################
# Find the 'ebook-convert' executable

for X in $EBC_MAYBE
do
    if [[ -x "$X" ]]
    then
        EBOOK_CONVERT="$X"
        continue
    fi
done

if [[ -z "$EBOOK_CONVERT" ]]
then
    echo "ERROR: unable to locate 'ebook-convert' executable, cannot continue"
    exit 1
fi

########################################
# Build a string containing options which may or may not need to be included
# in the final 'ebook-convert' command line.

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

if $H1_NO_SPLIT
then
    OPTA+=( '--page-breaks-before' '/' )
    OPTA+=( '--chapter' '/' )
fi

###############################################################################
# Compute afont-size mapping list.  This is computed by figuring out the ratio
# of the currently specified $SIZE to '20' pt (default size), and then scaling
# all other sizes of the default font-size mapping by the same ratio, but also
# rounding any fractional sizes to 2 decimal places with bc(1).
###############################################################################

_ratio="$( echo "r($SIZE / 20, 2)" | bc -l )"
echo "Font scaling ratio: $_ratio"
_font_map=""
for _map in '8.40' '11.60' '15.00' '20.00' '22.50' '28.40' '33.50' '36.80' '40.00' ; do
    _scaled="$( echo "r( ${_map} * ${_ratio}, 2)" | bc -l )"
    _font_map="${_font_map} ${_scaled}"
done
_font_map_option="$(
    echo "${_font_map}"					| \
    expand						| \
    sed -e 's/^ *//' -e 's/ *$//' -e 's/  */, /g'
)"

###############################################################################
#
# Do the deed
#
# 'ebook-convert' command line option reference:
#   https://manual.calibre-ebook.com/generated/en/ebook-convert.html

if $SET_X
then
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
    --pdf-page-margin-top           112                                  \
    --pdf-page-margin-bottom        104                                  \
                                                                         \
    --minimum-line-height           $SPACE                               \
    --change-justification          $JUSTIFY                             \
    --smarten-punctuation                                                \
    --pdf-hyphenate                                                      \
    ;
