#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function FslSliceTime_help
{
    echo
    echo "FslSliceTime.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "AFNI programs: nifti_tool, 3dcalc"
    echo "FSL  programs: slicetimer"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to slice time correct functional images using FSL."
    echo "Past versions of FSL's slicetimer are known to perform slice time correction"
    echo "INCORRECTLY, which can mess with a lot of stuff. The version of fsl used for slice"
    echo "time correction is written into the slice time corrected nifti file's description."
    echo "As an additional quality check, this function outputs the nifti file SliceCheck.nii"
    echo "which is the last volume of the slice time corrected image minus the last volume of"
    echo "the original image. SliceCheck.nii should equal 0 near the center of the z plane and"
    echo "grow in value as the z plane increases. All volumes are resampled to matched the center"
    echo "z slice."
    echo
    echo "FSLDIR : ${FSLDIR}"
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -O Order            filename of single-column custom slice order file (first slice is"
    echo "                      1 not 0). Typically, you will not need to use this option as the"
    echo "                      default acquisition order is ascending which is what is more than"
    echo "                      likely the fMRI acquisition order if it is from the hospital or"
    echo "                      North Campus."
    echo "                      DEFAULT: NONE"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -T TR               specify repetition time of data"
    echo "                      DEFAULT: 2 seconds"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend slice time corrected image"
    echo "                      DEFAULT: a"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSearch     text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: run*nii'
    echo
}

if (( $# == 0 ))
then
    FslSliceTime_help
    exit
fi

# set some variables
SubjectMaster=Subjects
Order=
UserEmail=`whoami`@umich.edu
TR=2
SubDirectory=func
Prepend=a
RunDirectory='run*'
VolumeSearch='run*nii'
StartTime=`date`
UseOrder=false
FslVer=`basename ${FSLDIR}`

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:O:U:T:f:n:r:v:h opt
    do
        case "$opt" in
            h)
                FslSliceTime_help
                exit
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            O)
                Order=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            T)
                TR=${OPTARG}
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
                FslSliceTime_help
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

# check if Order file was specified
if [ ! -z "$Order" ]
then
    UseOrder=true
    if [ ! -e $Order ]
    then
        echo
        echo "Order file ${Order} does not exist."
        echo "Check -O option"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi
fi

echo "FSLDIR : ${FSLDIR}"

# all subjects should be good, now we do actual work
for iSubject in "${subjects[@]}"
do
    # grab files again
    FuncDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunDirs=(`ls -d ${FuncDirec}/${RunDirectory}`)

    # slice time correct images
    echo "slice time correcting : ${RunDirs[@]}"
    for iRun in "${RunDirs[@]}"
    do
        WarpFiles=(`ls -d ${iRun}/${VolumeSearch}`)
        for iWarpFile in "${WarpFiles[@]}"
        do
            TopDir=`dirname ${iWarpFile}`
            FileName=`basename ${iWarpFile}`

            if [ "$UseOrder" = true ]
            then
                slicetimer -i ${iWarpFile} \
                    --out=${TopDir}/${Prepend}${FileName} \
                    --repeat=${TR}
                    --ocustom=${Order}
            else
                slicetimer -i ${iWarpFile} \
                    --out=${TopDir}/${Prepend}${FileName} \
                    --repeat=${TR}
            fi

            # create SliceCheck.nii
            3dcalc -a ${TopDir}/${Prepend}${FileName}'[$]' -b ${iWarpFile}'[$]' -expr 'a-b' \
                -prefix ${TopDir}/SliceCheck.nii -overwrite

            descrip="${Prepend}${FileName} - ${FileName} `fslnvols ${iWarpFile}` vol"
            nifti_tool -mod_hdr -overwrite -mod_field descrip "${descrip}" \
                -infiles ${TopDir}/SliceCheck.nii

            # note fsl version
            nifti_tool -mod_hdr -overwrite -mod_field descrip "${FslVer}" \
                -infiles ${TopDir}/${Prepend}${FileName}
        done
    done
done

EndTime=`date`
# mail when all are finished
mail -s 'FslSliceTime.bash' ${UserEmail} <<EOF
Start: ${StartTime}
End  : ${EndTime}

Slice timed ${#subjects[@]} subjects
EOF
    
