import argparse
import numpy as np
import os.path

parser = argparse.ArgumentParser(
    description='Motion parameter post-processing for fMRI')

parser.add_argument('--inputtype',
    nargs=1,
    choices=['spm', 'fsl', 'afni'],
    required=True,
    help="package used for motion correction",
    dest='InputType')
parser.add_argument('--inputfile',
    nargs=1,
    required=True,
    help="input file name",
    dest="InputFile")
parser.add_argument('--outputtype',
    nargs=1,
    choices=['vector', 'matrix'],
    required=True,
    help="output type",
    dest="OutputType")
parser.add_argument('--outputfile',
    nargs=1,
    required=True,
    help="output file name recording censor vectors",
    dest="OutputFile")
parser.add_argument('--outputfd',
    nargs=1,
    required=True,
    help="output file name recording FD values",
    dest="OutputFd")
    
args = parser.parse_args()

data = np.loadtxt(args.InputFile[0])

# check column numbers
if data.shape[1] != 6:
    raise ValueError(
        "File: {}, expected 6 coulmns but found {}".
        format(args.InputFile[0], data.shape[1]))

if args.InputType[0] in ["fsl", "afni"]:
    data = data[:, [3, 4, 5, 0, 1, 2]]

# x y z roll pitch yaw
data[:, [3, 4, 5]] = data[:, [3, 4, 5]] * 50
frameDis = np.sum(np.abs(np.diff(data, axis=0)), axis=1)
frameDis = np.concatenate(([0], frameDis))
thres = 0.9

if args.OutputType[0] == "matrix":
    output = np.zeros(frameDis.size, sum(frameDis > thres))
    loc = np.where(frameDis > thres)
    cols = np.array(range(0, loc.size))
else:
    output = np.double(frameDis < thres)
 
np.savetxt(args.OutputFile[0], output, fmt='%d')
np.savetxt(args.OutputFd[0], frameDis, fmt='%02.6f')
