from typing import Optional
# Third party imports
import numpy as np
import pandas as pd
from scipy.signal import dlsim, TransferFunction
from .patient import Patient
from .tci_control import TCIController
from .disturbances import Disturbances


class Simulator:
    """Class to add environment and usefull functions for simulation.

    Parameters
    ----------
    patient: Patient, optional
        The virtual patient object. If None a random patient is generaed with random_generation_arg parameters.
    random_generation_arg: dict, optional
        Argument to pass to generate_random_patient_method. The default is empty.
    tci_propo: str, optional 
        Type of TCI for Propofol. Can be either 'Plasma', 'Effect_site' or 'none'. Defaults to 'none'.
    tci_remi: str, optional
        Type of TCI for Remifentanil. Can be either 'Plasma', 'Effect_site' or 'none'. Defaults to 'none'.
    disturbance_profil: str, optional
        Type of disturbance profile to apply. See disturbance module for more details. The default is None.
    noise: bool, optional
        If True, add noise to the outputs of the patient model. The default is False.
    save_signals : bool, optional
        Save all internal variables at each sampling time in a data frame. The default is True.
    bis_delay_max : float, optional
        Maximum value of the BIS delay caused by Signal Quality Index (SQI) expressed in (s) according to the relationship proposed in [Wahlquist2025]_. The default is 120 (s).
    arg_disturbance: dict, optional
        Additional argument to pass to the function compute_disturbances. The default is empty.
    arg_tci_propo: dict, optional
        Additional argument to pass to tci class initialization for propofol. The default is empty.
    arg_tci_remi: dict, optional
        Additional argument to pass to tci class initialization for remifentanil. The default is empty.
    arg_tci_nore: dict, optional
        Additional argument to pass to tci class initialization for norepinephrine. The default is empty.
    arg_tci_atra: dict, optional
        Additional argument to pass to tci class initialization for atracurium. The default is empty.

    References
    ---------- 
    .. [Wahlquist2025] Y. Wahlquist, et al. "Kalman filter soft sensor to handle signal quality loss
        in closed-loop controlled anesthesia" Biomedical Signal Processing and Control 104 (2025): 107506.
        doi: https://doi.org/10.1016/j.bspc.2025.107506
    """

    def __init__(self,
                 patient: Optional[Patient] = None,
                 random_generation_arg: Optional[dict] = None,
                 tci_propo: Optional[str] = None,
                 tci_remi: Optional[str] = None,
                 tci_nore: Optional[bool] = None,
                 tci_atra: Optional[bool] = None,
                 disturbance_profil: Optional[str] = None,
                 noise: bool = False,
                 bis_delay_max: float = 120,
                 save_signals: bool = True,
                 arg_disturbance: Optional[dict] = None,
                 arg_tci_propo: Optional[dict] = None,
                 arg_tci_remi: Optional[dict] = None,
                 arg_tci_nore: Optional[dict] = None,
                 arg_tci_atra: Optional[dict] = None,
                 ):
        """Initialize the Simulator with a patient, and eventual TCI pumps. """
        if arg_disturbance is None:
            arg_disturbance = {}
        if arg_tci_propo is None:
            arg_tci_propo = {}
        if arg_tci_remi is None:
            arg_tci_remi = {}
        if arg_tci_nore is None:
            arg_tci_nore = {}
        if arg_tci_atra is None:
            arg_tci_atra = {}
        if random_generation_arg is None:
            random_generation_arg = {}
        if patient is None:
            self.patient = self.generate_random_patient(**random_generation_arg)
        else:
            self.patient = patient
        self.ts = self.patient.ts
        self.time = 0
        self.arg_disturbance = arg_disturbance
        self.noise = noise
        self.bis_delay_max = bis_delay_max
        self.save_signals = save_signals

        self.demographic = [
            self.patient.age,
            self.patient.height,
            self.patient.weight,
            self.patient.sex
        ]

        self.disturbances = Disturbances(
            dist_profil=disturbance_profil,
            **arg_disturbance,
        )

        if tci_propo is not None:
            if tci_propo not in ['Plasma', 'Effect_site']:
                raise ValueError('tci_propo must be either "Plasma", "Effect_site" or None')
            if 'model_used' not in arg_tci_propo.keys():
                arg_tci_propo['model_used'] = self.patient.model_propo
            self.tci_propo = TCIController(
                self.demographic,
                drug_name='Propofol',
                sampling_time=self.ts,
                **arg_tci_propo,
            )
        else:
            self.tci_propo = None
        if tci_remi is not None:
            if tci_remi not in ['Plasma', 'Effect_site']:
                raise ValueError('tci_remi must be either "Plasma", "Effect_site" or None')
            if 'model_used' not in arg_tci_remi.keys():
                arg_tci_remi['model_used'] = self.patient.model_remi
            self.tci_remi = TCIController(
                self.demographic,
                drug_name='Remifentanil',
                sampling_time=self.ts,
                **arg_tci_remi,
            )
        else:
            self.tci_remi = None
        if tci_nore is not None:
            if tci_nore not in ['Plasma', 'Effect_site']:
                raise ValueError('tci_nore must be either "Plasma" or None')
            if 'model_used' not in arg_tci_nore.keys():
                arg_tci_nore['model_used'] = self.patient.model_nore
            self.tci_nore = TCIController(
                self.demographic,
                drug_name='Norepinephrine',
                sampling_time=self.ts,
                **arg_tci_nore,
            )
        else:
            self.tci_nore = None
        if tci_atra is not None:
            if tci_atra not in ['Plasma', 'Effect_site']:
                raise ValueError('tci_remi must be either "Plasma", "Effect_site" or "none"')
            if 'model_used' not in arg_tci_atra.keys():
                arg_tci_atra['model_used'] = self.patient.model_atra
            self.tci_atra = TCIController(
                self.demographic,
                drug_name='Atracurium',
                sampling_time=self.ts,
                **arg_tci_atra,
            )
        else:
            self.tci_atra = None

        # Initialize the buffer to simulate BIS delay
        self.bis_delay_buffer = np.ones(int(np.ceil(self.bis_delay_max / self.ts))) * self.patient.bis

        if noise:
            self.map_noise_std = 30
            self.hr_noise_std = 17
            self.bis_noise_std = 35
            # MAP
            xi = 2
            a = 4 * xi**2 - 2
            y = (-a + np.sqrt(a**2 + 4)) / 2
            omega = 0.01/np.sqrt(y)
            map_filter = TransferFunction([1], [1 / omega**2, 2 * xi / omega, 1])
            self.map_noise_filter = map_filter.to_discrete(self.ts, method='bilinear')
            # HR
            xi = 10
            a = 4 * xi**2 - 2
            y = (-a + np.sqrt(a**2 + 4)) / 2
            omega = 0.02/np.sqrt(y)
            hr_filter = TransferFunction([1], [1 / omega**2, 2 * xi / omega, 1])
            self.hr_noise_filter = hr_filter.to_discrete(self.ts, method='bilinear')
            # bis
            xi = 1
            a = 4 * xi**2 - 2
            y = (-a + np.sqrt(a**2 + 4)) / 2
            omega = 0.04/np.sqrt(y)
            bis_filter = TransferFunction([1], [1 / omega**2, 2 * xi / omega, 1])
            self.bis_noise_filter = bis_filter.to_discrete(self.ts, method='bilinear')

            white_noise_map = np.random.normal(0, self.map_noise_std, 1000)
            white_noise_hr = np.random.normal(0, self.hr_noise_std, 1000)
            white_noise_bis = np.random.normal(0, self.bis_noise_std, 1000)
            _, self.map_noise = dlsim(self.map_noise_filter, u=white_noise_map)
            _, self.hr_noise = dlsim(self.hr_noise_filter, u=white_noise_hr)
            _, self.bis_noise = dlsim(self.bis_noise_filter, u=white_noise_bis)
            self.noise_index = 0

        # init output variable
        self.bis = self.patient.bis
        self.map = self.patient.map
        self.hr = self.patient.hr

        # Save data
        if self.save_signals:
            self.init_dataframe()
            self.save_data()

    def one_step(self,
                 input_propo: float = 0,
                 input_remi: float = 0,
                 input_nore: float = 0,
                 input_atra: float = 0,
                 blood_rate: float = 0,
                 sqi: float = 100,
                 ) -> tuple[float, float, float, float]:
        r"""Simulate one step of the patient model with given inputs.

        If tci pumps are used, the inputs are the target concentrations. Otherwise, they are the infusion rates.

        Parameters
        ----------
        input_propo : float, optional
            Infusion rate (mg/s) or target concentration (µg/ml) for Propofol. The default is 0.
        input_remi : float, optional
            Infusion rate (µg/s) or target concentration (ng/ml) for Remifentanil. The default is 0.
        input_nore : float, optional
            Infusion rate (µg/s) or target concentration (ng/ml) for Norepinephrine. The default is 0.
        input_atracurium : float, optional
            Infusion rate (mg/s) or target concentration (µg/ml) for Atracurium. The default is 0.
        blood_rate : float, optional
            Fluid rates from blood volume (mL/min), negative is bleeding while positive is a transfusion.
        sqi: float, optional
            Signal Quality Index of the BIS signal. It affects the BIS delay (expressed in seconds) according to the relationship proposed in [Wahlquist2025]_: :math:`bis\_delay = bis\_delay\_max * (1 - \frac{sqi}{100})`. The default is 100.

        Returns
        -------
        tuple[float, float, float, float]
            BIS, MAP, HR, TOF values after one step of simulation.

        References
        ---------- 
        .. [Wahlquist2025] Y. Wahlquist, et al. "Kalman filter soft sensor to handle signal quality loss
            in closed-loop controlled anesthesia" Biomedical Signal Processing and Control 104 (2025): 107506.
            doi: https://doi.org/10.1016/j.bspc.2025.107506
        """
        if self.tci_propo is not None:
            infusion_propo = self.tci_propo.one_step(target=input_propo)
        else:
            infusion_propo = input_propo
        if self.tci_remi is not None:
            infusion_remi = self.tci_remi.one_step(target=input_remi)
        else:
            infusion_remi = input_remi
        if self.tci_nore is not None:
            infusion_nore = self.tci_nore.one_step(target=input_nore)
        else:
            infusion_nore = input_nore
        if self.tci_atra is not None:
            infusion_atra = self.tci_atra.one_step(target=input_atra)
        else:
            infusion_atra = input_atra

        disturbances = self.disturbances.compute_dist(
            time=self.time,
        )

        self.patient.one_step(
            u_propo=infusion_propo,
            u_remi=infusion_remi,
            u_nore=infusion_nore,
            u_atra=infusion_atra,
            dist=disturbances,
            blood_rate=blood_rate,
        )
        self.bis = self.patient.bis
        self.map = self.patient.map
        self.hr = self.patient.hr

        # add noise
        if self.noise:
            self.add_noise()

        # bis delay
        delay = self.bis_delay_max * (1 - sqi / 100)
        delay_steps = int(np.ceil(delay / self.ts)) - 1
        if delay_steps > 0:

            # Approximated by excess
            self.bis_delay_buffer = np.roll(self.bis_delay_buffer, -1)
            self.bis_delay_buffer[delay_steps:] = [self.bis] * len(self.bis_delay_buffer[delay_steps:])
            self.bis = self.bis_delay_buffer[0]
        else:
            self.bis_delay_buffer = np.ones(int(np.ceil(self.bis_delay_max / self.ts))) * self.bis

        self.time += self.ts

        if self.save_signals:
            self.save_data(
                inputs=[
                    infusion_propo,
                    infusion_remi,
                    infusion_nore,
                    infusion_atra,
                    sqi,
                ]
            )
        return self.patient.bis, self.patient.map, self.patient.hr, self.patient.tof

    def add_noise(self):
        r"""
        Add noise on MAP, HR and BIS.

        All noise are considered white noise filtered by a second order transfert function:

        - For MAP, the standard deviation of the white noise is 30 and the filter is a second-order low-pass noise filter with damping ratio ξ=2 and cutoff frequency ω=0.01.
        - For HR, the standard deviation of the white noise is 17 and the filter is a second-order low-pass noise filter with damping ratio ξ=10 and cutoff frequency ω=0.02. In addition, the output is ceiled to the nearest integer.
        - For BIS, the standard deviation of the white noise is 35 and the filter is a second-order low-pass noise filter with damping ratio ξ=1 and cutoff frequency ω=0.04.

        See identification details on this `Notebook <https://github.com/AnesthesiaSimulation/PAS_vs_vitalDB/blob/main/scripts/identify_noise.ipynb>`_

        """
        self.noise_index += 1
        if self.noise_index >= len(self.bis_noise):
            # new list noise
            white_noise_map = np.random.normal(0, self.map_noise_std, 1000)
            white_noise_hr = np.random.normal(0, self.hr_noise_std, 1000)
            white_noise_bis = np.random.normal(0, self.bis_noise_std, 1000)
            _, self.map_noise = dlsim(self.map_noise_filter, u=white_noise_map)
            _, self.hr_noise = dlsim(self.hr_noise_filter, u=white_noise_hr)
            _, self.bis_noise = dlsim(self.bis_noise_filter, u=white_noise_bis)
            self.noise_index = 0

        self.bis += self.bis_noise[self.noise_index]
        self.bis = np.clip(self.bis, 0, 100)
        self.map += self.map_noise[self.noise_index]
        self.hr += self.hr_noise[self.noise_index]
        self.hr = np.round(self.hr)

    def init_dataframe(self):
        r"""Initilize the dataframe variable with the following columns:

            - 'Time': Simulation time (s)
            - 'BIS': Bispectral Index
            - 'SQI': Signal Quality Index
            - 'LOC': Loss of consciousness
            - 'TOL': Tolerance level
            - 'TOF': Train-of-four (%)
            - 'TPR': Total eripheral resistance (mmHg min/ mL) 
            - 'SV': Stroke volume (ml)
            - 'HR': Heart rate (beat/min)
            - 'MAP': Mean Arterial Pressure (mmHg)
            - 'CO': Cardiac Output (L/min)
            - 'u_propo': Propofol infusion rate (mg/s)
            - 'u_remi': Remifentanil infusion rate (µg/s)
            - 'u_nore': Norepinephrine infusion rate (µg/s)
            - 'u_atra': Atracurium infusion rate (µg/s)
            - 'x_propo_1' to 'x_propo_4': States of the propofol PK model
            - 'x_remi_1' to 'x_remi_4': States of the remifentanil PK model
            - 'x_nore': State of the norepinephrine PK model
            - 'x_atra_1' to 'x_atra_4': States of the atracurium PK model
            - 'blood_volume': Blood volume (L)

            if applicable TCI targets are also added:

            - 'target_propo': Target concentration for Propofol (µg/ml)
            - 'target_remi': Target concentration for Remifentanil (ng/ml)
        """
        self.Time = 0
        column_names = ['Time',  # time
                        'BIS', 'SQI', 'LOC', 'TOL', 'TOF', 'MAP', 'CO',  # outputs
                        'TPR', 'SV', 'HR', 'SAP', 'DAP',  # outputs
                        'u_propo', 'u_remi', 'u_nore', 'u_atra',  # inputs
                        'blood_volume']  # nore concentration and blood volume
        propo_state_names = [f'x_propo_{i + 1}' for i in range(len(self.patient.propo_pk.x))]
        remi_state_names = [f'x_remi_{i + 1}' for i in range(len(self.patient.remi_pk.x))]
        nore_state_names = [f'x_nore_{i + 1}' for i in range(len(self.patient.nore_pk.x))]
        atra_state_names = [f'x_atra_{i + 1}' for i in range(len(self.patient.atracurium_pk.x))]
        column_names += propo_state_names + remi_state_names + nore_state_names + atra_state_names
        if self.tci_propo is not None:
            column_names.append('target_propo')
        if self.tci_remi is not None:
            column_names.append('target_remi')
        if self.tci_nore is not None:
            column_names.append('target_nore')
        if self.tci_atra is not None:
            column_names.append('target_atra')
        self.dataframe = pd.DataFrame(columns=column_names, dtype=float)

    def save_data(self, inputs: list = None):
        r"""Save all current internal variables as a new line in self.dataframe."""
        # store data
        if inputs is None:
            inputs = [0]*5
        new_line = {'Time': self.time,
                    'BIS': self.bis,  # measures
                    'LOC': self.patient.loc,
                    'TOL': self.patient.tol,
                    'TPR': self.patient.tpr,
                    'TOF': self.patient.tof,
                    'SV': self.patient.sv,
                    'HR': self.hr,
                    'MAP': self.map,
                    'CO': self.patient.co,
                    'SAP': self.patient.sap,
                    'DAP': self.patient.dap,
                    'u_propo': 0,  # inputs
                    'u_remi': 0,
                    'u_nore': 0,
                    'u_atra': 0,
                    'SQI': inputs[4],
                    'blood_volume': self.patient.blood_volume}  # blood volume
        if inputs is None:
            inputs = [0, 0, 0, 0, 100]
        line_x_propo = {f'x_propo_{i + 1}': self.patient.propo_pk.x[i, 0] for i in range(len(self.patient.propo_pk.x))}
        line_x_remi = {f'x_remi_{i + 1}': self.patient.remi_pk.x[i, 0] for i in range(len(self.patient.remi_pk.x))}
        line_x_nore = {f'x_nore_{i + 1}': self.patient.nore_pk.x[i, 0] for i in range(len(self.patient.nore_pk.x))}
        line_x_atra = {f'x_atra_{i + 1}': self.patient.atracurium_pk.x[i, 0]
                       for i in range(len(self.patient.atracurium_pk.x))}
        new_line.update(line_x_propo)
        new_line.update(line_x_remi)
        new_line.update(line_x_nore)
        new_line.update(line_x_atra)
        self.dataframe = pd.concat(
            [df for df in (self.dataframe, pd.DataFrame(new_line, index=[1], dtype=float)) if not df.empty],
            ignore_index=True
        )
        if len(self.dataframe) >= 2:
            self.dataframe.loc[len(self.dataframe)-2, 'u_propo'] = inputs[0]
            self.dataframe.loc[len(self.dataframe)-2, 'u_remi'] = inputs[1]
            self.dataframe.loc[len(self.dataframe)-2, 'u_nore'] = inputs[2]
            self.dataframe.loc[len(self.dataframe)-2, 'u_atra'] = inputs[3]
            if self.tci_propo is not None:
                self.dataframe.loc[len(self.dataframe)-2, 'target_propo'] = self.tci_propo.target
            if self.tci_remi is not None:
                self.dataframe.loc[len(self.dataframe)-2, 'target_remi'] = self.tci_remi.target
            if self.tci_nore is not None:
                self.dataframe.loc[len(self.dataframe)-2, 'target_nore'] = self.tci_nore.target
            if self.tci_atra is not None:
                self.dataframe.loc[len(self.dataframe)-2, 'target_atra'] = self.tci_atra.target

    def full_sim(
        self,
        inputs_propo: Optional[np.ndarray] = None,
        inputs_remi: Optional[np.ndarray] = None,
        inputs_nore: Optional[np.ndarray] = None,
        inputs_atra: Optional[np.ndarray] = None,
        x0_propo: Optional[np.array] = None,
        x0_remi: Optional[np.array] = None,
        x0_nore: Optional[np.array] = None,
        x0_atra: Optional[np.array] = None,
        interp=False,
    ) -> pd.DataFrame:
        """Perform a simulation over multiple step times using the inputs profiles provided.

        Parameters
        ----------
        inputs_propo : Optional[np.ndarray], optional
            Infusion rates or TCI targets for propofol over time. The default is null.
        inputs_remi : Optional[np.ndarray], optional
            Infusion rates or TCI targets for remifentnanil over time. The default is null.
        inputs_nore : Optional[np.ndarray], optional
            Infusion rates or TCI targets for norepinephrine over time. The default is null.
        inputs_atra : Optional[np.ndarray], optional
            Infusion rates or TCI targets for remifentanil over time. The default is null.
        x0_propo : Optional[np.array], optional
            Initial state of the propofol PK model. The default is zeros.
        x0_remi : Optional[np.array], optional
            Initial state of the remifentanil PK model. The default is zeros.
        x0_nore : Optional[np.array], optional
            Initial state of the norepinephrine PK model. The default is zeros.
        x0_atra : Optional[np.array], optional
            Initial state of the atracurium PK model. The default is zeros.
        interp : bool, optional
            Whether to use zero-order-hold (False, the default) or linear (True) interpolation for the input array.

        Returns
        -------
        pd.DataFrame
            Dataframe including all the signals during the simulation.
        """
        if inputs_propo is None and inputs_remi is None and inputs_nore is None and inputs_atra is None:
            raise ValueError('No input provided')
        # Propofol input
        if inputs_propo is None:
            if inputs_remi is not None:
                inputs_propo = np.zeros_like(inputs_remi)
            elif inputs_nore is not None:
                inputs_propo = np.zeros_like(inputs_nore)
            else:
                inputs_propo = np.zeros_like(inputs_atra)
        # Remifentanil input
        if inputs_remi is None:
            inputs_remi = np.zeros_like(inputs_propo)
        # Norepinephrine input
        if inputs_nore is None:
            inputs_nore = np.zeros_like(inputs_propo)
        # Atracurium input
        if inputs_atra is None:
            inputs_atra = np.zeros_like(inputs_propo)

        # INPUT consistency check
        if not (len(inputs_propo) == len(inputs_remi) and len(inputs_propo) == len(inputs_nore) == len(inputs_atra)):
            raise ValueError('Inputs must have the same length')

        # TCI computation

        # propofol
        if self.tci_propo is not None:
            infusion_propo = np.zeros_like(inputs_propo, dtype=float)
            if not (inputs_propo == 0).all():
                for i in range(len(inputs_propo)):
                    infusion_propo[i] = self.tci_propo.one_step(inputs_propo[i])
        else:
            infusion_propo = inputs_propo
        # remifentanil
        if self.tci_remi is not None:
            infusion_remi = np.zeros_like(inputs_remi, dtype=float)
            if not (inputs_propo == 0).all():
                for i in range(len(inputs_propo)):
                    infusion_remi[i] = self.tci_remi.one_step(inputs_remi[i])
        else:
            infusion_remi = inputs_remi

        # norepinephrine
        if self.tci_nore is not None:
            infusion_nore = np.zeros_like(inputs_nore, dtype=float)
            if not (inputs_nore == 0).all():
                for i in range(len(inputs_nore)):
                    infusion_nore[i] = self.tci_nore.one_step(inputs_nore[i])
        else:
            infusion_nore = inputs_nore

        # atracurium
        if self.tci_atra is not None:
            infusion_atra = np.zeros_like(inputs_atra, dtype=float)
            if not (inputs_atra == 0).all():
                for i in range(len(inputs_atra)):
                    infusion_atra[i] = self.tci_atra.one_step(inputs_atra[i])
        else:
            infusion_atra = inputs_atra

        # Disturbance
        Time = np.arange(0, (len(inputs_propo))*self.ts, self.ts)
        dist_vec = np.array(self.disturbances.compute_dist(Time))

        results_patient = self.patient.full_sim(
            infusion_propo,
            infusion_remi,
            infusion_nore,
            infusion_atra,
            dist_vec,
            x0_propo,
            x0_remi,
            x0_nore,
            x0_atra,
            interp,
        )

        if self.noise:
            white_noise_map = np.random.normal(0, self.map_noise_std, len(inputs_propo))
            white_noise_hr = np.random.normal(0, self.hr_noise_std, len(inputs_propo))
            white_noise_bis = np.random.normal(0, self.bis_noise_std, len(inputs_propo))
            _, map_noise = dlsim(self.map_noise_filter, u=white_noise_map)
            _, hr_noise = dlsim(self.hr_noise_filter, u=white_noise_hr)
            _, bis_noise = dlsim(self.bis_noise_filter, u=white_noise_bis)
            results_patient['BIS'] = (results_patient['BIS'] + bis_noise).clip(lower=0, upper=100)
            results_patient['MAP'] += map_noise
            results_patient['HR'] = (results_patient['HR'] + hr_noise).round()

        if self.tci_propo is not None:
            results_patient['target_propo'] = inputs_propo
        if self.tci_remi is not None:
            results_patient['target_remi'] = inputs_remi
        if self.tci_nore is not None:
            results_patient['target_nore'] = inputs_nore
        if self.tci_atra is not None:
            results_patient['target_atra'] = inputs_atra

        return results_patient

    def generate_random_patient(
        self,
        distribution: Optional[str] = 'uniform',
        patient_arg: Optional[dict] = None,
    ):
        """
        Generate a random patient with characteristics following either a uniform distribution or a distribution fitted on VitalDB data.

        Paramters
        ----------
        distribution: str, optionnal
            Choose how patient characteristic are drawn. Can be "uniform" or "VitalDB". Default is "uniform".
        patient_arg: list, optionnal
            Arguments to pass to init the patient class. Default is an empty list.
        Return
        -------
        patient: Patient object
            Instance of the patient class.
        """
        if patient_arg is None:
            patient_arg = {}

        if distribution == 'uniform':
            age = np.random.randint(low=18, high=81)
            height = np.random.randint(low=150, high=190)
            weight = np.random.randint(low=50, high=100)
            sex = np.random.randint(low=0, high=2)
        elif distribution == 'VitalDB':

            mean_male = [55.4, 167.6, 65.8]  # age, height, weight
            mean_female = [51.6, 157.7, 54.4]
            sigma_male = [
                [116.2, -13.9, -41.4],
                [-13.9,  33.3,  18.1],
                [-41.4,  18.1, 105.0]]
            sigma_female = [
                [251.5, -44.0, -19.0],
                [-44.0,  21.3,  22.5],
                [-19.0,  22.5,  68.8]]
            sex = np.random.randint(low=0, high=2)
            good_range = False
            while not good_range:
                if sex == 0:
                    vec = np.random.multivariate_normal(mean_female, sigma_female)
                else:
                    vec = np.random.multivariate_normal(mean_male, sigma_male)
                good_age = (vec[0] >= 18) and (vec[0] <= 80)
                good_height = (vec[1] >= 145) and (vec[1] <= 185)
                good_weight = (vec[2] >= 40) and (vec[2] <= 95)
                good_range = good_age and good_height and good_weight
            age = vec[0]
            height = vec[1]
            weight = vec[2]
        else:
            raise ValueError('Only uniform and VitalDB are available as distribution')

        patient = Patient(
            [age, height, weight, sex],
            **patient_arg,
        )
        return patient
