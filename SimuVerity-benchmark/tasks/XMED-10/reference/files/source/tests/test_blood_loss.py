import matplotlib.pyplot as plt
from python_anesthesia_simulator import Patient, Simulator

# %% Initialization patient
ts = 5
age, height, weight, sex = 74, 164, 88, 1
George = Patient([age, height, weight, sex], ts=ts,
                 model_propo="Eleveld", model_remi="Eleveld", co_update=True)

simulator = Simulator(
    George,
    tci_propo='Effect_site',
    tci_remi='Effect_site',
)
print(simulator.tci_propo.Ad)
# %% Simulation

N_simu = int(120 * 60/ts)

uN = 0
target_propo = 3.0
target_remi = 2
blood_loss_rate = 200  # ml/min
blood_gain_rate = 50  # ml/min
time_start_bleeding = 61 * 60  # seconds
time_end_bleeding = 71 * 60  # seconds
time_start_transfusion = 75 * 60  #
time_end_transfusion = 115 * 60  # seconds
for index in range(N_simu):
    if index*ts > time_start_bleeding and index*ts < time_end_bleeding:
        blood_rate = - blood_loss_rate
    elif index*ts > time_start_transfusion and index*ts < time_end_transfusion:
        blood_rate = blood_gain_rate
    else:
        blood_rate = 0
    simulator.one_step(
        input_propo=target_propo,
        input_remi=target_remi,
        input_nore=uN,
        blood_rate=blood_rate,
    )


# %% test
index_start_bleeding = int(time_start_bleeding/ts)
index_end_bleeding = int(time_end_bleeding/ts)
index_start_transfusion = int(time_start_transfusion/ts)
index_end_transfusion = int(time_end_transfusion/ts)


def test_bleeding_effect():
    """if bleeding is not stopped, BIS, MAP and CO should decrease, TOL and drugs concentration should increase."""
    assert simulator.dataframe['x_propo_1'][index_start_bleeding] < simulator.dataframe['x_propo_1'][index_end_bleeding]
    assert simulator.dataframe['x_remi_1'][index_start_bleeding] < simulator.dataframe['x_remi_1'][index_end_bleeding]
    assert simulator.dataframe['BIS'][0] > simulator.dataframe['BIS'][index_end_bleeding]
    assert simulator.dataframe['MAP'][0] > simulator.dataframe['MAP'][index_end_bleeding]
    assert simulator.dataframe['CO'][0] > simulator.dataframe['CO'][index_end_bleeding]
    assert simulator.dataframe['TOL'][0] < simulator.dataframe['TOL'][index_end_bleeding]


def test_stop_bleeding_effect():
    """ if transfusion is not stopped, BIS, MAP and CO should increase, and TOL should decrease."""
    assert simulator.dataframe['BIS'][index_start_transfusion] < simulator.dataframe['BIS'][index_end_transfusion]
    assert simulator.dataframe['MAP'][index_start_transfusion] < simulator.dataframe['MAP'][index_end_transfusion]
    assert simulator.dataframe['CO'][index_start_transfusion] < simulator.dataframe['CO'][index_end_transfusion]
    assert simulator.dataframe['TOL'][index_start_transfusion] > simulator.dataframe['TOL'][index_end_transfusion]


# %% plot
if __name__ == '__main__':
    fig, ax = plt.subplots(3)
    Time = simulator.dataframe['Time']/60
    ax[0].plot(Time, simulator.dataframe['u_propo'])
    ax[1].plot(Time, simulator.dataframe['u_remi'])
    ax[2].plot(Time, simulator.dataframe['u_nore'])

    ax[0].set_ylabel("Propo")
    ax[1].set_ylabel("Remi")
    ax[2].set_ylabel("Nore")
    for i in range(3):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    fig, ax = plt.subplots(1)

    ax.plot(Time, simulator.dataframe['x_propo_4'], label="Propofol")
    ax.plot(Time, simulator.dataframe['x_remi_4'], label="Remifentanil")
    ax.plot(Time, simulator.dataframe['x_nore_1'], label="Norepinephrine")
    plt.title("Hypnotic effect site Concentration")
    ax.set_xlabel("Time (min)")
    plt.legend()
    plt.grid()
    plt.show()

    fig, ax = plt.subplots(5, figsize=(10, 10))

    ax[0].plot(Time, simulator.dataframe['BIS'], label="BIS")
    ax[0].plot(Time, simulator.dataframe['TOL']*100, label="TOL (x100)")
    ax[0].legend()
    ax[1].plot(Time, simulator.dataframe['MAP'])
    ax[2].plot(Time, simulator.dataframe['CO'])
    ax[3].plot(Time, simulator.dataframe['HR'], label="HR")
    ax[3].plot(Time, simulator.dataframe['SV'], label="SV")
    ax[3].legend()
    ax[4].plot(Time, simulator.dataframe['blood_volume'])

    ax[1].set_ylabel("MAP")
    ax[2].set_ylabel("CO")
    ax[4].set_ylabel("blood volume")
    ax[4].set_xlabel("Time (min)")
    for i in range(5):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    # test
    test_bleeding_effect()
    test_stop_bleeding_effect()
    print("All tests passed successfully.")
