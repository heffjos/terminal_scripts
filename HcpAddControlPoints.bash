#!/bin/bash

par_dir=$1

if [ $# -eq 0 ]
then
    echo "HcpAddControlPoints.bash par_dir"
    exit
fi

if [ ! -d ${par_dir} ]
then
    echo "Participant directory does not exist: ${par_dir}"
    exit
fi

check_files=(
    ${par_dir}/mri/brainmask.mgz
    ${par_dir}/mri/wm.mgz
    ${par_dir}/surf/lh.white
    ${par_dir}/surf/lh.pial
    ${par_dir}/surf/rh.white
    ${par_dir}/surf/rh.pial
)
# ${par_dir}/surf/rh.inflated.nofix
# ${par_dir}/surf/lh.inflated.nofix

for one_file in ${check_files[@]}
do
    if [ ! -f ${one_file} ]
    then
        echo "Files does not exist: ${one_file}"
        exit
    fi
done

freeview -v ${par_dir}/mri/orig_nu.mgz \
    ${par_dir}/mri/brainmask.mgz \
    ${par_dir}/mri/wm.mgz:colormap=heat:opacity=0.4:visible=0 \
    -f ${par_dir}/surf/lh.white:edgecolor=blue \
    ${par_dir}/surf/lh.pial:edgecolor=red \
    ${par_dir}/surf/rh.white:edgecolor=blue \
    ${par_dir}/surf/rh.pial:edgecolor=red
