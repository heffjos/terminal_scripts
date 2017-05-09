#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslAnat_help
{
    echo
    echo "FslAnat.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "This is a wrapper for fsl_anat function. The input should be  nifti images with correct"
    echo "header information meaning at least the qform_code should not equal 0. Typically"
    echo "anatomical images acquired from North campus do not have this code set; however, very"
    echo "recently they started setting the code for anatomical images only and I do not know"
    echo "if this is only for one scanner. You can always check header information with fslhd or"
    echo "nifti_tool commands."
    echo
    echo "OPTIONS:"
    echo "  -C                  turn off step that does automated cropping"
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
    echo "                      DEFAULT: 2mm"
    echo
}

if (( $# == 0 ))
then
    FslAnat_help
    exit
fi

# set some variables
StartTime=`date`
UseCrop=true
ReferenceImage=/zubdata/oracle7/Researchers/heffjos/Templates/2mm_single_subj_T1.nii
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
SubDirectory=anatomy
AnatImage=t1spgr.nii
Prepend=2mm

# parse the arguments
while (( $# > 0 ))
do
    while getopts CI:M:U:a:f:n:h opt
    do
        case "$opt" in
            C)
                UseCrop=false
                ;;
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

# now do the processing
for iSubject in "${subjects[@]}"
do
    FullAnatImage=${MasterDir}/${iSubject}/${SubDirectory}/${AnatImage}
    pdir=`dirname ${FullAnatImage}`
    fname=`basename ${FullAnatImage}`
    OutAnat=${pdir}/${fname/.nii/.anat}

    if [ "$UseCrop" = false ]
    then
        fsl_anat -i ${FullAnatImage} --nocrop --clobber
    else
        fsl_anat -i ${FullAnatImage} --clobber
    fi

    # resample brain
    3dresample -input ${OutAnat}/T1_to_MNI_nonlin.nii \
        -prefix ${OutAnat}/${Prepend}_T1_to_MNI_nonlin.nii \
        -master ${ReferenceImage} \
        -rmode Cu
done

EndTime=`date`
# mail when all are finished
mail -s 'FslAnat.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Registered ${#subjects[@]} subjects
EOF
    
