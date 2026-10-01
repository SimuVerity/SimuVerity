import numpy as np
import matplotlib.pyplot as plt
from python_anesthesia_simulator import Patient, metrics, Simulator

ts = 10
age = 35
weight = 70
height = 170
sex = 0

# %%

George_1 = Patient([age, height, weight, sex], ts=ts)
George_2 = Patient([age, height, weight, sex], ts=ts)
George_3 = Patient([age, height, weight, sex], ts=ts)
George_4 = Patient([age, height, weight, sex], ts=ts, model_hemo='VitalDB')

simu_1 = Simulator(George_1, disturbance_profil='realistic', tci_propo='Effect_site')
simu_2 = Simulator(George_2, disturbance_profil='simple', tci_propo='Effect_site')
start_step = 20 * 60
end_step = 30 * 60
simu_3 = Simulator(
    George_3,
    disturbance_profil='step',
    arg_disturbance={'start_step': start_step, 'end_step': end_step},
    tci_propo='Effect_site',
)
simu_4 = Simulator(George_4, disturbance_profil='VitalDB', tci_propo='Effect_site')

# %% Simulation

N_simu = int(60 * 60 / ts)


target_propo = np.ones(N_simu)*2
u_remi = np.ones(N_simu)*0.5

results_1 = simu_1.full_sim(target_propo, u_remi)
results_2 = simu_2.full_sim(target_propo, u_remi)
results_3 = simu_3.full_sim(target_propo, u_remi)
results_4 = simu_4.full_sim(target_propo, u_remi)

# %% metrics

metric_1 = metrics.compute_control_metrics(
    results_1.loc[:9 * 60 / ts, 'Time'],
    results_1.loc[:9 * 60 / ts, 'BIS'],
    phase='induction'
)
metric_2 = metrics.compute_control_metrics(
    results_2.loc[:9 * 60 / ts, 'Time'],
    results_2.loc[:9 * 60 / ts, 'BIS'],
    phase='induction'
)
metric_3 = metrics.compute_control_metrics(
    results_3['Time'],
    results_3['BIS'],
    phase='total',
    start_step=start_step,
    end_step=end_step
)

metric_1_new = metrics.new_metrics_induction(
    results_1.loc[:9 * 60 / ts, 'Time'].values,
    results_1.loc[:9 * 60 / ts, 'BIS'].values,
)

metric_3_new = metrics.new_metrics_maintenance(
    results_3.loc[9 * 60 / ts:, 'Time'].values,
    results_3.loc[9 * 60 / ts:, 'BIS'].values,
)


# %% test
def test_intubation_effect():
    """Test that the intubation effect is visible on the signals."""
    assert results_4.query('Time==3*60')['HR'].iloc[0] < results_4.query('Time==5*60')['HR'].iloc[0]
    assert results_4.query('Time==3*60')['SAP'].iloc[0] < results_4.query('Time==5*60')['SAP'].iloc[0]
    assert results_4.query('Time==3*60')['DAP'].iloc[0] < results_4.query('Time==5*60')['DAP'].iloc[0]


def test_surgery_effect():
    """Test that the surgery effect is visible on the signals."""
    assert results_4.query('Time==40*60')['HR'].iloc[0] < results_4.query('Time==50*60')['HR'].iloc[0]
    assert results_4.query('Time==40*60')['SAP'].iloc[0] < results_4.query('Time==50*60')['SAP'].iloc[0]
    assert results_4.query('Time==40*60')['DAP'].iloc[0] < results_4.query('Time==50*60')['DAP'].iloc[0]


def test_metrics():
    # No undershoot during induction
    assert metric_1['BIS_NADIR'].iloc[0] > 50
    assert metric_2['BIS_NADIR'].iloc[0] > 50

    assert np.allclose(metric_1['US'].iloc[0], 0.0)
    assert np.allclose(metric_2['US'].iloc[0], 0.0)

    # Time to target equal to 9 minutes
    assert np.allclose(metric_1['TT'].iloc[0].round(), 7)
    assert np.allclose(metric_2['TT'].iloc[0].round(), 7)
    assert np.allclose(metric_3['TT'].iloc[0].round(), 7)

    # Settling time at 10% equal to 9 minutes
    assert np.allclose(metric_1['ST10'].iloc[0].round(), 7)
    assert np.allclose(metric_2['ST10'].iloc[0].round(), 7)
    assert np.allclose(metric_3['ST10'].iloc[0].round(), 7)

    # Settling time at 20% equal to 6 minutes
    assert np.allclose(metric_1['ST20'].iloc[0].round(), 4)
    assert np.allclose(metric_2['ST20'].iloc[0].round(), 4)
    assert np.allclose(metric_3['ST20'].iloc[0].round(), 4)

    # test maintenance phase
    assert np.isnan(metric_3['TTp'].iloc[0])
    assert metric_3['BIS_NADIRp'].iloc[0] > 50
    assert np.allclose(metric_3['TTn'].iloc[0].round(), 0)
    assert metric_3['BIS_NADIRn'].iloc[0] < 50


def test_new_metrics():
    """test the new metrics."""

    assert (metric_1_new['Sleep_Time'].round() == 4).all()
    assert (metric_1_new["Low BIS time"] == 0).all()
    assert abs(metric_1_new['Lowest BIS'].iloc[0] - 53) <= 1e-1
    assert (metric_1_new['Settling time'].round() == 4).all()

    assert (metric_3_new['Time out of range'] == 0).all()
    assert abs(metric_3_new['Lowest BIS'].iloc[0] - 47.3) <= 1e-1
    assert abs(metric_3_new['Highest BIS'].iloc[0] - 59.0) <= 1e-1

# %% plots


if __name__ == '__main__':
    Time = results_1['Time'] / 60

    fig, ax = plt.subplots(3)
    ax[0].plot(Time, results_1['u_propo'])
    ax[1].plot(Time, results_1['u_remi'])
    ax[2].plot(Time, results_1['u_nore'])

    ax[0].set_ylabel("Propo")
    ax[1].set_ylabel("Remi")
    ax[2].set_ylabel("Nore")

    plt.show()

    simu_4.disturbances.plot_dist()

    fig, ax = plt.subplots(4)

    ax[0].plot(Time, results_1['BIS'])
    ax[1].plot(Time, results_1['MAP'])
    ax[2].plot(Time, results_1['CO'])
    ax[3].plot(Time, results_1['HR'])
    ax[0].plot(Time, results_2['BIS'])
    ax[1].plot(Time, results_2['MAP'])
    ax[2].plot(Time, results_2['CO'])
    ax[3].plot(Time, results_2['HR'])
    ax[0].plot(Time, results_3['BIS'])
    ax[1].plot(Time, results_3['MAP'])
    ax[2].plot(Time, results_3['CO'])
    ax[3].plot(Time, results_3['HR'])
    ax[0].plot(Time, results_4['BIS'])
    ax[1].plot(Time, results_4['SAP'])
    ax[2].plot(Time, results_4['CO'])
    ax[3].plot(Time, results_4['HR'])

    ax[0].set_ylabel("BIS")
    ax[1].set_ylabel("MAP")
    ax[2].set_ylabel("CO")
    ax[3].set_ylabel("HR")
    ax[3].set_xlabel("Time (min)")
    for i in range(4):
        ax[i].grid()
    plt.show()

    test_metrics()
    test_new_metrics()
    test_intubation_effect()
    test_surgery_effect()
    print('All tests passed successfully!')
