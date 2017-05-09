#!/bin/bash

function FslPCA_Help
{
    echo
    echo "FslCompCor.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to perform principal component analysis on both white"
    echo "matter and csf masked time series. (Given techical jargon later.)"
    echo
    echo "OPTIONS:"
    echo "  -B CsfOutDir            output directory for csf principal components. This directory"
    echo "                          is created in the run directory of the fMRI file"
    echo "                          DEFAULT: RegressDir/2MM_CSF_PCA"
    echo "  -C CsfMask              file name for csf anatomical mask"
    echo "                          DEFAULT: 2mm_Alvin_CsfMask.nii"
    echo "  -M SubjectMaster        directory to scan for subjects"
    echo "                          DEFAULT: Subjects"
    echo "  -U UserEmail            email address mailed when job finished"
    echo "                          DEFAULT: `whoami`@umich.edu"
    echo "  -W WhiteMatterMask      file name for white matter anatomical mask"
    echo "                          DEFAULT: 2mm_Prior_Afni_WhiteMask.nii"
    echo "  -X WhiteMatterOutDir    output directory for white matter principal components. This"
    echo "                          directory is created in the run directory of the fMRI file"
    echo "                          DEFAULT: RegressDir/2MM_WM_PCA"
    echo "  -f SubDirectory         directory to run directories or files, search directlry below"
    echo "                          subject directory"
    echo "                          DEFAULT: func"
    echo "  -m MaskPath             path to directory holding csf and wm anatomical masks,"
    echo "                          searched directly below subject directory"
    echo "                          DEFULAT: anatomy/t1spgr.anat/2MM_MASKS"
    echo "  -r RunDirectory         text to search for run directories, if using wild card"
    echo "                          expression, surround it with single quotes. For example:"
    echo "                          'run*'"
    echo '                          DEFAULT: run*'
    echo "  -v VolumeSearch         text to search for volumes"
    echo "                          if using a wild_car expression, surround it with single"
    echo "                          quotes for example: 'ra_spm8_run*nii'"
    echo '                          DEFAULT: run*nii'
    echo
}

if (( $# == 0 ))
then
    FslPCA_Help
    exit
fi

# set some variables
CsfOutDir=RegressDir/2MM_CSF_PCA
CsfMask=2mm_Alvin_CsfMask.nii
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
WhiteMatterMask=2mm_Prior_Afni_WhiteMask.nii
WhiteMatterOutDir=RegressDir/2MM_WM_PCA
SubDirectory=func
MaskPath=anatomy/t1spgr.anat/2MM_MASKS
RunDirectory='run*'
VolumeSearch='ra_spm8_run*nii'

# parse the arguments
while (( $# > 0 ))
do
    while getopts B:C:M:U:W:X:f:m:r:v:h opt
    do
        case "$opt" in
            h)
                FslPCA_Help
                exit
                ;;
            B)
                CsfOutDir=${OPTARG}
                ;;
            C)
                CsfMask=${OPTARG}
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            W)
                WhiteMatterMask=${OPTARG}
                ;;
            X)
                WhiteMatterOutDir=${OPTARG}
                ;;
            f)
                SubDirectory=${OPTARG}
                ;;
            m)
                MaskPath=${OPTARG}
                ;;
            r)
                RunDirectory=${OPTARG}
                ;;
            v)
                VolumeSearch=${OPTARG}
                ;;
            [?])
                echo "Invalid option: ${opt}"
                FslPCA_Help
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
    SubjDir=${MasterDir}/${iSubject}

    # check MaskPath existence
    if [ ! -d ${SubjDir}/${MaskPath} ]
    then
        echo
        echo "Subject ${iSubject} is missing MaskPath"
        echo "Searched for ${MaskPath}, but found nothing"
        echo "Check -m option"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    # check CsfMask existence
    if [ ! -f ${SubjDir}/${MaskPath}/${CsfMask} ]
    then
        echo
        echo "Subject ${iSubject} is missing csf mask ${CsfMask}"
        echo "Looked in ${SubjDir}/${MaskPath}"
        echo "Check -C flag"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    # check WhiteMatterMask existence
    if [ ! -f ${SubjDir}/${MaskPath}/${WhiteMatterMask} ]
    then
        echo
        echo "Subject ${iSubject} is missing white matter mask ${WhiteMatterMask}"
        echo "Looked in ${SubjDir}/${MaskPath}"
        echo "Check -W flag"
        echo " * * * A B O R T I N G * * *"
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
        elif [ ${#RunFiles[@]} -ne 1 ]
        then
            echo
            echo "Subject ${iSubject} has more then one file to warp."
            echo "Looked in ${RunDirect} with regex '${VolumeSearch}'"
            echo "There can only be one."
            echo "Check -v option."
            echo " * * * A B O R T I N G * * *"
            echo
            exit
        else
            RunName=`basename ${oneRun}`
            echo "Subject : ${iSubject}/${RunName} found ${#RunFiles[@]} run(s)"
        fi

        # check if PCA was already performed for csf
        if [ -d ${oneRun}/${CsfOutDir} ]
        then
            echo
            echo "Subject ${iSubject} csf pca done already."
            echo "Run: ${oneRun}"
            echo "Remove existing pca directories and run again."
            echo
            exit
        fi

        # check if PCA was already performed for wm
        if [ -d ${oneRun}/${WhiteMatterOutDir} ]
        then
            echo
            echo "Subject ${iSubject} wm pca done already."
            echo "Run: ${oneRun}"
            echo "Remove existing pca directories and run again."
            echo
            exit
        fi
    done
done

# now do the real work
for iSubject in "${subjects[@]}"
do
    # grab files again
    FuncDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunDirs=(`ls -d ${FuncDirec}/${RunDirectory}`)
    wm=${MasterDir}/${iSubject}/${MaskPath}/${WhiteMatterMask}
    csf=${MasterDir}/${iSubject}/${MaskPath}/${CsfMask}

    # perform PCA
    echo "peforming pca : ${RunDirs[@]}"
    for iRun in "${RunDirs[@]}"
    do
        mkdir -p ${iRun}/${CsfOutDir}
        mkdir -p ${iRun}/${WhiteMatterOutDir}
        WarpFiles=(`ls -d ${iRun}/${VolumeSearch}`)
        for iWarpFile in "${WarpFiles[@]}"
        do
            fname=`basename ${iWarpFile}`
            pname=`dirname ${iWarpFile}`

            # detrend input first
            3dTproject -input ${iWarpFile} \
                -prefix ${iRun}/detrend_${fname} \
                -polort 2

            # pca on csf
            3dpc -vmean -vnorm -nscale -pcsave ALL \
                -prefix ${iRun}/${CsfOutDir}/csf \
                -mask ${csf} \
                ${iRun}/detrend_${fname}

            # log command
            echo "3dTproject -input ${iWarpFile} \\" > ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "    -prefix ${iRun}/detrend_${fname} \\" >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "    -polort 2" >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "3dpc -vmean -vnorm -nscale -pcsave ALL \\" >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "    -prefix ${iRun}/${CsfOutDir}/csf \\" >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "    -mask ${csf} \\" >> ${iRun}/${CsfOutDir}/CsfCommand.log
            echo "    ${iRun}/detrend_${fname}.nii"  >> ${iRun}/${CsfOutDir}/CsfCommand.log

            # pca on wm
            3dpc -vmean -vnorm -nscale -pcsave ALL \
                -prefix ${iRun}/${WhiteMatterOutDir}/wm \
                -mask ${wm} \
                ${iRun}/detrend_${fname}

            # log command
            echo "3dTproject -input ${iWarpFile} \\" > ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "    -prefix ${iRun}/detrend_${fname} \\" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "    -polort 2" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "3dpc -vmean -vnorm -nscale -pcsave ALL \\" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "    -prefix ${iRun}/${WhiteMatterOutDir}/wm \\" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "    -mask ${wm} \\" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log
            echo "    ${iRun}/detrend_${fname}.nii" >> ${iRun}/${WhiteMatterOutDir}/WmCommand.log

            # clean up files
            rm ${iRun}/detrend_${fname}
            rm ${iRun}/${WhiteMatterOutDir}/*{BRIK,HEAD}
            rm ${iRun}/${CsfOutDir}/*{BRIK,HEAD}
        done
    done
done
