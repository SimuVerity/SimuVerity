import matplotlib.pyplot as plt
import numpy as np

from python_anesthesia_simulator import Patient, Simulator


# Simulation duration in seconds
Tsim = 1000
# Patient physical data
age = 35
weight = 70
height = 170
sex = 0

# %% Baseline simulation
# Sampling time in seconds
ts = 1

# Number of simulation steps
Nsim = int(Tsim/ts)

# Initialize infusion profiles for propofol, remifentanil and norepinephrine
propofol_infusion_profile = np.zeros((Nsim,))        # mg/s
remifentanil_infusion_profile = np.zeros((Nsim,))    # ug/s
norepinephrine_infusion_profile = np.zeros((Nsim,))    # ug/s

# Propofol profile
propofol_infusion_profile[0:int(50/ts)] = 2          # 2 mg/s for 50 seconds
propofol_infusion_profile[int(150/ts):] = 0.2        # 0.2 mg/s from 150s onward

# Remifentanil profile
remifentanil_infusion_profile[0:int(100/ts)] = 1      # 1 ug/s for 100 seconds
remifentanil_infusion_profile[int(200/ts):] = 0.1    # 0.1 ug/s from 200s onward

# norepinephrine profile
norepinephrine_infusion_profile[int(1800/ts):] = 0.1    # 0.1 ug/s from 1800s onward

# Patient object
George_1 = Patient([age, height, weight, sex],
                   ts=ts,
                   model_propo="Schnider",
                   model_remi="Minto",
                   model_nore="Beloeil",
                   random_PD=False)

df_George_1 = George_1.full_sim(u_propo=propofol_infusion_profile,
                                u_remi=remifentanil_infusion_profile,
                                u_nore=norepinephrine_infusion_profile)

# %% Simulation ts 50
# Sampling time in seconds
ts = 50

# Number of simulation steps
Nsim = int(Tsim/ts)

# Initialize infusion profiles for propofol, remifentanil and norepinephrine
propofol_infusion_profile = np.zeros((Nsim,))        # mg/s
remifentanil_infusion_profile = np.zeros((Nsim,))    # ug/s
norepinephrine_infusion_profile = np.zeros((Nsim,))    # ug/s

# Propofol profile
propofol_infusion_profile[0:int(50/ts)] = 2          # 2 mg/s for 50 seconds
propofol_infusion_profile[int(150/ts):] = 0.2        # 0.2 mg/s from 150s onward

# Remifentanil profile
remifentanil_infusion_profile[0:int(100/ts)] = 1      # 1 ug/s for 100 seconds
remifentanil_infusion_profile[int(200/ts):] = 0.1    # 0.1 ug/s from 200s onward

# norepinephrine profile
norepinephrine_infusion_profile[int(1800/ts):] = 0.1    # 0.1 ug/s from 1800s onward

# Patient object
George_2 = Patient([age, height, weight, sex],
                   ts=ts,
                   model_propo="Schnider",
                   model_remi="Minto",
                   model_nore="Beloeil",
                   random_PD=False)


df_George_2 = George_2.full_sim(u_propo=propofol_infusion_profile,
                                u_remi=remifentanil_infusion_profile,
                                u_nore=norepinephrine_infusion_profile)

# %% Simulation ts 50 one_step
# Sampling time in seconds
ts = 50

# Number of simulation steps
Nsim = int(Tsim/ts)

# Initialize infusion profiles for propofol, remifentanil and norepinephrine
propofol_infusion_profile = np.zeros((Nsim,))        # mg/s
remifentanil_infusion_profile = np.zeros((Nsim,))    # ug/s
norepinephrine_infusion_profile = np.zeros((Nsim,))    # ug/s

# Propofol profile
propofol_infusion_profile[0:int(50/ts)] = 2          # 2 mg/s for 50 seconds
propofol_infusion_profile[int(150/ts):] = 0.2        # 0.2 mg/s from 150s onward

# Remifentanil profile
remifentanil_infusion_profile[0:int(100/ts)] = 1      # 1 ug/s for 100 seconds
remifentanil_infusion_profile[int(200/ts):] = 0.1    # 0.1 ug/s from 200s onward

# norepinephrine profile
norepinephrine_infusion_profile[int(1800/ts):] = 0.1    # 0.1 ug/s from 1800s onward

# Patient object
George_3 = Patient([age, height, weight, sex],
                   ts=ts,
                   model_propo="Schnider",
                   model_remi="Minto",
                   model_nore="Beloeil",
                   random_PD=False)

simu_Greorge_3 = Simulator(George_3)

for k in range(Nsim-1):

    uProp_k = propofol_infusion_profile[k]
    uRemi_k = remifentanil_infusion_profile[k]
    uNore_k = norepinephrine_infusion_profile[k]

    simu_Greorge_3.one_step(
        input_propo=uProp_k,
        input_remi=uRemi_k,
        input_nore=uNore_k,
    )


# %% Downsample the dataframe for tests
df_George_1_downsampled = df_George_1[df_George_1['Time'].isin(df_George_2['Time'])]
George_1_vectors = {col: df_George_1_downsampled[col].tolist() for col in df_George_1_downsampled.columns}
bis_vector = George_1_vectors['BIS']
map_vector = George_1_vectors['MAP']
co_vector = George_1_vectors['CO']
tol_vector = George_1_vectors['TOL']

# %%


def test_full_sim_results():
    """Check that the simulations results are not affected by the sampling time and by the simulation method"""
    # Check results at low concentrations
    assert max(abs(bis_vector-df_George_2['BIS'])) < 1e-1
    assert max(abs(map_vector-df_George_2['MAP'])) < 1
    assert max(abs(co_vector-df_George_2['CO'])) < 1
    assert max(abs(tol_vector-df_George_2['TOL'])) < 1e-1

    assert max(abs(bis_vector-simu_Greorge_3.dataframe['BIS'])) < 1e-1
    assert max(abs(map_vector-simu_Greorge_3.dataframe['MAP'])) < 1
    assert max(abs(co_vector-simu_Greorge_3.dataframe['CO'])) < 1
    assert max(abs(tol_vector-simu_Greorge_3.dataframe['TOL'])) < 1e-1


# %% plot
if __name__ == '__main__':
    fig, ax = plt.subplots(5)

    ax[0].plot(df_George_1['Time'], df_George_1['BIS'])
    ax[0].plot(df_George_2['Time'], df_George_2['BIS'], '.')
    ax[0].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['BIS'], '*')

    ax[1].plot(df_George_1['Time'], df_George_1['MAP'])
    ax[1].plot(df_George_2['Time'], df_George_2['MAP'], '.')
    ax[1].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['MAP'], '*')

    ax[2].plot(df_George_1['Time'], df_George_1['CO'])
    ax[2].plot(df_George_2['Time'], df_George_2['CO'], '.')
    ax[2].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['CO'], '*')

    ax[3].plot(df_George_1['Time'], df_George_1['TOL'])
    ax[3].plot(df_George_2['Time'], df_George_2['TOL'], '.')
    ax[3].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['TOL'], '*')

    ax[4].plot(df_George_1['Time'], df_George_1['u_propo'])
    ax[4].plot(df_George_1['Time'], df_George_1['u_remi'])
    ax[4].plot(df_George_1['Time'], df_George_1['u_nore'])
    ax[4].plot(df_George_2['Time'], df_George_2['u_propo'], '.')
    ax[4].plot(df_George_2['Time'], df_George_2['u_remi'], '.')
    ax[4].plot(df_George_2['Time'], df_George_2['u_nore'], '.')
    ax[4].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['u_propo'], '*')
    ax[4].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['u_remi'], '*')
    ax[4].plot(simu_Greorge_3.dataframe['Time'], simu_Greorge_3.dataframe['u_nore'], '*')

    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("MAP")
    ax[2].set_ylabel("CO")
    ax[3].set_ylabel("TOL")
    ax[4].set_ylabel("infusion rates")
    ax[4].set_xlabel("Time (min)")
    for i in range(5):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    test_full_sim_results()
    print('All tests passed successfully!')
# %%
