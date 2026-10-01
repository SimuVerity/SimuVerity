import matplotlib.pyplot as plt
import numpy as np

from python_anesthesia_simulator import patient, Simulator

# %% Simulation setup
# Simulation duration in seconds
Tsim = 1000
# Patient physical data
age = 20
weight = 70
height = 170
sex = 0
# Sampling time
ts = 2

Nsim = int(Tsim/ts)

# Initialize infusion profiles for propofol, remifentanil and norepinephrine
propofol_infusion_profile = np.zeros((Nsim,))        # mg/s
remifentanil_infusion_profile = np.zeros((Nsim,))    # ug/s
norepinephrine_infusion_profile = np.zeros((Nsim,))    # ug/s


# Initialize sqi profiles
start_step = 500
end_step = 700

# constant sqi
sqi = 50

# Step sqi from 100 to 50
sqi_profile_1 = np.zeros((Nsim,))
sqi_profile_1[0:int(start_step/ts)] = 100
sqi_profile_1[int(start_step/ts):] = sqi

# Double step sqi from 100 to 0 and back
# To check if the current value of the bis is resumed when sqi comes back to 100
sqi_profile_2 = np.zeros((Nsim,))
sqi_profile_2[0:int(start_step/ts)] = 100
sqi_profile_2[int(start_step/ts):int(end_step/ts)] = 0
sqi_profile_2[int(end_step/ts):] = 100

# Propofol infusion profile
propofol_infusion_profile[0:int(50/ts)] = 2          # 2 mg/s for 50 seconds
propofol_infusion_profile[int(150/ts):] = 0.2        # 0.2 mg/s from 150s onward

# expected value of the BIS delay for constant and step sqi
bis_delay_1 = 120 * (1 - sqi/100)

# %% Simulation 1: Induction phase
# Create the patient object
George_1 = patient.Patient([age, height, weight, sex], ts=ts, random_PD=False)
simu_1 = Simulator(George_1)
# One step simulation
for k in range(Nsim-1):
    uProp_k = propofol_infusion_profile[k]
    simu_1.one_step(input_propo=uProp_k, sqi=sqi)

# %% Simulation 2: Maintenance phase
# Create the patient objects
George_2 = patient.Patient([age, height, weight, sex], ts=ts, random_PD=False)
George_3 = patient.Patient([age, height, weight, sex], ts=ts, random_PD=False)
George_4 = patient.Patient([age, height, weight, sex], ts=ts, random_PD=False)
# Set the targets for equilibrium point
bis_target_1 = 50
tol_target_1 = 0.9
map_target_1 = 80
# Initialize the patients at the desired equilibrium point
George_2.initialized_at_maintenance(bis_target=bis_target_1, tol_target=tol_target_1, map_target=map_target_1)
uP, uR, uN = George_2.u_propo_eq, George_2.u_remi_eq, George_2.u_nore_eq
George_3.initialized_at_maintenance(bis_target=bis_target_1, tol_target=tol_target_1, map_target=map_target_1)
uP, uR, uN = George_3.u_propo_eq, George_3.u_remi_eq, George_3.u_nore_eq
George_4.initialized_at_maintenance(bis_target=bis_target_1, tol_target=tol_target_1, map_target=map_target_1)
uP, uR, uN = George_4.u_propo_eq, George_4.u_remi_eq, George_4.u_nore_eq

simu_2 = Simulator(George_2, disturbance_profil='step')
simu_3 = Simulator(George_3, disturbance_profil='step')
simu_4 = Simulator(George_4, disturbance_profil='step')
# One step simulation
for k in range(Nsim-1):
    sqi_1 = sqi_profile_1[k]
    sqi_2 = sqi_profile_2[k]
    simu_2.one_step(input_propo=uP, input_remi=uR, input_nore=uN)
    simu_3.one_step(input_propo=uP, input_remi=uR, input_nore=uN, sqi=sqi_1)
    simu_4.one_step(input_propo=uP, input_remi=uR, input_nore=uN, sqi=sqi_2)


# Compute the delays obtained in simulation
change = simu_1.dataframe['BIS'] != simu_1.dataframe['BIS'].shift()
first_change_index = simu_1.dataframe['BIS'][change].index[1]
simulated_delay_1 = simu_1.dataframe['Time'][first_change_index]


above_threshold_3 = simu_3.dataframe[simu_3.dataframe['BIS'] > 59]
first_crossing_3 = above_threshold_3.iloc[0]
time_george_3 = first_crossing_3['Time']

above_threshold_4 = simu_4.dataframe[simu_4.dataframe['BIS'] > 59]
first_crossing_4 = above_threshold_4.iloc[0]
time_george_4 = first_crossing_4['Time']

# %%


def test_delay():
    """Check that the BIS delays obtained in the simulations match those expected"""
    # Check the delay during the induction phase
    assert simulated_delay_1 >= np.floor(bis_delay_1)
    assert time_george_3 >= 660
    assert time_george_3 < 720
    assert time_george_4 >= 700
    assert time_george_4 < 720


# %% plot
if __name__ == '__main__':

    fig, ax = plt.subplots(2)
    ax[0].plot(simu_1.dataframe['Time'], simu_1.dataframe['BIS'])
    ax[1].plot(simu_1.dataframe['Time'], simu_1.dataframe['u_propo'])
    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("Propofol infusion")
    ax[1].set_xlabel("Time (min)")
    for i in range(2):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    fig, ax = plt.subplots(2)
    ax[0].plot(simu_2.dataframe['Time'], simu_2.dataframe['BIS'])
    ax[0].plot(simu_3.dataframe['Time'], simu_3.dataframe['BIS'])
    ax[1].plot(simu_3.dataframe['Time'], simu_3.dataframe['SQI'])
    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("sqi")
    ax[1].set_xlabel("Time (min)")
    for i in range(2):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    fig, ax = plt.subplots(2)
    ax[0].plot(simu_2.dataframe['Time'], simu_2.dataframe['BIS'])
    ax[0].plot(simu_4.dataframe['Time'], simu_4.dataframe['BIS'])
    ax[1].plot(simu_4.dataframe['Time'], simu_4.dataframe['SQI'])
    ax[1].set_ylabel("sqi")
    ax[1].set_xlabel("Time (min)")
    for i in range(2):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    test_delay()
    print("All tests passed successfully.")
