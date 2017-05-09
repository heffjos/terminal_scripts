#!/bin/bash

function SpmSliceTime_help
{
    echo
    echo "SpmSliceTime.bash [OPTIONS] Subject1 Subject2 ... SubjectN"
    echo
    echo "AFNI programs: 3dcalc, nifti_tool"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to slice time correct functional images using SPM."
    echo "As an additional quality check, this function outputs the nifti file SliceCheck.nii"
    echo "which is the last volume of the slice time corrected image minus the last volume of"
    echo "the original image. SliceCheck.nii should equal 0 near the center of the z plane and"
    echo "grow in value as the z plane increases. All volumes are resampled to matched the center"
    echo "z slice."
    echo
    echo "OPTIONS:"
    echo "  -F FMRI_TR          the TR for volume acquisition"
    echo "                      DEFAULT: 2.0"
    echo "  -G ReferenceSlice   set teh value for the reference slice for timing correction"
    echo "                      this can be a number or a wor. Allowable words:"
    echo "                      'first', 'middle', 'last' without quotes"
    echo "                      DEFAULT: middle"
    echo "  -M SubjectMaster    directory to scan for subjects"
    echo "                      DEFAULT: Subjects"
    echo "  -O Order            slice acquisition order"
    echo "                      can be ascending, descending, or a text/mat file name"
    echo "                      The file must be a single-column custom slice order file"
    echo "                      The first slice is 1. Typically you will not need to use this option"
    echo "                      as the default acquisition order is ascending for hospital or North Campus scans"
    echo "                      DEFAULT: ascending"
    echo "  -U UserEmail        email address mailed when job finished"
    echo "                      DEFAULT: `whoami`@umich.edu"
    echo "  -f SubDirectory     directory to run directories or files, search directly below subject directory"
    echo "                      DEFAULT: func"
    echo "  -n Prepend          text to prepend slice time corrected image"
    echo "                      DEFAULT: a_spm8_"
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
    SpmSliceTime_help
    exit
fi

# set some variables
TR='2.0'
ReferenceSlice=middle
ReferenceIsNum=false
SubjectMaster=Subjects
Order=ascending
UserEmail=`whoami`@umich.edu
SubDirectory=func
Prepend=a_spm8_
RunDirectory='run*'
VolumeSearch='run*nii'
StartTime=`date`
Testing=false

# parse the arguments
while (( $# > 0 ))
do
    while getopts hF:G:M:O:U:f:n:r:tv: opt
    do
        case "$opt" in
            h)
                SpmSliceTime_help
                exit
                ;;
            F)
                TR=${OPTARG}
                ;;
            G)
                ReferenceSlice=${OPTARG}
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
            f)
                SubDirectory=${OPTARG}
                ;;
            n)
                Prepend=${OPTARG}
                ;;
            r)
                RunDirectory=${OPTARG}
                ;;
            t)
                Testing=true
                ;;
            v)
                VolumeSearch=${OPTARG}
                ;;
            [?])
                echo "Invalid option: ${opt}"
                SpmSliceTime_help
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

# check if valid ReferenceSlice value
re='^[0-9]+([.][0-9]+)?$'
if [[ ${ReferenceSlice} != first && ${ReferenceSlice} != middle && ${ReferenceSlice} != last ]]
then
    ReferenceIsNum=true
    if ! [[ ${ReferenceSlice} =~ $re ]]
    then
        echo "Invalid ReferenceSlice: ${ReferenceSlice}"
        echo "Check your -G flag."
        echo "* * * A B O R T I N G * * *"
        echo
        exit
    fi
fi

# check if valid TR
if ! [[ $TR =~ $re ]]
then
    echo "Inavlid TR: ${TR}, expected number"
    echo "Check your -F flag."
    echo " * * * A B O R T I N G * * *"
    echo
    exit
fi

# check if valid order
if [[ ${Order} != ascending && ${Order} != descending ]]
then
    if ! [[ -f ${Order} ]]
    then    
        echo "Invalid order: ${Order}"
        echo "Check your -O flag."
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi
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

# now check if all runs have same slices
NumSlice=`fslhd ${AllFiles[0]} | grep ^dim3 | awk '{print $NF}'`
for OneFile in ${AllFiles[@]}
do
    tmp=`fslhd ${OneFile} | grep ^dim3 | awk '{print $NF}'`
    if [[ ${tmp} != ${NumSlice} ]]
    then
        echo "All files must have same number of slices."
        echo "Number of slices different for ${OneFile}"
        echo "Expected ${NumSlice} but found ${tmp}"
        echo " * * * A B O R T I N G * * *"
        exit
    fi
done

# now check if reference slice is less than total slices
if [[ ${ReferenceIsNum} == true ]]
then
    echo checking ${ReferenceSlice} ${NumSlice}
    if [[ ${ReferenceSlice} -gt ${NumSlice} ]]
    then
        echo "Reference slice is greater than the number of slices."
        echo "Reference slice is ${ReferenceSlice}"
        echo "Expected it to be lower than ${NumSlice}"
        echo " * * * A B O R T I N G * * *"
        exit
    fi
fi

# do testing
if [[ ${Testing} == true ]]
then
    echo "TR:             $TR"
    echo "ReferenceSlice: $ReferenceSlice"
    echo "SubjectMaster:  $SubjectMaster"
    echo "Order:          $Order"
    echo "UserEmail:      $UserEmail"
    echo "SubDirectory:   $SubDirectory"
    echo "Prepend:        $Preprend"
    echo "RunDirectory:   $RunDirectory"
    echo "VolumeSearch:   $VolumeSearch"
    echo "StartTime:      $StartTime"
    echo "Testing:        $Testing"
    echo AllFiles: ${AllFiles[@]}
    exit
fi

# everything should be good so let's do the actual work now
DirToMake=./matlabScripts/CustomBatch/SpmSliceTime/`date +%Y_%m`
mkdir -p ${DirToMake}
if ! [[ -d ${DirToMake} ]]
then
    echo "Cannont create directory ${DirToMake}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

now=`date +%Y%m%d_%H%M%S`
MFile=${DirToMake}/SpmSliceTime_${now}.m
echo > ${MFile}
if ! [[ -f ${MFile} ]]
then
    echo "Cannot create file ${MFile}"
    echo "Check your permissions."
    echo " * * * A B O R T I N G * * *"
    exit
fi

# make matlab script
echo 'matlabbatch{1}.spm.temporal.st.scans = {' >> ${MFile}
for Run in ${AllFiles[@]}
do
    fname=`basename ${Run}`
    pname=`dirname ${Run}`
    echo "cellstr(spm_select('ExtFPList', '${pname}', '^${fname}', inf));" >> ${MFile}
done
echo "};" >> ${MFile}
echo >> ${MFile}
echo "NumSlice = ${NumSlice};" >> ${MFile}
echo "TR = ${TR};" >> ${MFile}
echo "matlabbatch{1}.spm.temporal.st.nslices = NumSlice;" >> ${MFile}
echo "matlabbatch{1}.spm.temporal.st.tr = TR;" >> ${MFile}
echo "matlabbatch{1}.spm.temporal.st.ta = TR-(TR/NumSlice);" >> ${MFile}
if [[ ${Order} == ascending ]]
then
    echo "matlabbatch{1}.spm.temporal.st.so = 1:NumSlice;" >> ${MFile}
elif [[ ${Order} == descending ]]
then
    echo "matlabbatch{1}.spm.temporal.st.so = NumSlice:-1:1;" >> ${MFile}
else
    echo "matlabbatch{1}.spm.temporal.st.so = load(${Order});" >> ${MFile}
fi

if [[ ${ReferenceSlice} == first ]]
then
    echo "matlabbatch{1}.spm.temporal.st.refslice = 1;" >> ${MFile}
elif [[ ${ReferenceSlice} == middle ]]
then
    echo "matlabbatch{1}.spm.temporal.st.refslice = ceil(NumSlice/2);" >> ${MFile}
elif [[ ${ReferenceSlice} == last ]]
then
    echo "matlabbatch{1}.spm.temporal.st.refslice = NumSlice;" >> ${MFile}
else
    echo "matlabbatch{1}.spm.temporal.st.refslice = ${ReferenceSlice};" >> ${MFile}
fi

echo "matlabbatch{1}.spm.temporal.st.prefix = '${Prepend}';" >> ${MFile}

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

# now let's check slice time correction
echo
echo "AllDone now creating SliceCheck.nii for subjects"
for OneFile in ${AllFiles[@]}
do
    echo ${OneFile}
    fname=`basename ${OneFile}`
    pname=`dirname ${OneFile}`
    Corrected=${pname}/${Prepend}${fname}
    nifti_tool -mod_hdr -mod_field qform_code 1 -mod_field sform_code 1 -input ${Corrected} -overwrite
    3dcalc -a ${OneFile}'[$]' -b ${Corrected}'[$]' -expr 'b-a' -prefix ${pname}/SliceCheck.nii -overwrite
done

# mail when finished
EndTime=`date`
mail -s 'SpmSliceTime.bash' ${UserEmail} << EOF
Start: ${StartTime}
End  : ${EndTime}

Corrected ${#AllFiles[@]} files
EOF
