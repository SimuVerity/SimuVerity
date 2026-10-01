import matplotlib.pyplot as plt
from python_anesthesia_simulator import Patient, TCIController, Simulator


Ts = 10
George_1 = Patient([18, 170, 60, 0], ts=Ts, model_propo="Eleveld", model_remi="Eleveld", co_update=False)
George_2 = Patient([18, 170, 60, 0], ts=Ts, model_propo="Eleveld", model_remi="Eleveld", co_update=False)

tci_propo = TCIController(
    [18, 170, 60, 0],
    drug_name="Propofol",
    sampling_time=Ts,
    model_used="Eleveld",
)


# %% Simulation

N_simu = int(60 * 60/Ts)

bis_target_1 = 50
tol_target_1 = 0.9
map_target_1 = 80

George_1.initialized_at_maintenance(bis_target=bis_target_1, tol_target=tol_target_1, map_target=map_target_1)
uP, uR, uN = George_1.u_propo_eq, George_1.u_remi_eq, George_1.u_nore_eq

simu_1 = Simulator(George_1)
simu_1.one_step(
    input_propo=uP,
    input_remi=uR,
    input_nore=uN,
)

bis_target_2 = 40
tol_target_2 = 0.95
map_target_2 = 85
uP_2, uR_2, uN_2 = George_1.find_equilibrium(bis_target=bis_target_2, tol_target=tol_target_2, map_target=map_target_2)
c_propo_2 = George_1.c_blood_propo_eq
up_2, ur_2 = George_2.find_bis_equilibrium_with_ratio(bis_target=bis_target_1, rp_ratio=2)
George_2.initialized_at_given_input(up_2, ur_2)
simu_2 = Simulator(George_2)

for index in range(N_simu):
    if index < N_simu // 5:
        simu_1.one_step(input_propo=uP, input_remi=uR, input_nore=uN)
        # update the TCI controller with the current state
        tci_propo.x = George_1.propo_pk.x[:4]
    else:
        u_propo = tci_propo.one_step(c_propo_2)
        simu_1.one_step(input_propo=u_propo, input_remi=uR_2, input_nore=uN_2)
    simu_2.one_step(input_propo=up_2, input_remi=ur_2, input_nore=0)


# %% test


def test_equilibrium():
    """Verify that the equilibrium is reached at the beginning and at the end of the simulation."""
    assert abs(simu_1.dataframe['BIS'].iloc[0]-bis_target_1) < 5e-1
    assert abs(simu_1.dataframe['BIS'].iloc[-1]-bis_target_2) < 1
    assert abs(simu_1.dataframe['TOL'].iloc[0]-tol_target_1) < 1e-2
    assert abs(simu_1.dataframe['TOL'].iloc[-1]-tol_target_2) < 1e-2
    assert abs(simu_1.dataframe['MAP'].iloc[0]-map_target_1) < 2e-1
    assert abs(simu_1.dataframe['MAP'].iloc[-1]-map_target_2) < 3e-1
    assert abs(simu_2.dataframe['BIS'].iloc[-1]-bis_target_1) < 2


def test_hill_inversion():
    """ensure that the inversion of bis is effective"""
    ce_propo = 4
    ce_remi = 5
    bis = George_1.bis_pd.compute_bis(ce_propo, ce_remi)
    ce_propo_computed = George_1.bis_pd.inverse_hill(bis, ce_remi)

    assert abs(ce_propo - ce_propo_computed) < 1e-3


# %% plot
if __name__ == '__main__':
    fig, ax = plt.subplots(3)
    Time = simu_1.dataframe['Time']/60
    ax[0].plot(Time, simu_1.dataframe['u_propo'])
    ax[1].plot(Time, simu_1.dataframe['u_remi'])
    ax[2].plot(Time, simu_1.dataframe['u_nore'])

    ax[0].set_ylabel("Propo")
    ax[1].set_ylabel("Remi")
    ax[2].set_ylabel("Nore")
    for i in range(3):
        ax[i].grid()

    plt.show()

    fig, ax = plt.subplots(1)

    ax.plot(Time, simu_1.dataframe['x_propo_4'], label="Propofol")
    ax.plot(Time, simu_1.dataframe['x_remi_4'], label="Remifentanil")
    ax.plot(Time, simu_1.dataframe['x_nore_1'], label="Norepinephrine")
    plt.title("Hypnotic effect site Concentration")
    ax.set_xlabel("Time (min)")
    plt.legend()
    plt.grid()
    plt.show()

    fig, ax = plt.subplots(4)

    ax[0].plot(Time, simu_1.dataframe['BIS'])
    ax[1].plot(Time, simu_1.dataframe['MAP'])
    ax[2].plot(Time, simu_1.dataframe['CO'])
    ax[3].plot(Time, simu_1.dataframe['TOL'])

    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("MAP")
    ax[2].set_ylabel("CO")
    ax[3].set_ylabel("TOL")
    ax[3].set_xlabel("Time (min)")
    for i in range(4):
        ax[i].grid()
    plt.ticklabel_format(style='plain')
    plt.show()

    # plot input and bis for patient 2
    Time = simu_2.dataframe['Time']/60
    fig, ax = plt.subplots(2)
    ax[0].plot(Time, simu_2.dataframe['u_propo'], label="Propofol")
    ax[0].plot(Time, simu_2.dataframe['u_remi'], label="Remifentanil")
    ax[0].plot(Time, simu_2.dataframe['u_nore'], label="Norepinephrine")
    ax[0].set_ylabel("Input")
    ax[0].legend()
    ax[0].grid()
    ax[1].plot(Time, simu_2.dataframe['BIS'])
    ax[1].set_ylabel("BIS")
    ax[1].set_xlabel("Time (min)")
    ax[1].grid()
    plt.show()

    # test
    test_equilibrium()
    test_hill_inversion()
    print("All tests passed successfully.")
