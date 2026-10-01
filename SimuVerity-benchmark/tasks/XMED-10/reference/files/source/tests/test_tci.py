import matplotlib.pyplot as plt
import numpy as np
from python_anesthesia_simulator import Patient, TCIController, Simulator


age = 28
height = 165
weight = 65
sex = 0
patient_info = [age, height, weight, sex]

sampling_time = 2
propofol_target = 4
remifentanil_target = 3
norepinephrine_target = 2
atracurium_target = 0.5
# init the patient simulation
patient_tci = Patient(
    patient_info,
    ts=sampling_time,
    model_propo='Schnider',
    model_remi='Minto',
    model_nore="Oualha",
)
simulator_wo_tci = Simulator(patient_tci)
patient_tci_2 = Patient(
    patient_info,
    ts=sampling_time,
    model_propo='Schnider',
    model_remi='Minto',
    model_nore="Oualha",
)

simulator_w_tci = Simulator(patient_tci_2,
                            tci_propo='Effect_site',
                            tci_remi='Effect_site',
                            tci_nore='Plasma',
                            tci_atra='Effect_site',
                            )

# initialize TCI
tci_propo = TCIController(
    patient_info,
    sampling_time=sampling_time,
    drug_name='Propofol',
    model_used="Schnider",
)
tci_remi = TCIController(
    patient_info,
    sampling_time=sampling_time,
    drug_name='Remifentanil',
    model_used="Minto",
)
tci_nore = TCIController(
    patient_info,
    sampling_time=sampling_time,
    drug_name='Norepinephrine',
    model_used="Oualha",
)
tci_atra = TCIController(
    patient_info,
    sampling_time=sampling_time,
    drug_name='Atracurium',
)

N_simu = 15 * 60 // sampling_time  # 10 minutes


for time_step in range(N_simu):
    u_propo = tci_propo.one_step(propofol_target)
    u_remi = tci_remi.one_step(remifentanil_target)
    u_nore = tci_nore.one_step(norepinephrine_target)
    u_atra = tci_atra.one_step(atracurium_target)

    simulator_wo_tci.one_step(u_propo, u_remi, u_nore, u_atra)

# test
results_simulator_w_tci = simulator_w_tci.full_sim(
    inputs_propo=np.array([propofol_target]*N_simu),
    inputs_remi=np.array([remifentanil_target]*N_simu),
    inputs_nore=np.array([norepinephrine_target]*N_simu),
    inputs_atra=np.array([atracurium_target]*N_simu),
)


def test_tci_ouput_range():
    """ensure that the command belong in the acceptable range."""
    assert (simulator_wo_tci.dataframe['u_propo'] >= 0).all()
    assert (simulator_wo_tci.dataframe['u_propo'] <= tci_propo.infusion_max).all()
    assert (simulator_wo_tci.dataframe['u_remi'] >= 0).all()
    assert (simulator_wo_tci.dataframe['u_remi'] <= tci_remi.infusion_max).all()


def test_tci_behavior():
    # ensure that the concentration reach the target (maximum of 1%)
    assert simulator_wo_tci.dataframe['x_propo_4'].iloc[-1] <= propofol_target * 1.01
    assert simulator_wo_tci.dataframe['x_propo_4'].iloc[-1] >= propofol_target * 0.99
    assert simulator_wo_tci.dataframe['x_remi_4'].iloc[-1] <= remifentanil_target * 1.01
    assert simulator_wo_tci.dataframe['x_remi_4'].iloc[-1] >= remifentanil_target * 0.99
    assert simulator_wo_tci.dataframe['x_nore_1'].iloc[-1] <= norepinephrine_target * 1.01
    assert simulator_wo_tci.dataframe['x_nore_1'].iloc[-1] >= norepinephrine_target * 0.99
    assert simulator_wo_tci.dataframe['x_atra_4'].iloc[-1] <= atracurium_target * 1.01
    assert simulator_wo_tci.dataframe['x_atra_4'].iloc[-1] >= atracurium_target * 0.99

    # ensure that there is not too much overshoot (maximum 5%)
    assert (simulator_wo_tci.dataframe['x_propo_4'] <= propofol_target * 1.05).all()
    assert (simulator_wo_tci.dataframe['x_remi_4'] <= remifentanil_target * 1.05).all()
    assert (simulator_wo_tci.dataframe['x_nore_1'] <= norepinephrine_target * 1.2).all()
    assert (simulator_wo_tci.dataframe['x_atra_4'] <= atracurium_target * 1.05).all()


def test_tci_from_simulator():
    # ensure that both simulation are the same
    for signal in ['u_propo', 'u_remi', 'x_propo_1', 'x_remi_1', 'u_nore', 'x_nore_1', 'u_atra', 'x_atra_1']:
        assert np.allclose(simulator_wo_tci.dataframe[signal].iloc[:-1], results_simulator_w_tci[signal])


if __name__ == "__main__":
    plt.subplot(2, 1, 1)
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, simulator_wo_tci.dataframe['u_propo'], label='Propofol (mg/s)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, simulator_wo_tci.dataframe['u_remi'], label='Remifentanil (ug/s)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['u_nore'], label='Norepinephrine (ug/s)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['u_atra']/100, label='Atracurium (ug/s)')
    plt.plot(results_simulator_w_tci['Time'] / 60,
             results_simulator_w_tci['u_propo'], '--', label='Propofol in simulator (mg/s)')
    plt.plot(results_simulator_w_tci['Time'] / 60,
             results_simulator_w_tci['u_remi'], '--', label='Remifentanil in simulator (ug/s)')
    plt.ylabel('Drug rate')
    plt.grid()
    plt.legend()

    plt.subplot(2, 1, 2)
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['x_propo_4'], label='Propofol (ug/ml)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['x_remi_4'], label='Remifentanil (ng/ml)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['x_nore_1'], label='Norepinephrine (ng/ml)')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60,
             simulator_wo_tci.dataframe['x_atra_4'], label='Atracurium (ng/ml)')
    plt.plot(results_simulator_w_tci['Time'] / 60,
             results_simulator_w_tci['x_propo_4'], '--', label='Propofol in simulator (ug/ml)')
    plt.plot(results_simulator_w_tci['Time'] / 60,
             results_simulator_w_tci['x_remi_4'], '--', label='Remifentanil in simulator (ng/ml)')
    # plot target
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, [propofol_target] *
             len(simulator_wo_tci.dataframe['Time']), '--', label='Propofol target')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, [remifentanil_target] *
             len(simulator_wo_tci.dataframe['Time']), '--', label='Remifentanil target')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, [norepinephrine_target] *
             len(simulator_wo_tci.dataframe['Time']), '--', label='Norepinephrine target')
    plt.plot(simulator_wo_tci.dataframe['Time'] / 60, [atracurium_target] *
             len(simulator_wo_tci.dataframe['Time']), '--', label='Atracurium target')

    plt.ylabel('Effect site concentration ')
    plt.xlabel('Time (min)')
    plt.legend()
    plt.grid()

    plt.show()

    test_tci_ouput_range()
    test_tci_behavior()
    test_tci_from_simulator()
    print("All tests passed successfully.")
