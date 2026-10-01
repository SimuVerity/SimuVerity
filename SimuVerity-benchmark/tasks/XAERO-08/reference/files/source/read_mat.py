import mat73
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Load four variables
h = mat73.loadmat('simulink_stuff/h.mat')
t = mat73.loadmat('simulink_stuff/timer.mat')
x = mat73.loadmat('simulink_stuff/x.mat')
tht = mat73.loadmat('simulink_stuff/theta.mat')

# Verify dict keys
# print(h.keys())
# print(t.keys())
# print(x.keys())
# print(tht.keys())

# Index '0' of all arrays is the timestamp
# Index '1' stores the values we want
h_vals = h['h'][1]
t_vals = t['t'][1]
x_vals = x['x'][1]
tht_vals = tht['tht'][1]

# Create DataFrame
df = pd.DataFrame()

# Insert into dataframe
df['t'] = t_vals
df['x'] = x_vals
df['h'] = h_vals
df['tht'] = tht_vals

# Sanity check dataframe
# print(df.columns)
print(df.info())
print(df.head())

# Visualise h vs t
df.plot(x='t', y='h', style='.')
plt.show()