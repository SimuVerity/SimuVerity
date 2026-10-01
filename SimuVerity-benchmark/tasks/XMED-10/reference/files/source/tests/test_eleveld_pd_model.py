import matplotlib.pyplot as plt
import numpy as np

from python_anesthesia_simulator import patient, Simulator

# %% Simulation setup

# Simulation duration in seconds
Tsim = 3600
# Patient physical data
weight = 70
height = 170
sex = 0

ts = 1

sqi = 50
sqi_delay = 120 * (1 - sqi/100)

Nsim = int(Tsim/ts)

# Initialize infusion profiles for propofol, remifentanil and norepinephrine
propofol_infusion_profile = np.zeros((Nsim,))        # mg/s
remifentanil_infusion_profile = np.zeros((Nsim,))    # ug/s
norepinephrine_infusion_profile = np.zeros((Nsim,))    # ug/s

# Propofol profile
propofol_infusion_profile[0:int(50/ts)] = 2          # 2 mg/s for 50 seconds
propofol_infusion_profile[int(150/ts):] = 0.2        # 0.2 mg/s from 150s onward

# %% Young patient simulation
age = 20
bis_delay_1 = 15 + np.exp(0.0517*age)
George_1 = patient.Patient([age, height, weight, sex],
                           ts=ts,
                           model_propo="Eleveld",
                           model_bis="Eleveld",
                           random_PD=False)
George_11 = patient.Patient([age, height, weight, sex],
                            ts=ts,
                            model_propo="Eleveld",
                            model_bis="Eleveld",
                            random_PD=False)
George_111 = patient.Patient([age, height, weight, sex],
                             ts=ts,
                             model_propo="Eleveld",
                             model_bis="Eleveld",
                             random_PD=False)

simu_11 = Simulator(George_11)
simu_111 = Simulator(George_111)

# Full simulation
df_George_1 = George_1.full_sim(u_propo=propofol_infusion_profile)
# One step simulation
for k in range(Nsim-1):
    uProp_k = propofol_infusion_profile[k]
    simu_11.one_step(input_propo=uProp_k,)
    simu_111.one_step(input_propo=uProp_k, sqi=sqi)

# %% Medium age patient simulation
age = 60
bis_delay_2 = 15 + np.exp(0.0517*age)
George_2 = patient.Patient([age, height, weight, sex],
                           ts=ts,
                           model_propo="Eleveld",
                           model_bis="Eleveld",
                           random_PD=False)
George_22 = patient.Patient([age, height, weight, sex],
                            ts=ts,
                            model_propo="Eleveld",
                            model_bis="Eleveld",
                            random_PD=False)
George_222 = patient.Patient([age, height, weight, sex],
                             ts=ts,
                             model_propo="Eleveld",
                             model_bis="Eleveld",
                             random_PD=False)

simu_22 = Simulator(George_22)
simu_222 = Simulator(George_222)

# Full simulation
df_George_2 = George_2.full_sim(u_propo=propofol_infusion_profile)
# One step simulation
for k in range(Nsim-1):
    uProp_k = propofol_infusion_profile[k]
    simu_22.one_step(input_propo=uProp_k)
    simu_222.one_step(input_propo=uProp_k, sqi=sqi)

# %% Elderly patient simulation
age = 80
bis_delay_3 = 15 + np.exp(0.0517*age)
George_3 = patient.Patient(
    [age, height, weight, sex],
    ts=ts,
    model_propo="Eleveld",
    model_bis="Eleveld",
    random_PD=False
)
George_33 = patient.Patient(
    [age, height, weight, sex],
    ts=ts,
    model_propo="Eleveld",
    model_bis="Eleveld",
    random_PD=False
)
George_333 = patient.Patient(
    [age, height, weight, sex],
    ts=ts,
    model_propo="Eleveld",
    model_bis="Eleveld",
    random_PD=False
)

simu_33 = Simulator(George_33)
simu_333 = Simulator(George_333)


# Full simulation
df_George_3 = George_3.full_sim(u_propo=propofol_infusion_profile)
# One step simulation
for k in range(Nsim-1):
    uProp_k = propofol_infusion_profile[k]
    simu_33.one_step(input_propo=uProp_k)
    simu_333.one_step(input_propo=uProp_k, sqi=sqi)


# %% Compute the delays obtained in simulation
change = df_George_1['BIS'] != df_George_1['BIS'].shift()
first_change_index = df_George_1['BIS'][change].index[1]
simulated_delay_1 = df_George_1['Time'][first_change_index]

change = simu_11.dataframe['BIS'] != simu_11.dataframe['BIS'].shift()
first_change_index = simu_11.dataframe['BIS'][change].index[1]
simulated_delay_11 = simu_11.dataframe['Time'][first_change_index]

change = simu_111.dataframe['BIS'] != simu_111.dataframe['BIS'].shift()
first_change_index = simu_111.dataframe['BIS'][change].index[1]
simulated_delay_111 = simu_111.dataframe['Time'][first_change_index]

change = df_George_2['BIS'] != df_George_2['BIS'].shift()
first_change_index = df_George_2['BIS'][change].index[1]
simulated_delay_2 = df_George_2['Time'][first_change_index]

change = simu_22.dataframe['BIS'] != simu_22.dataframe['BIS'].shift()
first_change_index = simu_22.dataframe['BIS'][change].index[1]
simulated_delay_22 = simu_22.dataframe['Time'][first_change_index]

change = simu_222.dataframe['BIS'] != simu_222.dataframe['BIS'].shift()
first_change_index = simu_222.dataframe['BIS'][change].index[1]
simulated_delay_222 = simu_222.dataframe['Time'][first_change_index]

change = df_George_3['BIS'] != df_George_3['BIS'].shift()
first_change_index = df_George_3['BIS'][change].index[1]
simulated_delay_3 = df_George_3['Time'][first_change_index]

change = simu_33.dataframe['BIS'] != simu_33.dataframe['BIS'].shift()
first_change_index = simu_33.dataframe['BIS'][change].index[1]
simulated_delay_33 = simu_33.dataframe['Time'][first_change_index]

change = simu_333.dataframe['BIS'] != simu_333.dataframe['BIS'].shift()
first_change_index = simu_333.dataframe['BIS'][change].index[1]
simulated_delay_333 = simu_333.dataframe['Time'][first_change_index]


# %%


def test_delay():
    """Check that the BIS delays obtained in the simulations match those of the Eleveld model"""

    assert simulated_delay_1 >= np.floor(bis_delay_1)
    assert simulated_delay_11 >= np.floor(bis_delay_1)
    assert simulated_delay_111 >= np.floor(bis_delay_1+sqi_delay)
    assert simulated_delay_2 >= np.floor(bis_delay_2)
    assert simulated_delay_22 >= np.floor(bis_delay_2)
    assert simulated_delay_222 >= np.floor(bis_delay_2+sqi_delay)
    assert simulated_delay_3 >= np.floor(bis_delay_3)
    assert simulated_delay_33 >= np.floor(bis_delay_1)
    assert simulated_delay_333 >= np.floor(bis_delay_3+sqi_delay)


# %% plot
if __name__ == '__main__':
    fig, ax = plt.subplots(2)

    ax[0].plot(df_George_1['Time'], df_George_1['BIS'])
    ax[0].plot(simu_11.dataframe['Time'], simu_11.dataframe['BIS'], '--')
    ax[0].plot(df_George_2['Time'], df_George_2['BIS'])
    ax[0].plot(simu_22.dataframe['Time'], simu_22.dataframe['BIS'], '--')
    ax[0].plot(df_George_3['Time'], df_George_3['BIS'])
    ax[0].plot(simu_33.dataframe['Time'], simu_33.dataframe['BIS'], '--')

    ax[1].plot(df_George_1['Time'], df_George_1['u_propo'])

    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("Propofol infusion")
    ax[1].set_xlabel("Time (min)")
    for i in range(2):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    fig, ax = plt.subplots(2)

    ax[0].plot(df_George_1['Time'], df_George_1['BIS'])
    ax[0].plot(simu_111.dataframe['Time'], simu_111.dataframe['BIS'], '--')
    ax[0].plot(df_George_2['Time'], df_George_2['BIS'])
    ax[0].plot(simu_222.dataframe['Time'], simu_222.dataframe['BIS'], '--')
    ax[0].plot(df_George_3['Time'], df_George_3['BIS'])
    ax[0].plot(simu_333.dataframe['Time'], simu_333.dataframe['BIS'], '--')

    ax[1].plot(df_George_1['Time'], df_George_1['u_propo'])

    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("Propofol infusion")
    ax[1].set_xlabel("Time (min)")
    for i in range(2):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    test_delay()
    print('All tests passed successfully!')
