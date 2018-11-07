import argparse
import numpy as np
import os.path

parser = argparse.ArgumentParser(
    description='Motion parameter post-processing for fMRI')

parser.add_argument('--inputtype',
    choices=['spm', 'fsl', 'afni', 'hcp'],
    required=True,
    help="package used for motion correction",
    dest='InputType')
parser.add_argument('--inputfile',
    required=True,
    help="input file name",
    dest="InputFile")
parser.add_argument('--outputfd',
    required=True,
    help="output file name recording FD values",
    dest="OutputFd")
    
args = parser.parse_args()

data = np.loadtxt(args.InputFile)
if args.InputType == "hcp":
    data = data[:, 0:6]

# check column numbers
if data.shape[1] != 6:
    raise ValueError("File: {}, expected 6 coulmns but found {}".
                     format(args.InputFile, data.shape[1]))

if args.InputType in ["fsl", "afni"]:
    data = data[:, [3, 4, 5, 0, 1, 2]]

# x y z roll pitch yaw
factor = 50 / 360 if args.InputType == "hcp" else 50
print("factor used: {}".format(factor))
print(data.shape)
data[:, [3, 4, 5]] = data[:, [3, 4, 5]] * factor

frameDis = np.sum(np.abs(np.diff(data, axis=0)), axis=1)
frameDis = np.concatenate(([0], frameDis))

np.savetxt(args.OutputFd, frameDis, fmt='%02.6f')
