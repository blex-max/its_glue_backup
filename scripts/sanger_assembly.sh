#!/usr/bin/env bash

#   .__  __           __________.__              .__  .__                 #
#   |__|/  |_  ______ \______   \__|_____   ____ |  | |__| ____   ____    #
#   |  \   __\/  ___/  |     ___/  \____ \_/ __ \|  | |  |/    \_/ __ \   #
#   |  ||  |  \___ \   |    |   |  |  |_> >  ___/|  |_|  |   |  \  ___/   #
#   |__||__| /____  >  |____|   |__|   __/ \___  >____/__|___|  /\___  >  #
#                 \/               |__|        \/             \/     \/   #
#                                                                         #
##                                                                       ##
###                                                                     ###  
####         Author : Alex Byrne                                       ####    
####         Contact : ablex7@gmail.com                                ####
####                                                                   ####
####         Run from top level of seq_pipeline project folder         ####
####         By default, expects .ab1 files in the format:             ####
####         samplecode_ITS*.ext - The '_ITS' bit is key               ####
####                                                                   ####
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# FIRST TIME? RUN CREATE_ENV.sh:
conda activate ./seq_conda

### basecalling/assembly
# Using Tracy since 
# i) it's recent
# ii) it's expressly designed for (modern) Sanger data

# Tracy can output basecalls directly
# .tsv output gives a sort of qual scores

# assemble forward and reverse direct from traces
# -t specifies trimming stringency (default), 
# -f set to 1 for hard consensus, i.e. 100% match. 
# -f 0.5 seems to get decent consensus without Ns
# tracy doc/output sparse, discussing with author on github (feb 2022)

# assemble without ref
for file in ./data/traces/*ITS4* ; do
    xbase=${file##*/}
    code=$(awk -F'_ITS' '{print $1}' <<< "$xbase") #code excluding primer id
    F='_ITS1F'
    ffile=(./data/traces/$code$F*)
    tag='_cons'
    
    ./tracy/tracy consensus \
    -o data/tracy_assemble/$code$tag \
    -q 0 -u 0 -r 0 -s 0 -i \
    -b $code \
    $ffile \
    $file \
    &>> logs/cons_log.txt 
done
# STDOUT and STDERR logged
# no trimming performed with -qurs

# Sietse's data DOESN'T WORK DUE TO OUTDATED FILE TYPE

# add counter!

### Collate seqs?

cat ./data/tracy_assemble/*cons.fa > ./data/con_list.fasta

###  xtract ITS with ITSx

# ITSx with tracy -d 1 can detect ITS1 and ITS2 but often not surrounding SSU/LSU. 
# Presumably because forming the consensus seq trims off these regions.
# So I guess it detects 5.8S and just takes either side of it to be ITS.
# hypothesis confirmed - using forward strand nets us LSU

# Using tracy assemble with -d 0.5 to get consensus sequence, 
# rather than -d 1, gives a con seq that lets us catch SSU for 6_512_1_A01.
# But I imagine the end of the seq is garbage?
# Catching SSU is most important, seqs then start at same location!

ITSx -i ./data/con_list.fasta -o ./data/its_out/its \
-t 'fungi' \
--complement F \
--graphical F \
--save_regions 'ITS1,5.8S,ITS2' \
--cpu 4

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
while read p; do
  echo $p
  pt=(./data/tracy_assemble/$p*_cons.txt)
  c=`cat $pt`
  c=${c%%[[:space:]]Align*}
  c=${c//(*)/}
  nd_ar+=($c)
done < data/its_out/its_no_detections.txt

printf "%s\n" "${nd_ar[@]}" > noits.fa

# try ITSx on those, now checking complement also

ITSx -i ./noits.fa -o ./data/its_out/sing \
-t 'fungi' \
--graphical F \
--save_regions 'ITS1,5.8S,ITS2' \
--cpu 4

# cat these results - drop those we can't find ITS for, this is our major quality filter
Clusters: 179 Size min 1, max 20, avg 1.5
Singletons: 141, 53.2% of seqs, 78.8% of clusters

cat ./data/its_out/*ITS1* > ./data/fasta/its1.fasta
cat ./data/its_out/*5_8S* > ./data/fasta/5_8S.fasta
cat ./data/its_out/*ITS2* > ./data/fasta/its2.fasta


#join ITS1 5.8S ITS2

python3 ./scripts/itsx_its_cat.py \
'./data/fasta/its1.fasta' \
'./data/fasta/5_8S.fasta' \
'./data/fasta/its2.fasta' \
-op './results/cat_its.fa'

# vsearch cluster to OTUs
# --id 0.97 : 97% pairwise to match to an OTU. This isn't ideal but it's certainly standard
# --sizeorder: abundance trumps distance for ties
# --maxaccepts: number of decent hits to look for before making a decision (default 1!)

vsearch --cluster_size './results/cat_its.fa' \
--centroids './results/OTU_centroids.fa' \
--otutabout './results/OTU_cluster_memb.tsv' \
--uc './results/OTU_cluster_data.uc' \
--id 0.97 \
--sizeorder --clusterout_sort --maxaccepts 5

# vsearch sintax, bootstrap support 0.8 per Edgar (https://www.drive5.com/usearch/manual/cmd_sintax.html)

vsearch --sintax './results/OTU_centroids.fa' \
--db ./ext_dbs/utax_unite8.3.gz \
--sintax_cutoff 0.8 \
--tabbedout './results/sintax_class.tsv'




