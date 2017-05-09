#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslWarpOnlyFmri_help
{
    echo
    echo "FslWarpOnlyFmri.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to warp functional images into mni space using FSL."
    echo "FslAnat.bash and FslWarpFmri.bash are both needed to run before this batch. The main intention"
    echo "of this script to allow resampling from the original functional images to a lower resolution."
    echo "The following steps are performed in this order:"
    echo " -warp the functional into mni space using applywarp"
    echo " -resample functional images to lower resolution."
    echo
    echo "OPTIONS:"
    echo "  -I ReferenceImage   The reference image sets the output warped anatomy voxel"
    echo "                      sizes, image dimensions, and transformation matrix. It is not used"
    echo "                      in any way for the normalization."
    echo "                      DEFAULT: /zubdata/oracle7/Researchers/heffjos/Templates/2mm_single_subj_T1.nii"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -P MatPrefix        The prefix name given to the linear and bbr mat transforms. THIS FLAG IS REQUIRED."
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -a AnatomyDir       path to subject anatomy directory, searched directly below subject directory"
    echo "                      DEFAULT: anatomy/t1spgr.anat"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend output warped functional and anatomical images"
    echo "                      DEFAULT: w2mm_"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSeasrch    text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: ra_spm8_run*nii'
    echo
}

#skullstripped brain = T1_biascorr_brain.nii
#brain = T1_biascorr.nii
#white matter = T1_fast_pve_2.nii
#nolinear transform=T1_to_MNI_nonlin_coeff.nii

    
if (( $# == 0 ))
then
    FslWarpOnlyFmri_help
    exit
fi
    
# set some variables
ReferenceImage=/zubdata/oracle7/Researchers/heffjos/Templates/2mm_single_subj_T1.nii
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
AnatomyDir=anatomy/t1spgr.anat
SubDirectory=func
Prepend=w2mm_
RunDirectory='run*'
VolumeSearch='ra_spm8_run*nii'
StartTime=`date`
MatPrefix=

# parse the arguments
while (( $# > 0 ))
do
    while getopts I:M:U:a:f:g:n:r:v:hP: opt
    do
        case "$opt" in
            h)
                FslWarpOnlyFmri_help
                exit
                ;;
            I)
                ReferenceImage=${OPTARG}
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            P)
                MatPrefix=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            a)
                AnatomyDir=${OPTARG}
                ;;
            f)
                SubDirectory=${OPTARG}
                ;;
            n)
                Prepend=${OPTARG}
                ;;
            r)
                RunDirectory=${OPTARG}
                ;;
            v)
                VolumeSearch=${OPTARG}
                ;;
            [?])
                echo "Inavlid option: ${opt}"
                FslWarpOnlyFmri_help
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

# make sure prefix was specified
if [ -z "$MatPrefix" ]
then
    echo "MatPrefix is empty. THIS FLAG IS REQUIRED."
    echo "Read the help for its purpose."
    echo "* * * A B O R T I N G * * *"
    exit
fi

# make sure subjects were specified
if [ ${#subjects[@]} -eq 0 ]
then
    echo
    echo "No subjects specified."
    echo ' * * * A B O R T I N G * * *'
    echo
    exit
fi

# check if reference images exits
if [ ! -z "${ReferenceImage}" ]
then
    if [ ! -f ${ReferenceImage} ]
    then
        echo
        echo "Reference file does not exist or points to directory: ${ReferenceImage}"
        echo "Check -I flag."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi
else
    echo "Not using a reference image."
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

    # check if anatomy direcotry is present
    if [ ! -d ${MasterDir}/${iSubject}/${AnatomyDir} ]
    then
        echo
        echo "Anatomy directory ${MasterDir}/${iSubject}/${AnatomyDir} does not exist"
        echo "Subject ${iSubject}"
        echo "Check your -a flag."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    # check some files in anatomy directory
    TmpDir=${MasterDir}/${iSubject}/${AnatomyDir}

    # check for nonlinear transform is present
    if [ ! -e ${TmpDir}/T1_to_MNI_nonlin_coeff.nii ]
    then
        echo "T1_to_MNI_nonlin_coeff.nii was not found in ${TmpDir}"
        echo "Run FslAnat.bash before this script"
        echo " * * * A B O R T I N G * * *"
        exit
    fi

    # check if bbr warp is present
    if [ ! -e ${TmpDir}/${MatPrefix}2anat_bbr.mat ]
    then    
        echo "${MatPrefix}2anat_bbr.mat was not found in ${TmpDir}"
        echo "Check -P flag or run FslWarpFmri.bash if you have not yet."
        echo " * * * A B O R T I N G * * *"
        exit
    fi

    # check if func directory is present
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

    # check run directory
    RunDirec=(`ls -d ${FullDirec}/${RunDirectory}`)
    if [ -z "$RunDirec" ]
    then
        echo
        echo "No run directories found in ${FullDirec}"
        echo "Used regex '${RunDirectory}'"
        echo "Check -r option"
        echo " * * * A B O R T I N G * * *"
        exit
    fi

    for oneRun in "${RunDirec[@]}"
    do
        # check if directory exists
        if [ ! -d ${oneRun} ]
        then
            echo
            echo "Run directory ${oneRun} does not exist"
            echo "Check -r option."
            echo " * * * A B O R T I N G * * *"
            echo
            exit
        fi

        # check if directory contains run files
        RunFiles=(`ls -d ${oneRun}/${VolumeSearch}`)
        if [ ${#RunFiles[@]} -eq 0 ]
        then
            echo
            echo "Subject ${iSubject} has no files to warp."
            echo "Looked in ${RunDirec} with regex '${VolumeSearch}'"
            echo "Check -v option"
            echo " * * * A B O R T I N G * * *"
            echo
            exit
        else
            RunName=`basename ${oneRun}`
            echo "Subject : ${iSubject}/${RunName} found ${#RunFiles[@]} run(s)"
        fi
    done
done

# all subject shold be good, now we do actual work
for iSubject in "${subjects[@]}"
do
    # grab files again
    FuncDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunDirs=(`ls -d ${FuncDirec}/${RunDirectory}`)
    SubjAnatDir=${MasterDir}/${iSubject}/${AnatomyDir}

    # finally apply warps to functional images
    echo "warping functionals : ${RunDirs[@]}"
    for iRun in "${RunDirs[@]}"
    do
        WarpFiles=(`ls -d ${iRun}/${VolumeSearch}`)
        for iWarpFile in "${WarpFiles[@]}"
        do
            TopDir=`dirname ${iWarpFile}`
            FileName=`basename ${iWarpFile}`

            applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_2mm \
                      --in=${iWarpFile} \
                      --warp=${SubjAnatDir}/T1_to_MNI_nonlin_coeff \
                      --premat=${SubjAnatDir}/${MatPrefix}2anat_bbr.mat \
                      --out=${TopDir}/TmpWarp.nii \
                      --interp=spline

            # resample brain
            if [ ! -z "${ReferenceImage}" ]
            then
                3dresample -input ${TopDir}/TmpWarp.nii \
                    -prefix ${TopDir}/${Prepend}${FileName} \
                    -master ${ReferenceImage} \
                    -rmode Cu

                rm ${TopDir}/TmpWarp.nii
            else
                mv ${TopDir}/TmpWarp.nii  ${TopDir}/${Prepend}${FileName}
            fi
        done
    done
done
    
EndTime=`date`
# mail when all are finished
mail -s 'FslWarpOnlyFmri.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Registered ${#subjects[@]} subjects
EOF

