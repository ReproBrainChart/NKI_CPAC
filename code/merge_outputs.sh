#!/bin/bash
set -e -u -x
outputsource=ria+file:///cbica/comp_space/RBC/NKI_RERUN/c-pac-1.8.5/output_ria#003487bb-b745-4f4d-a3a3-607838cc1f13
cd /cbica/comp_space/RBC/NKI_RERUN/c-pac-1.8.5

# The following should be pasted into the merge_outputs.sh script
datalad clone ${outputsource} merge_ds -b prerun
cd merge_ds
NBRANCHES=$(git branch -a | grep job- | sort | wc -l)
echo "Found $NBRANCHES branches to merge"

gitref=$(git show-ref prerun | cut -d ' ' -f1 | head -n 1)

# query all branches for the most recent commit and check if it is identical.
# Write all branch identifiers for jobs without outputs into a file.
for i in $(git branch -a | grep job- | sort); do [ x"$(git show-ref $i \
  | cut -d ' ' -f1)" = x"${gitref}" ] && \
  echo $i; done | tee code/noresults.txt | wc -l


for i in $(git branch -a | grep job- | sort); \
  do [ x"$(git show-ref $i  \
     | cut -d ' ' -f1)" != x"${gitref}" ] && \
     echo $i; \
done | tee code/has_results.txt

mkdir -p code/merge_batches
num_branches=$(wc -l < code/has_results.txt)
CHUNKSIZE=200

split -l ${CHUNKSIZE} --numeric-suffixes code/has_results.txt code/__results_batch
chunks_files=$(find code -name '__results_batch*' | sort )
num_chunks=$(echo ${chunks_files} | wc -w)
for chunkfile in ${chunks_files}
do
    chunknum=$(basename ${chunkfile} | sed 's/__results_batch\([0-9][0-9]*\)/\1/')
    git merge -m "merge results batch ${chunknum}/${num_chunks}" $(cat ${chunkfile})
done

# Push the merge back
git push

# Get the file availability info
git annex fsck --fast -f output-storage

# This should not print anything
MISSING=$(git annex find --not --in output-storage)

if [[ ! -z "$MISSING" ]]
then
    echo Unable to find data for $MISSING
    exit 1
fi

datalad push --data nothing


# Now push the results to fcp-indi
source ~/.aws/fcpindi.sh
git annex copy --from output-storage --to fcp-indi
MISSING=$(git annex find --not --in fcp-indi)
datalad push --data nothing

cd ../analysis
datalad update --how=merge -s output
git merge main
git checkout main
git merge prerun

