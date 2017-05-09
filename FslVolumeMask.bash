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
    echo "want to run this on a brain warped in MNI space. The input anatomy should be the warped"
    echo "bias corrected image, which is the 2mm_T1_to_MNI_nonlin.nii if FslAnat.bash was left at"
    echo "default settings."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -I ReferenceImage   If a reference image is specified, the masks will be resampled to"
    echo "                      that of the reference image. The voxel sizes, image dimensions,"
    echo "                      and transformation matrix will match that of the reference image."
    echo "                      The resampled masks are output to a different directory specified"
    echo "                      by the -o flag. This is only performed if a ReferenceImage is"
    echo "                      specified."
    echo "                      DEFAULT: NONE"
    echo "  -f SubDirectory     directory to anatomy image. This is appended directly after"
    echo "                      the subject directory"
    echo "                      DEFAULT: anatomy/t1spgr.anat"
    echo "  -n Prepend          text to prepend to masks, typically I set this to the anatomy"
    echo "                      image voxel sizes. This is only used if ReferenceImage (-o flag)"
    echo "                      is specified."
    echo "                      DEFAULT: 2mm"
    echo "  -o MaskDirName      Name of output mask directroy. This is only used if"
    echo "                      ReferenceImage"
    echo "                      (-o flag) is specified."
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
AnatImage=T1_to_MNI_nonlin.nii
SubDirectory=anatomy/t1spgr.anat
AlvinMask=/pecina/Data/Templates/ALVIN_v1/ALVIN_mask_v1.hdr
WhiteMask=/pecina/Data/Templates/avg152T1_white_Thr0.5Bin.nii
Prepend=2mm
MaskDirName=2MM_MASKS
ReferenceImage=

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:U:I:f:n:o:h opt
    do
        case "$opt" in
            M)
                SubjectMaster=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            I)
                ReferenceImage=${OPTARG}
                ;;
            f)
                SubDirectory=${OPTARG}
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
    echo "Contact adminstrator"
    echo "* * * A B O R T I N G * * *"
    echo
    exit
fi

# check if refernce image exists if specified
if [ ! -z ${ReferenceImage} -a ! -f ${ReferenceImage} ]
then
    echo
    echo "ReferenceImage ${ReferenceImage} does not exist."
    echo "Check -I option."
    echo "* * * A B O R T I N G * * *"
    echo
    exit
fi

# check if white matter prior mask exists (thresholded at 0.5)
if [ ! -f ${WhiteMask} ]
then
    echo
    echo "White mask ${WhiteMask} does not exist"
    echo "Contact adminstrator"
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
        echo "Make sure to run corrects FslAnat.bash before"
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
    MaskDir=${FullDirec}/MASKS

    if [ ! -d ${MaskDir} ]
    then 
        mkdir ${MaskDir}
        echo "Creating default masks..."

        # bet normalized brain
        echo "betting ${AnatImage} for ${iSubject}"
        bet ${HighRes} ${MaskDir}/${OutName}_bet.nii -m

        # fast normalized bet brain
        echo "fasting ${OutName}_bet.nii for ${iSubject}"
        fast -o ${MaskDir}/${OutName}_fast ${MaskDir}/${OutName}_bet.nii

        # create csf mask first
        fslmaths ${MaskDir}/${OutName}_fast_pve_0.nii -thr 0.99 -bin -mas ${AlvinMask} ${MaskDir}/Alvin_CsfMask.nii

        # create multiple wm masks

        # create fsl wm mask
        fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin -ero -ero ${MaskDir}/Fsl_WhiteMask.nii

        # create fsl one ero mask
        fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin -ero ${MaskDir}/OneEro_WhiteMask.nii

        # create thresholded and binarized mask
        fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -thr 0.99 -bin ${MaskDir}/ThrBinWhiteMask.nii

        # create afni white matter mask
        3dmask_tool -input ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/Afni_WhiteMask.nii -dilate_result -2

        # now do the custom mask with afni
        3dcalc -a ${MaskDir}/ThrBinWhiteMask.nii -prefix ${MaskDir}/AfniIntermediate.nii \
               -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
               -expr 'a*(1-amongst(0,b,c,d,e,f,g))'
        3dcalc -a ${MaskDir}/AfniIntermediate.nii -prefix ${MaskDir}/Custom_WhiteMask.nii \
               -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
               -expr 'a*(1-amongst(0,b,c,d,e,f,g))'

        # create WM masked by prior, thresholded, and binarized mask
        fslmaths ${MaskDir}/${OutName}_fast_pve_2.nii -mas ${WhiteMask} -thr 0.99 -bin ${MaskDir}/MasThrBinWhiteMask.nii

        # create base WM mask now by eroding with AFNI -- this is the best mask to use
        3dmask_tool -input ${MaskDir}/MasThrBinWhiteMask.nii -prefix ${MaskDir}/Prior_Afni_WhiteMask.nii -dilate_result -2
    else
        echo "${MaskDir} already exists. The masks will be resampled if -o option was specified."
    fi

    if [ ! -z ${ReferenceImage} ]
    then
        mkdir ${FullDirec}/${MaskDirName}
        for oneImage in ${MaskDir}/*nii
        do
            echo ${oneImage}
            fname=`basename ${oneImage}`
            3dresample -input ${oneImage} \
                       -prefix ${FullDirec}/${MaskDirName}/${Prepend}_${fname} \
                       -master ${ReferenceImage} \
                       -rmode NN
        done
    fi
done

EndTime=`date`
# mail when all are finished
mail -s 'CreateAnatMasks.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Registered ${#subjects[@]} subjects
EOF
    

