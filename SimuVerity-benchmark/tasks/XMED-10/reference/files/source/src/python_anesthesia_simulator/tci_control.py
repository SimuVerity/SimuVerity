import numpy as np

from .pk_models import CompartmentModel, AtracuriumModel


class TCIController():
    """Implement the control algorithm coded in the TCI device Orchestra PRIMUS, from [Shafer1992]_.


    Warning: This code has been retro enginering and does not came from an official source.

    Parameters
    ----------
    patient_info : list
        Patient information = [age (yr), height (cm), weight (kg), sex( 0= female, 1 = male)].
    drug_name : str
        Can be either 'Propofol', 'Remifentanil', 'Norepinephrine' or 'Atracurium'.
    model_used : str
        Could be "Minto", "Eleveld" for Remifentanil,
        "Schnider", "Marsh_initial", "Marsh_modified", "Shuttler" or "Eleveld" for Propofol,
        "Oualha", or "Beloeil" for Norepinephrine,
        "WardWeatherleyLago" for Atracurium
    maximum_rate : float
        Maximum drug rate in mg/s or µg/s depending on the unit.
    sampling_time : float, optional
        Sampling time of the model for the calculs. The default is 1s.
    control_time : float, optional
        Sampling time of the controller, must be a multiple of the sampling time. The default is 10s.
    target_compartement : str, optional
        Can be either "plasma" or "effect_site", for Norepinephrine only plasma is available. The default is 'effect_site' except for norepinephrine.

    Attributes
    ----------
    sampling_time : float
        Sampling time of the model for the calculs.
    control_time : float
        Sampling time of the controller.
    target_id : int
        index of the target compartment in the state vector.
    infusion_max : float
        Maximum drug rate in mg/s or µg/s.
    Ad : np.array
        Discretized state matrix of the mode with the sampling time of the model.
    Bd : np.array
        Discretized input matrix of the model.
    Ad_control : np.array
        Discretized state matrix of the model with the sampling time of the controller.
    Bd_control : np.array
        Discretized input matrix of the model with the sampling time of the controller.
    Ce : list
        List of the effect site concentration after a 10s infusion.
    infusion_rate : float
        Last control move chosen.
    x : np.array
        Array to store the patient state at simulation time.
    target : float
        Target concentration.

    References
    ----------
    .. [Shafer1992]  S. L. Shafer and K. M. Gregg, “Algorithms to rapidly achieve and maintain stable drug concentrations at the site of drug effect with a computer-controlled infusion pump,”0 Journal of Pharmacokinetics and Biopharmaceutics, vol. 20, no. 2, pp. 147–169, Apr. 1992, doi: 10.1007/BF01070999.

    """

    def __init__(
            self,
            patient_info: list,
            drug_name: str,
            model_used: str = None,
            maximum_rate: float = 500,
            sampling_time: float = 1,
            control_time: float = 10,
            target_compartement: str = 'effect_site',
    ):
        """Init the class and do pre-computation.

        Returns
        -------
        None.

        """
        if sampling_time > control_time:
            raise ValueError("Sampling time can't be bigger than TCI control time (10s by default)")
        if model_used is None:
            if drug_name == 'Propofol':
                model_used = 'Schnider'
            elif drug_name == 'Remifentanil':
                model_used = 'Minto'
            elif drug_name == 'Norepinephrine':
                model_used = 'Beloeil'
            elif drug_name == 'Atracurium':
                model_used = 'WardWeatherleyLago'
            else:
                raise ValueError("drug_name must be either 'Propofol', 'Remifentanil', 'Norepinephrine' or 'Atracurium'")
        self.sampling_time = sampling_time
        self.control_time = control_time
        if target_compartement == 'plasma':
            self.target_id = 0
        elif target_compartement == 'effect_site':
            self.target_id = 3
        else:
            raise ValueError('target_compartement must be either "plasma" or "effect_site"')
        if drug_name == 'Norepinephrine':
            self.target_id = 0
        self.infusion_max = maximum_rate  # in mg/s or µg/s respectively Propo and Remi

        height = patient_info[1]
        weight = patient_info[2]
        sex = patient_info[3]
        if sex == 1:  # homme
            lbm = 1.1 * weight - 128 * (weight / height) ** 2
        elif sex == 0:  # femme
            lbm = 1.07 * weight - 148 * (weight / height) ** 2

        if drug_name != 'Atracurium':
            pk_model = CompartmentModel(patient_info, lbm, drug_name, ts=sampling_time, model=model_used)
            self.Ad = pk_model.discretize_sys.A
            self.Bd = pk_model.discretize_sys.B

            pk_model = CompartmentModel(patient_info, lbm, drug_name, ts=control_time, model=model_used)
            self.Ad_control = pk_model.discretize_sys.A
            self.Bd_control = pk_model.discretize_sys.B
            self.u_endo = pk_model.u_endo
        else:
            pk_model = AtracuriumModel(
                patient_info,
                ts=sampling_time,
                model=model_used,
            )
            self.Ad = pk_model.discretize_sys.A
            self.Bd = pk_model.discretize_sys.B
            pk_model = AtracuriumModel(
                patient_info,
                ts=control_time,
                model=model_used,
            )
            self.Ad_control = pk_model.discretize_sys.A
            self.Bd_control = pk_model.discretize_sys.B
            self.u_endo = 0

        self.n_state = len(self.Ad)
        # find the response to a 10s infusion
        x = np.zeros((self.n_state, 1))
        x_p = np.zeros((self.n_state, 1))
        self.Ce = []
        t = sampling_time
        self.t_peak = 0
        while self.t_peak == 0:
            if t < control_time+1:
                x = self.Ad @ x + self.Bd * 1  # simulation of an infusion of 1 mg/s
            else:
                x = self.Ad @ x  # simulation of no infusion
            t += sampling_time
            self.Ce.append(float(x[self.target_id, 0]))
            if x[self.target_id] < x_p[self.target_id]:
                self.t_peak = t-sampling_time
            x_p = x
        self.Ce = np.array(self.Ce)
        # variable used for control
        self.infusion_rate = 0  # last control move chosen
        self.x = pk_model.x  # state to store the real patient
        self.target = 0
        self.tpeak_0 = 0
        self.tpeak_1 = 0
        self.time = 0

    def one_step(self, target: float = 0) -> float:
        """Implement one_step of the model. It must be called each sampling time.

        Parameters
        ----------
        target : float, optional
            target concentration (µg/ml for propofol, ng/ml for Remifentanil). The default is 0.

        Returns
        -------
        infusion rate: float
            infusion rate in mg/s per Propofol and µg/s for remifentanil.

        """

        if self.time % self.control_time == 0 or target != self.target:

            # if the target change, we reset the peak time
            if target != self.target:
                self.tpeak_0 = self.t_peak
                self.target = target

            # compute trajectory from where we are without any infusion
            x_temp = self.x
            Ce_0 = np.zeros(int(max(self.control_time+self.sampling_time, self.t_peak)/self.sampling_time))
            for t in range(int(max(self.control_time+self.sampling_time, self.t_peak)/self.sampling_time)):
                x_temp = self.Ad @ x_temp + self.Bd * self.u_endo
                Ce_0[t] = x_temp[self.target_id, 0]

            # compute the infusion rate to reach the target

            # if we are close to the target, we compute the infusion rate to reach the target at the next step time
            if Ce_0[0] > 0.95*target and Ce_0[0] < 1.05 * target:
                self.infusion_rate = (target - (self.Ad_control @ self.x)[0]) / self.Bd_control[0] - self.u_endo
                self.infusion_rate = max(0, self.infusion_rate)
            # if we are far from the target, we compute the infusion rate to reach the target at the next peak
            else:
                # if the target is reached, we stop the infusion
                if Ce_0[int(self.control_time/self.sampling_time)] > self.target:
                    self.infusion_rate = 0
                # if the target is not reached, we compute the infusion rate to reach the target at the next peak
                else:
                    # compute a first guess of the infusion using the last peak time
                    infusion_rate_temp = ((self.target - Ce_0[int(self.tpeak_0/self.sampling_time)-1]) /
                                          self.Ce[int(self.tpeak_0/self.sampling_time)-1])
                    self.infusion_rate = min(infusion_rate_temp, self.infusion_max)
                    self.tpeak_1 = (Ce_0 + infusion_rate_temp*self.Ce).argmax() * self.sampling_time
                    counter = 0
                    # we iterate to find the peak time
                    while self.tpeak_1 != self.tpeak_0 and counter < 500:
                        self.tpeak_0 = self.tpeak_1
                        infusion_rate_temp = ((self.target - Ce_0[int(self.tpeak_0/self.sampling_time)-1]) /
                                              self.Ce[int(self.tpeak_0/self.sampling_time)-1])
                        self.infusion_rate = max(min(infusion_rate_temp, self.infusion_max), 0)
                        self.tpeak_1 = (Ce_0 + infusion_rate_temp*self.Ce).argmax() * self.sampling_time
                        counter += 1

                    # if the peak time is not found, we use the last infusion rate
                    if counter == 500:
                        self.infusion_rate = max(min(infusion_rate_temp, self.infusion_max), 0)

        else:
            self.infusion_rate = self.infusion_rate

        self.time += self.sampling_time
        self.x = self.Ad @ self.x + self.Bd * (self.infusion_rate + self.u_endo)
        self.infusion_rate = max(min(self.infusion_rate, self.infusion_max), 0)
        if isinstance(self.infusion_rate, np.ndarray):
            self.infusion_rate = self.infusion_rate[0]
        return self.infusion_rate
