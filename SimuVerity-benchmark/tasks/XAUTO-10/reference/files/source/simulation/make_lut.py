import numpy as np
import multiprocessing
import functools
from simulation import *

# Run simulation with ratios from 0 to 100%
# Take run with best desired yaw minus actual yaw

min_angle = -0.6356685485304198
max_angle =  0.6345749252211202
min_velocity = 0.5
max_velocity = 40 # m/s
max_torque = 80 # Nm
steering_angle_resolution = 17
velocity_resolution = 17
n_samples = 100
skip = 200

def makeEntry(angle, velocity):
  min_diff = None
  l, r = None, None
  for ratio in np.linspace(0, 100, n_samples):
    rp = ratio/100
    lin, rin = max_torque*rp, max_torque*(1-rp)
    ax, ay, wheel_velocity, yaw_rate, des_rate = simulate(velocity, velocity, lin, rin, angle)

    # Take best after index 200
    for k in range(skip, len(yaw_rate)):
      diff = abs(des_rate[k] - yaw_rate[k])

      if (min_diff is None) or (diff < min_diff):
        min_diff = diff
        l, r = lin, rin
    # Take index 200
    #k = skip
    #diff = abs(des_rate[k] - yaw_rate[k])
    #
    #if (min_diff is None) or (diff < min_diff):
    #  min_diff = diff
    #  l, r = lin, rin

  #lut[-1].append((l, r))
  #print('.', end='', flush=True)

  return l, r

def unwrapArgs(args):
  lock, progress, rest = args
  i, j = rest[0]
  with lock:
    progress[i][j] = 'o'
    print_progress(progress)
  # print(args)
  result = makeEntry(*rest[1])
  with lock:
    progress[i][j] = 'x'
    print_progress(progress)
  return rest[0], result

def simulationInputIterator():
  for i, angle in zip(range(steering_angle_resolution), np.linspace(min_angle, max_angle, steering_angle_resolution)):
    for j, velocity in zip(range(velocity_resolution), np.linspace(min_velocity, max_velocity, velocity_resolution)):
      yield (i, j), (angle, velocity)

def print_progress(progress):
  s = '\n' * 8
  for i, row in enumerate(progress):
    s += "%3d " % i
    for j, val in enumerate(row):
      s += str(val) + ' '
    s += '\n'

  print(s)

def init_pool_processes(the_lock):
  lock = the_lock

def generate():
  # Prepare empty lut
  lut = [[None for j in range(velocity_resolution)] for i in range(steering_angle_resolution)]

  with multiprocessing.Manager() as manager:
    lock = manager.Lock()
    progress = manager.list([manager.list(['_' for j in range(velocity_resolution)]) for i in range(steering_angle_resolution)])
    with multiprocessing.Pool(16) as p:
      results = p.map(unwrapArgs, map(lambda x: (lock, progress, x), simulationInputIterator()))
      print()
      for (i, j), (l, r) in results:
        lut[i][j] = (l, r)

  return lut

def toCLUT(lut):
  s = '{\n'
  for i in lut:
    s += '\t{ '
    for j in i:
      s += '{ %f, %f, }, ' % (j[0], j[1])
    s += '}, \n'
  s += '};'
  return s

def generate_to_file(filename):
  lut = generate()
  clut = toCLUT(lut)
  print(clut)
  with open(filename, 'w') as lut_file:
    lut_file.write(clut)

lut = generate_to_file("myfile")
