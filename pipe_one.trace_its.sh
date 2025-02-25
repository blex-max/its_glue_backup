#!/usr/bin/env bash
#                                                                         #
#               .__  __                   .__                             #
#               |__|/  |_  ______    ____ |  |  __ __   ____              #
#               |  \   __\/  ___/   / ___\|  | |  |  \_/ __ \             #
#               |  ||  |  \___ \   / /_/  >  |_|  |  /\  ___/             #
#               |__||__| /____  >  \___  /|____/____/  \___  >            #
##                            \/  /_____/                  \/            ##
###                                                                     ###  
####         Author : Alex Byrne                                       ####    
####         Contact : ablex7@gmail.com                                ####
####                                                                   ####
####         See its_glue github for usage details.                    ####
####                                                                   ####
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

set -e

while getopts t:f:r:o:x flag
do
    case "${flag}" in
        t) trace_dir=${OPTARG};;
        f) f_tag=${OPTARG};;
        r) r_tag=${OPTARG};;
        o) out_dir=${OPTARG};;
        x) overwrite="y";; 
        
        *) echo "ERROR: invalid flag! Have you read the README?" >&2
           exit 1
           ;;
    esac
done

if [[ "$trace_dir" == "" || "$f_tag" == "" || "$r_tag" == "" ]] ; then
    echo "ERROR: flags -t, -f, and -r require arguments." >&2
    exit 1
fi

if [[ "$out_dir" == "" ]] ; then
    out_dir='.'
fi

if [[ "$overwrite" == "y" ]] ; then
    mkdir -p "$out_dir"/assembly "$out_dir"/its "$out_dir"/logs
else
    mkdir "${out_dir}"/assembly "${out_dir}"/its "${out_dir}"/logs
fi

echo "" # blank line to space output

# FIRST TIME? RUN CREATE_ENV.sh:
CONDA_BASE=$(conda info --base)
source "$CONDA_BASE/etc/profile.d/conda.sh"
if conda activate ./seq_conda ; then
    echo "activated conda env"
else 
    echo 'ERROR: conda environment not set up! Have you run CREATE_ENV.sh?' >&2
    exit 1
fi

### basecalling/assembly
# Using Tracy since 
# i) it's recent
# ii) it's expressly designed for (modern) Sanger data
# iii) I've had active discussions/collaboration from the devs

# check all filenames are unique

# assemble forward and reverse direct from traces
echo "running Tracy..."
trac_count=0
for file in "$trace_dir"/*"$r_tag"* ; do

    # take full path of file and delete all except filename
    xbase="${file##*/}"
    
    # get filename excluding primer/direction id
    code=${xbase%%"$r_tag"*}
    
    # check only a pair of files for given $code
    uchk=$(ls "$trace_dir"/"$code"* | wc -l)
    if [ "$uchk" -ne 2 ] ; then
        echo "ERROR: multiple matching filenames detected for $code" >&2
        exit 1
    fi
    
    # grab matching file
    ffile=("$trace_dir"/"$code"*"$f_tag"*)
    
    # assemble - -t 0 -q 100 -u 300 -r 100 -s 300 best so far
    if
    ./tracy/tracy consensus \
    -o "$out_dir"/assembly/"$code"_cons \
    -t 2 \
    -b "$code" \
    "$ffile" \
    "$file" \
    >> "$out_dir"/logs/basecall_log.txt 2>&1
    then

    trac_count=$((trac_count + 1))

    else
    echo "assembly failure for $code!"
    
    fi

done


if [ "$trac_count" -eq 0 ] ; then
    echo "ERROR: assembled 0 samples! Check log files for details"
    exit 1
fi

echo "assembled $trac_count samples"

# STDOUT and STDERR logged
# no trimming performed with -qurs
# only intersect taken with -i

# add counter!

### Collate seqs

cat "$out_dir"/assembly/*cons.fa > "$out_dir"/assembly/con_list.fasta

###  xtract ITS with ITSx
echo "running ITSx..."
ITSx -i "$out_dir"/assembly/con_list.fasta -o "$out_dir"/its/its \
-t 'fungi' \
--graphical F \
--save_regions 'ITS1,5.8S,ITS2' \
--cpu 4 \
--minlen 30 \
>> "$out_dir"/logs/its_log.txt 2>&1

# extract forward and reverse strands from sequences where no ITS could be recognised in the consensus seq
# init empty array
# for line in its_no_detections, which corresponds to a sample code
# find the appropriate txt file in tracy assemble data
# read it into memory
# extract everything before ' Align'
# remove bracketed things
# append to array
# finally print all that out seperating with newlines

nd_ar=()
nd_count=0
while read -r p; do

  pt=("$out_dir"/assembly/"$p"*_cons.txt)
  
  c=$(cat "$pt")
  c=${c%%[[:space:]]Align*}
  c=${c//(*)/}
  
  nd_ar+=("$c")
  
  nd_count=$((nd_count + 1))
  
done < "$out_dir"/its/its_no_detections.txt

if [[ $nd_count -ne 0 ]] ; then
echo "no ITS detected in consensus for $nd_count samples, trying single direction strands..."
fi

printf "%s\n" "${nd_ar[@]}" > "$out_dir"/its/noconits.fa


# try ITSx on those
ITSx -i "$out_dir"/its/noconits.fa -o "$out_dir"/its/sing \
-t 'fungi' \
--graphical F \
--save_regions 'ITS1,5.8S,ITS2' \
--cpu 4 \
--minlen 30 \
>> "$out_dir"/logs/its_log.txt 2>&1

echo "sorting results..."

# cat results - drop those we can't find ITS for, this is our major quality filter
cat "$out_dir"/its/*ITS1* > "$out_dir"/its/its1.merge.fa
cat "$out_dir"/its/*5_8S* > "$out_dir"/its/5_8S.merge.fa
cat "$out_dir"/its/*ITS2* > "$out_dir"/its/its2.merge.fa


#join ITS1 5.8S ITS2 per sample
python3 ./scripts/modules/itsx_its_cat.py \
"$out_dir/its/its1.merge.fa" \
"$out_dir/its/5_8S.merge.fa" \
"$out_dir/its/its2.merge.fa" \
-op "$out_dir/its/ALL_ITS.fa"

echo "done!"
