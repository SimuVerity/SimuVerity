# Standard import
from typing import Optional
# Third party imports
import numpy as np
import pandas as pd
import casadi as cas
# Local imports
from .pk_models import CompartmentModel, AtracuriumModel
from .pd_models import BIS_model, LOC_model, TOL_model, Hemo_meca_PD_model, TOF_model


class Patient:
    r"""Define a Patient class able to simulate Anesthesia process.

    Parameters
    ----------
    Patient_characteristic: list
        Patient_characteristic = [age (yr), height(cm), weight(kg), sex(0: female, 1: male)]
    co_base : float, optional
        Initial cardiac output. The default is 6.5L/min.
    hr_base : float, optional
        Initial heart rate. The default is 60 beat/min.
    map_base : float, optional
        Initial Mean Arterial Pressure. The default is 90mmHg.
    model_propo : str, optional
        Name of the Propofol PK Model. The default is 'Schnider'.
    model_remi : str, optional
        Name of the Remifentanil PK Model. The default is 'Minto'.
    model_nore : str, optional
        Name of the norepinephrine PK Model. The default is 'Beloeil'.
    model_atracurium : str, optional
        Name of the atracurium PK Model. The default is 'WardWeatherleyLago'.
    model_bis : str, optional
        Name of the BIS PD Model. The default is 'Bouillon'.
    model_loc : str, optional
        Name of the LOC PD Model. The default is 'Kern'
    model_tof, : str, optional
        Name of the TOF PD Model. The default is 'Weatherley'.
    model_hemo : str, optional
        Name of the hemodynamic model. The default is 'Su'.
    ts : float, optional
        Sampling time (s). The default is 1.
    hill_param : list
        Parameter of the BIS model (Propo Remi interaction)
        list [C50p_BIS, C50r_BIS, gamma_BIS, beta_BIS, E0_BIS, Emax_BIS, Delay_BIS].
        If Delay_BIS is not provided it is assumed equal to 0.
        The default is None.
    atracurium_model_params : dict, optional
        For "WardWeatherleyLago":
        dict {'V1', 'V2', 'Cl', 't12_alpha', 't12_beta', 'ke0', 'tau'}.
        If it is not provided average values are used.
    atracurium_hill_params : dict, optional
        For "WardWeatherleyLago":
        dict {'c50', 'gamma'}.
        If it is not provided average values are used.
    random_PK : bool, optional
        Add uncertainties in the Propofol and Remifentanil PK models. The default is False.
    random_PD : bool, optional
        Add uncertainties in the BIS PD model. The default is False.
    co_update : bool, optional
        Turn on the option to update PK parameters thanks to the CO value. The default is False.
    truncated : bool, optional
        Use truncated normal distribution (between [-3, +3] std) for the random parameters. The default is False.

    Attributes
    ----------
    age : float
        Age of the patient (yr).
    height : float
        Height of the patient (cm).
    weight : float
        Weight of the patient (kg).
    sex : bool
        0 for female, 1 for male.
    co_base : float
        Initial cardiac output (L/min).
    map_base : float
        Initial mean arterial pressure (mmHg).
    ts : float
        Sampling time (s).
    model_propo : str
        Name of the propofol PK model.
    model_remi : str
        Name of the remifentanil PK model.
    model_remi : str
        Name of the norepinephrine PK model.
    model_atracurium : str
        Name of the atracurium PK model.
    model_bis : str
        Name of the BIS PD model.
    model_loc : str
        Name of the LOC PD model
    model_tof : str
        Name of the TOF PD model.
    model_hemo : str
        Name of the hemo model.
    hill_param : list
        Parameter of the BIS model (Propo Remi interaction)
        list [C50p_BIS, C50r_BIS, gamma_BIS, beta_BIS, E0_BIS, Emax_BIS, Delay_BIS].
        If Delay_BIS is not provided it is assumed equal to 0.
    atracurium_model_params : dict, optional
        For "WardWeatherleyLago":
            dict {'V1', 'V2', 'Cl', 't12_alpha', 't12_beta', 'ke0', 'tau'}
    atracurium_hill_params : dict, optional
        For "WardWeatherleyLago":
            dict {'c50', 'gamma'}
    random_PK : bool
        Add uncertainties in the Propofol and Remifentanil PK models.
    random_PD : bool
        Add uncertainties in the BIS PD model.
    co_update : bool
        Turn on the option to update PK parameters thanks to the CO value.
    save_data_bool : bool
        Save all internal variables at each sampling time in a data frame.
    lbm : float
        Lean body mass (kg).
    propo_pk : CompartmentModel
        4-comparments model for Propofol.
    remi_pk : CompartmentModel
        4-comparments model for Remifentanil.
    nore_pk : CompartmentModel
        1-comparments model for Norepinephrine.
    atracurium_pk : CompartmentModel
        4-comparments model for Atracurium.
    bis_pd : BIS_model
        Surface-response model for bis computation.
    tol_pd : TOL_model
        Hierarchical model for TOL computation.
    hemo_pd : Hemo_PD_model
        Hemodynamic model for CO and MAP computation.
    tof_pd : TOF_model
        Hill curve model for tof computation.
    data : pd.DataFrame
        Dataframe containing all the internal variables at each sampling time.
    bis : float
        Bispectral index (%).
    tol : float
        Tolerance of laryngoscopy probability (0-1).
    co : float
        Cardiac output (L/min).
    map : float
        Mean arterial pressure (mmHg).
    tof : float
        Neuromuscular blockade level (%).
    blood_volume : float
        Blood volume (L).
    bis_noise_std : float
        Standard deviation of the BIS noise.
    co_noise_std : float
        Standard deviation of the CO noise.
    map_noise_std : float
        Standard deviation of the MAP noise.
    bis_delay_max : float
        Maximum value of the BIS delay caused by signal quality index expressed in (s).
    bis_delay_buffer: array
        Buffer of BIS values to simulate delay.
    """

    def __init__(self,
                 patient_characteristic: list,
                 co_base: float = None,
                 hr_base: float = None,
                 map_base: float = None,
                 model_propo: str = 'Schnider',
                 model_remi: str = 'Minto',
                 model_nore: str = 'Beloeil',
                 model_atra: str = 'WardWeatherleyLago',
                 model_bis: str = 'Bouillon',
                 model_loc: str = 'Kern',
                 model_tof: str = 'Weatherley',
                 model_hemo: str = 'Su',
                 ts: float = 1,
                 hill_param: list = None,
                 atracurium_model_params: dict = None,
                 atracurium_hill_params: dict = None,
                 random_PK: bool = False,
                 random_PD: bool = False,
                 co_update: bool = False,
                 truncated: bool = None):
        """
        Initialise a patient class for anesthesia simulation.

        Returns
        -------
        None.

        """
        if atracurium_model_params is None:
            atracurium_model_params = {}
        if atracurium_hill_params is None:
            atracurium_hill_params = {}
        self.age = patient_characteristic[0]
        self.height = patient_characteristic[1]
        self.weight = patient_characteristic[2]
        self.sex = patient_characteristic[3]
        self.co_base = co_base
        self.hr_base = hr_base
        self.map_base = map_base
        self.ts = ts
        self.model_propo = model_propo
        self.model_remi = model_remi
        self.model_nore = model_nore
        self.model_atra = model_atra
        self.model_hemo = model_hemo
        self.model_bis = model_bis
        self.model_loc = model_loc
        self.model_tof = model_tof
        self.hill_param = hill_param
        self.atracurium_model_params = atracurium_model_params
        self.atracurium_hill_params = atracurium_hill_params
        self.random_PK = random_PK
        self.random_PD = random_PD
        self.co_update = co_update

        # LBM computation
        if self.sex == 1:  # homme
            self.lbm = 1.1 * self.weight - 128 * (self.weight / self.height) ** 2
        elif self.sex == 0:  # femme
            self.lbm = 1.07 * self.weight - 148 * (self.weight / self.height) ** 2

        # Init PK models for all drugs
        self.propo_pk = CompartmentModel(patient_characteristic, self.lbm, drug="Propofol",
                                         ts=self.ts, model=model_propo, random=random_PK, truncated=truncated)

        self.remi_pk = CompartmentModel(patient_characteristic, self.lbm, drug="Remifentanil",
                                        ts=self.ts, model=model_remi, random=random_PK, truncated=truncated)

        self.nore_pk = CompartmentModel(patient_characteristic, self.lbm, drug="Norepinephrine",
                                        ts=self.ts, model=model_nore, random=random_PK, truncated=truncated)
        self.atracurium_pk = AtracuriumModel(patient_characteristic,
                                             ts=self.ts, model=model_atra,
                                             model_params=atracurium_model_params)

        # Init PD model for BIS
        self.bis_pd = BIS_model(hill_model=model_bis, hill_param=hill_param, random=random_PD,
                                ts=self.ts, age=self.age, truncated=truncated)
        self.hill_param = self.bis_pd.hill_param

        # Init PD model for TOL
        self.tol_pd = TOL_model(model='Bouillon', random=random_PD, truncated=truncated)

        # Init PD model for TOL
        self.loc_pd = LOC_model(hill_model=model_loc, random=random_PD, truncated=truncated)

        # Init PD model for Hemodynamic
        if co_base is not None and hr_base is not None:
            sv_base = co_base / hr_base * 1000
        else:
            sv_base = None
        self.hemo_pd = Hemo_meca_PD_model(
            age=self.age,
            ts=self.ts,
            random=random_PD,
            hr_base=hr_base,
            sv_base=sv_base,  # L to ml
            map_base=map_base,
            truncated=truncated,
        )
        self.hr_base = self.hemo_pd.abase_hr
        self.map_base = self.hemo_pd.base_map
        self.co_base = self.hemo_pd.abase_hr * self.hemo_pd.abase_sv / 1000  # L/min

        # Init PD model fo TOF
        self.tof_pd = TOF_model(hill_model=model_tof, hill_param=atracurium_hill_params)

        # init blood loss volume
        self.blood_volume = self.propo_pk.v1
        self.blood_volume_init = self.propo_pk.v1

        # Init all the output variable
        self.bis = self.bis_pd.compute_bis(0, 0)
        self.tol = self.tol_pd.compute_tol(0, 0)
        self.loc = self.loc_pd.compute_loc(0, 0)
        self.tof = self.tof_pd.compute_tof(0)
        self.tpr = self.hemo_pd.tpr_base
        self.sv = self.hemo_pd.abase_sv
        self.hr = self.hemo_pd.abase_hr
        self.co = self.hr*self.sv / 1000
        self.map = self.tpr*self.hr*self.sv
        self.dap = self.map - 2 / 9 * self.sv
        self.sap = self.map + 4 / 9 * self.sv

    def one_step(self, u_propo: float = 0, u_remi: float = 0, u_nore: float = 0, u_atra: float = 0, sqi: float = 100,
                 blood_rate: float = 0, dist: list = None) -> tuple[float, float, float, float]:
        r"""
        Simulate one step time of the patient.

        Parameters
        ----------
        u_propo : float, optional
            Propofol infusion rate (mg/s). The default is 0.
        u_remi : float, optional
            Remifentanil infusion rate (µg/s). The default is 0.
        u_nore : float, optional
            Norepinephrine infusion rate (µg/s). The default is 0.
        u_atra : float, optional
            Atracurium infusion rate (µg/s). The default is 0.
        blood_rate : float, optional
            Fluid rates from blood volume (mL/min), negative is bleeding while positive is a transfusion.
            The default is 0.
        dist : list, optional
            Disturbance vector on [BIS (%), MAP (mmHg), CO (L/min), TPR (mmHg.min/mL), SV (mL), HR (beat/min)]. The default is [0]*6.
        noise : bool, optional
            bool to add measurement noise on the outputs. The default is True.

        Returns
        -------
        bis : float
            Bispectral index(%).
        loc: float,
            Loss of consciousness
        co : float
            Cardiac output (L/min).
        map : float
            Mean arterial pressure (mmHg).
        tol : float
            Tolerance of Laryngoscopy index (0-1).
        tof : float
            Neuromuscular Blockade level (%)

        """
        if dist is None:
            dist = [0]*6
        # update PK model with CO
        if self.co_update:
            self.propo_pk.update_param_CO(self.co / (self.co_base))
            self.remi_pk.update_param_CO(self.co / (self.co_base))
            self.nore_pk.update_param_CO(self.co / (self.co_base))

        # blood loss effect
        if blood_rate != 0 or self.blood_volume != self.blood_volume_init:
            self.blood_loss(blood_rate)

        # compute PK model
        self.c_es_propo = self.propo_pk.one_step(u_propo)
        self.c_es_remi = self.remi_pk.one_step(u_remi)
        self.c_blood_nore = self.nore_pk.one_step(u_nore)
        self.c_es_atra = self.atracurium_pk.one_step(u_atra)
        # BIS
        self.bis = self.bis_pd.one_step(self.c_es_propo, self.c_es_remi)
        # TOL
        self.tol = self.tol_pd.compute_tol(self.c_es_propo, self.c_es_remi)
        # LOC
        self.loc = self.loc_pd.compute_loc(self.c_es_propo, self.c_es_remi)
        # TOF
        self.tof = self.tof_pd.compute_tof(self.c_es_atra)
        # Hemodynamic
        y_hemo = self.hemo_pd.one_step(
            cp_propo=self.propo_pk.x[0, 0],
            cp_remi=self.remi_pk.x[0, 0],
            cp_nore=self.c_blood_nore,
            v_ratio=(self.blood_volume / self.blood_volume_init),
            disturbances=dist[-3:],
        )
        self.tpr = y_hemo[0]
        self.sv = y_hemo[1]
        self.hr = y_hemo[2]
        self.map = y_hemo[3]
        self.co = y_hemo[4]

        # disturbances
        self.bis += dist[0]
        self.map += dist[1]
        self.co += dist[2]

        self.dap = self.map - 2 / 9 * self.sv
        self.sap = self.map + 4 / 9 * self.sv

        return (self.bis, self.loc, self.co, self.map, self.tol, self.tof)

    def find_equilibrium(self, bis_target: float, tol_target: float,
                         map_target: float) -> tuple[float, float, float]:
        r"""
        Find the input to meet the targeted outputs at the equilibrium.

        Solve the optimization problem to find the equilibrium input for BIS - TOL:

        .. math::  min_{C_{p,es}, C_{r,es}} \frac{||BIS_{target} - BIS||^2}{100^2} + ||TOL_{target} - TOL||^2

        Then compute the concentration of Noradrenaline to meet the MAP target.

        Finally, compute the input of Propofol, Remifentanil and Noradrenaline to meet the targeted concentration.

        Parameters
        ----------
        bis_target : float
            BIS target (%).
        tol_target : float
            TOL target ([0, 1]).
        map_target:float
            MAP target (mmHg).

        Returns
        -------
        u_propo : float:
            Propofol infusion rate (mg/s).
        u_remi : float:
            Remifentanil infusion rate (µg/s).
        u_nore : float:
            Norepinephrine infusion rate (µg/s).

        """
        # find Remifentanil and Propofol Concentration from BIS and TOL
        cep = cas.MX.sym('cep')  # effect site concentration of propofol in the optimization problem
        cer = cas.MX.sym('cer')  # effect site concentration of remifentanil in the optimization problem

        bis = self.bis_pd.compute_bis(cep, cer)
        tol = self.tol_pd.compute_tol(cep, cer)

        J = (bis - bis_target)**2 / 100**2 + (tol - tol_target)**2
        w = [cep, cer]
        w0 = [self.bis_pd.c50p, self.bis_pd.c50r / 2.5]
        lbw = [0, 0]
        ubw = [50, 50]

        opts = {'ipopt.print_level': 0, 'print_time': 0}
        prob = {'f': J, 'x': cas.vertcat(*w)}
        solver = cas.nlpsol('solver', 'ipopt', prob, opts)
        sol = solver(x0=w0, lbx=lbw, ubx=ubw)
        w_opt = sol['x'].full().flatten()
        self.c_blood_propo_eq = w_opt[0]
        self.c_blood_remi_eq = w_opt[1]

        # get Norepinephrine rate from MAP target
        # first compute the effect of propofol and remifentanil on MAP
        y_hemo = self.hemo_pd.state_at_equilibrium(
            self.c_blood_propo_eq,
            self.c_blood_remi_eq,
            0)
        map_without_nore = y_hemo[3]
        # Then compute the right nore concentration to meet the MAP target
        wanted_map_effect = map_target - map_without_nore
        self.c_blood_nore_eq = self.hemo_pd.c50_nore_map * (wanted_map_effect /
                                                            (self.hemo_pd.emax_nore_map - wanted_map_effect)
                                                            )**(1 / self.hemo_pd.gamma_nore_map)
        y_hemo = self.hemo_pd.state_at_equilibrium(
            self.c_blood_propo_eq,
            self.c_blood_remi_eq,
            self.c_blood_nore_eq)
        self.co_eq = y_hemo[4]
        # update pharmacokinetics model from co value
        if self.co_update:
            self.propo_pk.update_param_CO(self.co_eq / self.co_base)
            self.remi_pk.update_param_CO(self.co_eq / self.co_base)
            self.nore_pk.update_param_CO(self.co_eq / self.co_base)
        # get rate input
        self.u_propo_eq = self.c_blood_propo_eq / self.propo_pk.get_system_gain()
        self.u_remi_eq = self.c_blood_remi_eq / self.remi_pk.get_system_gain()
        self.u_nore_eq = self.c_blood_nore_eq / self.nore_pk.get_system_gain()
        if self.co_update:
            # set it back to normal
            self.propo_pk.update_param_CO(1)
            self.remi_pk.update_param_CO(1)
            self.nore_pk.update_param_CO(1)

        return self.u_propo_eq, self.u_remi_eq, self.u_nore_eq

    def find_bis_equilibrium_with_ratio(self, bis_target: float,
                                        rp_ratio: float = 2) -> tuple[float, float]:
        r"""
        Find the input of Propofol and Remifentanil to meet the BIS target at the
        equilibrium with a fixed ratio between drugs rates.

        Solve the optimization problem:

        .. math:: J = (bis - bis_{target})^2

        Where :math:`bis` is the BIS computed from the pharmacodynamic model.
        And with the constraints:

        .. math:: u_{propo} = u_{remi} * rp_{ratio}
        .. math:: A_{propo} x_{propo} + B_{propo} u_{propo} = 0
        .. math:: A_{remi} x_{remi} + B_{remi} u_{remi} = 0

        Parameters
        ----------
        bis_target : float
            BIS target (%).
        rp_ratio : float
            remifentanil over propofol rates ratio. The default is 2.

        Returns
        -------
        u_propo : float:
            Propofol infusion rate (mg/s).
        u_remi : float:
            Remifentanil infusion rate (µg/s).

        """
        # solve the optimization problem
        w = []
        w0 = []
        lbw = []
        ubw = []
        J = 0
        g = []
        lbg = []
        ubg = []

        Ap = self.propo_pk.discretize_sys.A
        Bp = self.propo_pk.discretize_sys.B
        Ar = self.remi_pk.discretize_sys.A
        Br = self.remi_pk.discretize_sys.B

        x0p = np.linalg.solve(Ap - np.eye(4), - Bp * 7 / 20)
        x0r = np.linalg.solve(Ar - np.eye(4), - Br * 7 / 10)
        w0 += x0p[:, 0].tolist()
        w0 += x0r[:, 0].tolist()

        xp = cas.MX.sym('xp', 4, 1)
        xr = cas.MX.sym('xr', 4, 1)
        UP = cas.MX.sym('up', 1)
        w = [xp, xr, UP]
        w0 += [7 / 2]
        lbw = [1e-3] * 9
        ubw = [1e4] * 9

        bis = self.bis_pd.compute_bis(xp[3], xr[3])
        J = (bis_target - bis)**2

        g = [(Ap - np.eye(4)) @ xp + Bp * UP, (Ar - np.eye(4)) @ xr + Br * (rp_ratio * UP)]
        lbg = [-1e-8] * 8
        ubg = [1e-8] * 8
        opts = {'ipopt.print_level': 0, 'print_time': 0}
        prob = {'f': J, 'x': cas.vertcat(*w), 'g': cas.vertcat(*g)}
        solver = cas.nlpsol('solver', 'ipopt', prob, opts)
        sol = solver(x0=w0, lbx=lbw, ubx=ubw, lbg=lbg, ubg=ubg)
        w_opt = sol['x'].full().flatten()

        self.u_propo_eq = w_opt[-1]
        self.u_remi_eq = rp_ratio * self.u_propo_eq
        return self.u_propo_eq, self.u_remi_eq

    def initialized_at_given_input(self, u_propo: float = 0, u_remi: float = 0, u_nore: float = 0):
        r"""
        Initialize the patient Simulator at the given input as an equilibrium point.

        For each drug, the equilibrium state is computed from the input.
        Then this state is used to intitialze each drug pharmacokinetic model.

        Warning, this option does not work if the `co_update` option is set to True.

        Parameters
        ----------
        u_propo : float, optional
            Propofol infusion rate (mg/s). The default is 0.
        u_remi : float, optional
            Remifentanil infusion rate (µg/s). The default is 0.
        u_nore : float, optional
            Norepinephrine infusion rate (µg/s). The default is 0.

        Returns
        -------
        None.

        """
        self.u_propo_eq = u_propo
        self.u_remi_eq = u_remi
        self.u_nore_eq = u_nore

        if self.co_update:
            print(self.co_eq)
            self.propo_pk.update_param_CO(self.co_eq / self.co_base)
            self.remi_pk.update_param_CO(self.co_eq / self.co_base)
            self.nore_pk.update_param_CO(self.co_eq / self.co_base)

        self.c_blood_propo_eq = u_propo * self.propo_pk.get_system_gain()
        self.c_blood_remi_eq = u_remi * self.remi_pk.get_system_gain()
        self.c_blood_nore_eq = u_nore * self.nore_pk.get_system_gain()

        # PK models
        self.propo_pk.x = np.array([[self.c_blood_propo_eq] * len(self.propo_pk.x)]).T

        self.remi_pk.x = np.array([[self.c_blood_remi_eq] * len(self.remi_pk.x)]).T

        self.nore_pk.x = np.array([[self.c_blood_nore_eq] * len(self.nore_pk.x)]).T

        # PD hemo
        self.hemo_pd.initialized_at_given_concentration(
            self.c_blood_propo_eq,
            self.c_blood_remi_eq,
            self.c_blood_nore_eq)

        # recompute output variable
        # BIS
        self.bis = self.bis_pd.compute_bis(self.propo_pk.x[3, 0], self.remi_pk.x[3, 0])
        # TOL
        self.tol = self.tol_pd.compute_tol(self.propo_pk.x[3, 0], self.remi_pk.x[3, 0])
        # Loc
        self.loc = self.loc_pd.compute_loc(self.propo_pk.x[3, 0], self.remi_pk.x[3, 0])
        # TOF
        self.tof = self.tof_pd.compute_tof(self.atracurium_pk.x[3, 0])
        # Hemodynamic
        y_hemo = self.hemo_pd.one_step(self.propo_pk.x[0, 0], self.remi_pk.x[0, 0], self.nore_pk.x[0, 0])
        self.tpr = y_hemo[0]
        self.sv = y_hemo[1]
        self.hr = y_hemo[2]
        self.map = y_hemo[3]
        self.co = y_hemo[4]

    def initialized_at_maintenance(self, bis_target: float, tol_target: float,
                                   map_target: float) -> tuple[float, float, float]:
        r"""Initialize the patient model at the equilibrium point for the given output value.

        Parameters
        ----------
        bis_target : float
            BIS target (%).
        tol_target : float
            TOL target ([0, 1]).
        map_target:float
            MAP target (mmHg).

        Returns
        -------
        u_propo : float:
            Propofol infusion rate (mg/s).
        u_remi : float:
            Remifentanil infusion rate (µg/s).
        u_nore : float:
            Norepinephrine infusion rate (µg/s).

        """
        # Find equilibrium point

        self.find_equilibrium(bis_target, tol_target, map_target)

        # set them as starting point in the simulator

        self.initialized_at_given_input(u_propo=self.u_propo_eq,
                                        u_remi=self.u_remi_eq,
                                        u_nore=self.u_nore_eq)
        if self.co_update:
            self.propo_pk.update_param_CO(self.co_eq / self.co_base)
            self.remi_pk.update_param_CO(self.co_eq / self.co_base)
            self.nore_pk.update_param_CO(self.co_eq / self.co_base)
        return self.u_propo_eq, self.u_remi_eq, self.u_nore_eq

    def blood_loss(self, fluid_rate: float = 0):
        """Actualize the patient parameters to mimic blood loss.

        Parameters
        ----------
        fluid_rate : float, optional
            Fluid rates from blood volume (mL/min), negative is bleeding while positive is a transfusion.
            The default is 0.

        Returns
        -------
        None.

        """
        fluid_rate = fluid_rate / 1000 / 60  # in L/s
        # compute the blood volume
        self.blood_volume += fluid_rate * self.ts

        # Update the models
        self.propo_pk.update_param_blood_loss(self.blood_volume / self.blood_volume_init, self.co / (self.co_base))
        self.remi_pk.update_param_blood_loss(self.blood_volume / self.blood_volume_init, self.co / (self.co_base))
        self.nore_pk.update_param_blood_loss(self.blood_volume / self.blood_volume_init, self.co / (self.co_base))
        self.bis_pd.update_param_blood_loss(self.blood_volume / self.blood_volume_init)

    def full_sim(
        self,
        u_propo: Optional[np.ndarray] = None,
        u_remi: Optional[np.ndarray] = None,
        u_nore: Optional[np.ndarray] = None,
        u_atra: Optional[np.ndarray] = None,
        disturbances: Optional[np.ndarray] = None,
        x0_propo: Optional[np.array] = None,
        x0_remi: Optional[np.array] = None,
        x0_nore: Optional[np.array] = None,
        x0_atra: Optional[np.array] = None,
        interp=False,
    ) -> pd.DataFrame:
        r"""Simulates the patient model using the drugs infusions profiles provided as inputs.

        Parameters
        ----------
        u_propo : numpy array, optional
            Propofol infusion rate (mg/s). Must be a 1D array.
        u_remi : numpy array, optional
            Remifentanil infusion rate (µg/s). Must be a 1D array.
        u_nore : numpy array, optional
            Norepinephrine infusion rate (µg/s). Must be a 1D array.
        u_atra : numpy array, optional
            Atracurium infusion rate (µg/s). Must be a 1D array.
        disturbances : numpy array, optional
            2D numpy array with disturbance vector, axis 1=signals; axis 2= Time. Default is null.
        x0_propo : numpy array, optional
            Initial state of the propofol PK model. The default is zeros.
        x0_remi : numpy array, optional
            Initial state of the remifentanil PK model. The default is zeros.
        x0_nore : numpy array, optional
            Initial state of the norepinephrine PK model. The default is zeros.
        x0_atra : numpy array, optional
            Initial state of the atracurium PK model. The default is zeros.
        interp : bool, optional
            Whether to use zero-order-hold (False, the default) or linear (True) interpolation for the input array.

        Requirements
        ------------
        - At least one of `u_propo`, `u_remi`, `u_nore` or `u_atra` must be provided.
        - All input arrays (`u_propo`, `u_remi`, `u_nore`, 'u_atra') must have the same length.
          If any of them is not provided, it will be automatically filled with zeros to match the length of the others.
        - The simulation duration is determined by the length of the input arrays.

        Returns
        -------
        pandas.Dataframes
            Dataframe with all the data.

        """
        # INPUT check
        if u_propo is None and u_remi is None and u_nore is None and u_atra is None:
            raise ValueError('No input given')
        # Propofol infusion
        if u_propo is None:
            if u_remi is not None:
                u_propo = np.zeros_like(u_remi)
            elif u_nore is not None:
                u_propo = np.zeros_like(u_nore)
            else:
                u_propo = np.zeros_like(u_atra)
        # Remifentanil infusion
        if u_remi is None:
            u_remi = np.zeros_like(u_propo)
        # Norepinephrine infusion
        if u_nore is None:
            u_nore = np.zeros_like(u_propo)
        # Atracurium infusion
        if u_atra is None:
            u_atra = np.zeros_like(u_propo)
        if disturbances is None:
            disturbances = np.zeros((6, len(u_propo)))
        # INPUT consistency check
        if not (len(u_propo) == len(u_remi) == len(u_nore) == len(u_atra) == len(disturbances[0])):
            raise ValueError('Inputs must have the same length')

        # simulate
        x_propo = self.propo_pk.full_sim(u_propo, x0_propo, interp)
        x_remi = self.remi_pk.full_sim(u_remi, x0_remi, interp)
        x_nore = self.nore_pk.full_sim(u_nore, x0_nore, interp)
        x_atra = self.atracurium_pk.full_sim(u_atra, x0_atra, interp)

        # compute outputs
        bis = self.bis_pd.full_sim(x_propo[3, :], x_remi[3, :]) + disturbances[0, :]
        tol = self.tol_pd.compute_tol(x_propo[3, :], x_remi[3, :])
        loc = self.loc_pd.compute_loc(x_propo[3, :], x_remi[3, :])
        tof = self.tof_pd.compute_tof(x_atra[3, :])
        if x_nore.ndim == 1:
            y = self.hemo_pd.full_sim(
                x_propo[0, :],
                x_remi[0, :],
                x_nore[:],
                disturbances=disturbances[3:, :].T)
        else:
            y = self.hemo_pd.full_sim(
                x_propo[0, :],
                x_remi[0, :],
                x_nore[0, :],
                disturbances=disturbances[3:, :].T)

        tpr = y[:, 0]
        sv = y[:, 1]
        hr = y[:, 2]
        map = y[:, 3] + disturbances[1, :]
        co = y[:, 4] + disturbances[2, :]

        # save data
        dap = map - 2 / 9 * sv
        sap = map + 4 / 9 * sv
        df = pd.DataFrame({
            'Time': np.arange(0, len(u_propo) * self.ts, self.ts),
            'BIS': bis, 'LOC': loc, 'TOL': tol, 'TOF': tof, 'TPR': tpr, 'SV': sv,
            'HR': hr, 'MAP': map, 'CO': co, 'DAP': dap, 'SAP': sap,
            'u_propo': u_propo, 'u_remi': u_remi, 'u_nore': u_nore, 'u_atra': u_atra
        })

        for i in range(np.shape(x_propo)[0]):
            df['x_propo_' + str(i + 1)] = x_propo[i, :]
        for i in range(np.shape(x_remi)[0]):
            df['x_remi_' + str(i + 1)] = x_remi[i, :]
        for i in range(np.shape(x_atra)[0]):
            df['x_atra_' + str(i + 1)] = x_atra[i, :]
        if x_nore.ndim == 1:
            df['x_nore_1'] = x_nore
        else:
            for i in range(np.shape(x_nore)[0]):
                df['x_nore' + str(i + 1)] = x_nore[i, :]

        return df

    def initialized_at_given_state(self, x0_atra: np.ndarray):
        r"""
        Initialize the atracurium linear model at the given state.

        Parameters
        ----------
        x0 : numpy array
            Initial state vector of the atracurium linear model.

        Returns
        -------
        None.

        """
        self.atracurium_pk.initialize_state(x0_atra)
