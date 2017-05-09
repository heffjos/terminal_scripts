#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslAnat_help
{
    echo
    echo "FslAnat.bash [OPTIONS] AnatomyFile1 AnatomyFile2 ... AnatomyFile3"
    echo
    echo "USAGE:"
    echo
    echo "This is a wrapper for fsl_anat function. In addition it segments the normalized brain."
    echo
    echo "OPTIONS:"
    echo "  -C                  turn on step that does automated cropping"
    echo "  -I ReferenceSize    this controls the image dimensions, voxel sizes, and transformation matrix"
    echo "                      valid values are the following:"
    echo "                      2mm   - uses /zubdata/apps/fsl5.0.2.2/data/standard/MNI152_T1_2mm.nii.gz"
    echo "                      mc2mm - uses /zubdata/apps/fsl5.0.2.2/data/standard/MNI152_T1_mc2mm.nii.gz"
    echo "                      3mm   - uses /zubdata/apps/fsl5.0.2.2/data/standard/MNI152_T1_3mm.nii.gz"
    echo "                      DEFAULT: mc2mm"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo
}

if (( $# == 0 ))
then
    FslAnat_help
    exit
fi

# set some variables
UserEmail=`whoami`@umich.edu
StartTime=`date`
UseCrop=false
ReferenceSize=mc2mm
fsl_anat=/zubdata/apps/Tools/Programs/TerminalScripts/FslAnatCustom

# parse the arguments
while (( $# > 0 ))
do
    while getopts U:hI:C opt
    do
        case "$opt" in
            U)
                UserEmail=${OPTARG}
                ;;
            C)
                UseCrop=true
                ;;
            I)
                ReferenceSize=${OPTARG}
                ;;
            h)
                FslAnat_help
                ;;
            [?])
                echo "Inavlid option: ${opt}"
                FslAnat_help
                exit
                ;;
        esac
    done

    shift $((OPTIND-1))
    OPTIND=0

    # assume arguments with no flags are subjects
    if [ $# -gt 0 ]
    then
        let nSubjects++
        subjects[${nSubjects}]=$1
        shift
    fi
done

###

# make sure subjects were specified
if [ ${#subjects[@]} -eq 0 ]
then
    echo
    echo "No subjects specified."
    echo ' * * * A B O R T I N G * * *'
    echo
    exit
fi

# do file checking for all subjects
for iSubject in "${subjects[@]}"
do
    if [ ! -f ${iSubject} ]
    then
        echo
        echo "File doest not exist or points to a directory: ${iSubject}"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    TmpFile=${iSubject%.*}
    if [ -d ${TmpFile}.anat ]
    then
        echo
        echo "Output directory already exists: ${TmpFile}.anat"
        echo "Either remove or rename directory and run function again."
        echo " * * * A B O R T I N G * * *"
        exit
    fi
done

# check to make sure valid ReferenceSize was specified
Valid=false
for oneOpt in 2mm mc2mm 3mm
do
    if [ ${oneOpt} = ${ReferenceSize} ]
    then
        Valid=true
    fi
done

if [ "$Valid" = false ]
then
    echo
    echo "Invalid reference size ${ReferenceSize}"
    echo "Valid sizes are 2mm, mc2mm, or 3mm"
    echo " * * * A B O R T I N G * * *"
    echo
    exit
fi

case ${ReferenceSize} in
    2mm)
        AlvinMask=/zubdata/oracle7/Researchers/heffjos/Templates/FSL_2mm_ALVIN_mask.nii
        ;;
    mc2mm)
        AlvinMask=/zubdata/oracle7/Researchers/heffjos/Templates/2mm_ALVIN_mask_v1.nii
        ;;
    3mm)
        AlvinMask=/zubdata/oracle7/Researchers/heffjos/Templates/3mm_ALVIN_mask.nii
        ;;
esac

# now do the processing
for iSubject in "${subjects[@]}"
do
    pdir=`dirname ${iSubject}`
    fname=`basename ${iSubject}`
    OutAnat=${pdir}/${fname/.nii/.anat}

    if [ "$UseCrop" = false ]
    then
        ${fsl_anat}  -i ${iSubject} --nocrop -r ${ReferenceSize} --clobber
    else
        ${fsl_anat} -i ${iSubject} -r ${ReferenceSize} --clobber
    fi

    # bet normalized brain
    bet ${OutAnat}/T1_to_MNI_nonlin.nii ${OutAnat}/T1_to_MNI_nonlin_bet

    # fast normalized bet brain
    fast -o ${OutAnat}/T1_to_MNI_nonlin_fast ${OutAnat}/T1_to_MNI_nonlin_bet.nii

    # create masks
    echo "Creating CSF and WM masks."
    MaskDir=${OutAnat}/Masks
    mkdir ${MaskDir}

    # create csf mask first
    fslmaths ${OutAnat}/T1_to_MNI_nonlin_fast_pve_0.nii -thr 0.99 -bin -mas ${AlvinMask} ${MaskDir}/${ReferenceSize}_Alvin_CsfMask.nii

    # create multiple wm masks

    # create fsl wm mask
    fslmaths ${OutAnat}/T1_to_MNI_nonlin_fast_pve_2.nii -thr 0.99 -bin -ero -ero ${MaskDir}/${ReferenceSize}_Fsl_WhiteMask.nii

    # create fsl one ero mask
    fslmaths ${OutAnat}/T1_to_MNI_nonlin_fast_pve_2.nii -thr 0.99 -bin -ero ${MaskDir}/${ReferenceSize}_OneEro_WhiteMask.nii

    # create thresholded and binarized mask
    fslmaths ${OutAnat}/T1_to_MNI_nonlin_fast_pve_2.nii -thr 0.99 -bin ${MaskDir}/ThrBinWhiteMask.nii

    # create afni white matter mask
    3dmask_tool -input ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/${ReferenceSize}_Afni_WhiteMask.nii -dilate_result -2

    # now do the custom mask with afni
    3dcalc -a ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/AfniIntermediate.nii \
           -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
           -expr 'a*(1-amongst(0,b,c,d,e,f,g))'
    3dcalc -a ${MaskDir}/AfniIntermediate.nii -prefix ${MaskDir}/${ReferenceSize}_Custom_WhiteMask.nii \
           -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
           -expr 'a*(1-amongst(0,b,c,d,e,f,g))'

    mv ${OutAnat} ${pdir}/${ReferenceSize}_${fname/.nii/.anat}
done

EndTime=`date`
# mail when all are finished
mail -s 'FslAnat.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Registered ${#subjects[@]} subjects
EOF
    
