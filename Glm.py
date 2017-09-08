import os
import re
import sys
import argparse

import numpy as np
import nibabel as nib

from scipy import stats

from nibabel import cifti2 as ci
from nibabel import nifti1 as ni1
from nibabel import nifti2 as ni2

CIFTI_EXTENSIONS = (
    "dconn",
    "dtseries",
    "pconn",
    "ptseries",
    "dscalar",
    "dlabel",
    "pdconn",
    "dpconn",
    "pconnseries",
    "pconnscalar",
    "dfan",
    "dfibersamp",
    "dfansamp"
)

CIFTI_RE_EXTENSIONS = "\.(" + "|".join(CIFTI_EXTENSIONS) + ")\.nii$"
CIFTI_RE = re.compile(CIFTI_RE_EXTENSIONS)

NIFTI_RE = re.compile(r"\.nii(\.gz)?$")

def check_nifti_ext(file_name):
    return bool(NIFTI_RE.search(file_name))

def check_cifti_ext(file_name):
    return bool(CIFTI_RE.search(file_name))

def check_image_ext(file_name):
    return check_nifti_ext(file_name) or check_cifti_ext(file_name)

def cifti_check_same_space(lhs, rhs):
    print("cifti_check_same_space not implemented.")
    print("You are treading over water.")
    return True

def nifti_check_same_space(lhs, rhs):
    in_same_space = True
    lhs_dim = lhs.header["dim"]
    rhs_dim = rhs.header["dim"]

    if lhs_dim[0] == rhs_dim[0]:
        in_same_space = (in_same_space and 
            np.all(lhs_dim[1:lhs_dim[0]] == rhs_dim[1:rhs_dim[0]]))
    elif (lhs_dim[0] - rhs_dim[0]) == 1:
        in_same_space = (in_same_space and
            np.all(lhs_dim[1:rhs_dim[0]] == rhs_dim[1:rhs_dim[0]]))
    elif (lhs_dim[0] - rhs_dim[0]) == -1:
        in_same_space = (in_same_space and
            np.all(lhs_dim[1:lhs_dim[0]] == rhs_dim[1:lhs_dim[0]]))
    else:
        in_same_space = False
    
    return (np.all(lhs.affine == rhs.affine) and 
        in_same_space)
            

parser = argparse.ArgumentParser(description = "Perform HCP regression of design onto input")

parser.add_argument("--input", 
    required = True,
    help = "file name for single participant image data",
)
parser.add_argument("--design",
    required = True,
    help = "file name for design (can be image or text file)"
)
parser.add_argument("--mask",
    required = False,
    help = "file name for the mask; values not equal to one are included."
)
parser.add_argument("--out",
    required = True,
    help = "output file name for GLM parameter estimates"
)

parser.add_argument("--des_norm",
    required = False,
    action = "store_true",
    help = "switch on normalization of the design matrix columns to unit std. deviation"
)

parser.add_argument("--cifti",
    required = False,
    action = "store_true",
    help = "input/output is cifti format"
)

args = parser.parse_args()

# check if input files exist
if not os.path.isfile(args.input):
    print("Input file does not exist: {}".format(args.input))
    sys.exit()
if args.cifti and not check_cifti_ext(args.input):
    print("Expecting cifti image extension.")
    print("Input: {}".format(args.input))
    sys.exit()
elif not args.cifti and check_cifti_ext(args.input):
    print("Expecting nifti image. Input may be possibly cifti")
    print("Input: {}".format(args.input))
    sys.exit()

if not os.path.isfile(args.design):
    print("Design file does not exist: {}".format(args.design))
    sys.exit()

spatial_regression = check_image_ext(args.design)
if spatial_regression:
    if ((args.cifti and not check_cifti_ext(args.design)) or
        (not args.cifti and check_cifti_ext(args.design))):
        print("Input:  {}".format(args.input))
        print("Design: {}".format(args.design))
        print("Input and design must be both ciftis or both niftis when performing spatial regression.")
        sys.exit()

if args.mask:
    if not os.path.isfile(args.mask):
        print("Mask file does not exist: {}".format(args.mask))
        sys.exit()
    if ((args.cifti and not check_cifti_ext(args.mask)) or
        (not args.cifti and check_cifti_ext(args.mask))):
        print("Input: {}".format(args.input))
        print("Mask: {}".format(args.design))
        print("Input and mask must be both ciftis or both niftis.")

# load in the data
img = nib.load(args.input)
is_cifti = args.cifti
Y = img.get_data()
Y_shape = Y.shape

if args.mask:
    print("Using mask {}".format(args.mask))
    mask = nib.load(args.mask)
    if is_cifti and not cifti_check_same_space(img, mask):
        print("Input: {}".format(args.input))
        print("Mask: {}".format(args.mask))
        print("Input and mask are not in the same space.")
        sys.exit()
    elif not is_cifti and not nifti_check_same_space(img, mask):
        print("Input: {}".format(args.input))
        print("Mask: {}".format(args.mask))
        print("Input and mask are not in the same space.")
        sys.exit()
    mask_data = mask.get_data() != 0

    if len(mask_data.shape) < len(Y.shape):
        if is_cifti:
            Y = Y[:, mask_data].T
        else:
            Y = Y[mask_data, :]
    else:
        if is_cifti:
            Y = Y[mask_data].T
        else:
            Y = Y[mask_data]
elif is_cifti:
    Y = Y.T
else:
    Y = Y.reshape(np.prod(Y.shape[0:3]), Y.shape[-1])

if spatial_regression:
    design = nib.load(args.design)
    if is_cifti and not cifti_check_same_space(img, design):
        print("Input: {}".format(args.input))
        print("Design: {}".format(args.desing))
        print("Input and design are not in the same space.")
        sys.exit()
    elif not is_cifti and not nifti_check_same_space(img, design):
        print("Input: {}".format(args.input))
        print("Design: {}".format(args.design))
        print("Input and design are not in the same space.")
        sys.exit()
    H = design.get_data()
    H_shape = H.shape

    if args.mask:
        if len(mask_data.shape) < len(H.shape):
            if is_cifti:
                H = H[:, mask_data].T
            else:
                H = H[mask_data, :]
        else:
            if is_cifti:
                H = H[:, mask_data].T
            else:
                H = H[mask_data]
    elif is_cifti:
        H = H.T
    else:
        H = H.reshape(np.prod(H.shape[0:3]), H.shape[-1])
else:
    H = np.loadtxt(args.design) 
    n_comp = H.shape[1]

# niftis are usually stored 
# ciftis are usually stored n x voxels (n = time or components)
# spatial regression -  Y: voxels x time, H: voxels x components, B: components x time
# temporal regression - Y: time x voxels, H: time x components,   B: components x voxels

if spatial_regression:
    Y = Y - Y.mean(axis = 0)[np.newaxis, :]
else:
    Y = Y.T - Y.T.mean(axis = 0)[np.newaxis, :]

if args.des_norm:
    H = stats.zscore(H)
else:
    H = H - H.mean(axis = 0)[np.newaxis, :]

if spatial_regression:
    B = np.linalg.pinv(H).dot(Y).T   # time x components
    out_file_name = re.compile(r"\.txt$").sub("", args.out)
    np.savetxt(out_file_name + ".txt", B, fmt = "%.8f")
else:
    B = np.linalg.pinv(H).dot(Y)
    if is_cifti:
        out_file_name = CIFTI_RE.sub("", args.out)

        if args.mask:
            tmp_B = np.zeros((n_comp, Y_shape[1]))
            tmp_B[:, mask] = tmp_B
            B = tmp_B

        scalar_map = ci.Cifti2MatrixIndicesMap(
            (0,), 
            "CIFTI_INDEX_TYPE_SCALARS",
            maps = [ci.Cifti2NamedMap() for i in range(n_comp)],
        )

        geometry_map = ci.Cifti2MatrixIndicesMap(
            (1,), 
            "CIFTI_INDEX_TYPE_BRAIN_MODELS", 
            maps = img.header.matrix.get_index_map(1)
        )

        matrix = ci.Cifti2Matrix()
        matrix.append(scalar_map)
        matrix.append(geometry_map)
        hdr = ci.Cifti2Header(matrix)
        out = ci.Cifti2Image(B, hdr)
        out.nifti_header.set_intent(3006, name = "ConnDenseScalar")
        out.nifti_header.set_data_dtype(np.float32)
        ci.save(out, out_file_name + ".dscalar.nii")
    else:
        out_file_name = NIFTI_RE.sub("", args.out)

        if args.mask:
            tmp_B = np.zeros(Y_shape[:3] + (n_comp,))
            tmp_B[mask_data, :] = B.T
            B = tmp_B
        elif is_cifti:
            B = B.T
        else:
            B = B.T.reshape(Y_shape[:3] + (n_comp,))

        out = ni1.Nifti1Image(B, img.affine)
        out.header.set_data_dtype(np.float32)
        xyz, t = tuple(ni1.unit_codes[key] for key in img.header.get_xyzt_units())
        out.header.set_xyzt_units(xyz, t)
        out.header["qform_code"] = 4
        out.header["sform_code"] = 4
        out.header["descrip"] = "Glm.py"
        ni1.save(out, out_file_name + ".nii.gz")
