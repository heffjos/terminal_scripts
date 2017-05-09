#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

function AfniSeedCorr_help
{
    echo
    echo "AfniSeedCorr.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to extract an mean time series from an roi defined as"
    echo "a nifti file and correlate it with the whole brain resulting in a seed-based correlation"
    echo "map."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "  -R Roi              path to nifti file defining an roi."
    echo "                      If you want perform multiple seed-based correlations, put the arguments"
    echo "                      in quotation marks."
    echo "                      REQUIRED"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -a AddOn            A flag indicating to not overwrite previous correlations and start"
    echo "                      file numbering from the last in SeedCorr"
    echo "                      DEFAUL: false"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject"
    echo "                      directory"
    echo "                      DEFAULT: func"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSeasrch    text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo "                      DEFAULT: clean_w2mm_ra_spm8_run*nii"
    echo
}

if (( $# == 0 ))
then
    AfniSeedCorr_help
    exit
fi


# set some variables
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
SubDirectory=func
RunDirectory='run*'
VolumeSearch='clean_w2mm_ra_spm8_run*nii'
StartTime=`date`
RoiIndex=0
nSubjects=0
AddOn=false

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:U:R:af:r:v:h opt
    do
        case "$opt" in
            h)
                AfniSeedCorr_Help
                exit
                ;;
            M)
                SubjectMaster=${OPTARG}
                ;;
            U)
                UserEmail=${OPTARG}
                ;;
            R)
                RoiArg=${OPTARG}
                ;;   
            a)
                AddOn=true
                ;;
            f)
                SubDirectory=${OPTARG}
                ;;
            r)
                RunDirectory=${OPTARG}
                ;;
            v)
                VolumeSearch=${OPTARG}
                ;;
            [?])
                echo "Inavlid option: ${opt}"
                AfniSeedCorr_Help
                exit
                ;;
        esac
    done

    shift $((OPTIND-1))
    OPTIND=0

    # assume arguments with no flags are subjects
    if [ $# -gt 0 ]
    then
        subjects[${nSubjects}]=$1
        let nSubjects++
        shift
    fi
done

###

# make sure rois were specified and that they exist
if [ ${#RoiArg[@]} -eq 0 ]
then
    echo "No rois specified."
    echo "Not doing anything."
    echo "* * * A B O R T I N G * * *"
    exit
else
    for oneRoi in ${RoiArg[@]}
    do
        if [ ! -f ${oneRoi} ]
        then
            echo "Roi file: ${oneRoi}"
            echo "does not exist."
            echo " * * * A B O R T I N G * * *"
            exit
        else
            Rois[${RoiIndex}]=${oneRoi}
            let RoiIndex++
        fi
    done
fi

# make sure participants were specified
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
        elif [ ${#RunFiles[@]} -gt 1 ]
        then
            echo
            echo "Participant ${iSubject} has ${#RunFiles[@]} run files in ${oneRun}."
            echo "Only 1 is expected"
            echo "Run files: ${RunFiles[@]}"
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

# checks are good, dow work now
for onePar in ${subjects[@]}
do
    echo ${onePar}
    FuncDir=${MasterDir}/${onePar}/${SubDirectory}
    for oneRun in `ls -1d ${FuncDir}/${RunDirectory}`
    do
        Vol=`echo ${oneRun}/${VolumeSearch}`
        OutDir=${oneRun}/SeedCorr
        mkdir ${OutDir}
        CNum=1
        OutScript=${OutDir}/Command_`printf %02d ${CNum}`.bash

        RoiNum=1
        if [ ${AddOn} == true ]
        then
            # handle correlation map numbering
            while [ -f ${OutDir}/rmap_`printf %04d ${RoiNum}`.nii ]
            do
                let RoiNum++
            done

            # handle out script numbering
            while [ -f ${OutScript} ]
            do
                let CNum++
                OutScript=${OutDir}/Command_`printf %02d ${CNum}`.bash
            done
        else
            # initialize script
            echo "#!/bin/bash" > ${OutScript}
            echo >> ${OutScript}
        fi

        for oneRoi in ${Rois[@]}
        do
            # set up naming
            RoiFileName=`basename ${oneRoi}`
            TimeSeries=${OutDir}/${RoiFileName/nii/1D}

            # write useful information to out script
            echo "# ${RoiFileName} : `printf %04d ${RoiNum}`" >> ${OutScript}
            echo >> ${OutScript}

            # extract mean time series
            echo "3dmaskave -mask ${oneRoi} -quiet ${Vol} > ${TimeSeries}" >> ${OutScript}
            echo >> ${OutScript}

            # correlate 1D with time series
            CorrMap=${OutDir}/rmap_`printf %04d ${RoiNum}`.nii
            echo "3dTcorr1D -pearson -prefix ${CorrMap} ${Vol} ${TimeSeries} -overwrite" >> ${OutScript} 
            echo "nifti_tool -input ${CorrMap} \\" >> ${OutScript}
            echo "    -mod_hdr -mod_field descrip ${RoiFileName/nii/1D} -overwrite" >> ${OutScript}
            echo >> ${OutScript}

            # z-score the correlation map
            ZMap=${OutDir}/zmap_`printf %04d ${RoiNum}`.nii
            echo "3dcalc -a ${CorrMap} -expr 'atanh(a)' -prefix ${ZMap} -overwrite" >> ${OutScript}
            echo "nifti_tool -input ${ZMap} \\" >> ${OutScript}
            echo "    -mod_hdr -mod_field descrip ${RoiFileName/nii/1D} -overwrite" >> ${OutScript}
            echo >> ${OutScript}
            echo >> ${OutScript}

            let RoiNum++
        done

        chmod +x ${OutScript}

        ${OutScript} 2>&1 | tee ${OutDir}/Command_`printf %02d ${CNum}`.log
        echo "Done with par ${onePar}."
        echo
    done
done
    
