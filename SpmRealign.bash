#!/bin/bash

function SpmRealign_help
{
    echo
    echo "SpmRealign.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to realign functional images using SPM defaults."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend output realigned functional images"
    echo "                      DEFAULT: R"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSearch     text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: a_spm8_run*nii'
    echo
}

if (( $# == 0 ))
then
    SpmRealign_help
    exit
fi

# set some variables
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
SubDirectory=func
Prepend=R
RunDirectory='run*'
VolumeSearch='a_spm8_run*nii'

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:U:f:n:r:v:h opt
    do
        case "$opt" in
            h)
                FslRealignFmri_help
                exit
                ;;
            M)
                SubjectMaster=${OPTARG}
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
                SpmRealign_help
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

# everything should be good so let's do the actual work now
DirToMake=./matlabScripts/CustomBatch/SpmRealign/`date +%Y_%m`
mkdir -p ${DirToMake}
if ! [[ -d ${DirToMake} ]]
then
    echo "Cannont create directory ${DirToMake}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

now=`date +%Y%m%d_%H%M%S`
MFile=${DirToMake}/SpmRealign_${now}.m
echo > ${MFile}
if ! [[ -f ${MFile} ]]
then
    echo "Cannot create file ${MFile}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

# everything is good now we create MFile
let index=1
for iSubject in "${subjects[@]}"
do
    # grab runs for subject
    FullDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunFiles=(`ls -d ${FullDirec}/${RunDirectory}/${VolumeSearch}`)
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.data = {" >> ${MFile}

    for oneRun in ${RunFiles[@]}
    do
        fname=`basename ${oneRun}`
        pname=`dirname ${oneRun}`
        echo "cellstr(spm_select('ExtFPList', '${pname}', '^${fname}', inf));" >> ${MFile}
    done
    echo "};" >> ${MFile}

    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.quality = 0.9;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.sep = 4;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.fwhm = 5;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.rtm = 1;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.interp = 2;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.wrap = [0 0 0];" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.eoptions.weight = '';" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.roptions.which = [2 1];" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.roptions.interp = 4;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.roptions.wrap = [0 0 0];" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.roptions.mask = 1;" >> ${MFile}
    echo "matlabbatch{${index}}.spm.spatial.realign.estwrite.roptions.prefix = '${Prepend}';" >> ${MFile}
    echo >> ${MFile}
    let index++
done

echo "% set spm defaults before running anything" >> ${MFile}
echo "fprintf(1, 'Setting SPM defaults...');" >> ${MFile}
echo "spm('defaults', 'FMRI');" >> ${MFile}
echo "spm_jobman('initcfg');" >> ${MFile}
echo "fprintf(1, 'Done!\\n');" >> ${MFile}
echo "spm_jobman('run_nogui', matlabbatch);" >> ${MFile}

# now let's run the script
StartTime=`date`
RequiredPath=`pwd`/`dirname ${MFile}`
fname=`basename ${MFile}`
fname=${fname/%.m/}
matlab -nodisplay << EOF
addpath('${RequiredPath}')
${fname}
exit
EOF

for iSubject in "${subjects[@]}"
do
    # grab runs for subject
    FullDirec=${MasterDir}/${iSubject}/${SubDirectory}
    RunFiles=(`ls -d ${FullDirec}/${RunDirectory}/${VolumeSearch}`)

    for oneRun in ${RunFiles[@]}
    do
        pname=`dirname ${oneRun}`
        fname=`basename ${oneRun}`
        nifti_tool -input ${pname}/${Prepend}${fname} -mod_hdr -mod_field qform_code 1 -mod_field sform_code 1 -overwrite
    done
done

# mail when finished
EndTime=`date`
mail -s 'SpmRealign.bash' ${UserEmail} << EOF
Start: ${StartTime}
End  : ${EndTime}

Corrected ${#subjects[@]} subjects
EOF
