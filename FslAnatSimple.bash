#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslAnatSimple_Help
{
    echo
    echo "FslAnatSimple.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "This is an alternate script for FslAnat.bash. You should only run this script if"
    echo "FslAnat.bash script fails to properly warp the anatomical image into MNI space, meaning"
    echo "there are huge distortions in the anatmoical image. Sometimes the distortions are"
    echo "caused by miscoregistration between the anatomical and functional, so make sure to"
    echo "examine that first."
    echo
    echo "  -I ReferenceImage   The reference image sets the output warped anatomy voxel"
    echo "                      sizes, image dimensions, and transformation matrix. It is not used"
    echo "                      in any way for the normalization."
    echo "                      DEFAULT: /zubdata/oracle7/Researchers/heffjos/Templates/2mm_single_subj_T1.nii"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -a AnatImage        file name for anatomy image"
    echo "                      DEFAULT: t1spgr.nii"
    echo "  -f SubDirectory     directory to anatomy image. This is appended directly"
    echo "                      after the subject directory"
    echo "                      DEFAULT: anatomy"
    echo "  -n Prepend          prefix to output nonlinearly warped files. I recommend using the"
    echo "                      voxel sizes of the ReferenceImage"
    echo "                      DEFAULT: 2mm_"
    echo
}

if (( $# == 0 ))
then
    FslAnatSimple_Help
    exit
fi

# set some variables
StartTime=`date`
ReferenceImage=/zubdata/oracle7/Researchers/heffjos/Templates/2mm_single_subj_T1.nii
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
SubDirectory=anatomy
AnatImage=t1spgr.nii
Prepend=2mm_

# parse the arguments
while (( $# > 0 ))
do
    while getopts I:M:U:a:f:n:h opt
    do
        case "$opt" in
            I)
                ReferenceImage=${OPTARG}
                ;;
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
            n)
                Prepend=${OPTARG}
                ;;
            h)
                FslAnatSimple_Help
                ;;
            [?])
                echo "Inavlid option: ${opt}"
                FslAnatSimple_Help
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

# do file checking for all subjects
for iSubject in "${subjects[@]}"
do
    # check if subject directory is present
    if [ ! -d ${MasterDir}/${iSubject} ]
    then
        echo
        echo "Subject directory ${iSubject} does not exist."
        echo ' * * * A B O R T I N G * * *'
        echo
        exit
    fi

    # check if anatomy directory is present
    FullDirec=${MasterDir}/${iSubject}/${SubDirectory}
    if [ ! -d ${FullDirec} ]
    then
        echo
        echo "Looked for directory ${FullDirec} but it was not found."
        echo "Check -f option."
        echo ' * * * A B O R T I N G * * * '
        echo
        exit
    fi

    if [ ! -f ${FullDirec}/${AnatImage} ]
    then    
        echo
        echo "File does not exist: ${AnatImage}"
        echo "In directory ${FullDirec}/${AnatImage}"
        echo "Check -a flag."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi
done

# check Reference image exists and is a file
if [ ! -f ${ReferenceImage} ]
then
    echo
    echo "Reference file does not exist or points to directory: ${ReferenceImage}"
    echo "Check -I flag."
    echo " * * * A B O R T I N G * * *"
    echo
    exit
fi

# now the real work
for iSubject in "${subjects[@]}"
do
    FullAnatImage=${MasterDir}/${iSubject}/${SubDirectory}/${AnatImage}
    pdir=`dirname ${FullAnatImage}`
    fname=`basename ${FullAnatImage}`
    OutAnat=${pdir}/${fname/.nii/.anat}

    echo ${iSubject}
    if [ -d ${OutAnat} ]
    then    
        echo "Removing existing directory: ${OutAnat}"
        rm -r ${OutAnat}
    fi
    mkdir ${OutAnat}

    # reorient brain to match standard space
    echo reorient
    fslreorient2std ${FullAnatImage} ${OutAnat}/T1.nii
    # cp ${OutAnat}/T1.nii ${OutAnat}/T1_biascorr.nii

    # bias correct brain
    echo bias correction
    3dUniformize -anat ${OutAnat}/T1.nii -prefix ${OutAnat}/T1_biascorr.nii -quiet

    # skull strip T1
    echo skullstrip
    bet ${OutAnat}/T1_biascorr.nii ${OutAnat}/T1_biascorr_brain.nii
    # bet ${OutAnat}/T1.nii ${OutAnat}/bet_T1.nii
    # cp ${OutAnat}/bet_T1.nii ${OutAnat}/T1_biascorr_brain.nii

    # fast skull strip T1
    echo fast
    fast --out=${OutAnat}/T1_fast ${OutAnat}/T1_biascorr_brain.nii
   
    # linearly register T1 to MNI space 
    echo linear registration
    flirt -in ${OutAnat}/T1_biascorr_brain.nii \
          -ref ${FSLDIR}/data/standard/MNI152_T1_2mm_brain \
          -out ${OutAnat}/T1_to_MNI_lin_bet \
          -omat ${OutAnat}/T1_to_MNI_lin_bet.mat \
          -bins 256 \
          -cost corratio \
          -searchrx -90 90 \
          -searchry -90 90 \
          -searchrz -90 90 \
          -dof 12  \
          -interp spline

    # nonlinearly register T1 to MNI space
    echo nonlinear registration
    fnirt --in=${OutAnat}/T1_biascorr.nii \
          --aff=${OutAnat}/T1_to_MNI_lin_bet.mat \
          --config=T1_2_MNI152_2mm.cnf \
          --cout=${OutAnat}/T1_to_MNI_nonlin_coeff \
          --iout=${OutAnat}/T1_to_MNI_nonlin \
          --jout=${OutAnat}/T1_to_MNI_nonlin_jac 

    # resample brain to match our template
    echo resample
    3dresample -input ${OutAnat}/T1_to_MNI_nonlin.nii \
               -prefix ${OutAnat}/${Prepend}T1_to_MNI_nonlin.nii \
               -master ${ReferenceImage} \
               -rmode Cu
done
        
    

