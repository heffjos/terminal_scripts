#!/bin/bash

export FSLOUTPUTTYPE=NIFTI

# 3dTcorr1D

function CorrMaps_help
{
    echo
    echo "CorrMaps.bash [OPTIONS]"
    echo
    echo "USAGE:"
    echo
    echo "The purpose of this script is to calculate seed-based correlation images for a set of 'cleaned'"
    echo "scans, 'cleaned' meaning nuisance signals have been regressed out of the scan."
    echo
    echo "OPTIONS:"
    echo "  -I ImagePath    The image path points to the location of each subject's 'cleaned' scan."
    echo "                  Templates Subject and Run can be used here. Regular expressions can also be"
    echo "                  used, but ImagePath must be surrounded by quotes then. Here are example image"
    echo "                  paths:"
    echo "                      '/zubdata/oracle1/Eureka/[Subject]/Inactive/st_func/[Run]/FSL_CleanFiles/CwasClean_s555_w3mm_Ra_spm8*nii'"
    echo "                      '/zubdata/oracle1/Neurofeedback/[Subject]/RESTING/[Run]/CleanFiles/CwasClean_s555_w3mm_Ra_spm8_run*nii'"
    echo "                      '/zubdata/oracle1/mchance/phase2/[Subject]/func/RS/[Run]/CleanFiles/CwasClean_s555_w3mm_rarun*nii'"
    echo "                  REQUIRED"
    echo "  -M Mask         Full file path to mask used for brain when performing seed correlation."
    echo "                  REQUIRED"
    echo "  -O OutputDir    The output directory points to the directory where the output is written. A folder is created for each subject and correlation map"
    echo "                  numbers correspond to line of the coordinates in the CoordList."
    echo "                  REQUIRED"
    echo "  -R CoordList    The coord list is a text file in which each line lists the MNI coordinates and"
    echo "                  the sphere radius. Here are example contents for a coord list text file:"
    echo "                      -6 38 16 3"
    echo "                      -45 -4 7 3"
    echo "                      -3 -7 40 3"
    echo "                  REQUIRED"
    echo "  -S SubjectList  The subject list is a text file listing the subject names and run separated"
    echo "                  by comma on each line. Here are example contents for a subject list text file:"
    echo "                      Subject1,run_01"
    echo "                      Subject2,run_02"
    echo "                      Subject3,run_03"
    echo "                  Subjects and runs can be useed as 'templates' in other argments."
    echo "                  REQUIRED"
}

if (( $# == 0 ))
then
    CorrMaps_help
    exit
fi

# set some variables
ImagePath=
CoordList=
SubjectList=
OutputDir=
Mask=

# parse the arguments
while (( $# > 0 ))
do
    while getopts I:M:O:R:S: opt
    do
        case "$opt" in
            h)
                CorrMaps_help
                exit
                ;;
            I)
                ImagePath=${OPTARG}
                ;;
            M)
                Mask=${OPTARG}
                ;;
            O)
                OutputDir=${OPTARG}
                ;;
            R)
                CoordList=${OPTARG}
                ;;
            S)
                SubjectList=${OPTARG}
                ;;
            [?])
                echo "Invalid option: ${opt}"
                exit
                ;;
        esac
    done

    shift $((OPTIND-1))
    OPTIND=0

done

###

# make sure ImagePath was spcified
if [ -z "$ImagePath" ]
then
    echo "ImagePath is empty. THIS FLAG IS REQUIRED."
    echo "Read the help for its purpose."
    echo "* * * A B O R T I N G * * *"
    exit
fi

# make sure Mask was specified and exists
if [ -z "$Mask" ]
then
    echo "Mask is empty. THIS FLAG IS REQUIRED."
    echo "Read the help for its purpose."
    echo " * * * A B O R T I N G * * *"
    exit
elif [ ! -f ${Mask} ]
then
    echo "Mask does not exist: ${Mask}"
    echo "Check -M flag."
    echo " * * * A B O R T I N G * * *"
    exit
fi

# make sure OutputDir was specified and exist
if [ -z "$OutputDir" ]
then
    echo "OutputDir is empty. THIS FLAG IS REQUIRED."
    echo "Read the help for its purpose."
    echo " * * * A B O R T I N G * * *"
    exit
elif [ ! -d ${OutputDir} ]
then
    echo "OutputDir ${OutputDir} does not exist."
    echo "Check -O flag."
    echo " * * * A B O R T I N G * * *"
    exit
fi

# make sure CoordList was specified and exists
if [ -z "$CoordList" ]
then
    echo "CoordList is empty. THIS FLAG IS REQUIRED."
    echo "Read the help for its purpose."
    echo "* * * A B O R T I N G * * *"
    exit
elif [ ! -f ${CoordList} ]
then
    echo "CoordList ${CoordList} does not exist."
    echo "Check -R flag."
    echo " * * * A B O R T I N G * * *"
    exit
fi

# make sure SubjectList was specified
if [ -z "$SubjectList" ]
then
    echo "SubjectList is empty. THIS FLAG IS REQURIED."
    echo "Read the help for its purpose."
    echo "* * * A B O R T I N G * * *"
    exit
elif [ ! -f ${SubjectList} ]
then
    echo "SubjectList ${SubjectList} does not exist."
    echo "Check -S flag."
    echo "* * * A B O R T I N G * * *"
    exit
fi

# make sure all subjects have 'cleaned' scans
while read line
do
    Subject=`echo ${line} | awk -F, '{print $1}'`
    Run=`echo ${line} | awk -F, '{print $2}'`

    SubjPath=${ImagePath/'[Subject]'/${Subject}}
    SubjPath=${SubjPath/'[Run]'/${Run}}
    TmpImage=(`ls ${SubjPath}`)

    if [ ${#TmpImage[@]} -gt 1 ]
    then
        echo
        echo "Subject ${Subject} Run ${Run}"
        echo "Found more than one cleaned file"
        echo "Check -S flag."
        echo " * * * A B O R T I N G * * * "
        echo
        exit
    elif [ ${#TmpImage[@]} -eq 0 ]
    then
        echo
        echo "Subject ${Subject} Run ${Run}"
        echo "Found no clean files"
        echo "Check -S flag"
        echo " * * * A B O R T I N G * * *"
        echo
        exit
    fi

    if [ ! -f ${TmpImage} ]
    then
        echo
        echo "Subject ${Subject} Run ${Run}"
        echo "Clean file does not exist."
        echo "Check -S flag."
        echo " * * * A B O R T I N G * * * "
        echo
        exit
    fi

done < ${SubjectList}

# all subjects should be good, now we do actual work
while read line
do
    Subject=`echo ${line} | awk -F, '{print $1}'`
    Run=`echo ${line} | awk -F, '{print $2}'`
    echo "Working on Subject ${Subject} Run ${Run}"

    SubjPath=${ImagePath/'[Subject]'/${Subject}}
    SubjPath=${SubjPath/'[Run]'/${Run}}
    TmpImage=(`ls ${SubjPath}`)

    # make subject output directory
    mkdir ${OutputDir}/${Subject}

    # make log files
    sFile=${OutputDir}/${Subject}/RoiExtract.bash
    echo "#!/bin/bash" > ${sFile}
    echo >> ${sFile}

    let i=1
    while read coord
    do
        num=`printf %04d $i`
        rname=ROI_${coord// /_}_${num}

        # extract roi time course first
        echo "3dmaskave -nball ${coord} -quiet \\" >> ${sFile}
        echo "  ${TmpImage} \\" >> ${sFile}
        echo "  1> ${OutputDir}/${Subject}/${rname}.1D " >> ${sFile}
        echo >> ${sFile}

        # now do map correlation
        echo "3dTcorr1D -pearson \\" >> ${sFile}
        echo "    -prefix ${OutputDir}/${Subject}/rmap_${num}.nii \\" >> ${sFile}
        echo "    -mask ${Mask} \\" >> ${sFile}
        echo "    ${TmpImage} ${OutputDir}/${Subject}/${rname}.1D" >> ${sFile}
        echo >> ${sFile}

        # correct tailarach header
        echo "nifti_tool -mod_hdr \\" >> ${sFile} 
        echo "  -mod_field qform_code 4 \\" >> ${sFile} 
        echo "  -mod_field sform_code 4 \\" >> ${sFile} 
        echo "  -overwrite \\" >> ${sFile} 
        echo "  -input ${OutputDir}/${Subject}/rmap_${num}.nii" >> ${sFile}

        # now do fisher z transform
        echo "3dcalc -a ${OutputDir}/${Subject}/rmap_${num}.nii \\" >> ${sFile}
        echo "    -expr 'atanh(a)' \\" >> ${sFile} 
        echo "    -prefix ${OutputDir}/${Subject}/zmap_${num}.nii" >> ${sFile}
        echo >> ${sFile}

        # correct tailarach header
        echo "nifti_tool -mod_hdr \\" >> ${sFile} 
        echo "  -mod_field qform_code 4 \\" >> ${sFile} 
        echo "  -mod_field sform_code 4 \\" >> ${sFile} 
        echo "  -overwrite \\" >> ${sFile} 
        echo "  -input ${OutputDir}/${Subject}/zmap_${num}.nii" >> ${sFile}
        echo "######" >> ${sFile}
        echo >> ${sFile}

        let i++
    done < ${CoordList}

    chmod +x ${sFile}
    ${sFile} 2>&1 | tee ${OutputDir}/${Subject}/RoiExtract.log

done < ${SubjectList}

            

        
    
