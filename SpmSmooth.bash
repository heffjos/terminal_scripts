#!/bin/bash
function SpmSmooth_help
{
    echo
    echo "SpmSmooth [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to smooth functional images using SPM."
    echo
    echo "OPTIONS:"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend output realigned functional images"
    echo "                      DEFAULT: s"
    echo "  -r RunDirectory     text to search for run directories"
    echo "                      DEFAULT: run*"
    echo "  -v VolumeSearch     text to search for volumes"
    echo "                      if using a wild_car expression, surround it with single quotes"
    echo "                      for example: 'ra_spm8_run*nii'"
    echo '                      DEFAULT: w2mm_Ra_spm8_run*nii'
    echo "  -x X                smoothing in x directions"
    echo "                      DEFAULT: 8"
    echo "  -y Y                smoothing in y direction"
    echo "                      DEFAULT: 8"
    echo "  -z Z                smoothing in z direction"
    echo "                      DEFAULT: 8"
    echo
}

if (( $# == 0 ))
then
    SpmSmooth_help
    exit
fi

# set some variables
SubjectMaster=Subjects
UserEmail=`whoami`@umich.edu
SubDirectory=func
Prepend=s
RunDirectory='run*'
VolumeSearch='w2mm_Ra_spm8_run*nii'
X=8
Y=8
Z=8

# parse the arguments
while (( $# > 0 ))
do
    while getopts M:U:f:n:r:v:hx:y:z: opt
    do
        case "$opt" in
            h)
                SpmSmooth_help
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
            x)
                X=${OPTARG}
                ;;
            y)
                Y=${OPTARG}
                ;;
            z)
                Z=${OPTARG}
                ;;
            [?])
                echo "Invalid option: ${opt}"
                SpmSmooth_help
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
AllFiles=()
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
            AllFiles+=( ${RunFiles[@]} )
        fi
    done
done

# everything should be good so let's do the actual work now
DirToMake=./matlabScripts/CustomBatch/SpmSmooth/`date +%Y_%m`
mkdir -p ${DirToMake}
if ! [[ -d ${DirToMake} ]]
then
    echo "Cannont create directory ${DirToMake}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

now=`date +%Y%m%d_%H%M%S`
MFile=${DirToMake}/SpmSmooth_${now}.m
echo > ${MFile}
if ! [[ -f ${MFile} ]]
then
    echo "Cannot create file ${MFile}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

echo "matlabbatch{1}.spm.spatial.smooth.data = [..." >> ${MFile}
# everything is good now we create MFile
for OneFile in "${AllFiles[@]}"
do
    fname=`basename ${OneFile}`
    pname=`dirname ${OneFile}`
    echo "    cellstr(spm_select('ExtFPList', '${pname}', '^${fname}', inf));..." >> ${MFile}
done
echo "];" >> ${MFile}
echo "matlabbatch{1}.spm.spatial.smooth.fwhm = [${X} ${Y} ${Z}];" >> ${MFile}
echo "matlabbatch{1}.spm.spatial.smooth.dtype = 0;" >> ${MFile}
echo "matlabbatch{1}.spm.spatial.smooth.im = 0;" >> ${MFile}
echo "matlabbatch{1}.spm.spatial.smooth.prefix = '${Prepend}';" >> ${MFile}

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

for OneFile in "${AllFiles[@]}"
do
    pname=`dirname ${OneFile}`
    fname=`basename ${OneFile}`
    OrigS=`nifti_tool -disp_hdr -field sform_code -quiet -input ${OneFile}`
    OrigQ=`nifti_tool -disp_hdr -field qform_code -quiet -input ${OneFile}`
    NewFile=${pname}/${Prepend}${fname}
    nifti_tool -mod_hdr -mod_field sform_code ${OrigS} -input ${NewFile} -overwrite
    nifti_tool -mod_hdr -mod_field qform_code ${OrigQ} -input ${NewFile} -overwrite
done

# mail when finished
EndTime=`date`
mail -s 'SpmSmooth.bash' ${UserEmail} << EOF
Start: ${StartTime}
End  : ${EndTime}

Smoothed ${#AllFiles[@]} files
EOF

