#!/bin/bash

# Use the passed list of lokal pom.xml (maven) files and create dependency-tree in dot format.
#
# The DOT-output will be modified (replace 'digraph' with 'subgraph') and surround by 'digraph G' and formatting information.
#
# use the DOT file like:
#   xdot --filter=dot $output_file
# or use for print on several A4 paper
#   dot -Tps2 $output_file | ps2pdf -dSAFER -dOptimize=true -sPAPERSIZE=a4 - $output_file.pdf
#
# @see: https://maven.apache.org/plugins/maven-dependency-plugin/tree-mojo.html

#set -x
input_files=('pom.xml')
output_file='dependencies.dot'
# filter for atifacts
include='de.icongmbh.*:::'

exec_mvn='mvn -B dependency:tree -DoutputType=dot -DappendOutput=true'

sed_word_pattern='a-zA-Z\_0-9.-' # \w\d.-
# "groupId:artifactId:type[:classifier]:version[:scope]" -> "artifactId:type:version"
# #1: (groupId:)
# #2: (artifactId:type[:classifier]:version)
# #3: (:scope)"
exec_sed_normalize_artifacts="sed -e 's/\"\([$sed_word_pattern]*:\)\([$sed_word_pattern]*:[$sed_word_pattern]*:[$sed_word_pattern]*\)\(\:[$sed_word_pattern]*\)*/\"\2/g'"
# rename 'digraph' into 'subgraph'
exec_sed_rename_graph="sed 's/digraph/subgraph/g'"

# remove duplicate lines but not ' }'
# @see: http://theunixshell.blogspot.de/2012/12/delete-duplicate-lines-in-file-in-unix.html
exec_awk_duplicate_lines="awk '\$0 ~ \"}\" || !x[\$0]++'"
# remove duplicate braces (' } ')
# @see: https://www.linuxquestions.org/questions/programming-9/removing-duplicate-lines-with-sed-276169/#post1400421
exec_sed_duplicate_braces_line="sed -e'\$!N; /^\(.*\)\n\1\$/!P; D'"


# filter and cut DOT output out of mvn message
exec_grep_filter_console_message='grep -E "[{;}]" | grep -v -E "[\$@]"'
exec_cut_console_message='cut -d"]" -f2'

show_help() {
cat << EOF
Usage: ${0##*/} [-hsu [-f OUTFILE] [FILE]...
Create a DOT file based on Maven dependencies (as a 'subgraph') provided by FILE.

With no FILE the default '$input_files' will be used.
    
    -h          display this help and exit
    -o OUTFILE  write the result to OUTFILE instead of '$output_file' (default).
    -s          ONLY SNAPSHOT versions
    -u          Forces a check for updated releases and snapshots on remote
                Maven repositories
    
Example: ${0##*/} \`find . -mindepth 2 -iname pom.xml | grep -v "target"\`
EOF
}

### CMD ARGS
# process command line arguments
# @see: http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash#192266
OPTIND=1         # Reset in case getopts has been used previously in the shell.
while getopts "h?vo:" opt;
do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    o)  output_file=$OPTARG
        ;;
    s)  include="$include*-SNAPSHOT"
        ;;
    u)  exec_mvn="$mvn_exec -U"
        ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift;

# use left over arguments as list of POM files
if [ "${#}" -gt "1" ];
then
  input_files=("$@")
fi
### CMD ARGS

### DEPENDENCIES
# temp. working file for collect the mvn output
temp_output_file=`tempfile -p"${0##*/}"`

counter=1
# iterate over the POM file list and exec mvn
for pom_file in "${input_files[@]}"
do
  echo "working on [$counter/${#input_files[@]}]: $pom_file"
  # -DoutputFile and -Doutput seems not work in this special behaviour :-(
  #    mvn_cmd="$exec_mvn -DoutputFile=$temp_output_file -Doutput=$temp_output_file -Dincludes=\"$include\" -f \"$pom_file\" "
  # use the console output instead
  mvn_cmd="$exec_mvn -Dincludes=\"$include\" -f\"$pom_file\" 2>&1 | $exec_grep_filter_console_message | $exec_cut_console_message"
#  echo "$mvn_cmd"
  eval $mvn_cmd >> $temp_output_file
  [[ $? -gt 0 ]] && exit $?; # check the return value
  counter=$((counter + 1))
done

if [ ! -s "$temp_output_file" ]
then
  echo "the generated dependencies file ($temp_output_file) is empty"
  exit 1
fi
### DEPENDENCIES

### CLEAN UP
echo "create: $output_file"
echo -e 'digraph G { \n ' > $output_file
echo -e '    graph [fontsize=8 fontname="Courier" compound=true];\n    node [shape=record fontsize=8 fontname="Courier"];\n    rankdir="LR";\n    page="8.3,11.7";\n ' >> $output_file
# cleanup and normalize DOT content
cmd_cleanup="$exec_sed_rename_graph $temp_output_file | $exec_sed_normalize_artifacts | $exec_awk_duplicate_lines | $exec_sed_duplicate_braces_line"
#echo "$cmd_cleanup"
eval $cmd_cleanup >> $output_file
echo '}' >> $output_file

# clean up temp. work file
# @see: http://www.linuxjournal.com/content/use-bash-trap-statement-cleanup-temporary-files
trap "rm -f $temp_output_file" EXIT

