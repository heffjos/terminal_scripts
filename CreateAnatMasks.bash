#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function CreateAnatMasks_help
{
    echo
    echo "CreateAnatMasks.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to create binary masks for an input image. Typically, you"
    echo "want to run this on a brain warped in MNI space. If you used AntsWarpAnat.bash, the"
    echo "input anatomy should be the warped bias corrected image (2mm_T1_biascorr_to_MNI.nii if"
    echo " the -n option was set to default.)"
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -a AnatImage        name of anatomy image"
    echo "                      DEFAULT: 2mm_T1_biascorr_to_MNI.nii"
    echo "  -f SubDirectory     directory to anatomy image. This is appended directly after"
    echo "                      the subject directory"
    echo "                      DEFAULT: anatomy/t1spgr.anat/AntsWarp/"
    echo "  -m AlvinMask        full path to AVLIN mask. This mask is used to isolate the"
    echo "                      ventricles for CSF masks. All ALVIN masks are saved here:"
    echo "                      /zubdata/oracle7/Researchers/heffjos/Templates"
    echo "                      You must use the one with the same image dimension, voxel sizes"
    echo "                      and transformation matrix. If you need help with this ask Joe."
    echo "                      DEFAULT: /zubdata/oracle7/Researchers/heffjos/Templates/2mm_ALVIN_mask_v1.nii"
    echo "  -n Prepend          text to prepend to masks, typically I set this to the anatomy"
    echo "                      image voxel sizes"
    echo "                      DEFAULT: 2mm"
    echo "  -o MaskDirName      Name of output mask directroy"
    echo "                      DEFAULT: 2MM_MASKS"
    echo
}

if (( $# == 0 ))
then
    CreateAnatMasks_help
    exit
fi

# set some variables
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
AnatImage=2mm_T1_biascorr_to_MNI.nii
SubDirectory=anatomy/t1spgr.anat/AntsWarp
AlvinMask=/zubdata/oracle7/Researchers/heffjos/Templates/2mm_ALVIN_mask_v1.nii
Prepend=2mm
MaskDirName=2MM_MASKS

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:U:a:f:m:n:o:h opt
    do
        case "$opt" in
            M)
                SubjectMaster=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            a)
                AnatImage=${OPTARG}
                ;;
            f)
                SubDirectory=${OPTARG}
                ;;
            m)
                AlvinMask=${OPTARG}
                ;;
            n)
                Prepend=${OPTARG}
                ;;
            o)
                MaskDirName=${OPTARG}
                ;;
            h)
                CreateAnatMasks_help
                ;;
            [?])
                echo "Inavlid option: ${opt}"
                CreateAnatMask_help
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
    echo " * * * A B O R T I N G * * *"
    echo
    exit
fi

# check if master directory exists
MasterDir=`pwd`/${SubjectMaster}
if [ ! -d ${MasterDir} ]
then    
    echo
    echo "Directory ${MasterDir} does not exist."
    echo "Check your -M flag."
    echo " * * * A B O R T I N G * * *"
    echo
    exit
fi

# check if ALVIN mask exists
if [ ! -f ${AlvinMask} ]
then
    echo
    echo "AlvinMask ${AlvinMask} does not exist"
    echo "Check -m option"
    echo "* * * A B O R T I N G * * *"
    echo
    exit
fi

# do file checking for all subjects
for iSubject in "${subjects[@]}"
do
    # check if subject directory is present
    if [ ! -d ${MasterDir}/${iSubject} ]
    then
        echo
        echo "Subject directory ${iSubject} does not exist."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    # check if anat directory is present
    FullDirec=${MasterDir}/${iSubject}/${SubDirectory}
    if [ ! -d ${FullDirec} ]
    then
        echo
        echo "Looked for directory ${FullDirec} but it was not found."
        echo "Check -f option."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    if [ ! -f ${FullDirec}/${AnatImage} ]
    then    
        echo
        echo "Looked for anatomy file ${AnatImage} in ${FullDirec}"
        echo "Check -a option"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi
done

# now do the processing
OutName=${AnatImage/\.nii*/}
for iSubject in "${subjects[@]}"
do
    FullDirec=${MasterDir}/${iSubject}/${SubDirectory}
    HighRes=${FullDirec}/${AnatImage}
    MaskDir=${FullDirec}/${MaskDirName}
    mkdir ${MaskDir}

    # bet normalized brain
    echo "betting ${AnatImage} for ${iSubject}"
    bet ${HighRes} ${MaskDir}/${OutName}_bet.nii

    # fast normalized bet brain
    echo "fasting ${OutName}_bet.nii for ${iSubject}"
    fast -o ${MaskDir}/${OutName}_fast ${MaskDir}/${OutName}_bet.nii

    # create csf mask first
    fslmaths ${MaskDir}/${OutName}_fast_pve_0.nii -thr 0.99 -bin -mas ${AlvinMask} ${MaskDir}/${Prepend}_Alvin_CsfMask.nii

    # create multiple wm masks

    # create fsl wm mask
    fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin -ero -ero ${MaskDir}/${Prepend}_Fsl_WhiteMask.nii

    # create fsl one ero mask
    fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin -ero ${MaskDir}/${Prepend}_OneEro_WhiteMask.nii

    # create thresholded and binarized mask
    fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin ${MaskDir}/ThrBinWhiteMask.nii

    # create afni white matter mask
    3dmask_tool -input ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/${Prepend}_Afni_WhiteMask.nii -dilate_result -2

    # now do the custom mask with afni
    3dcalc -a ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/AfniIntermediate.nii \
           -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
           -expr 'a*(1-amongst(0,b,c,d,e,f,g))'
    3dcalc -a ${MaskDir}/AfniIntermediate.nii -prefix ${MaskDir}/${Prepend}_Custom_WhiteMask.nii \
           -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
           -expr 'a*(1-amongst(0,b,c,d,e,f,g))'

    ### now lets create AFNI masks
    ### need to create anatomy mask before doing this
    3dSeg -anat ${MaskDir}/${OutName}_bet.nii -mask AUTO -classes 'CSF ; GM ; WM' -prefix ${MaskDir}/Segsy
    3dcalc -a ${MaskDir}/Segsy/Classes+tlrc -expr 'amongst(a,1)' -prefix ${MaskDir}/Segsy/CSF.nii
    3dcalc -a ${MaskDir}/Segsy/Classes+tlrc -expr 'amongst(a,2)' -prefix ${MaskDir}/Segsy/GM.nii
    3dcalc -a ${MaskDir}/Segsy/Classes+tlrc -expr 'amongst(a,3)' -prefix ${MaskDir}/Segsy/WM.nii
    SegDir=${MaskDir}/Segsy

    # create csf mask first
    fslmaths ${SegDir}/CSF.nii -mas ${AlvinMask} -bin ${SegDir}/Afni_${Prepend}_AlvinCsfMask.nii

    # create wm mask
    fslmaths ${SegDir}/WM.nii -bin -ero -ero ${SegDir}/Afni_${Prepend}_TwoEro_WhiteMsak.nii
done

EndTime=`date`
# mail when all are finished
mail -s 'CreateAnatMasks.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Registered ${#subjects[@]} subjects
EOF
    

