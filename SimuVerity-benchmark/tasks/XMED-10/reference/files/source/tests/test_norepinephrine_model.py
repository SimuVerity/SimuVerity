import numpy as np
from scipy.signal import lsim, StateSpace
import matplotlib.pyplot as plt
from python_anesthesia_simulator import CompartmentModel

age = 28
height = 165
weight = 65
sex = 0

# define true systems
sampling_time = 1


# Beloeil model
Clp = 59.6/30 / 60  # L/s
Vp = 8.84  # L
A = np.array([-Clp/Vp])
B = np.array([1/Vp])
C = np.array([1])
D = np.array([0])
beloeil_pk_true = StateSpace(A, B, C, D)

# Oualha model
Clp = 0.11 * weight**0.75 / 60  # L/s
Vp = 0.08 * weight  # L
u_endo_oualha = 0.052 * weight**0.75 / 60  # µg/s
A = np.array([-Clp/Vp])
B = np.array([1/Vp])
oulha_pk_true = StateSpace(A, B, C, D)
x0_oulha = [u_endo_oualha / Clp]  # Initial condition for Oulha

Tlag_li = 13.7 * (weight/70)**0.25  # sg

c_prop = 3.53
Clp = 2.1 * np.exp(-0.377/100*(age-35))*np.exp(-3.57*(c_prop-3.53))*(weight/70)**0.75 / 60  # L/s
Vp = 2.4 * (weight/70)  # L
Cl2 = 0.6*(weight/70)**0.75 / 60  # L/s
V2 = 3.6 * (weight/70)  # L
u_endo_li = 497.7 * (weight/70)**0.75 / 60 / 1000  # Convert to µg/s
k10 = Clp / Vp
k12 = Cl2 / Vp
k21 = Cl2 / V2
# Matrices system definition
A = np.array([[-(k10 + k12), k12],
              [k21, -k21]])  # 1/s
B = np.transpose(np.array([[1/Vp, 0]]))  # 1/L
C = np.array([[1, 0]])
D = np.array([[0]])
li_pk_true = StateSpace(A, B, C, D)
x0_li = [u_endo_li / Clp]*2

# define system from package

beloeil_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Beloeil',
    ts=sampling_time,
)
oualha_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Oualha',
    ts=sampling_time,
)
li_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Li',
    ts=sampling_time,
)

# dirach test
N_simu = int(10*60 // sampling_time)  # 20 minutes
u_nore = np.zeros(N_simu)

u_nore[:20] = 2  # dirach at time 0

t = np.arange(0, N_simu).astype(float)


_, _, beloeil_out = lsim(beloeil_pk_true, T=t, U=u_nore, interp=False)
_, _, oulha_out = lsim(oulha_pk_true, T=t, U=u_nore + u_endo_oualha, X0=x0_oulha, interp=False)
_, _, li_out = lsim(li_pk_true, T=t, U=u_nore + u_endo_li, X0=x0_li, interp=False)
li_out[:, 0] = np.roll(li_out[:, 0], int(np.round(Tlag_li/sampling_time)))
li_out[:int(np.round(Tlag_li)), 0] = u_endo_li / Clp

y_beloeil = beloeil_pk_pas.full_sim(u_nore)
y_beloeil = y_beloeil[:]
y_oualha = oualha_pk_pas.full_sim(u_nore)
y_oualha = y_oualha[:]
x_li = li_pk_pas.full_sim(u_nore)
y_li = x_li[0, :]
if __name__ == '__main__':
    plt.plot(t*sampling_time, beloeil_out, 'r', label='Beloeil')
    plt.plot(t*sampling_time, oulha_out, 'g', label='Oulha')
    plt.plot(t*sampling_time, li_out[:, 0], 'b', label='Li')

    plt.plot(t*sampling_time, y_beloeil, 'r--', label='Beloeil PAS')
    plt.plot(t*sampling_time, y_oualha, 'g--', label='Oualha PAS')
    plt.plot(t*sampling_time, y_li, 'b--', label='Li PAS')
    plt.xlabel('Time (s)')
    plt.ylabel('Concentration (µg/L)')
    plt.legend()
    plt.grid()
    plt.show()


def test_dirach_response():
    """Ensure that dirach-response from package and true simulation are the same for all model."""

    assert np.allclose(beloeil_out, y_beloeil)
    assert np.allclose(oulha_out, y_oualha)
    assert np.allclose(li_out[:, 0], y_li)


sampling_time = 1
beloeil_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Beloeil',
    ts=sampling_time,
)
oualha_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Oualha',
    ts=sampling_time,
)
li_pk_pas = CompartmentModel(
    [age, height, weight, sex],
    lbm=None,
    drug='Norepinephrine',
    model='Li',
    ts=sampling_time,
)


# step test
N_simu = int(30*60 // sampling_time)  # 20 minutes
u_nore = np.ones(N_simu)*0.1

t = np.arange(0, N_simu)
_, _, beloeil_out = lsim(beloeil_pk_true, T=t, U=u_nore, interp=False)
_, _, oulha_out = lsim(oulha_pk_true, T=t, U=u_nore + u_endo_oualha, X0=x0_oulha, interp=False)
_, _, li_out = lsim(li_pk_true, T=t, U=u_nore + u_endo_li, X0=x0_li, interp=False)
li_out[:, 0] = np.roll(li_out[:, 0], int(np.round(Tlag_li/sampling_time)))
li_out[:int(np.round(Tlag_li)), 0] = u_endo_li / Clp

y_beloeil = np.zeros(N_simu)
y_oualha = np.zeros(N_simu)
y_li = np.zeros(N_simu)
y_oualha[0] = oualha_pk_pas.x[0, 0]
y_li[0] = li_pk_pas.x[0, 0]
for i in range(N_simu-1):
    beloeil_pk_pas.one_step(u_nore[i])
    oualha_pk_pas.one_step(u_nore[i])
    li_pk_pas.one_step(u_nore[i])
    y_beloeil[i+1] = beloeil_pk_pas.x[0, 0]
    y_oualha[i+1] = oualha_pk_pas.x[0, 0]
    y_li[i+1] = li_pk_pas.x[0, 0]


def test_step_response():
    """Ensure that step-response from package and true simulation are the same for all model."""

    assert np.allclose(beloeil_out, y_beloeil)
    assert np.allclose(oulha_out, y_oualha)
    assert np.allclose(li_out[:, 0], y_li)


if __name__ == '__main__':
    plt.plot(t, beloeil_out, 'r', label='Beloeil')
    plt.plot(t, oulha_out, 'g', label='Oulha')
    plt.plot(t, li_out[:, 0], 'b', label='Li', )
    plt.plot(t, y_beloeil, 'r--', label='Beloeil PAS')
    plt.plot(t, y_oualha, 'g--', label='Oualha PAS')
    plt.plot(t, y_li, 'b--', label='Li PAS')

    plt.xlabel('Time (s)')
    plt.ylabel('Concentration (µg/L)')
    plt.legend()
    plt.grid()
    plt.show()

    # run test
    test_dirach_response()
    test_step_response()
    print("All test ok")
