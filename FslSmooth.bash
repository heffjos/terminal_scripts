#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslSmooth_help
{
    echo
    echo "FslSmooth.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "FSL functions:  fslmaths"
    echo "AFNI functions: nifti_tool"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script it to smooth subject's functional images with FSL."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -S Sigma            sigm in mm for gauss kernel. This is NOT the same in SPM where the FWHM is directly specified."
    echo "                      Here, FWHM ~ 2.355 * sigma. Use the following table for the appropriate FWHM:"
    echo "                      4  mm ~ 1.6985 sigma"
    echo "                      5  mm ~ 2.1231 sigma"
    echo "                      6  mm ~ 2.5478 sigma"
    echo "                      7  mm ~ 2.9734 sigma"
    echo "                      8  mm ~ 3.3970 sigma"
    echo "                      9  mm ~ 3.8217 sigma"
    echo "                      10 mm ~ 4.2463 sigma"
    echo "                      It looks like FSL can only perform isotropic smoothing."
    echo "                      DEFAULT: 3.3970"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend slice time corrected image"
    echo "                      DEFAULT: s"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSearch     text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: fsl_w2mm_rarun*nii'
    echo
}

if (( $# == 0 ))
then
    FslSmooth_help
    exit
fi

# set some variables
SubjectMastker=Subjects
Sigma=3.3970
UserEmail=`whoami`@umich.edu
SubDirectory=func
Prepend=s
RunDirectory='run*'
VolumeSearch='fsl_w2mm_rarun*nii'

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:S:U:f:n:r:v:h opt
    do
        case "$opt" in
            h)
                FslSmooth_help
                exit
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            S)
                Sigma=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
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
                echo "Invalid option: ${opt}"
                FslSmooth_help
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
                
# all subjects should be good, now we do actual work
for iSubject in "${subjects[@]}"
do
    # grab files again
    FuncDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunDirs=(`ls -d ${FuncDirec}/${RunDirectory}`)

    # slice time correct images
    echo "smoothing : ${RunDirs[@]}"
    for iRun in "${RunDirs[@]}"
    do
        WarpFiles=(`ls -d ${iRun}/${VolumeSearch}`)
        for iWarpFile in "${WarpFiles[@]}"
        do
            TopDir=`dirname ${iWarpFile}`
            FileName=`basename ${iWarpFile}`

            fslmaths ${iWarpFile} -s ${Sigma} ${TopDir}/${Prepend}${FileName}

            nifti_tool -mod_hdr -mod_field descrip "Sigma: ${Sigma}" -overwrite -infiles ${TopDir}/${Prepend}${FileName}
        done
    done
done

EndTime=`date`
# mail when all are finished
mail -s 'FslSmooth.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Smoothed ${#subjects[@]} subjects
EOF
    
