#!/bin/bash

if [ $# != 1 ]
then
    echo "HcpConvertFs.bash fs_subject_dir"
    exit
fi

inDir=$1
if [ ! -d ${inDir} ]
then
    echo "Input directory does not exist: ${inDir}"
    echo "* * * A B O R T I N G * * *"
    exit
fi

# inflated pial white sphere sphere.reg thickness curv sulc
# ######## #### ##### ###### ########## ######### #### ####

scriptDir=`dirname $0`
subject=`basename ${inDir}`
outDir=${inDir}/converted
native=${outDir}/native
hcp=${outDir}/hcp
export SUBJECTS_DIR=`dirname ${inDir}`
if [ -d ${outDir} ]
then
    rm -rf ${outDir}
fi
mkdir ${outDir} ${native} ${hcp}

#Find c_ras offset between FreeSurfer surface and volume and generate matrix to transform surfaces
MatrixX=$(mri_info ${inDir}/mri/brain.finalsurfs.mgz | grep "c_r" | cut -d "=" -f 5 | sed s/" "/""/g)
MatrixY=$(mri_info ${inDir}/mri/brain.finalsurfs.mgz | grep "c_a" | cut -d "=" -f 5 | sed s/" "/""/g)
MatrixZ=$(mri_info ${inDir}/mri/brain.finalsurfs.mgz | grep "c_s" | cut -d "=" -f 5 | sed s/" "/""/g)
echo "1 0 0 ""$MatrixX" > ${inDir}/mri/c_ras.mat
echo "0 1 0 ""$MatrixY" >> ${inDir}/mri/c_ras.mat
echo "0 0 1 ""$MatrixZ" >> ${inDir}/mri/c_ras.mat
echo "0 0 0 1" >> ${inDir}/mri/c_ras.mat

for hemi in l r
do
    if [ "${hemi}" == l ]
    then
        outHemi=L
        structure=CORTEX_LEFT
    else
        outHemi=R
        structure=CORTEX_RIGHT
    fi

    echo "STATUS: Converting ${outHemi} surfaces."
    for surface in pial white inflated
    do
        if [ "${surface}" = pial ]
        then
            stype=ANATOMICAL
            secondary="-surface-secondary-type GRAY_WHITE"
        elif [ "${surface}" = white ]
        then
            stype=ANATOMICAL
            secondary="-surface-secondary-type PIAL"
        else
            stype=INFLATED
            secondary=
        fi

        workingImg=${native}/${subject}.${outHemi}.${surface}.native.surf.gii
        mris_convert ${inDir}/surf/${hemi}h.${surface} ${workingImg}
		wb_command -set-structure ${native}/${subject}.${outHemi}.${surface}.native.surf.gii \
            ${structure} -surface-type ${stype} ${secondary}
		wb_command -surface-apply-affine ${workingImg} ${inDir}/mri/c_ras.mat ${workingImg}
    done

    wb_command -surface-average ${native}/${subject}.${outHemi}.midthickness.native.surf.gii \
        -surf ${native}/${subject}.${outHemi}.white.native.surf.gii \
        -surf ${native}/${subject}.${outHemi}.pial.native.surf.gii
    wb_command -set-structure ${native}/${subject}.${outHemi}.midthickness.native.surf.gii \
        ${structure} -surface-type ANATOMICAL -surface-secondary-type MIDTHICKNESS

    echo "STATUS: Converting ${outHemi} spheres."
    for surface in sphere.reg sphere
    do
        mris_convert ${inDir}/surf/${hemi}h.${surface} \
            ${native}/${subject}.${outHemi}.${surface}.native.surf.gii
        wb_command -set-structure ${native}/${subject}.${outHemi}.${surface}.native.surf.gii \
            ${structure} -surface-type SPHERICAL
    done

    echo "STATUS: Converting ${outHemi} parcellations."
    for map in aparc aparc.a2009s
    do
        workingImg=${native}/${subject}.${outHemi}.${map}.native.label.gii
        mris_convert --annot ${inDir}/label/${hemi}h.${map}.annot \
            ${inDir}/surf/${hemi}h.white \
            ${workingImg}
        wb_command -set-structure ${workingImg} ${structure}
        wb_command -set-map-names ${workingImg} \
            -map 1 "$subject"_"$outHemi"_"$map"
        wb_command -gifti-label-add-prefix ${workingImg} \
            "${outHemi}_" \
            ${workingImg}
    done

    echo "STATUS: Converting ${outHemi} metrics."
    for metric in sulc thickness curv
    do
        workingImg=${native}/${subject}.${outHemi}.${metric}.native.shape.gii
        mris_convert -c ${inDir}/surf/${hemi}h.${metric} \
            ${inDir}/surf/${hemi}h.white \
            ${workingImg}
        wb_command -set-structure ${workingImg} ${structure}
        wb_command -metric-math "var * -1" ${workingImg} \
            -var var ${workingImg}
        wb_command -set-map-names ${workingImg} \
            -map 1 "$subject"_"$outHemi"_${metric}
        wb_command -metric-palette ${workingImg} \
            MODE_AUTO_SCALE_PERCENTAGE \
            -pos-percent 2 98 \
            -palette-name Gray_Interp \
            -disp-pos true \
            -disp-neg true \
            -disp-zero true
    done

	#Thickness specific operations
    workingImg=${native}/${subject}.${outHemi}.thickness.native.shape.gii
    roiImg=${native}/${subject}.${outHemi}.roi.native.shape.gii
    midthickness=${native}/${subject}.${outHemi}.midthickness.native.surf.gii
    curv=${native}/${subject}.${outHemi}.curv.native.shape.gii
	wb_command -metric-math "abs(thickness)" ${workingImg} \
        -var thickness ${workingImg}
	wb_command -metric-palette ${workingImg} MODE_AUTO_SCALE_PERCENTAGE \
        -pos-percent 4 96 \
        -interpolate true \
        -palette-name videen_style \
        -disp-pos true \
        -disp-neg false \
        -disp-zero false
	wb_command -metric-math "thickness > 0" ${roiImg} \
        -var thickness ${workingImg}
	wb_command -metric-fill-holes ${midthickness} ${roiImg} ${roiImg}
	wb_command -metric-remove-islands ${midthickness} ${roiImg} ${roiImg} 
	wb_command -set-map-names ${roiImg} -map 1 "$Subject"_${outHemi}_ROI
	wb_command -metric-dilate ${workingImg} ${midthickness} 10 ${workingImg} -nearest
	wb_command -metric-dilate ${curv} ${midthickness} 10 ${curv} -nearest
done

echo "STATUS: Merging parcellations to native.dlabel.nii"
for map in aparc aparc.a2009s
do
    wb_command -cifti-create-label ${native}/${subject}.${map}.native.dlabel.nii \
        -left-label ${native}/${subject}.L.${map}.native.label.gii \
        -right-label ${native}/${subject}.R.${map}.native.label.gii
    wb_command -set-map-names ${native}/${subject}.${map}.native.dlabel.nii \
        -map 1 "$subject"_${map}
done

echo "STATUS: Merging metrices into native.dscalar.nii"
for metric in sulc thickness curv
do
    wb_command -cifti-create-dense-scalar ${native}/${subject}.${metric}.native.dscalar.nii \
        -left-metric ${native}/${subject}.L.${metric}.native.shape.gii \
        -right-metric ${native}/${subject}.R.${metric}.native.shape.gii
    wb_command -set-map-names ${native}/${subject}.${metric}.native.dscalar.nii \
        -map 1 "$subject"_${metric}
done

echo "STATUS: Resampling to hcp space."
for hemi in L R
do
    for res in 32k 164k
    do
        curSphere=${native}/${subject}.${hemi}.sphere.reg.native.surf.gii
        newSphere=${scriptDir}/standard_mesh_atlases/resample_fsaverage/fs_LR-deformed_to-fsaverage.${hemi}.sphere.${res}_fs_LR.surf.gii

        # convert surfaces to hcp space
        echo "STATUS: Resample ${hemi} surfaces to ${res}_FS_LR space." 
        for surface in inflated pial white midthickness
        do
            inImg=${native}/${subject}.${hemi}.${surface}.native.surf.gii
            outImg=${hcp}/${subject}.${hemi}.${surface}.${res}_FS_LR.surf.gii

            wb_command -surface-resample \
                ${inImg} \
                ${curSphere} \
                ${newSphere} \
                BARYCENTRIC \
                ${outImg}
        done

        curMidthickness=${native}/${subject}.${hemi}.midthickness.native.surf.gii
        newMidthickness=${hcp}/${subject}.${hemi}.midthickness.${res}_FS_LR.surf.gii

        # convert metrics to hcp space
        echo "STATUS: Resample ${hemi} metrices to ${res}_FS_LR space." 
        for metric in sulc curv thickness
        do
            inImg=${native}/${subject}.${hemi}.${metric}.native.shape.gii
            outImg=${hcp}/${subject}.${hemi}.${metric}.${res}_FS_LR.shape.gii

            wb_command -metric-resample \
                ${inImg} \
                ${curSphere} \
                ${newSphere} \
                ADAP_BARY_AREA \
                ${outImg} \
                -area-surfs ${curMidthickness} ${newMidthickness}
        done

        # map labels to HCP space
        echo "STATUS: Resample ${hemi} labels to ${res}_FS_LR space." 
        for map in aparc aparc.a2009s
        do
            inImg=${native}/${subject}.${hemi}.${map}.native.label.gii
            outImg=${hcp}/${subject}.${hemi}.${map}.${res}_FS_LR.label.gii

            wb_command -label-resample \
                ${inImg} \
                ${curSphere} \
                ${newSphere} \
                ADAP_BARY_AREA \
                ${outImg} \
                -area-surfs ${curMidthickness} ${newMidthickness}
        done
    done
done
