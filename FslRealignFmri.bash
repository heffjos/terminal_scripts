#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslRealignFmri_help
{
    echo
    echo "FslRealignFmri.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "FSL programs:  mcflirt"
    echo "AFNI programs: 3dcalc, nifti_tool"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to realign functional images to a reference image using FSL."
    echo "The reference image is always chosen as an image from the first run found. All runs found will"
    echo "always be realigned together. The reference volume is placed a directory above the run directories."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -S ReferenceVol     volume number from first run selected as reference volume. Index is zero based so"
    echo "                      the first volume is indexed with 0."
    echo "                      DEFAULT: 9"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend output realigned functional images"
    echo "                      DEFAULT: r"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSearch     text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: arun*nii'
    echo
}

if (( $# == 0 ))
then
    FslRealignFmri_help
    exit
fi

# set some variables
SubjectMaster=Subjects
ReferenceVol=9
UserEmail=`whoami`@umich.edu
SubDirectory=func
Prepend=r
RunDirectory='run*'
VolumeSearch='arun*nii'

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:S:U:f:n:r:v:h opt
    do
        case "$opt" in
            h)
                FslRealignFmri_help
                exit
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            S)
                ReferenceVol=${OPTARG}
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
                FslRealignFmri_help
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

FslVer=`basename ${FSLDIR}`

# all subjects should be good, now we do actual work
for iSubject in "${subjects[@]}"
do
    # grab files again
    FuncDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunDirs=(`ls -d ${FuncDirec}/${RunDirectory}`)

    # create reference volume into func directory
    TmpRuns=(`ls -d ${RunDirs[0]}/${VolumeSearch}`)
    3dcalc -a ${TmpRuns[0]}[${ReferenceVol}] -expr 'a' -prefix ${FuncDirec}/FslRealignReferenceVol.nii -overwrite

    # note volume in header
    RunName=`basename ${TmpRuns[0]}`
    nifti_tool -mod_hdr -overwrite -mod_field descrip "${RunName} : ${ReferenceVol} vol" -infiles ${FuncDirec}/FslRealignReferenceVol.nii

    # realign images 
    echo "realigning : ${RunDirs[@]}"
    for iRun in "${RunDirs[@]}"
    do
        WarpFiles=(`ls -d ${iRun}/${VolumeSearch}`)
        for iWarpFile in "${WarpFiles[@]}"
        do
            TopDir=`dirname ${iWarpFile}`
            FileName=`basename ${iWarpFile%.*}`

            mcflirt -in ${iWarpFile} \
                -out ${TopDir}/${Prepend}${FileName} \
                -reffile ${FuncDirec}/FslRealignReferenceVol.nii \
                -stats \
                -plots

            nifti_tool -mod_hdr -mod_field descrip "${FslVer} : FalRealignFmri.bash" -overwrite -infiles ${TopDir}/${Prepend}${FileName}.nii

            # do some file organization
            mkdir ${TopDir}/RealignFiles
            mv ${TopDir}/${Prepend}${FileName}_meanvol.nii ${TopDir}/RealignFiles
            mv ${TopDir}/${Prepend}${FileName}_sigma.nii ${TopDir}/RealignFiles
            mv ${TopDir}/${Prepend}${FileName}_variance.nii ${TopDir}/RealignFiles
            mv ${TopDir}/${Prepend}${FileName}.par ${TopDir}/fsl_rp_${FileName}.txt
            
        done
    done
done

EndTime=`date`
# mail when all are finished
mail -s 'FslRealignFmri.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Realigned ${#subjects[@]} subjects
EOF
